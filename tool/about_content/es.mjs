// Español — traducción del maestro en.mjs.
export default {
  code: 'es',
  hreflang: 'es',
  dir: 'ltr',
  nativeName: 'Español',
  content: {
    title: 'Acerca de Aura OmniMesh — un protocolo de trueque local, sin servidores',
    metaDescription:
      'Qué es Aura OmniMesh, por qué existe y cómo funciona: un protocolo abierto que encuentra círculos de trueque multilaterales entre teléfonos cercanos — sin servidores, sin cuentas y sin internet.',
    kicker: 'Acerca de',
    backHome: 'Inicio',
    langLabel: 'Idiomas',
    h1: 'Intercambio sin infraestructura.',
    lede:
      'Aura OmniMesh es un protocolo de intercambio abierto y local-first. Los teléfonos en una misma sala se descubren entre sí, publican ofertas y necesidades firmadas, y encuentran círculos de trueque cerrados: bucles donde cada persona da una cosa y recibe otra. Sin servidores, sin cuentas, sin internet.',
    whatIs: {
      label: 'Definición',
      h2: 'Qué es Aura OmniMesh',
      paras: [
        'Aura OmniMesh es un protocolo y una aplicación gratuita para el intercambio directo entre personas físicamente cercanas. Cada dispositivo publica breves <em>intenciones</em> firmadas — una oferta («doy clases de guitarra») o una necesidad («necesito ayuda con una mudanza») — y un pequeño modelo de IA que corre en el propio teléfono las combina en círculos cerrados de tres a siete participantes.',
        'Todo aquello para lo que un mercado normalmente necesita una empresa — identidad, emparejamiento, confianza, historial — lo hacen los propios dispositivos, criptográficamente. El resultado es una red de intercambio que sigue funcionando donde el dinero, los bancos o internet no llegan.',
      ],
    },
    why: {
      label: 'Motivación',
      h2: 'Por qué existe',
      paras: [
        'El trueque directo suele fracasar por una razón matemática: quien tiene lo que tú necesitas rara vez necesita lo que tú tienes. Los economistas lo llaman la <em>doble coincidencia de necesidades</em>. Los círculos lo resuelven: A enseña a B, B presta a C, C abastece a A — el bucle se cierra aunque ningún par coincida directamente.',
        'La segunda razón es la independencia. Todo mercado existente funciona sobre servidores y cuentas: una empresa que puede caerse, censurar anuncios, subir comisiones o recolectar datos. OmniMesh elimina al intermediario como hecho arquitectónico, no como promesa: sencillamente no hay servidor en el que confiar, que citar judicialmente o que apagar.',
      ],
    },
    how: {
      label: 'Protocolo',
      h2: 'Cómo funciona',
      steps: [
        {
          t: 'La identidad es una clave, no una cuenta.',
          d: 'En el primer arranque el dispositivo genera un par de claves Ed25519. La clave privada nunca sale del dispositivo. Sin registro, sin correo, sin número de teléfono: tu clave es tu identidad.',
        },
        {
          t: 'Las intenciones son texto firmado.',
          d: 'Publicas ofertas y necesidades como frases cortas. Un modelo de lenguaje multilingüe que corre en el teléfono convierte cada una en un vector semántico, de modo que el emparejamiento funciona entre idiomas distintos.',
        },
        {
          t: 'Los dispositivos comparten un registro común.',
          d: 'Los teléfonos cercanos intercambian registros de operaciones firmadas por Bluetooth LE, Wi-Fi Direct o una red local compartida. El registro es un CRDT: independiente del orden y tolerante a particiones, así que todos los dispositivos convergen al mismo estado sin coordinador.',
        },
        {
          t: 'Todo se verifica, nada se supone.',
          d: 'Cada operación se comprueba: firma, autoría, reglas del protocolo. Una firma válida bajo la clave equivocada se rechaza igualmente — solo el dueño de una intención puede cambiar su estado. La reputación nunca se acepta de la red; cada dispositivo la recalcula localmente a partir de intercambios completados y firmados.',
        },
        {
          t: 'Un buscador encuentra los bucles cerrados.',
          d: 'El dispositivo explora el grafo local de ofertas y necesidades buscando círculos de 3 a 7 participantes. La búsqueda es determinista: los mismos datos producen los mismos círculos en cualquier teléfono.',
        },
        {
          t: 'El círculo se bloquea, la gente intercambia, la historia queda firmada.',
          d: 'Cada participante bloquea su paso; cuando todos están bloqueados, el círculo queda confirmado. Las personas se encuentran, intercambian y marcan el cumplimiento. Cada etapa es una operación firmada: retirarse rompe el círculo de forma visible para todos.',
        },
      ],
    },
    solves: {
      label: 'Problemas',
      h2: 'Qué resuelve',
      items: [
        '<strong>Intercambio cuando el dinero falla o falta</strong> — inflación, escasez de efectivo, comunidades sin banca.',
        '<strong>Mercados sin comisiones, cuentas ni servidores</strong> — nada que pagar, nadie ante quien registrarse.',
        '<strong>Funcionamiento totalmente sin conexión</strong> — desastres, apagones, zonas remotas, festivales, barcos, campamentos.',
        '<strong>Privacidad por construcción</strong> — nada sale del dispositivo salvo lo que publicas explícitamente a los pares cercanos.',
        '<strong>Emparejamiento multilateral</strong> — los bucles que el trueque entre dos personas matemáticamente no puede cerrar.',
      ],
    },
    who: {
      label: 'Audiencia',
      h2: 'Para quién es',
      items: [
        'Barrios, pueblos y redes de apoyo mutuo que quieren un tablón de intercambio local sin operador.',
        'Coworkings, campus, conferencias y festivales: salas densas llenas de habilidades complementarias.',
        'Comunidades en zonas de desastre o apagón, donde la independencia de la infraestructura es el objetivo.',
        'Personas que se niegan a entregar su historial de intercambios a una empresa a cambio de un servicio de emparejamiento.',
        'Investigadores y desarrolladores de sistemas peer-to-peer: el protocolo y el código están abiertos en GitHub.',
      ],
    },
    principles: {
      label: 'Principios',
      h2: 'Principios de diseño',
      items: [
        '<strong>Local-first.</strong> Tus datos viven en una base de datos integrada en tu dispositivo. El registro firmado es la fuente de verdad; borrar la app borra los datos.',
        '<strong>Cero recolección.</strong> Sin analítica, sin telemetría, sin cuentas. No existe backend de empresa al que enviar nada.',
        '<strong>Fallo cerrado.</strong> Lo que no se puede verificar se rechaza — nunca se adivina, nunca se supone.',
        '<strong>Determinismo.</strong> Todos los dispositivos calculan los mismos emparejamientos con los mismos datos; la corrección no depende de quién ejecute el código.',
        '<strong>Honestidad sobre los límites.</strong> El protocolo documenta lo que no hace, en lenguaje claro, aquí abajo.',
      ],
    },
    limits: {
      label: 'Límites',
      h2: 'Lo que no es',
      items: [
        'No es un sistema de pagos: sin tokens, sin saldos, sin custodia. La versión 1 es trueque puro de bienes, servicios y tiempo.',
        'No es global: el alcance está limitado por la radio y las redes locales. Es una red a escala de barrio, por diseño.',
        'No es resistente a Sybil: cualquiera puede crear una clave. La reputación se gana con círculos completados, nunca se otorga.',
        'iOS y Android no se emparejan directamente por radio (las API de plataforma difieren); el tráfico entre sistemas pasa por un puente de red local.',
      ],
    },
    faq: {
      h2: 'Preguntas frecuentes',
      items: [
        {
          q: '¿Es gratis?',
          a: 'Sí: gratuito y de código abierto, sin anuncios y sin nada a la venta. No hay servidores que financiar, así que no hay nada que monetizar.',
        },
        {
          q: '¿Qué idiomas entiende el emparejamiento?',
          a: 'El modelo en el dispositivo es multilingüe: una oferta escrita en un idioma puede coincidir con una necesidad escrita en otro. Hoy están validados inglés y ruso; la familia de modelos cubre docenas de idiomas.',
        },
        {
          q: '¿Puedo construir otra cosa sobre el protocolo?',
          a: 'Sí. Las capas — transporte, registro CRDT firmado, emparejador semántico — son separables, y el código fuente es público en GitHub, en el repositorio del proyecto.',
        },
      ],
    },
    footerTag: 'AURA OMNIMESH — un protocolo de intercambio local-first. Cero servidores por diseño.',
  },
};
