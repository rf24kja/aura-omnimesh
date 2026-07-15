// lib/domain/domain_models.dart
//
// Isar collections for the local-first CRDT sync layer.
// Run codegen after any schema change:
//   dart run build_runner build --delete-conflicting-outputs
//
// pubspec.yaml (minimum):
//   dependencies:
//     isar_community: ^3.3.2
//     isar_community_flutter_libs: ^3.3.2
//   dev_dependencies:
//     isar_community_generator: ^3.3.2
//     build_runner: ^2.4.0

import 'package:isar_community/isar.dart';

part 'domain_models.g.dart';

/// Semantic dimensionality of the on-device embedding model
/// (e.g. all-MiniLM-L6-v2 → 384). Kept as a compile-time constant so the
/// inference layer and storage layer can never drift apart.
const int kEmbeddingDimensions = 384;

/// Typed allocation categories. Persisted by name (stable string values in
/// the DB) instead of ordinal, so reordering the enum never corrupts data.
enum AllocationCategory {
  peerExchange('peer_exchange'),
  computeAllocation('compute_allocation'),
  energyTelemetry('energy_telemetry');

  const AllocationCategory(this.wireValue);

  /// Canonical value used on the mesh wire protocol / JSON payloads.
  final String wireValue;

  static AllocationCategory fromWire(String value) =>
      AllocationCategory.values.firstWhere(
        (c) => c.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown AllocationCategory wire value: "$value"',
        ),
      );
}

/// Directionality of an intent inside the exchange graph. Ring matching is
/// impossible without it: an edge A→B exists only when A's OFFER satisfies
/// B's NEED. Persisted by name; default keeps pre-migration rows valid
/// (Isar backfills new fields with the initializer value).
enum IntentDirection {
  offer('offer'),
  need('need');

  const IntentDirection(this.wireValue);
  final String wireValue;

  static IntentDirection fromWire(String value) =>
      IntentDirection.values.firstWhere(
        (d) => d.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown IntentDirection wire value: "$value"',
        ),
      );
}

/// Lifecycle of an intent inside the exchange protocol. Status transitions
/// are CRDT operations (gossiped, signed), never bare local mutations —
/// otherwise two partitions could lock the same intent into different
/// rings and diverge.
enum IntentStatus {
  open('open'),
  lockedInLoop('locked_in_loop'),
  satisfied('satisfied'),
  withdrawn('withdrawn');

  const IntentStatus(this.wireValue);
  final String wireValue;

  static IntentStatus fromWire(String value) =>
      IntentStatus.values.firstWhere(
        (s) => s.wireValue == value,
        orElse: () => throw FormatException(
          'Unknown IntentStatus wire value: "$value"',
        ),
      );
}

// ---------------------------------------------------------------------------
// NodeIdentity
// ---------------------------------------------------------------------------

@collection
class NodeIdentity {
  NodeIdentity({
    required this.cryptographicPublicKey,
    required this.localAlias,
    this.reliabilityScore = 0,
  });

  Id id = Isar.autoIncrement;

  /// Hex-encoded Ed25519 public key (64 lowercase hex chars / 32 bytes).
  /// Hash index: exact-match lookups only, O(1), minimal index size.
  @Index(unique: true, replace: false, type: IndexType.hash)
  late String cryptographicPublicKey;

  late String localAlias;

  /// Locally derived trust metric (0–100). Never trusted from remote peers;
  /// recomputed from signed transaction history on this device.
  late int reliabilityScore;

  /// Defensive validation before persisting an identity received off-mesh.
  bool get hasValidKeyFormat =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(cryptographicPublicKey);
}

// ---------------------------------------------------------------------------
// ResourceIntent
// ---------------------------------------------------------------------------

@collection
class ResourceIntent {
  ResourceIntent({
    required this.intentUuid,
    required this.originNodeKey,
    required this.allocationCategory,
    required this.rawTextPayload,
    required this.vectorData,
    required this.structuralQuantity,
    required this.epochTimestamp,
    this.direction = IntentDirection.offer,
  }) : assert(
          vectorData.length == kEmbeddingDimensions,
          'vectorData must be exactly $kEmbeddingDimensions dimensions',
        );

  Id id = Isar.autoIncrement;

