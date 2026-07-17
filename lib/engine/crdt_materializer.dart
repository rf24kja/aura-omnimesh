// lib/engine/crdt_materializer.dart
//
// Materializes the CRDT operation log into ResourceIntent rows. The log is
// the source of truth; the intent row is a derived view — this module is
// the ONLY writer of intent rows in the steady state.
//
// Out-of-order strategy: no incremental patching. Every trigger re-folds
// the FULL causal log for the affected intent (readCausalLog returns it in
// deterministic causalCompare order: Lamport clock, UUID tiebreak). Fold
// of a totally ordered log is arrival-order independent by construction —
// a lock op received before its create op simply no-ops this round and
// applies on the re-fold when the create arrives. Idempotent, convergent,
// no special cases.
//
// Concurrency: invoked exclusively from the engine's serialized task lane
// — no two folds of the same intent ever interleave.

import 'dart:convert';

import '../crypto/ed25519_signer.dart';
import '../domain/domain_models.dart';
import '../services/services.dart';

/// Wire values of supported operations. A payload's `op` outside this set
/// is rejected by rule — forward compatibility means IGNORING unknown ops,
/// not guessing at them.
abstract final class CrdtOps {
  static const String createIntent = 'create_intent';
  static const String lockIntent = 'lock_intent';
  static const String satisfyIntent = 'satisfy_intent';
  static const String withdrawIntent = 'withdraw_intent';
}

/// Fold outcome for one intent — diagnostics surface, not control flow.
class MaterializationReport {
  const MaterializationReport({
    required this.intentUuid,
    required this.applied,
    required this.rejectedSignature,
    required this.rejectedRule,
    required this.materialized,
  });

  final String intentUuid;

  /// Operations that passed verification + authorization and mutated state.
  final int applied;

  /// Operations dropped for signature failure — hostile or corrupt.
  final int rejectedSignature;

  /// Operations dropped for protocol-rule violations (wrong author,
  /// transition out of an absorbing state, malformed payload, op before
  /// create). Includes benign partition artifacts.
  final int rejectedRule;

  /// Whether a row was written this fold.
  final bool materialized;
}

class CrdtMaterializer implements DeltaApplier {
  CrdtMaterializer(this._repository);

  final MeshRepository _repository;

  /// Signature-verification cache: a transactionUuid verified once never
  /// needs re-verification on subsequent re-folds of the same log. Without
  /// this, every gossip batch re-verifies the entire history — O(n²)
  /// Ed25519 operations over the life of an intent.
  final Set<String> _verifiedTx = {};

  /// Known-bad transaction ids — cached too, so a hostile delta cannot
  /// force repeated verification work on every re-fold.
  final Set<String> _rejectedTx = {};

  /// Cumulative session counters for the diagnostics surface. Distinct
  /// hostile/corrupt ops are counted once (the _rejectedTx cache absorbs
  /// re-fold repeats); rule rejections include benign partition artifacts
  /// by design — see MaterializationReport.
  int get totalRejectedSignatures => _rejectedTx.length;
  int totalApplied = 0;
  int totalRejectedRule = 0;
  int totalFolds = 0;

  @override
  Future<void> applyDeltas(List<CrdtStateLog> deltas) async {
    final targets = <String>{for (final d in deltas) d.targetIntentUuid};
    for (final intentUuid in targets) {
      await materializeIntent(intentUuid);
    }
  }

