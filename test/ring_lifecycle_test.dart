// Full ring lifecycle through the REAL adapter -> engine -> materializer,
// with every operation signature-verified by the fold. This is the
// automated form of the emulator ring_probe run: it locks the adapter's
// op-authoring (acceptRing / satisfyRing / withdrawIntent) against the
// materializer's verification, so a one-byte drift in the signature
// preimage — CLAUDE.md invariant 1 — fails here instead of silently
// invalidating every operation on the mesh.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/engine/mesh_sync_engine.dart';
import 'package:omnimesh/main.dart';
import 'package:omnimesh/matching/ring_matcher.dart';
import 'package:omnimesh/services/services.dart';
import 'package:omnimesh/ui/mesh_ui_adapter.dart';

class _FakeTransport implements LocalMeshTransportService {
  final _nodes = StreamController<NodeDiscoveryEvent>.broadcast();
  final _deltas = StreamController<List<CrdtStateLog>>.broadcast();
  @override
  Stream<NodeDiscoveryEvent> get onNodeDiscovered => _nodes.stream;
  @override
  Stream<List<CrdtStateLog>> get onDeltaReceived => _deltas.stream;
  @override
  Future<void> startDiscovery({required NodeIdentity selfIdentity}) async {}
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> broadcastDelta(List<CrdtStateLog> elements) async {}
  @override
  Future<void> sendDeltaToPeer(String p, List<CrdtStateLog> e) async {}
  @override
  Future<void> dispose() async {
    await _nodes.close();
    await _deltas.close();
  }
}

