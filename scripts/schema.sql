-- Schema aplicado no projeto Supabase "fluxo-de-caixa" (kihnavaovspdjnegcraj)
-- via migration create_pessoas_ativos_contratos. Mantido aqui como referência versionada.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. PESSOAS (Proprietários, Responsáveis, Locatários)
CREATE TABLE IF NOT EXISTS public.pessoas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cpf TEXT UNIQUE,
    rg TEXT,
    nome TEXT NOT NULL,
    genero TEXT,
    nacionalidade TEXT,
    estado_civil TEXT,
    profissao TEXT,
    endereco TEXT,
    bairro TEXT,
    cidade TEXT,
    estado TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pessoas_cpf ON public.pessoas(cpf);
CREATE INDEX IF NOT EXISTS idx_pessoas_nome ON public.pessoas(nome);

-- 2. ATIVOS (Veículos e Imóveis)
CREATE TABLE IF NOT EXISTS public.ativos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo TEXT NOT NULL CHECK (tipo IN ('VEICULO', 'IMOVEL')),
    proprietario_id UUID REFERENCES public.pessoas(id) ON DELETE SET NULL,

    placa TEXT UNIQUE,
    renavam TEXT UNIQUE,
    chassi TEXT UNIQUE,
    fabricante TEXT,
    modelo TEXT,
    ano_fabricacao_modelo TEXT,
    cor TEXT,

    inscricao_imobiliaria TEXT,
    endereco_imovel TEXT,
    detalhes_imovel JSONB,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ativos_placa ON public.ativos(placa);
CREATE INDEX IF NOT EXISTS idx_ativos_renavam ON public.ativos(renavam);

-- 3. CONTRATOS / DOCUMENTOS (Termo de Responsabilidade, Declarações, Procurações)
-- tipo_contrato distingue o tipo; ativo_id é opcional (só Termo e Procuração
-- Detran envolvem veículo); dados JSONB guarda os campos específicos de cada
-- tipo (renda mensal, tempo de união, prazo de validade etc) — normalizar uma
-- tabela por tipo de documento não compensa pro volume atual.
CREATE TABLE IF NOT EXISTS public.contratos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tipo_contrato TEXT NOT NULL DEFAULT 'TERMO_DE_RESPONSABILIDADE',
    proprietario_id UUID NOT NULL REFERENCES public.pessoas(id) ON DELETE CASCADE,
    responsavel_id UUID NOT NULL REFERENCES public.pessoas(id) ON DELETE CASCADE,
    ativo_id UUID REFERENCES public.ativos(id) ON DELETE CASCADE,
    data_registro TIMESTAMPTZ NOT NULL,
    observacoes TEXT,
    dados JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contratos_proprietario ON public.contratos(proprietario_id);
CREATE INDEX IF NOT EXISTS idx_contratos_responsavel ON public.contratos(responsavel_id);
CREATE INDEX IF NOT EXISTS idx_contratos_ativo ON public.contratos(ativo_id);

ALTER TABLE public.pessoas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ativos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.contratos ENABLE ROW LEVEL SECURITY;

-- Políticas RLS: mesmo padrão usado em public.entries (acesso liberado ao anon,
-- sem Supabase Auth ainda — o app usa só uma trava client-side de senha/biometria).
CREATE POLICY "allow anon select" ON public.pessoas FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.pessoas FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.pessoas FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.pessoas FOR DELETE TO anon USING (true);

CREATE POLICY "allow anon select" ON public.ativos FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.ativos FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.ativos FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.ativos FOR DELETE TO anon USING (true);

CREATE POLICY "allow anon select" ON public.contratos FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.contratos FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.contratos FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.contratos FOR DELETE TO anon USING (true);

-- ============================================================
-- Financeiro completo: reflete SANGRIA, GRÁFICA, PIX e RETIRADA
-- da planilha, unificando despesas de loja e família (retiradas.categoria).
-- ============================================================

