// MeshSyncEngine in isolation: the gossip / anti-entropy / dedup core that
// bridge_sync_test only exercises through the bridge server. The engine
// never verifies signatures (that's the materializer's job downstream) —
// its correctness properties are about PROPAGATION:
//
//   * idempotency is the loop breaker — a delta already held must not be
//     re-gossiped or re-materialized, or a flood-gossip mesh melts into an
//     echo storm and drains every radio (engine lines 375-379);
//   * durability before network — publish persists even with zero peers,
//     and MeshUnreachableException is store-and-forward, never an error;
//   * anti-entropy fires once on the transition INTO connected, not on
//     every RSSI refresh.
//
// Real InMemoryMeshRepository + real CrdtMaterializer; only the radio is a
// controllable fake that records what the engine tried to send.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/engine/mesh_sync_engine.dart';
import 'package:omnimesh/main.dart' show InMemoryMeshRepository, jsonStablePayload;
import 'package:omnimesh/services/services.dart';

class _ControlledTransport implements LocalMeshTransportService {
  final _nodes = StreamController<NodeDiscoveryEvent>.broadcast();
  final _deltas = StreamController<List<CrdtStateLog>>.broadcast();

  final List<List<CrdtStateLog>> broadcasts = [];
  final List<(String, List<CrdtStateLog>)> directSends = [];
  bool throwOnBroadcast = false;

  void emitDiscovery(NodeDiscoveryEvent e) => _nodes.add(e);
  void emitInbound(List<CrdtStateLog> d) => _deltas.add(d);

  @override
  Stream<NodeDiscoveryEvent> get onNodeDiscovered => _nodes.stream;
  @override
  Stream<List<CrdtStateLog>> get onDeltaReceived => _deltas.stream;
  @override
  Future<void> startDiscovery({required NodeIdentity selfIdentity}) async {}
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> broadcastDelta(List<CrdtStateLog> elements) async {
    if (throwOnBroadcast) {
      throw const MeshUnreachableException('no connected peers');
    }
    broadcasts.add(List.of(elements));
  }

  @override
  Future<void> sendDeltaToPeer(
      String peerPublicKey, List<CrdtStateLog> elements) async {
    directSends.add((peerPublicKey, List.of(elements)));
  }

  @override
  Future<void> dispose() async {
    await _nodes.close();
    await _deltas.close();
  }
}

