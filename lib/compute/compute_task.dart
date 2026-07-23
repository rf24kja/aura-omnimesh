// lib/compute/compute_task.dart
//
// Module B (SwarmCompute) task lifecycle — the state machine + authorization
// folded from the signed CRDT log, mirroring CrdtMaterializer.materializeIntent
// but with compute semantics. See docs/MODULE_B_DESIGN.md §2.
//
// This is a PURE projection (log -> state); it is not a writer. When compute
// tasks gain a persisted row, the materializer (the sole row-writer,
// invariant 2) will call this fold and upsert the result — exactly how it
// folds intents today.
//
// Key difference from Module A intents: transitions are NOT all owner-only.
//   offer / withdraw  — authored by the REQUESTER (task owner)
//   claim / result    — authored by the WORKER (not the owner)
// A valid signature under a key that is not entitled to that specific
// transition is still rejected (auth != authz, invariant 7) — just with a
// per-op entitlement table instead of a single owner check.

import 'dart:convert';

import '../crypto/ed25519_signer.dart';
import '../domain/domain_models.dart';

/// Wire values of the compute operations. Additive to the protocol
/// (invariant 5) and disjoint from the intent ops, so the intent materializer
/// never confuses the two.
abstract final class ComputeOps {
  static const String offer = 'compute_task_offer';
  static const String claim = 'compute_task_claim';
  static const String result = 'compute_task_result';
  static const String withdraw = 'compute_task_withdraw';
}

enum ComputeTaskStatus { offered, claimed, completed, withdrawn }

/// Folded state of one compute task. Immutable; every transition yields a new
/// instance so a fold is arrival-order independent by construction.
class ComputeTaskState {
  const ComputeTaskState({
    required this.taskUuid,
    required this.requesterKey,
    required this.inputText,
    required this.status,
    this.claimedByKey,
    this.resultDigest,
  });

  final String taskUuid;

  /// Ed25519 public key of the requester — the only key that may offer or
  /// withdraw this task.
  final String requesterKey;

  /// The text whose embedding is to be computed.
  final String inputText;

  final ComputeTaskStatus status;

  /// Worker that claimed the task — the only key that may post its result.
  final String? claimedByKey;

  /// Proof-of-computation digest from the result op (see
  /// proof_of_computation.dart). A verifier re-runs the input and confirms it.
  final String? resultDigest;

  ComputeTaskState copyWith({
    ComputeTaskStatus? status,
    String? claimedByKey,
    String? resultDigest,
  }) =>
      ComputeTaskState(
        taskUuid: taskUuid,
        requesterKey: requesterKey,
        inputText: inputText,
        status: status ?? this.status,
        claimedByKey: claimedByKey ?? this.claimedByKey,
        resultDigest: resultDigest ?? this.resultDigest,
      );
}

/// Fold outcome — mirrors MaterializationReport so compute folds count work
/// the same way the intent fold does.
class ComputeTaskFold {
  const ComputeTaskFold({
    required this.state,
    required this.applied,
    required this.rejectedSignature,
    required this.rejectedRule,
  });

  final ComputeTaskState? state;
  final int applied;
  final int rejectedSignature;
  final int rejectedRule;
}

