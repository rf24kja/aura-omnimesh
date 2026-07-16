// lib/matching/ring_matcher.dart
//
// Module A core: closed-loop multilateral exchange matching.
// Builds a directed exchange graph over local ResourceIntents (edge A→B
// exists when A's OFFER semantically satisfies B's NEED) and enumerates
// simple cycles of length 3–7 — the "A codes for B, B lends a scooter to
// C, C supplies groceries to A" rings.
//
// Pure Dart, zero I/O in the algorithm core (fully unit-testable);
// RingMatchFacade at the bottom binds it to MeshRepository.
//
// Complexity control: candidate pairing is O(offers × needs × dims) and
// cycle search is bounded DFS with a hard expansion budget — local corpora
// (hundreds of intents, dozens of nodes) resolve in milliseconds; the
// budget guarantees a degenerate dense graph degrades to "best rings found
// so far" instead of freezing the UI isolate.

import '../domain/domain_models.dart';
import '../services/services.dart';

// ---------------------------------------------------------------------------
// Result models
// ---------------------------------------------------------------------------

/// One hop of a ring: [provider]'s offer satisfies [receiver]'s need.
class ExchangeEdge {
  const ExchangeEdge({
    required this.providerKey,
    required this.receiverKey,
    required this.offer,
    required this.need,
    required this.similarity,
  });

  final String providerKey;
  final String receiverKey;
  final ResourceIntent offer;
  final ResourceIntent need;

  /// Cosine similarity offer↔need in [0, 1] (embeddings are L2-normalized
  /// per EdgeInferenceService contract).
  final double similarity;
}

/// A closed loop of 3–7 participants where every node gives exactly one
/// offer and receives exactly one need. edges[i].receiverKey ==
/// edges[i+1].providerKey, and the last edge closes back to the first.
class BarterRing {
  BarterRing({required this.edges})
      : assert(edges.length >= 2),
        minSimilarity = edges
            .map((e) => e.similarity)
            .reduce((a, b) => a < b ? a : b),
        meanSimilarity =
            edges.map((e) => e.similarity).reduce((a, b) => a + b) /
                edges.length;

  final List<ExchangeEdge> edges;

  /// The weakest hop. Primary ranking key: a ring is only as convincing
  /// to its participants as its worst match — one bad hop and someone
  /// declines, collapsing the whole loop.
  final double minSimilarity;

  final double meanSimilarity;

  int get participantCount => edges.length;

  List<String> get participantKeys =>
      edges.map((e) => e.providerKey).toList(growable: false);

  /// Rotation-invariant identity: the same cycle discovered from any
  /// starting node maps to one id. Used for dedup and for addressing the
  /// ring in CRDT confirmation operations.
  String get canonicalId {
    final uuids = edges.map((e) => e.offer.intentUuid).toList();
    var best = 0;
    for (var i = 1; i < uuids.length; i++) {
      if (uuids[i].compareTo(uuids[best]) < 0) best = i;
    }
    final rotated = [...uuids.sublist(best), ...uuids.sublist(0, best)];
    return rotated.join('>');
  }

  /// Deterministic ranking: strongest weakest-hop first, mean as
  /// tiebreaker, canonicalId as the total-order anchor (two devices
  /// ranking the same graph MUST produce the same list — divergent
  /// rankings would have peers confirming different rings).
  static int rank(BarterRing a, BarterRing b) {
    final byMin = b.minSimilarity.compareTo(a.minSimilarity);
    if (byMin != 0) return byMin;
    final byMean = b.meanSimilarity.compareTo(a.meanSimilarity);
    if (byMean != 0) return byMean;
    return a.canonicalId.compareTo(b.canonicalId);
  }
}

// ---------------------------------------------------------------------------
// Matcher core (pure)
// ---------------------------------------------------------------------------

class RingMatcher {
  const RingMatcher({
    this.similarityThreshold = 0.45,
    this.minRingLength = 3,
    this.maxRingLength = 7,
    this.maxResults = 20,
    this.expansionBudget = 200000,
  })  : assert(minRingLength >= 2),
        assert(maxRingLength >= minRingLength && maxRingLength <= 12),
        assert(similarityThreshold > 0 && similarityThreshold < 1);

  /// Minimum offer↔need cosine to admit an edge into the graph.
  /// Calibrated 2026-07 on a 40-pair bilingual ad corpus against the
  /// bundled paraphrase-multilingual-MiniLM-L12-v2 int8: at 0.45
  /// English recall 100% / 0.7% false accepts, Russian 87% / 2.9%
  /// (tool/calibrate_threshold.mjs). Cross-lingual pairs pay roughly a
  /// 0.15–0.2 similarity discount — near-translations clear the bar
  /// (овощи↔vegetables 0.80), loose paraphrases may not (0.24–0.43).
  /// Every node must use the SAME threshold or ring discovery diverges
  /// across the mesh.
  final double similarityThreshold;

  final int minRingLength;
  final int maxRingLength;
  final int maxResults;

  /// Hard cap on DFS node expansions across the whole search.
  final int expansionBudget;

