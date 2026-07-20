// English — canonical master. Every other about_content/*.mjs is a
// translation of THIS file; change meaning here first.
export default {
  code: '', // served at /about/
  hreflang: 'en',
  dir: 'ltr',
  nativeName: 'English',
  content: {
    title: 'About Aura OmniMesh — a serverless, local-first barter protocol',
    metaDescription:
      'What Aura OmniMesh is, why it exists, and how it works: an open protocol that finds multilateral barter rings between nearby phones — no servers, no accounts, no internet required.',
    kicker: 'About',
    backHome: 'Home',
    langLabel: 'Languages',
    h1: 'Exchange without infrastructure.',
    lede:
      'Aura OmniMesh is an open, local-first exchange protocol. Phones in the same room discover each other, publish signed offers and needs, and find closed barter rings — loops where everyone gives one thing and receives one thing. No servers, no accounts, no internet.',
    whatIs: {
      label: 'Definition',
      h2: 'What Aura OmniMesh is',
      paras: [
        'Aura OmniMesh is a protocol and a free app for direct exchange between people who are physically near each other. Each device publishes short signed <em>intents</em> — an offer (“I teach guitar”) or a need (“I need help moving”) — and a small AI model running on the phone itself matches them into closed rings of three to seven participants.',
        'Everything a marketplace normally needs a company for — identity, matching, trust, history — is done by the devices themselves, cryptographically. The result is an exchange network that keeps working where money, banks, or the internet do not.',
      ],
    },
    why: {
      label: 'Motivation',
      h2: 'Why it exists',
      paras: [
        'Direct barter usually fails for a mathematical reason: the person who has what you need rarely needs what you have. Economists call it the <em>double coincidence of wants</em>. Rings solve it: A teaches B, B lends to C, C supplies A — the loop closes even though no pair matches directly.',
        'The second reason is independence. Every existing marketplace runs on servers and accounts — a company that can go offline, censor listings, raise fees, or harvest data. OmniMesh removes the middleman as an architectural fact, not as a promise: there is simply no server to trust, subpoena, or shut down.',
      ],
    },
    how: {
      label: 'Protocol',
      h2: 'How it works',
      steps: [
        {
          t: 'Identity is a key, not an account.',
          d: 'On first launch the device generates an Ed25519 keypair. The private key never leaves the device. No registration, no e-mail, no phone number — your key is your identity.',
        },
        {
          t: 'Intents are signed text.',
          d: 'You publish offers and needs as short sentences. A multilingual language model running on the phone converts each one into a semantic vector, so matching works across languages.',
        },
        {
          t: 'Devices gossip a shared log.',
          d: 'Nearby phones exchange signed operation logs over Bluetooth LE, Wi-Fi Direct, or a shared local network. The log is a CRDT: order-independent and partition-tolerant, so every device converges to the same state without a coordinator.',
        },
        {
          t: 'Everything is verified, nothing is assumed.',
          d: 'Each operation is checked: signature, authorship, protocol rules. A valid signature under the wrong key is still rejected — only an intent’s owner can change its status. Reputation is never accepted from the network; each device recomputes it locally from signed completed exchanges.',
        },
        {
          t: 'A matcher searches for closed loops.',
          d: 'The device scans the local graph of offers and needs for rings of 3–7 participants. The search is deterministic: the same data produces the same rings on every phone.',
        },
        {
          t: 'The ring locks, people exchange, history is signed.',
          d: 'Each participant locks their step; when all steps are locked the ring is confirmed. People meet, exchange, and mark fulfilment. Every stage is a signed operation — withdrawing visibly breaks the ring for everyone.',
        },
      ],
    },
    solves: {
      label: 'Problems',
      h2: 'What it solves',
      items: [
        '<strong>Exchange when money is weak or absent</strong> — inflation, cash shortages, unbanked communities.',
        '<strong>Marketplaces without fees, accounts, or servers</strong> — nothing to pay, nobody to register with.',
        '<strong>Working fully offline</strong> — disasters, blackouts, remote areas, festivals, ships, camps.',
        '<strong>Privacy by construction</strong> — nothing leaves the device except what you explicitly publish to nearby peers.',
        '<strong>Multilateral matching</strong> — the loops that two-person barter mathematically cannot close.',
      ],
    },
    who: {
      label: 'Audience',
      h2: 'Who it is for',
      items: [
        'Neighbourhoods, villages, and mutual-aid networks that want a local exchange board with no operator.',
        'Coworkings, campuses, conferences, and festivals — dense rooms full of complementary skills.',
        'Communities in disaster or blackout zones, where independence from infrastructure is the point.',
        'People who refuse to hand a company their trade history in exchange for a matching service.',
        'Researchers and developers of peer-to-peer systems — the protocol and code are open on GitHub.',
      ],
    },
    principles: {
      label: 'Principles',
      h2: 'Design principles',
      items: [
        '<strong>Local-first.</strong> Your data lives in an embedded database on your device. The signed log is the source of truth; deleting the app deletes the data.',
        '<strong>Zero collection.</strong> No analytics, no telemetry, no accounts. There is no company backend to send anything to.',
        '<strong>Fail-closed.</strong> Whatever cannot be verified is rejected — never guessed, never assumed.',
        '<strong>Determinism.</strong> Every device computes identical matches from identical data; correctness does not depend on who runs the code.',
        '<strong>Honesty about limits.</strong> The protocol documents what it does not do, in plain language, below.',
      ],
    },
    limits: {
      label: 'Boundaries',
      h2: 'What it is not',
      items: [
        'Not a payment system: no tokens, no balances, no custody. Version 1 is pure barter of goods, services, and time.',
        'Not global: range is bounded by radio and local networks. It is a neighbourhood-scale network by design.',
        'Not Sybil-proof: anyone can create a key. Reputation is earned from completed rings, never granted.',
        'iOS and Android do not pair directly over the air (platform APIs differ); cross-OS traffic goes through a local network bridge.',
      ],
    },
    faq: {
      h2: 'Frequently asked',
      items: [
        {
          q: 'Is it free?',
          a: 'Yes — free and open source, with no ads and nothing sold. There are no servers to fund, so there is nothing to monetise.',
        },
        {
          q: 'Which languages does matching understand?',
          a: 'The on-device model is multilingual: an offer written in one language can match a need written in another. English and Russian are validated today; the model family covers dozens of languages.',
        },
        {
          q: 'Can I build something else on the protocol?',
          a: 'Yes. The layers — transport, signed CRDT log, semantic matcher — are separable, and the source code is public on GitHub under the project repository.',
        },
      ],
    },
    footerTag: 'AURA OMNIMESH — a local-first exchange protocol. Zero servers by design.',
  },
};
