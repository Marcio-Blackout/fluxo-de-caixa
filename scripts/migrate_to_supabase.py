"""
Migração da planilha "Cópia de PAINEL (MODERNIZAÇAO)" (aba
"TERMO DE RESPONSABILIDADE - RESPOSTAS") para o Supabase (projeto fluxo-de-caixa).

Lê a planilha diretamente do Google Sheets via gspread (não precisa exportar CSV),
higieniza os dados e faz upsert em pessoas -> ativos -> contratos.

Instalação:
    pip install gspread google-auth pandas supabase

Configuração (variáveis de ambiente):
    SUPABASE_URL              -> https://kihnavaovspdjnegcraj.supabase.co
    SUPABASE_SERVICE_ROLE_KEY -> pegue em Project Settings > API > service_role (secret)
    GOOGLE_SERVICE_ACCOUNT_JSON -> caminho para o JSON da service account do Google
                                    (com acesso de leitor compartilhado na planilha)
    SHEET_ID                  -> 1IqUEzNcPxwlDuX6KIH0wB9ts1HnSPse4AcFeYxbbCt0 (padrão abaixo)
"""

import os
import re
from datetime import datetime, timezone

import gspread
from google.oauth2.service_account import Credentials
from supabase import Client, create_client

# ==============================================
# CONFIGURAÇÕES
# ==============================================
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
_DEFAULT_CREDENTIALS = os.path.join(
    os.path.dirname(__file__), "secrets", "migracao-supabase-a60aac7b25cd.json"
)
GOOGLE_SERVICE_ACCOUNT_JSON = os.environ.get("GOOGLE_SERVICE_ACCOUNT_JSON", _DEFAULT_CREDENTIALS)
SHEET_ID = os.environ.get("SHEET_ID", "1IqUEzNcPxwlDuX6KIH0wB9ts1HnSPse4AcFeYxbbCt0")
WORKSHEET_NAME = "TERMO DE RESPONSABILIDADE - RESPOSTAS"

supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

# Índices de coluna (0-based) confirmados na aba de respostas real.
# O formulário repete o mesmo bloco de perguntas para Proprietário e Responsável,
# por isso o acesso é posicional em vez de por nome de coluna.
COL = {
    "carimbo": 0,
    "prop_nome": 1,
    "prop_genero": 2,
    "prop_nacionalidade": 3,
    "prop_estado_civil": 4,
    "prop_profissao": 5,
    "prop_rg": 6,
    "prop_cpf": 7,
    "prop_endereco": 8,
    "prop_bairro": 9,
    "prop_cidade_estado": 10,  # formato "Camboriú/SC"
    "resp_nome": 14,
    "resp_genero": 15,
    "resp_nacionalidade": 16,
    "resp_estado_civil": 17,
    "resp_profissao": 18,
    "resp_rg": 19,
    "resp_cpf": 20,
    "resp_endereco": 21,
    "resp_bairro": 22,
    "resp_cidade_estado": 23,
    "tipo_veiculo": 27,
    "fabricante": 28,
    "modelo": 29,
    "ano": 30,
    "placa": 31,
    "cor": 32,
    "chassi": 33,
    "renavam": 34,
}

INVALID_STRINGS = {"", "ddd", "nan", "null", "none", "n/a"}


# ==============================================
# FUNÇÕES DE HIGIENIZAÇÃO
# ==============================================
def clean_str(val):
    """Limpa e padroniza strings, tratando placeholders inválidos como nulo."""
    if val is None:
        return None
    val = str(val).strip()
    if val.lower() in INVALID_STRINGS:
        return None
    return val


def clean_digits(val):
    """Remove caracteres não numéricos. Retorna None se resultado inválido."""
    val = clean_str(val)
    if val is None:
        return None
    digits = re.sub(r"\D", "", val)
    return digits if digits else None


def parse_cidade_estado(val):
    """Separa 'Camboriú/SC' em (cidade, estado)."""
    val = clean_str(val)
    if not val:
        return None, None
    if "/" in val:
        cidade, estado = val.rsplit("/", 1)
        return cidade.strip() or None, estado.strip() or None
    return val, None


def parse_timestamp(val):
    """Converte carimbo de data/hora (dd/mm/yyyy hh:mm:ss) para ISO 8601 UTC."""
    val = clean_str(val)
    if not val:
        return datetime.now(timezone.utc).isoformat()
    try:
        dt = datetime.strptime(val, "%d/%m/%Y %H:%M:%S")
        return dt.replace(tzinfo=timezone.utc).isoformat()
    except ValueError:
        return datetime.now(timezone.utc).isoformat()


# ==============================================
# UPSERTS
# ==============================================
def upsert_pessoa(pessoa_data):
    """Upsert em pessoas, priorizando CPF e caindo para nome como chave de dedup."""
    cpf = pessoa_data.get("cpf")
    nome = pessoa_data.get("nome")
    if not nome:
        return None

    existing = None
    if cpf:
        res = supabase.table("pessoas").select("id").eq("cpf", cpf).execute()
        if res.data:
            existing = res.data[0]

    if not existing:
        res = supabase.table("pessoas").select("id").ilike("nome", nome).execute()
        if res.data:
            existing = res.data[0]

    if existing:
        pessoa_id = existing["id"]
        supabase.table("pessoas").update(pessoa_data).eq("id", pessoa_id).execute()
        return pessoa_id

    res = supabase.table("pessoas").insert(pessoa_data).execute()
    return res.data[0]["id"] if res.data else None


