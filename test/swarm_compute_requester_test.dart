// Module B phase 4 — the requester + proof-by-re-execution. Offers a task,
// and verifies a returned result by re-running the embedding locally and
// comparing digests. Includes the full offer -> real worker -> verify chain,
// and the security case: a worker that signs a WRONG digest is caught as a
// mismatch even though its signature is perfectly valid.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/compute/compute_task.dart';
import 'package:omnimesh/compute/swarm_compute_gate.dart';
import 'package:omnimesh/compute/swarm_compute_requester.dart';
import 'package:omnimesh/compute/swarm_compute_worker.dart';
import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/services/services.dart';

class _FakeGateway implements ComputeTaskGateway {
  final List<CrdtStateLog> log = [];
  @override
  Future<int> currentClock() async =>
      log.isEmpty ? 0 : log.map((o) => o.lamportLogicalClock).reduce((a, b) => a > b ? a : b);
  @override
  Future<void> publish(List<CrdtStateLog> ops) async => log.addAll(ops);
  @override
  Future<List<CrdtStateLog>> taskLog(String uuid) async =>
      log.where((o) => o.targetIntentUuid == uuid).toList();
  @override
  Future<List<String>> offeredTaskUuids() async {
    final out = <String>[];
    for (final u in log.map((o) => o.targetIntentUuid).toSet()) {
      final s = (await foldComputeTask(await taskLog(u))).state;
      if (s?.status == ComputeTaskStatus.offered) out.add(u);
    }
    return out;
  }
}

/// Deterministic on input, so a worker and a requester running "the same model"
/// produce the same vector — exactly the property real proof-by-re-execution
/// depends on.
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
      (i) => ((s.codeUnitAt(i % s.length) + i * 31) % 200 - 100) / 100.0,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('aura-omnimesh/telemetry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _FakeGateway gateway;
  late _DetInference inference;
  late SwarmComputeRequester requester;
  late Ed25519IdentitySigner requesterSigner;
  late Ed25519IdentitySigner workerSigner;

  Future<void> author(
    Ed25519IdentitySigner by,
    String uuid,
    Map<String, dynamic> map,
    int clock,
  ) async {
    final payload = jsonEncode(map);
    gateway.log.add(CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: uuid,
      authoritySignature:
          await by.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    ));
  }

  setUp(() async {
    gateway = _FakeGateway();
    inference = _DetInference();
    requesterSigner = await Ed25519IdentitySigner.generate();
    workerSigner = await Ed25519IdentitySigner.generate();
    requester = SwarmComputeRequester(
      inference: inference,
      signer: requesterSigner,
      gateway: gateway,
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('offer publishes an offered task', () async {
    final uuid = await requester.offer('embed: привет мир');
    final s = (await foldComputeTask(await gateway.taskLog(uuid))).state;
    expect(s!.status, ComputeTaskStatus.offered);
    expect(s.requesterKey, requesterSigner.publicKeyHex);
  });

  test('verify is pending while the task is unfinished', () async {
    final uuid = await requester.offer('x');
    expect((await requester.verify(uuid)).verdict, ComputeVerdict.pending);
    // claimed but not completed -> still pending
    await author(
        workerSigner,
        uuid,
        computeClaimPayload(taskUuid: uuid, workerKey: workerSigner.publicKeyHex),
        50);
    expect((await requester.verify(uuid)).verdict, ComputeVerdict.pending);
  });

  test('full round-trip: offer -> real worker -> verified', () async {
    messenger.setMockMethodCallHandler(channel,
        (_) async => {'isCharging': true, 'batteryTemp': 30.0, 'wifiSsid': 'home'});
    final gate = SwarmComputeGate(trustedSsids: const {'home'});
    await gate.start();
    final worker = SwarmComputeWorker(
      gate: gate,
      inference: inference, // same deterministic model as the requester
      signer: workerSigner,
      gateway: gateway,
    );

    final uuid = await requester.offer('нужна помощь с переездом 引っ越し');
    final done = await worker.pumpOnce();
    expect(done, uuid);

    final v = await requester.verify(uuid);
    expect(v.verdict, ComputeVerdict.verified);
    expect(v.workerDigest, isNotNull);
    expect(v.localDigest, v.workerDigest);

    await worker.dispose();
    await gate.dispose();
  });

  test('a worker that signs a WRONG digest is caught as a mismatch', () async {
    final uuid = await requester.offer('honest input');
    await author(
        workerSigner,
        uuid,
        computeClaimPayload(taskUuid: uuid, workerKey: workerSigner.publicKeyHex),
        50);
    // A perfectly-signed result carrying a fabricated digest.
    await author(
        workerSigner,
        uuid,
        computeResultPayload(
            taskUuid: uuid,
            workerKey: workerSigner.publicKeyHex,
            outputDigest: 'deadbeef' * 8),
        51);

    final v = await requester.verify(uuid);
    expect(v.verdict, ComputeVerdict.mismatch,
        reason: 're-execution must expose a fabricated result');
    expect(v.localDigest, isNot(v.workerDigest));
  });

  test('withdraw cancels the task and verify reports withdrawn', () async {
    final uuid = await requester.offer('cancel me');
    await requester.withdraw(uuid);
    final v = await requester.verify(uuid);
    expect(v.verdict, ComputeVerdict.withdrawn);
    expect(v.state!.status, ComputeTaskStatus.withdrawn);
  });
}
