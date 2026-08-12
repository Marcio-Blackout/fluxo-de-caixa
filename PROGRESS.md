# Progresso — Painel de Controle Blackout

Última atualização: 2026-08-12

## O que é isso

Modernização da planilha Google Sheets "PAINEL DE CONTROLE" (usada no dia a
dia da Blackout, gráfica/despachante em Camboriú-SC) pra um app web com
Supabase como banco de dados. Substitui aos poucos os módulos da planilha
por telas reais, mantendo os que ainda não foram migrados como links diretos
pros formulários/planilha originais.

## Onde as coisas vivem

- **Código fonte de trabalho**: `github.com/Marcio-Blackout/fluxo-de-caixa`
  (branch `main`) — é aqui que a gente desenvolve e testa.
- **Produção**: `github.com/dev-zeq/blackout`, pasta `paineldecontrole/`,
  publicado em **lanblackout.com/paineldecontrole** via GitHub Pages.
  Toda mudança precisa ser copiada manualmente pros dois repos (não é um
  submodule/subtree — é literalmente copiar o `index.html`).
- **Banco de dados**: Supabase, projeto `fluxo-de-caixa`
  (`kihnavaovspdjnegcraj.supabase.co`), mesma org que o projeto
  `painel elis`. RLS habilitado em todas as tabelas com policy aberta pro
  `anon` (sem login de usuário — o app usa só uma trava local de
  senha/biometria WebAuthn, a chave pública fica exposta no HTML, é esperado).
- **Fonte original**: planilha Google Sheets "Cópia de PAINEL (MODERNIZAÇAO)"
  (cópia de "PAINEL DE CONTROLE", de `matugrinha22@gmail.com`), Drive do
  usuário. ID: `16aoOGD9mqHdchgje02F1g1wuIAFLsT8XvQtt9nDAdeA`.

## Arquitetura do app (`index.html`)

App único (HTML+CSS+JS vanilla, módulo ES, `@supabase/supabase-js@2` via
CDN). Sem build step — é o arquivo que sobe direto pro GitHub Pages.

- Tela de bloqueio (senha + WebAuthn opcional) → Home = grid de 16 cards
  (`MENU_ITEMS`), espelhando os atalhos da aba "PAINEL DE CONTROLE" da
  planilha.
- Views internas: `viewHome`, `viewCaixa` (Financeiro), `viewTermos`
  (Contratos), `viewCurriculo`, `viewSub` (sub-painéis de links).
- Sub-painéis (`SUBPANELS`) = grids de cards que abrem links externos reais
  (bancos, concessionárias, laboratórios), extraídos das abas "PAINEL X" da
  planilha original.

## Tabelas no Supabase

| Tabela | Pra quê | Status |
|---|---|---|
| `entries` | Entradas manuais balcão (Pix/Cartão/Dinheiro) | já existia antes desse trabalho |
| `pessoas` | Pessoas físicas (proprietário/responsável/outorgante/etc), reaproveitada por vários módulos | ✅ |
| `ativos` | Veículos (e imóveis, campo extensível) | ✅ |
| `contratos` | Termo de Responsabilidade + Declarações + Procurações, `tipo_contrato` distingue, `dados` JSONB pros campos específicos de cada tipo, `ativo_id` opcional | ✅ |
| `pix_recebidos` | Pix com taxa separada | ✅ |
| `sangria` | Depósitos do caixa pro banco | ✅ |
| `grafica_despesas` | Despesas da gráfica pagas do caixa | ✅ |
| `retiradas` | Toda saída de caixa, com `origem`/`destino`/`categoria` (LOJA/FAMILIA/MISTO) | ✅ |
| `despesas_fixas` | Aluguel, água, luz, internet, folha de pagamento — mensal, ativável/desativável | ✅ |
| `curriculos` | Pedidos de currículo de cliente, campos centrais + `dados` JSONB pro resto do formulário (93 perguntas) | ✅ |
| `fechamentos_caixa` | Abertura/notas/moedas/fundo de caixa por dia | ✅ |

Schema completo versionado em [`scripts/schema.sql`](scripts/schema.sql).

