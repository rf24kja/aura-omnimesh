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
if (!['create', 'lock', 'satisfy', 'fnv-create', 'fnv-ride'].includes(stage)) {
  console.error(
    'usage: node ring_probe.mjs <create|lock|satisfy|fnv-create|fnv-ride>',
  );
  process.exit(64);
}
const isFnv = stage.startsWith('fnv-');

const stateFile = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  isFnv ? 'ring_probe_state_fnv.json' : 'ring_probe_state.json',
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

// Port of HashingEmbeddingService (lib/main.dart): FNV-1a 32-bit over
// UTF-16 units, unigrams + bigrams, signed feature hashing, L2 norm.
// Math.imul keeps the multiply in 32-bit like Dart's & 0xFFFFFFFF mask.
const fnv1a = (s) => {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
};

const fnvEmbed = (input) => {
  const vector = Array(DIMS).fill(0);
  const tokens = input
    .toLowerCase()
    .split(/[^a-zа-я0-9]+/)
    .filter((t) => t.length > 1);
  const accumulate = (feature) => {
    const h = fnv1a(feature);
    vector[h % DIMS] += (h & 0x80000000) === 0 ? 1 : -1;
  };
  for (let i = 0; i < tokens.length; i++) {
    accumulate(tokens[i]);
    if (i + 1 < tokens.length) accumulate(`${tokens[i]}_${tokens[i + 1]}`);
  }
  let norm = 0;
  for (const x of vector) norm += x * x;
  if (norm === 0) {
    vector[0] = 1;
    return vector;
  }
  const inv = 1 / Math.sqrt(norm);
  return vector.map((x) => x * inv);
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

// fnv scenario: the EMULATOR user types the first offer and the last
// need via the spotlight; probes B (nodes[0]) and C (nodes[1]) complete
// the loop with text-identical offer/need pairs so FNV cosine == 1.
//   EMU offer  "dart tutoring for beginners"  -> B need (same text)
//   B   offer  "scooter loan in march"        -> C need (same text)
//   C   offer  "fresh groceries delivery"     -> EMU need (same text)
const FNV_TEXTS = {
  bOffer: 'scooter loan in march',
  bNeed: 'dart tutoring for beginners',
  cOffer: 'fresh groceries delivery',
  cNeed: 'scooter loan in march',
};

const fnvCreateOp = (node, uuid, direction, rawText) =>
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
        vector: fnvEmbed(rawText),
        quantity: 1,
        epochMs: Date.now(),
      },
    },
    10,
  );

const stageOps = (node, uuids, opName, status, ringId, clock) =>
  uuids.map((uuid) =>
    signedLog(
      node,
      uuid,
      { op: opName, intentUuid: uuid, ringId, status, author: node.pub },
      clock,
    ),
  );

if (stage === 'fnv-create') {
  const [b, c] = nodes;
  logs.push(
    fnvCreateOp(b, b.offerUuid, 'offer', FNV_TEXTS.bOffer),
    fnvCreateOp(b, b.needUuid, 'need', FNV_TEXTS.bNeed),
    fnvCreateOp(c, c.offerUuid, 'offer', FNV_TEXTS.cOffer),
    fnvCreateOp(c, c.needUuid, 'need', FNV_TEXTS.cNeed),
  );
} else if (stage === 'create') {
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
} else if (stage !== 'fnv-ride') {
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
  // fnv-ride waits for human-paced UI actions on the core node.
}, stage === 'fnv-ride' ? 240000 : 15000);

ws.onopen = () =>
  ws.send(
    JSON.stringify({
      type: 'helloChallenge',
      nonce: hex(nonce),
      node: { publicKey: nodes[0].pub, alias: aliases[0] },
    }),
  );

// --- fnv-ride: reactive companion for the on-device user journey. ---------
// Waits for the CORE NODE user to accept the ring (their lock gossip names
// the ringId), then locks B+C hops; waits for the user's satisfy, then
// satisfies B+C hops; exits when the final echo lands.
const parseOp = (l) => {
  try {
    return JSON.parse(l.op);
  } catch {
    return null;
  }
};

let ridePhase = 'awaitUserLock';
let rideRingId = null;
let pendingAck = new Set();

const rideHandle = (frame) => {
  if (frame.type !== 'delta') return;
  const [b, c] = nodes;
  const ours = new Set([b.pub, c.pub]);

  for (const l of frame.logs || []) {
    const payload = parseOp(l);
    if (!payload) continue;

    if (
      ridePhase === 'awaitUserLock' &&
      payload.op === 'lock_intent' &&
      typeof payload.ringId === 'string' &&
      payload.ringId.includes(b.offerUuid) &&
      !ours.has(payload.author)
    ) {
      rideRingId = payload.ringId;
      const locks = [
        ...stageOps(b, [b.offerUuid, b.needUuid], 'lock_intent',
            'locked_in_loop', rideRingId, 11),
        ...stageOps(c, [c.offerUuid, c.needUuid], 'lock_intent',
            'locked_in_loop', rideRingId, 11),
      ];
      pendingAck = new Set(locks.map((x) => x.txId));
      ws.send(JSON.stringify({ type: 'broadcast', logs: locks }));
      ridePhase = 'awaitLockAck';
      console.log('user locked -> B+C locks sent, ringId:', rideRingId);
    }

    if (pendingAck.delete(l.txId) && pendingAck.size === 0) {
      if (ridePhase === 'awaitLockAck') {
        ridePhase = 'awaitUserSatisfy';
        console.log('B+C locks ingested — ring should read CONFIRMED');
      } else if (ridePhase === 'awaitSatisfyAck') {
        console.log('B+C satisfies ingested — ring should read COMPLETED');
        console.log('RESULT: RIDE_OK');
        clearTimeout(deadline);
        ws.close();
        process.exit(0);
      }
    }

    if (
      ridePhase === 'awaitUserSatisfy' &&
      payload.op === 'satisfy_intent' &&
      payload.ringId === rideRingId &&
      !ours.has(payload.author)
    ) {
      const sats = [
        ...stageOps(b, [b.offerUuid, b.needUuid], 'satisfy_intent',
            'satisfied', rideRingId, 12),
        ...stageOps(c, [c.offerUuid, c.needUuid], 'satisfy_intent',
            'satisfied', rideRingId, 12),
      ];
      pendingAck = new Set(sats.map((x) => x.txId));
      ws.send(JSON.stringify({ type: 'broadcast', logs: sats }));
      ridePhase = 'awaitSatisfyAck';
      console.log('user fulfilled -> B+C satisfies sent');
    }
  }
};

const ourTxIds = new Set(logs.map((l) => l.txId));
ws.onmessage = (event) => {
  const frame = JSON.parse(event.data);
  if (frame.type === 'helloResponse') {
    if (stage === 'fnv-ride') {
      console.log('handshake done — riding along, waiting for user lock');
      return;
    }
    ws.send(JSON.stringify({ type: 'broadcast', logs }));
    console.log(`sent ${logs.length} signed ${stage} op(s)`);
    return;
  }
  if (stage === 'fnv-ride') {
    rideHandle(frame);
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
