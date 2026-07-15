// Protocol-level Light Client probe for the Aura OmniMesh bridge.
// Speaks the exact wire protocol of WebSocketLightClientTransport:
//  1. helloChallenge{nonce, node} -> helloResponse{publicKey, signature}
//     with Ed25519 verification over "aura-omnimesh/bridge-hello/v1"||0x00||nonce
//  2. broadcast{logs:[signed create_intent]} -> expects delta echo /
//     materialization on the core node.
import crypto from 'node:crypto';

const DIMS = 384;
const url = 'ws://localhost:7411';

const hex = (buf) => Buffer.from(buf).toString('hex');
const fromHex = (s) => Buffer.from(s, 'hex');

// Raw ed25519 public key -> DER SPKI for node:crypto.
const spki = (raw32) =>
  crypto.createPublicKey({
    key: Buffer.concat([fromHex('302a300506032b6570032100'), raw32]),
    format: 'der',
    type: 'spki',
  });

// Our light-client identity (real keypair — ops must verify on the node).
const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
const rawPub = publicKey
  .export({ format: 'der', type: 'spki' })
  .subarray(-32);
const myKeyHex = hex(rawPub);

const preimageHello = (nonce) =>
  Buffer.concat([
    Buffer.from('aura-omnimesh/bridge-hello/v1', 'utf8'),
    Buffer.from([0]),
    nonce,
  ]);

const crdtPreimage = (payloadJson, clock) => {
  const le = Buffer.alloc(8);
  let v = BigInt(clock);
  for (let i = 0; i < 8; i++) {
    le[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return Buffer.concat([Buffer.from(payloadJson, 'utf8'), le]);
};

const uuid = crypto.randomUUID();
const txId = crypto.randomUUID();
const vector = Array(DIMS).fill(0);
vector[0] = 1;
const payload = JSON.stringify({
  op: 'create_intent',
  author: myKeyHex,
  intent: {
    intentUuid: uuid,
    originNodeKey: myKeyHex,
    category: 'peer_exchange',
    direction: 'offer',
    rawText: 'offer: e2e probe from web light client',
    vector,
    quantity: 1,
    epochMs: Date.now(),
  },
});
const clock = 1;
const opSignature = hex(
  crypto.sign(null, crdtPreimage(payload, clock), privateKey),
);

const nonce = crypto.randomBytes(32);
const ws = new WebSocket(url);
const deadline = setTimeout(() => {
  console.log('RESULT: TIMEOUT');
  process.exit(2);
}, 15000);

ws.onopen = () => {
  console.log('socket open ->', url);
  ws.send(
    JSON.stringify({
      type: 'helloChallenge',
      nonce: hex(nonce),
      node: { publicKey: myKeyHex, alias: 'probe-light-client' },
    }),
  );
};

let handshakeDone = false;
ws.onmessage = (event) => {
  const frame = JSON.parse(event.data);
  if (frame.type === 'helloResponse' && !handshakeDone) {
    const ok = crypto.verify(
      null,
      preimageHello(nonce),
      spki(fromHex(frame.publicKey)),
      fromHex(frame.signature),
    );
    console.log('helloResponse from core node', frame.publicKey.slice(0, 16) + '…', 'alias:', frame.alias);
    console.log('ed25519 handshake signature valid:', ok);
    if (!ok) {
      console.log('RESULT: HANDSHAKE_INVALID');
      process.exit(1);
    }
    handshakeDone = true;
    console.log('sending signed create_intent', uuid);
    ws.send(
      JSON.stringify({
        type: 'broadcast',
        logs: [
          {
            txId,
            target: uuid,
            sig: opSignature,
            clock,
            op: payload,
          },
        ],
      }),
    );
    return;
  }
  if (frame.type === 'delta') {
    const echoed = (frame.logs || []).some((l) => l.txId === txId);
    console.log('delta frame received; contains our tx:', echoed);
    if (echoed) {
      console.log('RESULT: E2E_OK');
      clearTimeout(deadline);
      ws.close();
      process.exit(0);
    }
  }
  if (frame.type === 'nodeState') {
    console.log('nodeState:', JSON.stringify(frame.node), frame.state);
  }
};

ws.onerror = (e) => {
  console.log('socket error:', e.message || String(e));
};
ws.onclose = () => {
  if (!handshakeDone) {
    console.log('RESULT: CLOSED_BEFORE_HANDSHAKE');
    process.exit(1);
  }
};