## Módulos do menu — status

| Card | Status |
|---|---|
| 💰 Financeiro | ✅ completo: Entradas balcão, Pix, Saídas (retirada/sangria/gráfica), Resumo Loja x Família, Despesas Fixas, Fechamento de Caixa |
| 🔒 Fechamento | ✅ atalho direto pra seção de fechamento dentro do Financeiro |
| 📑 Contratos | ✅ completo: Termo de Responsabilidade (único com formulário de criação no app), + visualização de Declaração Autônomo/Trabalho/Residência/União Estável, Procuração Detran/Simples (só leitura, sem formulário de criação ainda) |
| 📄 Currículo | ✅ lista de pedidos + ficha detalhada + impressão. **Pendente**: instalar o Apps Script (`scripts/apps_script_curriculo.gs`) pra ligar o formulário do Google direto no Supabase — já entregue ao usuário, não confirmado se foi instalado/testado |
| ✂️ Tirar Fundo, 📧 Email, 💬 WhatsApp | ✅ links externos reais |
| 📝 Declaração, 🩺 Exames, 🧾 Boletos, 🚓 Detran, 🏛️ Prefeitura, 🔍 Antecedentes, 💳 Cartões Lojas, 📞 Telefonia, 💡 Água/Luz, 🔧 Prestadora | ✅ sub-painéis com links reais extraídos da planilha (não têm backend próprio — são consultas em site de terceiros, não fazia sentido trazer pro banco) |

## O que ficou de fora (decisão consciente, não esquecimento)

- **Histórico completo de Currículo** (2.111 currículos já feitos, aba
  "REGISTRO CURRICULOS FEITOS") — só migramos os 4 pendentes. Motivo: volume
  e sensibilidade de PII (nome, nascimento, telefone, endereço, filhos de
  2 mil+ pessoas) — decidimos não migrar em massa sem necessidade concreta.
- **Locação de veículos, venda de veículo/imóvel, prestação de serviço,
  rifas** — módulos de contrato que existem na planilha mas não foram
  mapeados pro banco ainda.
- **Planejamento Familiar multi-mês** (projeção de orçamento
  Agosto→Dezembro com salário base por pessoa) — é planejamento manual, não
  dado transacional; decidimos não inventar a estrutura sem alinhar com o
  usuário. O que existe hoje (Resumo Loja x Família) é o saldo *atual*
  calculado ao vivo, não uma projeção futura.
- **Criação via app pra Declaração/Procuração** — hoje só visualização;
  criar novo ainda é só pelo Google Forms original.
- **Ícones customizados nos cards** — hoje é emoji; foi sugerido substituir
  por SVG de marca (verde/preto), decisão pendente do usuário.

## Coisas específicas que valem saber

- A categorização `LOJA`/`FAMILIA`/`MISTO` das 41 retiradas migradas foi
  inferida automaticamente pelo nome do destino (ex: "DESPESA BLACKOUT" →
  LOJA). Pode ter erros — é editável no app, vale o usuário revisar.
- `contratos.ativo_id` é NULLABLE (alterado de NOT NULL) pra suportar tipos
  de documento sem veículo.
- Senha do app é local por aparelho/navegador (localStorage) — abrir em
  aparelho novo pede pra criar de novo, não sincroniza.
- Formulário de Currículo tem colunas duplicadas (5x "INFORME O CURSO...")
  — como JSON usa a pergunta como chave, só o último curso preenchido
  sobrevive na migração. Não corrigido (dado pré-existente da planilha).

## Como continuar

1. Confirmar com o usuário se o Apps Script do Currículo foi instalado e
   testou (enviar 1 resposta de formulário → conferir se aparece no app).
2. Perguntar se querem os ícones SVG customizados nos cards.
3. Próximos módulos candidatos (perguntar prioridade): Locação de Veículos,
   Venda de Veículo/Imóvel, Prestação de Serviço, ou criação via app pra
   Declaração/Procuração.
4. Lembrar sempre de replicar qualquer mudança em `index.html` pro repo de
   produção (`dev-zeq/blackout`, pasta `paineldecontrole/`) — não é
   automático.