  /// UUIDv4. Hash index — intents are addressed by exact id on the mesh.
  @Index(unique: true, replace: true, type: IndexType.hash)
  late String intentUuid;

  /// Foreign reference to [NodeIdentity.cryptographicPublicKey].
  /// Kept as an indexed denormalized key (not IsarLink) so CRDT deltas can
  /// arrive before the identity record does (partition tolerance).
  @Index(type: IndexType.hash)
  late String originNodeKey;

  @Enumerated(EnumType.name)
  late AllocationCategory allocationCategory;

  /// Offer vs need — drives edge orientation in the exchange graph.
  /// Non-late with initializer: Isar backfills pre-migration rows with
  /// `offer` instead of failing the schema upgrade.
  @Enumerated(EnumType.name)
  IntentDirection direction = IntentDirection.offer;

  /// Exchange lifecycle state. Migration-safe default: pre-existing rows
  /// backfill as `open`. Only `open` intents participate in ring matching.
  @Enumerated(EnumType.name)
  IntentStatus status = IntentStatus.open;

  late String rawTextPayload;

  /// Float32-backed list (`float` is Isar's 4-byte typedef of double).
  /// 384 dims × 4 bytes = 1.5 KB per row instead of 3 KB with float64 —
  /// halves the memory-mapped footprint for local semantic search.
  late List<float> vectorData;

  /// Unit depends on category: item count (peer_exchange),
  /// tokens/sec (compute_allocation), watt-hours (energy_telemetry).
  late int structuralQuantity;

  /// Unix epoch milliseconds, UTC. Indexed for recency scans in the UI.
  @Index()
  late int epochTimestamp;

  /// Cosine similarity against a query embedding. Runs on the raw list to
  /// avoid per-query allocations; returns 0.0 for degenerate vectors.
  double cosineSimilarity(List<double> query) {
    if (query.length != vectorData.length) {
      throw ArgumentError(
        'Dimension mismatch: ${query.length} vs ${vectorData.length}',
      );
    }
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < vectorData.length; i++) {
      dot += vectorData[i] * query[i];
      normA += vectorData[i] * vectorData[i];
      normB += query[i] * query[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (_sqrt(normA) * _sqrt(normB));
  }

  static double _sqrt(double x) {
    // Newton–Raphson to avoid importing dart:math into the model layer.
    if (x <= 0) return 0;
    var guess = x / 2;
    for (var i = 0; i < 12; i++) {
      guess = (guess + x / guess) / 2;
    }
    return guess;
  }
}

// ---------------------------------------------------------------------------
// CrdtStateLog
// ---------------------------------------------------------------------------

@collection
class CrdtStateLog {
  CrdtStateLog({
    required this.transactionUuid,
    required this.targetIntentUuid,
    required this.authoritySignature,
    required this.lamportLogicalClock,
    required this.operationPayloadJson,
  });

  Id id = Isar.autoIncrement;

  /// Idempotency key: a delta re-received via gossip is silently deduped.
  @Index(unique: true, replace: false, type: IndexType.hash)
  late String transactionUuid;

  /// Composite index: replay all operations for one intent in causal order
  /// with a single index scan — the hot path of CRDT state materialization.
  @Index(composite: [CompositeIndex('lamportLogicalClock')])
  late String targetIntentUuid;

  /// Hex-encoded Ed25519 signature over
  /// `utf8(operationPayloadJson) || lamportLogicalClock(le64)`.
  /// Verification happens in the crypto service before this row is written.
  late String authoritySignature;

  /// Lamport clock for causal ordering under partition. Ties are broken
  /// deterministically by comparing transactionUuid lexicographically.
  late int lamportLogicalClock;

  /// Serialized operation (op type, field deltas). Opaque to the storage
  /// layer; interpreted exclusively by the CRDT reconciliation engine.
  late String operationPayloadJson;

  /// Deterministic total order for merge: clock first, UUID as tiebreaker.
  static int causalCompare(CrdtStateLog a, CrdtStateLog b) {
    final byClock = a.lamportLogicalClock.compareTo(b.lamportLogicalClock);
    return byClock != 0
        ? byClock
        : a.transactionUuid.compareTo(b.transactionUuid);
  }
}
