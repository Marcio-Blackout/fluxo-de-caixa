/**
 * Script do Google Apps Script pra ligar o formulário de Currículo direto
 * no Supabase. Assim que um cliente envia o formulário, esse script roda
 * automaticamente e insere o pedido na tabela `curriculos` — aparece na
 * hora na tela de Currículo do Painel de Controle, sem precisar migrar
 * nada manualmente.
 *
 * COMO INSTALAR:
 * 1. Abra a planilha "PAINEL DE CONTROLE" no Google Sheets.
 * 2. Vá em Extensões > Apps Script.
 * 3. Apague o conteúdo do arquivo padrão (Código.gs) e cole este script inteiro.
 * 4. Salve (ícone de disquete).
 * 5. No menu de funções (dropdown ao lado do ícone de play), selecione
 *    "instalarGatilho" e clique em Executar (▶). Na primeira vez vai pedir
 *    autorização — aceite (é a sua própria conta Google, é seguro).
 * 6. Pronto. A partir de agora, toda resposta nova do formulário de
 *    Currículo cai direto no Supabase.
 *
 * Pra testar: preencha o formulário de Currículo uma vez e confira se
 * o pedido aparece no Painel de Controle, aba Currículo.
 */

// URL e chave pública do Supabase (a mesma usada no site — é segura pra
// ficar aqui, é a chave "publishable", feita pra ser usada no navegador).
const SUPABASE_URL = 'https://kihnavaovspdjnegcraj.supabase.co';
const SUPABASE_KEY = 'sb_publishable_h5AITv-_Fjmnq-xC6UC8xg_8CSMLoZK';
const NOME_DA_ABA_RESPOSTAS = 'CURRÍCULOS - RESPOSTAS';

function instalarGatilho() {
  // Remove gatilhos antigos desse tipo pra não duplicar.
  ScriptApp.getProjectTriggers().forEach(function (t) {
    if (t.getHandlerFunction() === 'aoEnviarCurriculo') {
      ScriptApp.deleteTrigger(t);
    }
  });
  const planilha = SpreadsheetApp.getActiveSpreadsheet();
  ScriptApp.newTrigger('aoEnviarCurriculo')
    .forSpreadsheet(planilha)
    .onFormSubmit()
    .create();
  Logger.log('Gatilho instalado com sucesso!');
}

function aoEnviarCurriculo(e) {
  try {
    // Só processa se a resposta foi na aba de Currículo (o formulário
    // desse painel pode ter várias abas de respostas diferentes).
    const nomeAba = e.range.getSheet().getName();
    if (nomeAba !== NOME_DA_ABA_RESPOSTAS) return;

    const respostas = e.namedValues; // { "Pergunta": ["Resposta"] }
    const pega = function (pergunta) {
      const v = respostas[pergunta];
      return v && v[0] ? v[0].toString().trim() : '';
    };
    const soDigitos = function (texto) {
      return texto.replace(/\D/g, '');
    };

    const nome = pega('SOMENTE O PRIMEIRO NOME');
    if (!nome) return; // resposta incompleta/teste, ignora

    const sobrenome = pega('RESTANTE DO SEU NOME (sobre nome)');
    const dataNascStr = pega('DATA DE NASCIMENTO'); // formato dd/mm/aaaa
    let dataNascimento = null;
    const partes = dataNascStr.split(/[\/\.\-]/);
    if (partes.length === 3) {
      dataNascimento = partes[2] + '-' + partes[1].padStart(2, '0') + '-' + partes[0].padStart(2, '0');
    }

    const dddSim = pega('O SEU TELEFONE PARA RECERBER LIGAÇÃO POSSUI O DDD 47? (codigo de área)') === 'SIM';
    const dddCustom = soDigitos(pega('E QUAL SERIA O CODIGO DE DDD DO SEU  TELEFONE?'));
    const numTel = soDigitos(pega('E QUAL O NUMERO DO SEU TELEFONE PARA LIGAÇÃO? (sem o DDD)'));
    const telefone = numTel ? (dddSim ? '47' : dddCustom) + numTel : null;

    const mesmoWpp = pega('ESSE NUMERO É O MESMO QUE VOCÊ ULTILIZA PARA WHATSASPP?').toLowerCase().indexOf('mesmo') !== -1;
    let whatsapp = null;
    if (mesmoWpp) {
      whatsapp = telefone;
    } else {
      const dddWpp = soDigitos(pega('E QUAL SERIA O CODIGO DE DDD DO NUMERO DE WHATSAPP?'));
      const numWpp = soDigitos(pega('E QUAL O NUMERO DO SEU WHATSAPP? (sem o DDD)'));
      whatsapp = numWpp ? dddWpp + numWpp : null;
    }

    // Guarda todas as respostas originais (escolaridade, cursos,
    // experiências, referências etc) sem perder nada.
    const dados = {};
    Object.keys(respostas).forEach(function (pergunta) {
      const valor = pega(pergunta);
      if (pergunta.trim() && valor) dados[pergunta] = valor;
    });

    const registro = {
      nome: nome,
      sobrenome: sobrenome || null,
      data_nascimento: dataNascimento,
      genero: pega('QUAL FOI O SEXO ATRIBUÍDO NO SEU NASCIMENTO?') || null,
      nacionalidade: pega('NACIONALIDADE') || null,
      estado_civil: pega('SEU ESTADO CIVIL?') || null,
      telefone: telefone,
      whatsapp: whatsapp,
      email: pega('QUAL O SEU EMAIL? ') || null,
      endereco: pega('QUAL O SEU ENDEREÇO ATUAL? ( Apenas o nome da Rua e numero da casa)') || null,
      bairro: pega('VOCÊ MORA EM QUAL BAIRRO?') || null,
      cidade: pega(' EM QUAL CIDADE? ') || null,
      estado: pega('QUAL ESTADO?') || null,
      status: 'PENDENTE',
      dados: dados,
      data_pedido: new Date().toISOString(),
    };

    const resposta = UrlFetchApp.fetch(SUPABASE_URL + '/rest/v1/curriculos', {
      method: 'post',
      contentType: 'application/json',
      headers: {
        apikey: SUPABASE_KEY,
        Authorization: 'Bearer ' + SUPABASE_KEY,
      },
      payload: JSON.stringify(registro),
      muteHttpExceptions: true,
    });

    Logger.log('Resposta do Supabase: ' + resposta.getResponseCode() + ' ' + resposta.getContentText());
  } catch (erro) {
    Logger.log('Erro ao enviar currículo pro Supabase: ' + erro);
  }
}
