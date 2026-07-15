// Three synthetic mesh nodes (A, B, C) driving a full ring lifecycle
// against a running core node's bridge (default ws://localhost:7411, use
// `adb forward tcp:7411 tcp:7411` for an emulator):
//
//   node tool/ring_probe.mjs create   -> 3 offers + 3 needs, cycle closes
//   node tool/ring_probe.mjs lock     -> every node locks its own intents
//   node tool/ring_probe.mjs satisfy  -> every node satisfies its own
//
// Identities and intent uuids persist in ring_probe_state.json next to
// this script so the three stages sign as the same authors. Vectors are
// crafted one-hot axes so the ring A->B->C->A closes deterministically
// (same construction as test/determinism_test.dart).
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DIMS = 384;
const URL_WS = process.env.BRIDGE_URL || 'ws://localhost:7411';
const stage = process.argv[2];
if (!['create', 'lock', 'satisfy'].includes(stage)) {
  console.error('usage: node ring_probe.mjs <create|lock|satisfy>');
  process.exit(64);
}

const stateFile = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  'ring_probe_state.json',
);

const hex = (buf) => Buffer.from(buf).toString('hex');

function newNode() {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  return {
    pub: hex(publicKey.export({ format: 'der', type: 'spki' }).subarray(-32)),
    privPkcs8: hex(privateKey.export({ format: 'der', type: 'pkcs8' })),
    offerUuid: crypto.randomUUID(),
    needUuid: crypto.randomUUID(),
  };
}

let state;
if (fs.existsSync(stateFile) && stage !== 'create') {
  state = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
} else {
  state = { nodes: [newNode(), newNode(), newNode()] };
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
}
const nodes = state.nodes;

const keyOf = (n) =>
  crypto.createPrivateKey({
    key: Buffer.from(n.privPkcs8, 'hex'),
    format: 'der',
    type: 'pkcs8',
  });

const crdtPreimage = (payloadJson, clock) => {
  const le = Buffer.alloc(8);
  let v = BigInt(clock);
  for (let i = 0; i < 8; i++) {
    le[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return Buffer.concat([Buffer.from(payloadJson, 'utf8'), le]);
};

const signedLog = (node, targetUuid, payloadObj, clock) => {
  const payload = JSON.stringify(payloadObj);
  return {
    txId: crypto.randomUUID(),
    target: targetUuid,
    sig: hex(crypto.sign(null, crdtPreimage(payload, clock), keyOf(node))),
    clock,
    op: payload,
  };
};

const oneHot = (axis) => {
  const v = Array(DIMS).fill(0);
  v[axis] = 1;
  return v;
};

// canonicalId per BarterRing: offer uuids rotated so the lexicographically
// smallest starts, joined with '>'.
const canonicalRingId = () => {
  const uuids = nodes.map((n) => n.offerUuid);
  let best = 0;
  for (let i = 1; i < uuids.length; i++) {
    if (uuids[i] < uuids[best]) best = i;
  }
  return [...uuids.slice(best), ...uuids.slice(0, best)].join('>');
};

const logs = [];
const aliases = ['probe-alpha', 'probe-beta', 'probe-gamma'];
const gives = [
  'offer: dart tutoring (probe A)',
  'offer: scooter loan (probe B)',
  'offer: fresh groceries (probe C)',
];

if (stage === 'create') {
  nodes.forEach((node, i) => {
    // Ring A->B->C->A: node i offers axis i; node i needs axis (i+2)%3,
    // i.e. the previous node's offer axis.
    const mk = (uuid, direction, axis, rawText) =>
      logs.push(
        signedLog(
          node,
          uuid,
          {
            op: 'create_intent',
            author: node.pub,
            intent: {
              intentUuid: uuid,
              originNodeKey: node.pub,
              category: 'peer_exchange',
              direction,
              rawText,
              vector: oneHot(axis),
              quantity: 1,
              epochMs: Date.now(),
            },
          },
          1,
        ),
      );
    mk(node.offerUuid, 'offer', i, gives[i]);
    mk(node.needUuid, 'need', (i + 2) % 3, `need: ${gives[(i + 2) % 3].slice(7)}`);
  });
} else {
  const ringId = canonicalRingId();
  const opName = stage === 'lock' ? 'lock_intent' : 'satisfy_intent';
  const status = stage === 'lock' ? 'locked_in_loop' : 'satisfied';
  const clock = stage === 'lock' ? 2 : 3;
  for (const node of nodes) {
    for (const uuid of [node.offerUuid, node.needUuid]) {
      logs.push(
        signedLog(
          node,
          uuid,
          { op: opName, intentUuid: uuid, ringId, status, author: node.pub },
          clock,
        ),
      );
    }
  }
  console.log('ringId:', ringId);
}

const nonce = crypto.randomBytes(32);
const ws = new WebSocket(URL_WS);
const deadline = setTimeout(() => {
  console.log('RESULT: TIMEOUT');
  process.exit(2);
}, 15000);

ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: 'helloChallenge',
      nonce: hex(nonce),
      node: { publicKey: nodes[0].pub, alias: aliases[0] },
    }),
  );

const ourTxIds = new Set(logs.map((l) => l.txId));
ws.onmessage = (event) => {
  const frame = JSON.parse(event.data);
  if (frame.type === 'helloResponse') {
    ws.send(JSON.stringify({ type: 'broadcast', logs }));
    console.log(`sent ${logs.length} signed ${stage} op(s)`);
    return;
  }
  if (frame.type === 'delta') {
    // Exit only on the relay echo of OUR ops — closing right after send
    // races the socket's write buffer and the batch can be discarded.
    const acked = (frame.logs || []).filter((l) => ourTxIds.has(l.txId));
    if (acked.length > 0) {
      console.log(`delta echo: ${acked.length} of our op(s) ingested`);
      console.log('RESULT: ACKED');
      clearTimeout(deadline);
      ws.close();
      process.exit(0);
    }
  }
};
ws.onerror = (e) => console.log('socket error:', e.message || String(e));