  /// Enumerates the top rings in the given intent snapshot.
  ///
  /// Guarantees:
  ///  - Each participant appears at most once per ring.
  ///  - Self-satisfaction is excluded (a node's offer never feeds its own
  ///    need — that's not an exchange).
  ///  - Every cycle is reported exactly once (canonical-start DFS).
  ///  - Output order is fully deterministic across devices.
  List<BarterRing> findRings(List<ResourceIntent> intents) {
    // --- Phase 1: split and pair. -----------------------------------------
    final offers = <ResourceIntent>[];
    final needs = <ResourceIntent>[];
    for (final intent in intents) {
      switch (intent.direction) {
        case IntentDirection.offer:
          offers.add(intent);
        case IntentDirection.need:
          needs.add(intent);
      }
    }
    if (offers.isEmpty || needs.isEmpty) return const [];

    // Adjacency: providerKey → outgoing edges, keeping only the BEST edge
    // per (provider, receiver) node pair. Multiple matching offer/need
    // combinations between the same two people collapse to the strongest;
    // parallel edges only multiply the cycle count without adding
    // materially different rings.
    final bestEdge = <String, Map<String, ExchangeEdge>>{};
    for (final offer in offers) {
      for (final need in needs) {
        if (offer.originNodeKey == need.originNodeKey) continue;
        final similarity = offer.cosineSimilarity(need.vectorData);
        if (similarity < similarityThreshold) continue;

        final perProvider =
            bestEdge.putIfAbsent(offer.originNodeKey, () => {});
        final current = perProvider[need.originNodeKey];
        if (current == null || similarity > current.similarity) {
          perProvider[need.originNodeKey] = ExchangeEdge(
            providerKey: offer.originNodeKey,
            receiverKey: need.originNodeKey,
            offer: offer,
            need: need,
            similarity: similarity,
          );
        }
      }
    }
    if (bestEdge.isEmpty) return const [];

    // Sorted adjacency lists → deterministic traversal order.
    final adjacency = <String, List<ExchangeEdge>>{
      for (final entry in bestEdge.entries)
        entry.key: entry.value.values.toList()
          ..sort((a, b) => a.receiverKey.compareTo(b.receiverKey)),
    };

    // --- Phase 2: canonical-start bounded DFS. ----------------------------
    // Convention: a cycle is discovered only from its lexicographically
    // smallest participant key, and the DFS never descends into keys
    // smaller than the start. Each simple cycle is therefore emitted
    // exactly once — no post-hoc dedup pass needed.
    final startKeys = adjacency.keys.toList()..sort();
    final results = <BarterRing>[];
    var budget = expansionBudget;

    for (final start in startKeys) {
      if (budget <= 0) break;
      final path = <ExchangeEdge>[];
      final onPath = <String>{start};

      void dfs(String current) {
        if (budget <= 0) return;
        final outgoing = adjacency[current];
        if (outgoing == null) return;

        for (final edge in outgoing) {
          if (budget-- <= 0) return;
          final next = edge.receiverKey;

          // Closing edge back to start ⇒ candidate ring.
          if (next == start) {
            final length = path.length + 1;
            if (length >= minRingLength && length <= maxRingLength) {
              results.add(BarterRing(edges: [...path, edge]));
            }
            continue;
          }

          // Canonical-start constraint + simple-cycle constraint.
          if (next.compareTo(start) <= 0) continue;
          if (onPath.contains(next)) continue;
          if (path.length + 1 >= maxRingLength) continue;

          path.add(edge);
          onPath.add(next);
          dfs(next);
          onPath.remove(next);
          path.removeLast();
        }
      }

      dfs(start);
    }

    // --- Phase 3: deterministic ranking + cap. ----------------------------
    results.sort(BarterRing.rank);
    return results.length > maxResults
        ? results.sublist(0, maxResults)
        : results;
  }
}

// ---------------------------------------------------------------------------
// Repository facade
// ---------------------------------------------------------------------------

/// Binds the pure matcher to stored state. Re-run [findRings] whenever
/// MeshSyncEngine.onNewDeltasPersisted fires — freshly gossiped intents
/// may have just closed a loop that was previously open.
class RingMatchFacade {
  const RingMatchFacade({
    required MeshRepository repository,
    this.matcher = const RingMatcher(),
  }) : _repository = repository;

  final MeshRepository _repository;
  final RingMatcher matcher;

  /// Pulls the peer-exchange corpus from storage and matches rings over
  /// it. Only OPEN intents participate: locked/satisfied/withdrawn ones
  /// re-entering the graph would double-commit the same resource into
  /// multiple rings. CPU-bound phase is synchronous on purpose: on native,
  /// wrap the call in Isolate.run for corpora beyond ~1k intents; on web
  /// (no isolates) the expansion budget keeps worst-case latency bounded.
  Future<List<BarterRing>> findRings() async {
    final corpus = await _repository.readIntentsByCategory(
      AllocationCategory.peerExchange,
    );
    final open = corpus
        .where((i) => i.status == IntentStatus.open)
        .toList(growable: false);
    return matcher.findRings(open);
  }
}
