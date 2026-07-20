// Português (BR) — tradução do mestre en.mjs.
export default {
  code: 'pt',
  hreflang: 'pt',
  dir: 'ltr',
  nativeName: 'Português',
  content: {
    title: 'Sobre o Aura OmniMesh — um protocolo de escambo local, sem servidores',
    metaDescription:
      'O que é o Aura OmniMesh, por que ele existe e como funciona: um protocolo aberto que encontra círculos de troca multilaterais entre celulares próximos — sem servidores, sem contas e sem internet.',
    kicker: 'Sobre',
    backHome: 'Início',
    langLabel: 'Idiomas',
    h1: 'Troca sem infraestrutura.',
    lede:
      'O Aura OmniMesh é um protocolo de troca aberto e local-first. Celulares na mesma sala se descobrem, publicam ofertas e necessidades assinadas e encontram círculos de troca fechados — ciclos em que cada pessoa dá uma coisa e recebe outra. Sem servidores, sem contas, sem internet.',
    whatIs: {
      label: 'Definição',
      h2: 'O que é o Aura OmniMesh',
      paras: [
        'O Aura OmniMesh é um protocolo e um aplicativo gratuito para troca direta entre pessoas fisicamente próximas. Cada dispositivo publica breves <em>intenções</em> assinadas — uma oferta (“dou aulas de violão”) ou uma necessidade (“preciso de ajuda na mudança”) — e um pequeno modelo de IA rodando no próprio celular as combina em círculos fechados de três a sete participantes.',
        'Tudo aquilo para que um marketplace normalmente precisa de uma empresa — identidade, matching, confiança, histórico — os próprios dispositivos fazem, criptograficamente. O resultado é uma rede de trocas que continua funcionando onde o dinheiro, os bancos ou a internet não funcionam.',
      ],
    },
    why: {
      label: 'Motivação',
      h2: 'Por que ele existe',
      paras: [
        'O escambo direto costuma fracassar por uma razão matemática: quem tem o que você precisa raramente precisa do que você tem. Os economistas chamam isso de <em>dupla coincidência de desejos</em>. Os círculos resolvem o problema: A ensina B, B empresta a C, C abastece A — o ciclo se fecha mesmo que nenhum par combine diretamente.',
        'A segunda razão é a independência. Todo marketplace existente roda sobre servidores e contas — uma empresa que pode sair do ar, censurar anúncios, aumentar taxas ou coletar dados. O OmniMesh remove o intermediário como fato arquitetural, não como promessa: simplesmente não existe servidor para confiar, intimar ou desligar.',
      ],
    },
    how: {
      label: 'Protocolo',
      h2: 'Como funciona',
      steps: [
        {
          t: 'Identidade é uma chave, não uma conta.',
          d: 'Na primeira execução, o dispositivo gera um par de chaves Ed25519. A chave privada nunca sai do dispositivo. Sem cadastro, sem e-mail, sem número de telefone — sua chave é a sua identidade.',
        },
        {
          t: 'Intenções são texto assinado.',
          d: 'Você publica ofertas e necessidades em frases curtas. Um modelo de linguagem multilíngue rodando no celular converte cada uma em um vetor semântico, então o matching funciona entre idiomas diferentes.',
        },
        {
          t: 'Os dispositivos trocam um registro compartilhado.',
          d: 'Celulares próximos trocam registros de operações assinadas por Bluetooth LE, Wi-Fi Direct ou rede local compartilhada. O registro é um CRDT: independente de ordem e tolerante a partições, todos os dispositivos convergem para o mesmo estado sem coordenador.',
        },
        {
          t: 'Tudo é verificado, nada é presumido.',
          d: 'Cada operação é checada: assinatura, autoria, regras do protocolo. Uma assinatura válida sob a chave errada é rejeitada mesmo assim — só o dono de uma intenção pode mudar seu status. A reputação nunca é aceita da rede; cada dispositivo a recalcula localmente a partir de trocas concluídas e assinadas.',
        },
        {
          t: 'Um buscador procura ciclos fechados.',
          d: 'O dispositivo varre o grafo local de ofertas e necessidades em busca de círculos de 3 a 7 participantes. A busca é determinística: os mesmos dados produzem os mesmos círculos em qualquer celular.',
        },
        {
          t: 'O círculo trava, as pessoas trocam, o histórico fica assinado.',
          d: 'Cada participante trava a sua etapa; quando todas estão travadas, o círculo é confirmado. As pessoas se encontram, trocam e marcam o cumprimento. Cada estágio é uma operação assinada — desistir quebra o círculo de forma visível para todos.',
        },
      ],
    },
    solves: {
      label: 'Problemas',
      h2: 'O que ele resolve',
      items: [
        '<strong>Troca quando o dinheiro está fraco ou ausente</strong> — inflação, escassez de dinheiro vivo, comunidades sem banco.',
        '<strong>Marketplaces sem taxas, contas ou servidores</strong> — nada a pagar, ninguém com quem se cadastrar.',
        '<strong>Funcionamento totalmente offline</strong> — desastres, apagões, áreas remotas, festivais, embarcações, acampamentos.',
        '<strong>Privacidade por construção</strong> — nada sai do dispositivo além do que você publica explicitamente aos vizinhos.',
        '<strong>Matching multilateral</strong> — os ciclos que o escambo entre duas pessoas matematicamente não consegue fechar.',
      ],
    },
    who: {
      label: 'Público',
      h2: 'Para quem é',
      items: [
        'Bairros, vilarejos e redes de apoio mútuo que querem um mural de trocas local sem operador.',
        'Coworkings, campi, conferências e festivais — espaços densos, cheios de habilidades complementares.',
        'Comunidades em zonas de desastre ou apagão, onde a independência da infraestrutura é o próprio objetivo.',
        'Pessoas que se recusam a entregar seu histórico de trocas a uma empresa em troca de um serviço de matching.',
        'Pesquisadores e desenvolvedores de sistemas peer-to-peer — o protocolo e o código estão abertos no GitHub.',
      ],
    },
    principles: {
      label: 'Princípios',
      h2: 'Princípios de projeto',
      items: [
        '<strong>Local-first.</strong> Seus dados vivem num banco embutido no seu dispositivo. O registro assinado é a fonte da verdade; apagar o app apaga os dados.',
        '<strong>Coleta zero.</strong> Sem analytics, sem telemetria, sem contas. Não existe backend de empresa para onde enviar qualquer coisa.',
        '<strong>Fail-closed.</strong> O que não pode ser verificado é rejeitado — nunca adivinhado, nunca presumido.',
        '<strong>Determinismo.</strong> Todos os dispositivos calculam os mesmos matchings a partir dos mesmos dados; a correção não depende de quem roda o código.',
        '<strong>Honestidade sobre os limites.</strong> O protocolo documenta o que ele não faz, em linguagem clara, logo abaixo.',
      ],
    },
    limits: {
      label: 'Limites',
      h2: 'O que ele não é',
      items: [
        'Não é um sistema de pagamentos: sem tokens, sem saldos, sem custódia. A versão 1 é escambo puro de bens, serviços e tempo.',
        'Não é global: o alcance é limitado pelo rádio e pelas redes locais. É uma rede em escala de bairro, por projeto.',
        'Não é à prova de Sybil: qualquer um pode criar uma chave. Reputação se ganha com círculos concluídos, nunca é concedida.',
        'iOS e Android não pareiam diretamente pelo rádio (as APIs das plataformas diferem); o tráfego entre sistemas passa por uma ponte de rede local.',
      ],
    },
    faq: {
      h2: 'Perguntas frequentes',
      items: [
        {
          q: 'É gratuito?',
          a: 'Sim — gratuito e de código aberto, sem anúncios e sem nada à venda. Não há servidores para sustentar, então não há o que monetizar.',
        },
        {
          q: 'Quais idiomas o matching entende?',
          a: 'O modelo no dispositivo é multilíngue: uma oferta escrita num idioma pode combinar com uma necessidade escrita em outro. Inglês e russo estão validados hoje; a família de modelos cobre dezenas de idiomas.',
        },
        {
          q: 'Posso construir outra coisa sobre o protocolo?',
          a: 'Sim. As camadas — transporte, registro CRDT assinado, matcher semântico — são separáveis, e o código-fonte é público no GitHub, no repositório do projeto.',
        },
      ],
    },
    footerTag: 'AURA OMNIMESH — um protocolo de troca local-first. Zero servidores por projeto.',
  },
};