void main() {
  late InMemoryMeshRepository repo;
  late CrdtMaterializer materializer;
  late _ControlledTransport transport;
  late MeshSyncEngine engine;
  late Ed25519IdentitySigner author;

  NodeIdentity self() => NodeIdentity(
        cryptographicPublicKey: 'ff' * 32,
        localAlias: 'self',
        reliabilityScore: 0,
      );

  NodeDiscoveryEvent discovery(String key, MeshNodeState state) =>
      NodeDiscoveryEvent(
        node: NodeIdentity(
            cryptographicPublicKey: key, localAlias: 'peer', reliabilityScore: 0),
        state: state,
        rssi: -50,
      );

  Future<CrdtStateLog> signedCreate(String uuid, int clock) async {
    final vector = List<double>.filled(kEmbeddingDimensions, 0.0)..[0] = 1.0;
    final payload = jsonStablePayload(
      op: 'create_intent',
      author: author.publicKeyHex,
      intent: <String, dynamic>{
        'intentUuid': uuid,
        'originNodeKey': author.publicKeyHex,
        'category': 'peer_exchange',
        'direction': 'offer',
        'rawText': '$uuid text',
        'vector': vector,
        'quantity': 1,
        'epochMs': 1000 + clock,
      },
    );
    return CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: uuid,
      authoritySignature:
          await author.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    );
  }

  /// Drain the serialized task lane (and any inbound stream microtasks)
  /// until the event loop is idle. Engine work is all main-isolate async.
  Future<void> settle() => pumpEventQueue(times: 50);

  setUp(() async {
    repo = InMemoryMeshRepository();
    materializer = CrdtMaterializer(repo);
    transport = _ControlledTransport();
    engine = MeshSyncEngine(
      repository: repo,
      transport: transport,
      applier: materializer,
    );
    author = await Ed25519IdentitySigner.generate();
  });

  tearDown(() async {
    await engine.dispose();
    await transport.dispose();
  });

  group('local publication — durability before network', () {
    test('persists, folds into an intent row, gossips, and advances the clock',
        () async {
      await engine.start(selfIdentity: self());
      final op = await signedCreate('i1', 1);

      final clock = await engine.publishLocalDeltas([op]);
      expect(clock, 1);
      expect((await repo.findIntentByUuid('i1'))!.status, IntentStatus.open,
          reason: 'locally authored op must be folded before listeners fire');

      await settle();
      expect(transport.broadcasts.expand((b) => b).map((l) => l.transactionUuid),
          contains(op.transactionUuid));
    });

    test('an empty publish is a no-op that returns the current clock',
        () async {
      await engine.start(selfIdentity: self());
      final clock = await engine.publishLocalDeltas(const []);
      expect(clock, 0);
      await settle();
      expect(transport.broadcasts, isEmpty);
    });

    test('zero peers (MeshUnreachableException) is store-and-forward, not error',
        () async {
      await engine.start(selfIdentity: self());
      transport.throwOnBroadcast = true;
      final op = await signedCreate('i2', 1);

      await engine.publishLocalDeltas([op]);
      await settle();

      // Row is durable despite the failed broadcast; engine is not errored.
      expect((await repo.findIntentByUuid('i2')), isNotNull);
      expect(engine.state.value.syncStatus, isNot(MeshSyncStatus.error));
    });
  });

  group('reactive ingestion — flood gossip terminates', () {
    test('a NEW inbound delta is persisted, folded, and forwarded once',
        () async {
      await engine.start(selfIdentity: self());
      final op = await signedCreate('i3', 1);

      final synced = engine.onDeltasSynced.first;
      transport.emitInbound([op]);
      await synced.timeout(const Duration(seconds: 5));
      await settle();

      expect((await repo.findIntentByUuid('i3'))!.status, IntentStatus.open);
      expect(transport.broadcasts.expand((b) => b).map((l) => l.transactionUuid),
          contains(op.transactionUuid),
          reason: 'a delta new to us must be flood-forwarded onward');
    });

    test('a DUPLICATE inbound delta does not re-gossip or re-fire — '
        'idempotency is the loop breaker', () async {
      await engine.start(selfIdentity: self());
      final op = await signedCreate('i4', 1);

      // First arrival: persisted + forwarded.
      final synced = engine.onDeltasSynced.first;
      transport.emitInbound([op]);
      await synced.timeout(const Duration(seconds: 5));
      await settle();
      expect(transport.broadcasts, isNotEmpty);

      // Second arrival of the SAME transaction: written == 0, so nothing
      // downstream must happen — no re-broadcast, no persisted-signal.
      transport.broadcasts.clear();
      var refired = 0;
      final sub = engine.onNewDeltasPersisted.listen((_) => refired++);

      transport.emitInbound([op]);
      await settle();

      expect(transport.broadcasts, isEmpty,
          reason: 'a delta already held must never be re-forwarded — that is '
              'what stops echo storms across the mesh');
      expect(refired, 0,
          reason: 'no new rows means no re-materialization churn');
      await sub.cancel();
    });
  });

  group('anti-entropy + peer set', () {
    test('becoming connected pushes the full log once; an RSSI-refresh repeat '
        'of connected does not re-push', () async {
      // Seed a durable backlog before any peer shows up.
      await repo.appendDeltas([await signedCreate('h1', 1)]);
      await repo.appendDeltas([await signedCreate('h2', 2)]);
      await engine.start(selfIdentity: self());

      final peer = 'aa' * 32;
      transport.emitDiscovery(discovery(peer, MeshNodeState.connected));
      await settle();

      expect(transport.directSends, hasLength(1),
          reason: 'exactly one anti-entropy push on the connected transition');
      expect(transport.directSends.single.$1, peer);
      expect(transport.directSends.single.$2, hasLength(2),
          reason: 'the whole causal log is streamed to the new peer');

      // A second `connected` for the same peer (RSSI refresh) must not
      // re-push the entire log over a battery-powered radio.
      transport.emitDiscovery(discovery(peer, MeshNodeState.connected));
      await settle();
      expect(transport.directSends, hasLength(1));
    });

    test('verifiedPeers tracks the connected set; lost removes; degraded is '
        'excluded from routable peers', () async {
      await engine.start(selfIdentity: self());
      final peer = 'bb' * 32;

      transport.emitDiscovery(discovery(peer, MeshNodeState.connected));
      await settle();
      expect(engine.state.value.connectionState,
          MeshConnectionState.secureBridge);
      expect(engine.state.value.verifiedPeers.map((n) => n.cryptographicPublicKey),
          contains(peer));

      transport.emitDiscovery(discovery(peer, MeshNodeState.degraded));
      await settle();
      expect(engine.state.value.verifiedPeers, isEmpty,
          reason: 'the router must never path through a degraded peer');

      transport.emitDiscovery(discovery(peer, MeshNodeState.lost));
      await settle();
      expect(engine.state.value.verifiedPeers, isEmpty);
      expect(engine.state.value.connectionState,
          MeshConnectionState.connecting,
          reason: 'no peers but still running -> connecting, not disconnected');
    });
  });
}
