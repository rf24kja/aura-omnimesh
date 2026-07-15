// lib/engine/reliability_scorer.dart
//
// Local reputation fold (ROADMAP Phase 1): recomputes
// NodeIdentity.reliabilityScore from the SIGNED history of completed
// rings. Scores derive exclusively from this device's own log — remote
// peers never ship scores (nodeIdentityFromWire pins them to 0), so a
// hostile node cannot inflate its own trust.
//
// Score model — deliberately blunt for Phase 1 and identical on every
// device holding the same log: +10 per DISTINCT completed ring the node
// provided a hop in, capped at 100. A ring counts as completed when
// every hop offer named by its canonicalId is materialized `satisfied`,
// i.e. after the full lock→satisfy protocol, every transition already
// signature- and ownership-checked by the CRDT fold.

import 'dart:async';
import 'dart:convert';

import '../domain/domain_models.dart';
import '../services/services.dart';

class ReliabilityScorer {
  ReliabilityScorer(this._repository);

  final MeshRepository _repository;

  static const int pointsPerRing = 10;
  static const int maxScore = 100;

  /// Debounce mirrors the adapter's rematch window: gossip bursts arrive
  /// as many batches; one trailing fold suffices.
  static const Duration _debounceWindow = Duration(milliseconds: 300);

  StreamSubscription<int>? _subscription;
  Timer? _debounce;
  bool _running = false;
  bool _queued = false;
  bool _disposed = false;

  /// Composition-root wiring: refold scores after every persisted batch.
  void attachTo(Stream<int> newDeltasPersisted) {
    _subscription ??= newDeltasPersisted.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(_debounceWindow, () => unawaited(recompute()));
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Recomputes scores for every node that provided a hop in a completed
  /// ring and upserts CHANGED NodeIdentity rows. Unknown identities are
  /// skipped — scoring attaches trust to known peers, it never fabricates
  /// identity rows. Returns the computed map (also for tests/diagnostics).
  Future<Map<String, int>> recompute() async {
    if (_disposed) return const {};
    // Coalescing guard, same shape as the adapter's rematch.
    if (_running) {
      _queued = true;
      return const {};
    }
    _running = true;
    try {
      return await _fold();
    } finally {
      _running = false;
      if (_queued && !_disposed) {
        _queued = false;
        unawaited(recompute());
      }
    }
  }

  Future<Map<String, int>> _fold() async {
    final log = await _repository.readDeltasSince(0);

    final ringIds = <String>{};
    for (final row in log) {
      try {
        final decoded = jsonDecode(row.operationPayloadJson);
        if (decoded is! Map<String, dynamic>) continue;
        if (decoded['op'] != 'lock_intent' &&
            decoded['op'] != 'satisfy_intent') {
          continue;
        }
        final ringId = decoded['ringId'];
        if (ringId is String) ringIds.add(ringId);
      } on FormatException {
        // Hostile or malformed payloads are non-events for scoring.
      }
    }

    // ringId → hop owners, kept only for fully satisfied rings.
    final completedPerNode = <String, Set<String>>{};
    for (final ringId in ringIds) {
      final offerUuids = ringId.split('>');
      if (offerUuids.length < 2) continue;

      final owners = <String>{};
      var completed = true;
      for (final uuid in offerUuids) {
        final offer = await _repository.findIntentByUuid(uuid);
        if (offer == null || offer.status != IntentStatus.satisfied) {
          completed = false;
          break;
        }
        owners.add(offer.originNodeKey);
      }
      if (!completed) continue;

      for (final owner in owners) {
        completedPerNode.putIfAbsent(owner, () => {}).add(ringId);
      }
    }

    final scores = <String, int>{};
    for (final entry in completedPerNode.entries) {
      final score =
          (entry.value.length * pointsPerRing).clamp(0, maxScore);
      scores[entry.key] = score;

      final node = await _repository.findNodeByPublicKey(entry.key);
      if (node != null && node.reliabilityScore != score) {
        node.reliabilityScore = score;
        await _repository.upsertNodeIdentity(node);
      }
    }
    return scores;
  }
}
