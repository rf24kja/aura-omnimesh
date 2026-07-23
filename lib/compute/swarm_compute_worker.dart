// lib/compute/swarm_compute_worker.dart
//
// Module B phase 3 — the compute worker. While the SwarmComputeGate reports
// `eligible` (charging + cool + trusted network, all verified), the worker
// claims one offered task, runs the on-device embedding, and publishes a
// signed compute_task_result carrying the proof-of-computation digest.
// See docs/MODULE_B_DESIGN.md §5 step 3.
//
// Everything is injected so the whole flow is testable off-device: the gate
// (with mocked telemetry), a fake inference service, a fake task gateway.
// The worker authors ops through the same signing path as Module A
// (crdtSignaturePreimage) and never invents a second scheme.

import 'dart:async';
import 'dart:convert';

import '../crypto/ed25519_signer.dart';
import '../domain/domain_models.dart';
import '../services/services.dart';
import 'compute_task.dart';
import 'proof_of_computation.dart';
import 'swarm_compute_gate.dart';

/// The worker's window onto the compute-task log. Backed in production by the
/// repository (offered-task query + readCausalLog) and the engine
/// (publishLocalDeltas); a fake in tests. Kept abstract so phase 3 does not
/// depend on the not-yet-wired compute persistence.
abstract class ComputeTaskGateway {
  /// Uuids of tasks a fold currently reports as `offered`.
  Future<List<String>> offeredTaskUuids();

  /// Full causal log for [taskUuid], for folding its current state.
  Future<List<CrdtStateLog>> taskLog(String taskUuid);

  /// Highest Lamport clock seen locally; the next op is stamped +1.
  Future<int> currentClock();

  /// Persist + gossip locally-authored ops (engine.publishLocalDeltas).
  Future<void> publish(List<CrdtStateLog> ops);
}

class SwarmComputeWorker {
  SwarmComputeWorker({
    required SwarmComputeGate gate,
    required EdgeInferenceService inference,
    required IdentitySigner signer,
    required ComputeTaskGateway gateway,
  })  : _gate = gate,
        _inference = inference,
        _signer = signer,
        _gateway = gateway;

  final SwarmComputeGate _gate;
  final EdgeInferenceService _inference;
  final IdentitySigner _signer;
  final ComputeTaskGateway _gateway;

  StreamSubscription<ComputeEligibility>? _sub;
  bool _draining = false;
  bool _disposed = false;

  bool get _eligible =>
      _gate.eligibility.value == ComputeEligibility.eligible;

  /// Begin reacting to eligibility: drain the offered queue whenever the gate
  /// transitions into `eligible`, and once now if it already is.
  void start() {
    _checkNotDisposed();
    _sub ??= _gate.onEligibilityChanged.listen((e) {
      if (e == ComputeEligibility.eligible) unawaited(_drain());
    });
    if (_eligible) unawaited(_drain());
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
  }

  /// Serialized drain: process offered tasks one at a time until the queue is
  /// empty or the gate leaves `eligible`. Serialization prevents the worker
  /// from racing two claims against itself.
  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_eligible && !_disposed) {
        final done = await pumpOnce();
        if (done == null) break;
      }
    } finally {
      _draining = false;
    }
  }

  /// Attempt exactly one task. Returns the completed task uuid, or null if the
  /// gate is not `eligible` or there is nothing claimable. Public for tests
  /// and for a caller that wants to pace the worker itself.
  Future<String?> pumpOnce() async {
    if (_disposed || !_eligible) return null;

    for (final uuid in await _gateway.offeredTaskUuids()) {
      final before = (await _fold(uuid));
      if (before == null || before.status != ComputeTaskStatus.offered) {
        continue; // stale listing — already claimed/withdrawn elsewhere
      }

      // Claim it.
      await _publishOp(
        uuid,
        computeClaimPayload(taskUuid: uuid, workerKey: _signer.publicKeyHex),
      );

      // Deterministic fold decides the winner; confirm we actually hold the
      // claim before spending any energy (another eligible worker may have
      // claimed first in causal order).
      final claimed = await _fold(uuid);
      if (claimed == null ||
          claimed.status != ComputeTaskStatus.claimed ||
          claimed.claimedByKey != _signer.publicKeyHex) {
        continue;
      }

      // Final safety interlock before the expensive step.
      if (!_eligible) return null;

      final vector = await _inference.generateEmbedding(claimed.inputText);
      final digest =
          await computeResultDigest(taskId: uuid, output: vector);

      // The compute is done and cheap to publish; do not abandon a finished
      // result on a late de-eligibility — the gate guards STARTING work.
      await _publishOp(
        uuid,
        computeResultPayload(
          taskUuid: uuid,
          workerKey: _signer.publicKeyHex,
          outputDigest: digest,
        ),
      );
      return uuid;
    }
    return null;
  }

  Future<ComputeTaskState?> _fold(String uuid) async =>
      (await foldComputeTask(await _gateway.taskLog(uuid))).state;

  Future<void> _publishOp(String taskUuid, Map<String, dynamic> payloadMap) async {
    final payload = jsonEncode(payloadMap);
    final clock = (await _gateway.currentClock()) + 1;
    final op = CrdtStateLog(
      transactionUuid: secureUuidV4(),
      targetIntentUuid: taskUuid,
      authoritySignature:
          await _signer.signToHex(crdtSignaturePreimage(payload, clock)),
      lamportLogicalClock: clock,
      operationPayloadJson: payload,
    );
    await _gateway.publish([op]);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('SwarmComputeWorker used after dispose()');
  }
}