def upsert_ativo(ativo_data):
    """Upsert em ativos pela placa, caindo para renavam se a placa faltar."""
    placa = ativo_data.get("placa")
    renavam = ativo_data.get("renavam")

    existing = None
    if placa:
        res = supabase.table("ativos").select("id").eq("placa", placa).execute()
        if res.data:
            existing = res.data[0]
    if not existing and renavam:
        res = supabase.table("ativos").select("id").eq("renavam", renavam).execute()
        if res.data:
            existing = res.data[0]

    if existing:
        ativo_id = existing["id"]
        supabase.table("ativos").update(ativo_data).eq("id", ativo_id).execute()
        return ativo_id

    res = supabase.table("ativos").insert(ativo_data).execute()
    return res.data[0]["id"] if res.data else None


def contrato_ja_existe(proprietario_id, responsavel_id, ativo_id):
    res = (
        supabase.table("contratos")
        .select("id")
        .eq("proprietario_id", proprietario_id)
        .eq("responsavel_id", responsavel_id)
        .eq("ativo_id", ativo_id)
        .execute()
    )
    return bool(res.data)


# ==============================================
# PROCESSAMENTO DE UMA LINHA
# ==============================================
def process_row(row, line_number):
    def get(key):
        idx = COL[key]
        return row[idx] if idx < len(row) else None

    timestamp = parse_timestamp(get("carimbo"))

    # 1. Proprietário
    prop_cidade, prop_estado = parse_cidade_estado(get("prop_cidade_estado"))
    proprietario_data = {
        "nome": clean_str(get("prop_nome")),
        "genero": clean_str(get("prop_genero")),
        "nacionalidade": clean_str(get("prop_nacionalidade")),
        "estado_civil": clean_str(get("prop_estado_civil")),
        "profissao": clean_str(get("prop_profissao")),
        "rg": clean_str(get("prop_rg")),
        "cpf": clean_digits(get("prop_cpf")),
        "endereco": clean_str(get("prop_endereco")),
        "bairro": clean_str(get("prop_bairro")),
        "cidade": prop_cidade,
        "estado": prop_estado,
    }
    if not proprietario_data["nome"]:
        print(f"[linha {line_number}] sem nome de proprietário, pulando")
        return
    proprietario_id = upsert_pessoa(proprietario_data)

    # 2. Responsável (se não houver, o próprio proprietário é o responsável)
    resp_nome = clean_str(get("resp_nome"))
    if resp_nome:
        resp_cidade, resp_estado = parse_cidade_estado(get("resp_cidade_estado"))
        responsavel_data = {
            "nome": resp_nome,
            "genero": clean_str(get("resp_genero")),
            "nacionalidade": clean_str(get("resp_nacionalidade")),
            "estado_civil": clean_str(get("resp_estado_civil")),
            "profissao": clean_str(get("resp_profissao")),
            "rg": clean_str(get("resp_rg")),
            "cpf": clean_digits(get("resp_cpf")),
            "endereco": clean_str(get("resp_endereco")),
            "bairro": clean_str(get("resp_bairro")),
            "cidade": resp_cidade,
            "estado": resp_estado,
        }
        responsavel_id = upsert_pessoa(responsavel_data)
    else:
        responsavel_id = proprietario_id

    # 3. Ativo (veículo)
    placa = clean_str(get("placa"))
    ativo_data = {
        "tipo": "VEICULO",
        "proprietario_id": proprietario_id,
        "fabricante": clean_str(get("fabricante")),
        "modelo": clean_str(get("modelo")),
        "ano_fabricacao_modelo": clean_str(get("ano")),
        "placa": placa.upper() if placa else None,
        "cor": clean_str(get("cor")),
        "chassi": clean_str(get("chassi")),
        "renavam": clean_digits(get("renavam")),
    }
    ativo_id = upsert_ativo(ativo_data)

    # 4. Contrato / Termo de Responsabilidade
    if proprietario_id and responsavel_id and ativo_id:
        if not contrato_ja_existe(proprietario_id, responsavel_id, ativo_id):
            supabase.table("contratos").insert(
                {
                    "tipo_contrato": "TERMO_DE_RESPONSABILIDADE",
                    "proprietario_id": proprietario_id,
                    "responsavel_id": responsavel_id,
                    "ativo_id": ativo_id,
                    "data_registro": timestamp,
                }
            ).execute()
            print(f"[linha {line_number}] contrato registrado para placa {ativo_data['placa']}")
        else:
            print(f"[linha {line_number}] contrato já existia, pulando")


def main():
    creds = Credentials.from_service_account_file(
        GOOGLE_SERVICE_ACCOUNT_JSON,
        scopes=["https://www.googleapis.com/auth/spreadsheets.readonly"],
    )
    gc = gspread.authorize(creds)
    sheet = gc.open_by_key(SHEET_ID).worksheet(WORKSHEET_NAME)

    rows = sheet.get_all_values()[1:]  # pula o cabeçalho
    print(f"Iniciando processamento de {len(rows)} registros...")

    for i, row in enumerate(rows, start=2):
        if not any(row):
            continue
        process_row(row, i)


if __name__ == "__main__":
    main()