void main() {
  late InMemoryMeshRepository repository;
  late CrdtMaterializer materializer;
  late MeshSyncEngine engine;
  late MeshUiAdapter adapter;
  late Ed25519IdentitySigner self;
  late Ed25519IdentitySigner beta;
  late Ed25519IdentitySigner gamma;

  // Ring: self offers axis0 (beta needs it); beta offers axis1 (gamma
  // needs it); gamma offers axis2 (self needs it). One-hot vectors make
  // each offer↔need an exact match, so the matcher closes the loop.
  late String selfOff, selfNeed, bOff, bNeed, cOff, cNeed;

  Future<CrdtStateLog> signedOp(
    Ed25519IdentitySigner by,
    String targetUuid,
    Map<String, dynamic> payloadMap,
    int clock,
  ) async {
    final payload = jsonEncode(payloadMap);
    return CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: targetUuid,
      authoritySignature:
          await by.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    );
  }

  Future<void> publishCreate(
    Ed25519IdentitySigner by,
    String uuid,
    IntentDirection dir,
    int axis,
    int clock,
  ) async {
    final vector = List<double>.filled(kEmbeddingDimensions, 0.0)..[axis] = 1.0;
    final op = await signedOp(by, uuid, {
      'op': 'create_intent',
      'author': by.publicKeyHex,
      'intent': {
        'intentUuid': uuid,
        'originNodeKey': by.publicKeyHex,
        'category': 'peer_exchange',
        'direction': dir.wireValue,
        'rawText': '$uuid text',
        'vector': vector,
        'quantity': 1,
        'epochMs': 1000 + clock,
      },
    }, clock);
    await repository.appendDeltas([op]);
    await materializer.applyDeltas([op]);
  }

  /// A peer (beta/gamma) locks or satisfies its own offer intent, the way
  /// its own device would. Self's transitions go through the adapter.
  Future<void> peerTransition(
    Ed25519IdentitySigner by,
    String uuid,
    String opName,
    String status,
    String ringId,
    int clock,
  ) async {
    final op = await signedOp(by, uuid, {
      'op': opName,
      'intentUuid': uuid,
      'ringId': ringId,
      'status': status,
      'author': by.publicKeyHex,
    }, clock);
    await repository.appendDeltas([op]);
    await materializer.applyDeltas([op]);
  }

  setUp(() async {
    repository = InMemoryMeshRepository();
    materializer = CrdtMaterializer(repository);
    engine = MeshSyncEngine(
      repository: repository,
      transport: _FakeTransport(),
      applier: materializer,
    );
    self = await Ed25519IdentitySigner.generate();
    beta = await Ed25519IdentitySigner.generate();
    gamma = await Ed25519IdentitySigner.generate();
    adapter = MeshUiAdapter(
      engine: engine,
      repository: repository,
      ringFacade: RingMatchFacade(repository: repository),
      signer: self,
    );

    selfOff = 'self-off';
    selfNeed = 'self-need';
    bOff = 'b-off';
    bNeed = 'b-need';
    cOff = 'c-off';
    cNeed = 'c-need';
    await publishCreate(self, selfOff, IntentDirection.offer, 0, 1);
    await publishCreate(beta, bNeed, IntentDirection.need, 0, 1);
    await publishCreate(beta, bOff, IntentDirection.offer, 1, 1);
    await publishCreate(gamma, cNeed, IntentDirection.need, 1, 1);
    await publishCreate(gamma, cOff, IntentDirection.offer, 2, 1);
    await publishCreate(self, selfNeed, IntentDirection.need, 2, 1);
    await adapter.attach();
  });

  String discoveredRingId() {
    final rings = adapter.state.value.discoveredRings;
    expect(rings, isNotEmpty, reason: 'the 3-loop must be discovered');
    return rings.single.ringId;
  }

  test('adapter-authored lock/satisfy ops pass materializer verification',
      () async {
    final ringId = discoveredRingId();

    // Self accepts: authors signed lock ops for its own offer + need.
    await adapter.acceptRing(ringId);
    expect(materializer.totalRejectedSignatures, 0,
        reason: 'adapter lock ops must verify — preimage must not drift');
    expect((await repository.findIntentByUuid(selfOff))!.status,
        IntentStatus.lockedInLoop);
    expect((await repository.findIntentByUuid(selfNeed))!.status,
        IntentStatus.lockedInLoop);

    // Peers lock their offers so the ring is fully confirmed.
    await peerTransition(beta, bOff, 'lock_intent', 'locked_in_loop',
        ringId, 2);
    await peerTransition(gamma, cOff, 'lock_intent', 'locked_in_loop',
        ringId, 2);
    await adapter.rematchForTest();

    final routed = adapter.state.value.routedRings.single;
    expect(routed.confirmed, isTrue);
    expect(routed.canFulfil, isTrue);

    // Self fulfils: authors signed satisfy ops for its locked intents.
    await adapter.satisfyRing(ringId);
    expect(materializer.totalRejectedSignatures, 0,
        reason: 'adapter satisfy ops must verify too');
    expect((await repository.findIntentByUuid(selfOff))!.status,
        IntentStatus.satisfied);

    // Peers satisfy their offers -> the whole ring completes.
    await peerTransition(beta, bOff, 'satisfy_intent', 'satisfied',
        ringId, 3);
    await peerTransition(gamma, cOff, 'satisfy_intent', 'satisfied',
        ringId, 3);
    await adapter.rematchForTest();

    expect(adapter.state.value.routedRings.single.completed, isTrue);
    expect(materializer.totalRejectedSignatures, 0);
  });

  test('satisfyRing throws when this device locked nothing in the ring',
      () async {
    final ringId = discoveredRingId();
    // Only the peers lock; self never accepted.
    await peerTransition(beta, bOff, 'lock_intent', 'locked_in_loop',
        ringId, 2);
    expect(
      () => adapter.satisfyRing(ringId),
      throwsA(isA<StateError>()),
    );
  });

  test('withdrawing a locked intent breaks the ring for everyone',
      () async {
    final ringId = discoveredRingId();
    await adapter.acceptRing(ringId);
    await peerTransition(beta, bOff, 'lock_intent', 'locked_in_loop',
        ringId, 2);
    await peerTransition(gamma, cOff, 'lock_intent', 'locked_in_loop',
        ringId, 2);

    await adapter.withdrawIntent(selfOff);
    expect((await repository.findIntentByUuid(selfOff))!.status,
        IntentStatus.withdrawn);
    await adapter.rematchForTest();
    expect(adapter.state.value.routedRings.single.broken, isTrue,
        reason: 'a withdrawn hop must mark the routed ring broken');
    expect(materializer.totalRejectedSignatures, 0);
  });
}