CREATE TABLE IF NOT EXISTS public.pix_recebidos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data DATE NOT NULL DEFAULT CURRENT_DATE,
    valor NUMERIC NOT NULL CHECK (valor > 0),
    taxa NUMERIC NOT NULL DEFAULT 0 CHECK (taxa >= 0),
    descricao TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.sangria (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data DATE NOT NULL DEFAULT CURRENT_DATE,
    valor NUMERIC NOT NULL CHECK (valor > 0),
    destino TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.grafica_despesas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data DATE NOT NULL DEFAULT CURRENT_DATE,
    valor NUMERIC NOT NULL CHECK (valor > 0),
    forma_pagamento TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.retiradas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data DATE NOT NULL DEFAULT CURRENT_DATE,
    valor NUMERIC NOT NULL CHECK (valor > 0),
    origem TEXT NOT NULL,
    destino TEXT NOT NULL,
    categoria TEXT NOT NULL CHECK (categoria IN ('LOJA', 'FAMILIA', 'MISTO')),
    descricao TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pix_data ON public.pix_recebidos(data);
CREATE INDEX IF NOT EXISTS idx_sangria_data ON public.sangria(data);
CREATE INDEX IF NOT EXISTS idx_grafica_data ON public.grafica_despesas(data);
CREATE INDEX IF NOT EXISTS idx_retiradas_data ON public.retiradas(data);
CREATE INDEX IF NOT EXISTS idx_retiradas_categoria ON public.retiradas(categoria);

ALTER TABLE public.pix_recebidos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sangria ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.grafica_despesas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.retiradas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow anon select" ON public.pix_recebidos FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.pix_recebidos FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.pix_recebidos FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.pix_recebidos FOR DELETE TO anon USING (true);

CREATE POLICY "allow anon select" ON public.sangria FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.sangria FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.sangria FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.sangria FOR DELETE TO anon USING (true);

CREATE POLICY "allow anon select" ON public.grafica_despesas FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.grafica_despesas FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.grafica_despesas FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.grafica_despesas FOR DELETE TO anon USING (true);

CREATE POLICY "allow anon select" ON public.retiradas FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.retiradas FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.retiradas FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.retiradas FOR DELETE TO anon USING (true);

-- Despesas fixas mensais (aluguel, água, luz, internet, folha de pagamento etc),
-- que não passam pelo caixa diário mas entram no resumo loja x família.
CREATE TABLE IF NOT EXISTS public.despesas_fixas (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT NOT NULL,
    valor NUMERIC NOT NULL CHECK (valor >= 0),
    categoria TEXT NOT NULL CHECK (categoria IN ('LOJA', 'FAMILIA')),
    ativa BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.despesas_fixas ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow anon select" ON public.despesas_fixas FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.despesas_fixas FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.despesas_fixas FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.despesas_fixas FOR DELETE TO anon USING (true);

-- ============================================================
-- Currículo: pedidos de cliente (formulário de 93 perguntas na planilha
-- original). Campos centrais viram colunas; o resto (escolaridade, cursos,
-- experiências, referências, CNH etc) fica em JSONB — normalizar cada grupo
-- repetido (até 5 cursos, até 4 empresas) não compensa pro volume atual.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.curriculos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nome TEXT NOT NULL,
    sobrenome TEXT,
    data_nascimento DATE,
    genero TEXT,
    nacionalidade TEXT,
    estado_civil TEXT,
    telefone TEXT,
    whatsapp TEXT,
    email TEXT,
    endereco TEXT,
    bairro TEXT,
    cidade TEXT,
    estado TEXT,
    status TEXT NOT NULL DEFAULT 'PENDENTE' CHECK (status IN ('PENDENTE', 'FEITO')),
    dados JSONB,
    data_pedido TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_curriculos_status ON public.curriculos(status);
CREATE INDEX IF NOT EXISTS idx_curriculos_nome ON public.curriculos(nome);

ALTER TABLE public.curriculos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow anon select" ON public.curriculos FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.curriculos FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.curriculos FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.curriculos FOR DELETE TO anon USING (true);

-- ============================================================
-- Fechamento diário: abertura de caixa e contagem física (notas/moedas)
-- pra conferência, um por dia. Não recalcula um "saldo final" definitivo
-- (a lógica exata da planilha original é ambígua) — o app mostra os
-- totais do dia (pix/sangria/gráfica/retiradas) ao lado pra conferência.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.fechamentos_caixa (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data DATE NOT NULL UNIQUE,
    abertura_caixa NUMERIC NOT NULL DEFAULT 0,
    notas NUMERIC NOT NULL DEFAULT 0,
    moedas NUMERIC NOT NULL DEFAULT 0,
    fundo_caixa NUMERIC NOT NULL DEFAULT 0,
    observacoes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.fechamentos_caixa ENABLE ROW LEVEL SECURITY;

CREATE POLICY "allow anon select" ON public.fechamentos_caixa FOR SELECT TO anon USING (true);
CREATE POLICY "allow anon insert" ON public.fechamentos_caixa FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "allow anon update" ON public.fechamentos_caixa FOR UPDATE TO anon USING (true) WITH CHECK (true);
CREATE POLICY "allow anon delete" ON public.fechamentos_caixa FOR DELETE TO anon USING (true);
