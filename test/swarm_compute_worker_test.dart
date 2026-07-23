// Module B phase 3 — the compute worker end to end, off-device: a real
// SwarmComputeGate (telemetry mocked to `eligible`), a fake task gateway
// standing in for the repository+engine, and a fake inference service. Proves
// the worker only works while eligible, claims then completes an offered task,
// and that the published result is a valid proof-of-computation of the
// inference output (round-trips through computeResultDigest).

import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/compute/compute_task.dart';
import 'package:omnimesh/compute/proof_of_computation.dart';
import 'package:omnimesh/compute/swarm_compute_gate.dart';
import 'package:omnimesh/compute/swarm_compute_worker.dart';
import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/services/services.dart';

class _FakeGateway implements ComputeTaskGateway {
  final List<CrdtStateLog> log = [];

  @override
  Future<int> currentClock() async => log.isEmpty
      ? 0
      : log.map((o) => o.lamportLogicalClock).reduce(max);

  @override
  Future<void> publish(List<CrdtStateLog> ops) async => log.addAll(ops);

  @override
  Future<List<CrdtStateLog>> taskLog(String taskUuid) async =>
      log.where((o) => o.targetIntentUuid == taskUuid).toList();

  @override
  Future<List<String>> offeredTaskUuids() async {
    final offered = <String>[];
    for (final u in log.map((o) => o.targetIntentUuid).toSet()) {
      final s = (await foldComputeTask(await taskLog(u))).state;
      if (s?.status == ComputeTaskStatus.offered) offered.add(u);
    }
    return offered;
  }
}

class _FakeInference implements EdgeInferenceService {
  int calls = 0;
  final List<double> vector =
      List<double>.generate(kEmbeddingDimensions, (i) => (i % 7) / 10.0);

  @override
  Future<void> warmUp() async {}
  @override
  InferenceAccelerator get activeAccelerator =>
      InferenceAccelerator.cpuFallback;
  @override
  Future<List<double>> generateEmbedding(String input) async {
    calls++;
    return vector;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('aura-omnimesh/telemetry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late _FakeGateway gateway;
  late _FakeInference inference;
  late SwarmComputeGate gate;
  late SwarmComputeWorker worker;
  late Ed25519IdentitySigner requester;
  late Ed25519IdentitySigner workerSigner;

  void setTelemetry(Map<String, Object?>? m) =>
      messenger.setMockMethodCallHandler(channel, (_) async => m);

  Map<String, Object?> eligible() =>
      {'isCharging': true, 'batteryTemp': 30.0, 'wifiSsid': 'home'};

  Future<void> publishOffer(String uuid, {String text = 'embed me'}) async {
    final payload = jsonEncode(computeOfferPayload(
      taskUuid: uuid,
      requesterKey: requester.publicKeyHex,
      inputText: text,
      epochMs: 1000,
    ));
    const clock = 1;
    gateway.log.add(CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: uuid,
      authoritySignature:
          await requester.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    ));
  }

  Future<ComputeTaskState?> stateOf(String uuid) async =>
      (await foldComputeTask(await gateway.taskLog(uuid))).state;

  setUp(() async {
    gateway = _FakeGateway();
    inference = _FakeInference();
    requester = await Ed25519IdentitySigner.generate();
    workerSigner = await Ed25519IdentitySigner.generate();
    setTelemetry(eligible());
    gate = SwarmComputeGate(trustedSsids: const {'home'});
    await gate.start(); // eligibility -> eligible
    worker = SwarmComputeWorker(
      gate: gate,
      inference: inference,
      signer: workerSigner,
      gateway: gateway,
    );
  });

  tearDown(() async {
    await worker.dispose();
    await gate.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('eligible worker claims and completes an offered task', () async {
    expect(gate.eligibility.value, ComputeEligibility.eligible);
    await publishOffer('task-1', text: 'нужна помощь с переездом');

    final done = await worker.pumpOnce();
    expect(done, 'task-1');

    final s = await stateOf('task-1');
    expect(s!.status, ComputeTaskStatus.completed);
    expect(s.claimedByKey, workerSigner.publicKeyHex);
    expect(inference.calls, 1);

    // The published result is a real proof-of-computation of the output.
    final expected =
        await computeResultDigest(taskId: 'task-1', output: inference.vector);
    expect(s.resultDigest, expected);
  });

  test('a non-eligible worker does nothing', () async {
    gate.stop(); // eligibility -> indeterminate
    await publishOffer('task-2');

    final done = await worker.pumpOnce();
    expect(done, isNull);
    expect(inference.calls, 0);
    expect((await stateOf('task-2'))!.status, ComputeTaskStatus.offered);
  });

  test('the worker ignores tasks that are already claimed', () async {
    await publishOffer('task-3');
    // A different worker already claimed it.
    final other = await Ed25519IdentitySigner.generate();
    final payload = jsonEncode(
        computeClaimPayload(taskUuid: 'task-3', workerKey: other.publicKeyHex));
    gateway.log.add(CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: 'task-3',
      authoritySignature:
          await other.signToHex(crdtSignaturePreimage(payload, 2)),
      lamportLogicalClock: 2,
      operationPayloadJson: payload,
    ));

    expect(await worker.pumpOnce(), isNull);
    expect(inference.calls, 0);
    final s = await stateOf('task-3');
    expect(s!.claimedByKey, other.publicKeyHex); // untouched
  });

  test('start() auto-drains the offered queue while eligible', () async {
    await publishOffer('t-a');
    await publishOffer('t-b');
    worker.start();
    await pumpEventQueue(times: 50);

    expect((await stateOf('t-a'))!.status, ComputeTaskStatus.completed);
    expect((await stateOf('t-b'))!.status, ComputeTaskStatus.completed);
    expect(inference.calls, 2);
  });

  test('pumpOnce returns null when there is nothing offered', () async {
    expect(await worker.pumpOnce(), isNull);
    expect(inference.calls, 0);
  });
}
