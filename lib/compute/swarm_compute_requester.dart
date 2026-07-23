// lib/compute/swarm_compute_requester.dart
//
// Module B phase 4 — the requester side. Offers a compute task, then VERIFIES
// a returned result by re-executing the embedding locally and confirming the
// worker's proof-of-computation digest. See docs/MODULE_B_DESIGN.md §4-§5.
//
// This is the correctness half of the trust model: the worker's signature
// proves *authenticity* (who claimed the digest), and this local re-run proves
// *correctness* — a deterministic task run twice must produce the same digest,
// so a wrong or fabricated result fails the check and is discarded. A verifier
// need not trust the worker, only the determinism of the task (invariant 3).

import 'dart:convert';

import '../crypto/ed25519_signer.dart';
import '../domain/domain_models.dart';
import '../services/services.dart';
import 'compute_task.dart';
import 'proof_of_computation.dart';
import 'swarm_compute_worker.dart' show ComputeTaskGateway;

enum ComputeVerdict {
  /// No result yet (still offered/claimed) or the task is unknown.
  pending,

  /// The requester withdrew the task.
  withdrawn,

  /// The worker's digest matches a local re-run — trust the result.
  verified,

  /// The worker's digest does NOT match a local re-run — reject it.
  mismatch,
}

class ComputeVerification {
  const ComputeVerification({
    required this.verdict,
    this.state,
    this.workerDigest,
    this.localDigest,
  });

  final ComputeVerdict verdict;
  final ComputeTaskState? state;

  /// Digest the worker signed (present once the task is completed).
  final String? workerDigest;

  /// Digest the requester re-derived locally (present when it re-ran).
  final String? localDigest;
}

class SwarmComputeRequester {
  SwarmComputeRequester({
    required EdgeInferenceService inference,
    required IdentitySigner signer,
    required ComputeTaskGateway gateway,
  })  : _inference = inference,
        _signer = signer,
        _gateway = gateway;

  final EdgeInferenceService _inference;
  final IdentitySigner _signer;
  final ComputeTaskGateway _gateway;

  /// Publish a compute task for [inputText]; returns its uuid.
  Future<String> offer(String inputText) async {
    final uuid = secureUuidV4();
    await _publishOp(
      uuid,
      computeOfferPayload(
        taskUuid: uuid,
        requesterKey: _signer.publicKeyHex,
        inputText: inputText,
        epochMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    return uuid;
  }

  /// Cancel an unfinished task (only the requester may — enforced by the fold).
  Future<void> withdraw(String taskUuid) => _publishOp(
        taskUuid,
        computeWithdrawPayload(
          taskUuid: taskUuid,
          requesterKey: _signer.publicKeyHex,
        ),
      );

  /// Fold the task and, if completed, re-run the embedding locally to confirm
  /// the worker's digest (proof-by-re-execution).
  Future<ComputeVerification> verify(String taskUuid) async {
    final state = (await foldComputeTask(await _gateway.taskLog(taskUuid))).state;
    if (state == null) {
      return const ComputeVerification(verdict: ComputeVerdict.pending);
    }
    switch (state.status) {
      case ComputeTaskStatus.offered:
      case ComputeTaskStatus.claimed:
        return ComputeVerification(
            verdict: ComputeVerdict.pending, state: state);
      case ComputeTaskStatus.withdrawn:
        return ComputeVerification(
            verdict: ComputeVerdict.withdrawn, state: state);
      case ComputeTaskStatus.completed:
        final local = await _inference.generateEmbedding(state.inputText);
        final localDigest =
            await computeResultDigest(taskId: taskUuid, output: local);
        return ComputeVerification(
          verdict: localDigest == state.resultDigest
              ? ComputeVerdict.verified
              : ComputeVerdict.mismatch,
          state: state,
          workerDigest: state.resultDigest,
          localDigest: localDigest,
        );
    }
  }

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
}