  /// Full re-fold of one intent's causal log. Deterministic: two devices
  /// holding the same log rows produce byte-identical intent state.
  Future<MaterializationReport> materializeIntent(String intentUuid) async {
    final log = await _repository.readCausalLog(intentUuid);
    var applied = 0;
    var rejectedSignature = 0;
    var rejectedRule = 0;

    ResourceIntent? state;

    for (final op in log) {
      // --- Parse + authenticate. ------------------------------------------
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

      if (!await _isSignatureValid(op, author)) {
        rejectedSignature += 1;
        continue;
      }

      // --- Apply under protocol rules. -------------------------------------
      switch (payload['op']) {
        case CrdtOps.createIntent:
          if (state != null) {
            // Duplicate create: first in causal order wins, deterministically
            // — both forks converge on the same winner via causalCompare.
            rejectedRule += 1;
            continue;
          }
          final built = _buildIntent(payload, author, intentUuid);
          if (built == null) {
            rejectedRule += 1;
            continue;
          }
          state = built;
          applied += 1;

        case CrdtOps.lockIntent ||
              CrdtOps.satisfyIntent ||
              CrdtOps.withdrawIntent:
          if (state == null) {
            // Op causally precedes create, or create hasn't gossiped here
            // yet. Benign under partition — the re-fold on create arrival
            // will apply it.
            rejectedRule += 1;
            continue;
          }
          if (author != state.originNodeKey) {
            // Authorization invariant: only the intent's owner authors its
            // status transitions. A valid signature under the WRONG key is
            // still a rejection — authentication is not authorization.
            rejectedRule += 1;
            continue;
          }
          if (state.status == IntentStatus.satisfied ||
              state.status == IntentStatus.withdrawn) {
            // Absorbing states: nothing transitions out. Prevents a stale
            // fork from resurrecting a completed exchange.
            rejectedRule += 1;
            continue;
          }
          state.status = switch (payload['op']) {
            CrdtOps.lockIntent => IntentStatus.lockedInLoop,
            CrdtOps.satisfyIntent => IntentStatus.satisfied,
            _ => IntentStatus.withdrawn,
          };
          applied += 1;

        default:
          rejectedRule += 1; // Unknown op from a newer protocol version.
      }
    }

    if (state != null) {
      await _repository.upsertIntent(state);
    }

    // Re-folds recount applied ops; the counter tracks fold WORK, which
    // is what the diagnostics surface is for — not unique-op accounting.
    totalFolds += 1;
    totalApplied += applied;
    totalRejectedRule += rejectedRule;

    return MaterializationReport(
      intentUuid: intentUuid,
      applied: applied,
      rejectedSignature: rejectedSignature,
      rejectedRule: rejectedRule,
      materialized: state != null,
    );
  }

  Future<bool> _isSignatureValid(CrdtStateLog op, String authorKey) async {
    if (_verifiedTx.contains(op.transactionUuid)) return true;
    if (_rejectedTx.contains(op.transactionUuid)) return false;

    final valid = await verifyEd25519Hex(
      message: crdtSignaturePreimage(
        op.operationPayloadJson,
        op.lamportLogicalClock,
      ),
      signatureHex: op.authoritySignature,
      publicKeyHex: authorKey,
    );
    (valid ? _verifiedTx : _rejectedTx).add(op.transactionUuid);
    return valid;
  }

  /// Strict construction from a create_intent payload. Any structural
  /// violation returns null (rule rejection) — a materializer that guesses
  /// at malformed remote data materializes garbage mesh-wide.
  ResourceIntent? _buildIntent(
    Map<String, dynamic> payload,
    String author,
    String expectedUuid,
  ) {
    final intent = payload['intent'];
    if (intent is! Map<String, dynamic>) return null;

    final uuid = intent['intentUuid'];
    final origin = intent['originNodeKey'];
    final category = intent['category'];
    final direction = intent['direction'];
    final rawText = intent['rawText'];
    final vector = intent['vector'];
    final quantity = intent['quantity'];
    final epochMs = intent['epochMs'];

    if (uuid is! String ||
        origin is! String ||
        category is! String ||
        direction is! String ||
        rawText is! String ||
        vector is! List ||
        quantity is! int ||
        epochMs is! int) {
      return null;
    }

    // Binding invariants: the op must target the uuid it claims, and only
    // the origin node may create its own intent.
    if (uuid != expectedUuid) return null;
    if (origin != author) return null;
    if (vector.length != kEmbeddingDimensions) return null;

    final vectorData = <double>[];
    for (final v in vector) {
      if (v is! num) return null;
      vectorData.add(v.toDouble());
    }

    try {
      return ResourceIntent(
        intentUuid: uuid,
        originNodeKey: origin,
        allocationCategory: AllocationCategory.fromWire(category),
        direction: IntentDirection.fromWire(direction),
        rawTextPayload: rawText,
        vectorData: vectorData,
        structuralQuantity: quantity,
        epochTimestamp: epochMs,
      );
      // Status is deliberately NOT read from the payload: intents are born
      // `open`; every later state is a separate signed operation. Letting
      // create ops smuggle in a status would bypass the transition rules.
    } on FormatException {
      return null; // Unknown category/direction wire value.
    }
  }
}