/// Fold a compute task's causal log into its current state. Deterministic:
/// the log is sorted by [CrdtStateLog.causalCompare] first, so two devices
/// holding the same rows produce identical state regardless of arrival order.
/// Every op is signature-verified against its claimed author before it can
/// affect state (authentication); entitlement is then checked per op type
/// (authorization).
Future<ComputeTaskFold> foldComputeTask(List<CrdtStateLog> log) async {
  final ordered = [...log]..sort(CrdtStateLog.causalCompare);
  ComputeTaskState? state;
  var applied = 0;
  var rejectedSignature = 0;
  var rejectedRule = 0;

  for (final op in ordered) {
    final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(op.operationPayloadJson);
      if (decoded is! Map<String, dynamic>) {
        rejectedRule += 1;
        continue;
      }
      payload = decoded;
    } on FormatException {
      rejectedRule += 1;
      continue;
    }

    final author = payload['author'];
    if (author is! String) {
      rejectedRule += 1;
      continue;
    }

    final valid = await verifyEd25519Hex(
      message: crdtSignaturePreimage(
        op.operationPayloadJson,
        op.lamportLogicalClock,
      ),
      signatureHex: op.authoritySignature,
      publicKeyHex: author,
    );
    if (!valid) {
      rejectedSignature += 1;
      continue;
    }

    switch (payload['op']) {
      case ComputeOps.offer:
        if (state != null) {
          // Duplicate offer: first in causal order wins, deterministically.
          rejectedRule += 1;
          continue;
        }
        final built = _buildOffered(payload, author, op.targetIntentUuid);
        if (built == null) {
          rejectedRule += 1;
          continue;
        }
        state = built;
        applied += 1;

      case ComputeOps.claim:
        if (state == null || state.status != ComputeTaskStatus.offered) {
          // Claim before offer, or task no longer open. First claim in
          // causal order wins; later claims fall here.
          rejectedRule += 1;
          continue;
        }
        state = state.copyWith(
          status: ComputeTaskStatus.claimed,
          claimedByKey: author,
        );
        applied += 1;

      case ComputeOps.result:
        if (state == null || state.status != ComputeTaskStatus.claimed) {
          rejectedRule += 1;
          continue;
        }
        if (author != state.claimedByKey) {
          // Authorization: only the worker that claimed may post the result.
          rejectedRule += 1;
          continue;
        }
        final digest = payload['outputDigest'];
        if (digest is! String || digest.isEmpty) {
          rejectedRule += 1;
          continue;
        }
        state = state.copyWith(
          status: ComputeTaskStatus.completed,
          resultDigest: digest,
        );
        applied += 1;

      case ComputeOps.withdraw:
        if (state == null) {
          rejectedRule += 1;
          continue;
        }
        if (author != state.requesterKey) {
          // Authorization: only the requester may withdraw its task.
          rejectedRule += 1;
          continue;
        }
        if (state.status == ComputeTaskStatus.completed ||
            state.status == ComputeTaskStatus.withdrawn) {
          // Absorbing states: a completed proof cannot be retracted.
          rejectedRule += 1;
          continue;
        }
        state = state.copyWith(status: ComputeTaskStatus.withdrawn);
        applied += 1;

      default:
        rejectedRule += 1; // Unknown / intent op — not ours.
    }
  }

  return ComputeTaskFold(
    state: state,
    applied: applied,
    rejectedSignature: rejectedSignature,
    rejectedRule: rejectedRule,
  );
}

/// Strict construction from an offer payload. Binding invariants: the op must
/// target the uuid it claims, and the requesterKey must be the op's author.
ComputeTaskState? _buildOffered(
  Map<String, dynamic> payload,
  String author,
  String expectedUuid,
) {
  final task = payload['task'];
  if (task is! Map<String, dynamic>) return null;
  final uuid = task['taskUuid'];
  final requester = task['requesterKey'];
  final input = task['inputText'];
  final epochMs = task['epochMs'];
  if (uuid is! String ||
      requester is! String ||
      input is! String ||
      epochMs is! int) {
    return null;
  }
  if (uuid != expectedUuid) return null;
  if (requester != author) return null;
  return ComputeTaskState(
    taskUuid: uuid,
    requesterKey: requester,
    inputText: input,
    status: ComputeTaskStatus.offered,
  );
}

// ---------------------------------------------------------------------------
// Canonical payload builders — used by the worker/requester (phases 3-4) and
// by tests, so every compute op is shaped identically.
// ---------------------------------------------------------------------------

Map<String, dynamic> computeOfferPayload({
  required String taskUuid,
  required String requesterKey,
  required String inputText,
  required int epochMs,
}) =>
    <String, dynamic>{
      'op': ComputeOps.offer,
      'author': requesterKey,
      'task': <String, dynamic>{
        'taskUuid': taskUuid,
        'requesterKey': requesterKey,
        'inputText': inputText,
        'epochMs': epochMs,
      },
    };

Map<String, dynamic> computeClaimPayload({
  required String taskUuid,
  required String workerKey,
}) =>
    <String, dynamic>{
      'op': ComputeOps.claim,
      'author': workerKey,
      'taskUuid': taskUuid,
    };

Map<String, dynamic> computeResultPayload({
  required String taskUuid,
  required String workerKey,
  required String outputDigest,
}) =>
    <String, dynamic>{
      'op': ComputeOps.result,
      'author': workerKey,
      'taskUuid': taskUuid,
      'outputDigest': outputDigest,
    };

Map<String, dynamic> computeWithdrawPayload({
  required String taskUuid,
  required String requesterKey,
}) =>
    <String, dynamic>{
      'op': ComputeOps.withdraw,
      'author': requesterKey,
      'taskUuid': taskUuid,
    };
