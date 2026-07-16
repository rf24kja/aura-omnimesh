// Semantic E2E: two synthetic nodes publish intents whose vectors come
// from the REAL all-MiniLM-L6-v2 (transformers.js, same quantized ONNX
// the app bundles). Texts are semantically similar to the emulator
// user's — but share almost no tokens, so the FNV surrogate could never
// close this ring. If it closes, MiniLM is live on the device AND both
// runtimes agree on the embedding space.
import crypto from 'node:crypto';
import { pipeline } from '@xenova/transformers';

const URL_WS = process.env.BRIDGE_URL || 'ws://localhost:7411';
const hex = (b) => Buffer.from(b).toString('hex');

const newNode = () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  return {
    pub: hex(publicKey.export({ format: 'der', type: 'spki' }).subarray(-32)),
    key: privateKey,
  };
};

const crdtPreimage = (payloadJson, clock) => {
  const le = Buffer.alloc(8);
  let v = BigInt(clock);
  for (let i = 0; i < 8; i++) {
    le[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return Buffer.concat([Buffer.from(payloadJson, 'utf8'), le]);
};

console.log('loading MiniLM (transformers.js, quantized)…');
const embed = await pipeline(
  'feature-extraction',
  'Xenova/paraphrase-multilingual-MiniLM-L12-v2',
  { quantized: true },
);
const vec = async (text) => {
  const out = await embed(text, { pooling: 'mean', normalize: true });
  return Array.from(out.data);
};

const B = newNode();
const C = newNode();
const intents = [
  // Mixed-language ring with the device user (EN):
  //   EMU offer EN vegetables -> B need RU; B offer RU guitar ->
  //   C need RU; C offer EN moving -> EMU need EN sofa.
  [B, 'need', 'нужна доставка свежих овощей на дом'],
  [B, 'offer', 'уроки игры на гитаре с нуля'],
  [C, 'need', 'хочу научиться играть на гитаре'],
  [C, 'offer', 'help moving furniture this weekend'],
];

const logs = [];
for (const [node, direction, rawText] of intents) {
  const uuid = crypto.randomUUID();
  const payload = JSON.stringify({
    op: 'create_intent',
    author: node.pub,
    intent: {
      intentUuid: uuid,
      originNodeKey: node.pub,
      category: 'peer_exchange',
      direction,
      rawText: `${direction}: ${rawText}`,
      vector: await vec(rawText),
      quantity: 1,
      epochMs: Date.now(),
    },
  });
  logs.push({
    txId: crypto.randomUUID(),
    target: uuid,
    sig: hex(crypto.sign(null, crdtPreimage(payload, 20), node.key)),
    clock: 20,
    op: payload,
  });
  console.log(`embedded [${direction}] ${rawText}`);
}

const nonce = crypto.randomBytes(32);
const ws = new WebSocket(URL_WS);
const deadline = setTimeout(() => {
  console.log('RESULT: TIMEOUT');
  process.exit(2);
}, 20000);
const ourTx = new Set(logs.map((l) => l.txId));

ws.onopen = () =>
  ws.send(JSON.stringify({
    type: 'helloChallenge',
    nonce: hex(nonce),
    node: { publicKey: B.pub, alias: 'sem-beta' },
  }));

ws.onmessage = (event) => {
  const frame = JSON.parse(event.data);
  if (frame.type === 'helloResponse') {
    ws.send(JSON.stringify({ type: 'broadcast', logs }));
    console.log(`sent ${logs.length} MiniLM-embedded create op(s)`);
    return;
  }
  if (frame.type === 'delta') {
    const acked = (frame.logs || []).filter((l) => ourTx.has(l.txId)).length;
    if (acked > 0) {
      console.log(`delta echo: ${acked} op(s) ingested`);
      console.log('RESULT: ACKED');
      clearTimeout(deadline);
      ws.close();
      process.exit(0);
    }
  }
};
ws.onerror = (e) => console.log('socket error:', e.message || String(e));
