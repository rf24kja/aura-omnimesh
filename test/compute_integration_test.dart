// Module B integration: the whole compute flow through the REAL MeshSyncEngine,
// InMemoryMeshRepository, and CrdtMaterializer — the same machinery Module A
// runs on. Proves offer -> worker -> result -> verify works end to end over the
// live signed log, and that compute ops are cleanly skipped by the intent
// materializer (no intent row, no inflated rejection counters).

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/compute/repository_compute_gateway.dart';
import 'package:omnimesh/compute/swarm_compute_gate.dart';
import 'package:omnimesh/compute/swarm_compute_requester.dart';
import 'package:omnimesh/compute/swarm_compute_worker.dart';
import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/engine/mesh_sync_engine.dart';
import 'package:omnimesh/main.dart' show InMemoryMeshRepository;
import 'package:omnimesh/services/services.dart';

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
  Future<void> broadcastDelta(List<CrdtStateLog> e) async {}
  @override
  Future<void> sendDeltaToPeer(String p, List<CrdtStateLog> e) async {}
  @override
  Future<void> dispose() async {
    await _nodes.close();
    await _deltas.close();
  }
}

class _DetInference implements EdgeInferenceService {
  @override
  Future<void> warmUp() async {}
  @override
  InferenceAccelerator get activeAccelerator =>
      InferenceAccelerator.cpuFallback;
  @override
  Future<void> dispose() async {}
  @override
  Future<List<double>> generateEmbedding(String input) async {
    final s = input.isEmpty ? ' ' : input;
    return List<double>.generate(
      kEmbeddingDimensions,
      (i) => ((s.codeUnitAt(i % s.length) + i * 13) % 200 - 100) / 100.0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aura-omnimesh/telemetry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('offer -> worker -> verify through the real engine; materializer clean',
      () async {
    final repository = InMemoryMeshRepository();
    final materializer = CrdtMaterializer(repository);
    final transport = _FakeTransport();
    final engine = MeshSyncEngine(
      repository: repository,
      transport: transport,
      applier: materializer,
    );
    final gateway =
        RepositoryComputeTaskGateway(repository: repository, engine: engine);
    final inference = _DetInference();

    final requesterSigner = await Ed25519IdentitySigner.generate();
    final workerSigner = await Ed25519IdentitySigner.generate();

    final requester = SwarmComputeRequester(
      inference: inference,
      signer: requesterSigner,
      gateway: gateway,
    );

    messenger.setMockMethodCallHandler(channel,
        (_) async => {'isCharging': true, 'batteryTemp': 30.0, 'wifiSsid': 'home'});
    final gate = SwarmComputeGate(trustedSsids: const {'home'});
    await gate.start();
    final worker = SwarmComputeWorker(
      gate: gate,
      inference: inference,
      signer: workerSigner,
      gateway: gateway,
    );

    // Requester offers over the real engine (persist + fold + gossip).
    final uuid = await requester.offer('compute this: 引っ越し помощь');
    expect(await gateway.offeredTaskUuids(), [uuid]);

    // Worker discovers, claims, computes, and posts a signed result.
    expect(await worker.pumpOnce(), uuid);

    // Requester verifies by local re-execution.
    final v = await requester.verify(uuid);
    expect(v.verdict, ComputeVerdict.verified);
    expect(v.localDigest, v.workerDigest);

    // The intent materializer must have IGNORED every compute op: no intent
    // row for the compute uuid, and no inflated rejection counters.
    expect(await repository.findIntentByUuid(uuid), isNull);
    expect(materializer.totalRejectedSignatures, 0);
    expect(materializer.totalRejectedRule, 0);

    await worker.dispose();
    await gate.dispose();
    await engine.dispose();
    await transport.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });
}
