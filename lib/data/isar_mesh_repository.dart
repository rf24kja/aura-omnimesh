// lib/data/isar_mesh_repository.dart
//
// Concrete Isar 3.x binding of MeshRepository (Core Mesh Nodes: iOS/Android).
// Depends on the generated code from domain_models.dart:
//   dart run build_runner build --delete-conflicting-outputs
//
// pubspec.yaml additions:
//   dependencies:
//     isar: ^3.1.0
//     isar_flutter_libs: ^3.1.0
//     path_provider: ^2.1.0

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/domain_models.dart';
import '../services/services.dart';

class IsarMeshRepository implements MeshRepository {
  IsarMeshRepository(this._isar);

  final Isar _isar;

  /// Convenience opener for Core Mesh Nodes. Web Light Clients must not
  /// call this — they bind a different backend behind [MeshRepository].
  static Future<IsarMeshRepository> open({String name = 'aura_omnimesh'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final isar = await Isar.open(
      [NodeIdentitySchema, ResourceIntentSchema, CrdtStateLogSchema],
      directory: dir.path,
      name: name,
      inspector: false,
    );
    return IsarMeshRepository(isar);
  }

  // -------------------------------------------------------------------------
  // NodeIdentity
  // -------------------------------------------------------------------------

  @override
  Future<int> upsertNodeIdentity(NodeIdentity node) async {
    if (!node.hasValidKeyFormat) {
      throw FormatException(
        'Rejected NodeIdentity with malformed Ed25519 hex key: '
        '"${node.cryptographicPublicKey}"',
      );
    }
    return _isar.writeTxn(() async {
      // Manual upsert keyed on the unique hash index. The public key index
      // is declared replace:false, so a blind put() of a duplicate key would
      // throw — instead we adopt the existing row id and merge fields,
      // preserving the locally computed reliabilityScore history semantics.
      final existing = await _isar.nodeIdentitys
          .getByCryptographicPublicKey(node.cryptographicPublicKey);
      if (existing != null) {
        node.id = existing.id;
      }
      return _isar.nodeIdentitys.put(node);
    });
  }

  @override
  Future<NodeIdentity?> findNodeByPublicKey(String publicKey) {
    return _isar.nodeIdentitys.getByCryptographicPublicKey(publicKey);
  }

  @override
  Stream<List<NodeIdentity>> watchAllNodes() {
    return _isar.nodeIdentitys.where().watch(fireImmediately: true);
  }

  // -------------------------------------------------------------------------
  // ResourceIntent
  // -------------------------------------------------------------------------

  @override
  Future<int> upsertIntent(ResourceIntent intent) async {
    if (intent.vectorData.length != kEmbeddingDimensions) {
      throw ArgumentError(
        'ResourceIntent.vectorData must be $kEmbeddingDimensions dims, '
        'got ${intent.vectorData.length}',
      );
    }
    return _isar.writeTxn(() {
      // intentUuid index is unique+replace: putBy overwrites the stale row
      // in place — CRDT-materialized state always wins over local copies.
      return _isar.resourceIntents.putByIntentUuid(intent);
    });
  }

  @override
  Future<ResourceIntent?> findIntentByUuid(String intentUuid) {
    return _isar.resourceIntents.getByIntentUuid(intentUuid);
  }

  @override
  Future<List<ResourceIntent>> readIntentsByCategory(
    AllocationCategory category, {
    IntentDirection? direction,
  }) {
    final base =
        _isar.resourceIntents.filter().allocationCategoryEqualTo(category);
    return direction == null
        ? base.findAll()
        : base.directionEqualTo(direction).findAll();
  }

  @override
  Future<List<ResourceIntent>> semanticSearch(
    List<double> queryEmbedding, {
    int limit = 20,
    double minSimilarity = 0.35,
    AllocationCategory? category,
  }) async {
    if (queryEmbedding.length != kEmbeddingDimensions) {
      throw ArgumentError(
        'Query embedding must be $kEmbeddingDimensions dims, '
        'got ${queryEmbedding.length}',
      );
    }
    if (limit <= 0) return const [];

    final List<ResourceIntent> candidates = category == null
        ? await _isar.resourceIntents.where().findAll()
        : await _isar.resourceIntents
            .filter()
            .allocationCategoryEqualTo(category)
            .findAll();

    // Baseline brute-force scan over Float32 vectors. Single pass to score,
    // then partial ordering by descending similarity. O(n·d) — fine for
    // on-device corpora; swap an ANN index behind this signature later.
    final scored = <({ResourceIntent intent, double score})>[];
    for (final intent in candidates) {
      final score = intent.cosineSimilarity(queryEmbedding);
      if (score >= minSimilarity) {
        scored.add((intent: intent, score: score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    return scored
        .take(limit)
        .map((entry) => entry.intent)
        .toList(growable: false);
  }

  // -------------------------------------------------------------------------
  // CrdtStateLog
  // -------------------------------------------------------------------------

  @override
  Future<int> appendDeltas(List<CrdtStateLog> deltas) async {
    if (deltas.isEmpty) return 0;

    return _isar.writeTxn(() async {
      // Idempotency pass 1: rows already persisted (gossip redelivery).
      // getAllByTransactionUuid preserves input order; null == not present.
      final existing = await _isar.crdtStateLogs.getAllByTransactionUuid(
        deltas.map((d) => d.transactionUuid).toList(growable: false),
      );

      // Idempotency pass 2: duplicates inside this same batch (a peer may
      // echo our own delta back within one gossip round).
      final seenInBatch = <String>{};
      final toWrite = <CrdtStateLog>[];
      for (var i = 0; i < deltas.length; i++) {
        if (existing[i] != null) continue;
        if (!seenInBatch.add(deltas[i].transactionUuid)) continue;
        toWrite.add(deltas[i]);
      }

      if (toWrite.isNotEmpty) {
        await _isar.crdtStateLogs.putAll(toWrite);
      }
      return toWrite.length;
    });
  }

  @override
  Future<List<CrdtStateLog>> readCausalLog(String targetIntentUuid) async {
    // Equality scan served by the (targetIntentUuid, lamportLogicalClock)
    // composite index. The in-memory sort applies the full deterministic
    // order including the UUID tiebreaker, which the index alone cannot
    // express — required for identical convergence across forks.
    final rows = await _isar.crdtStateLogs
        .filter()
        .targetIntentUuidEqualTo(targetIntentUuid)
        .findAll();
    rows.sort(CrdtStateLog.causalCompare);
    return rows;
  }

  @override
  Future<List<CrdtStateLog>> readDeltasSince(int afterLamportClock) async {
    final rows = await _isar.crdtStateLogs
        .filter()
        .lamportLogicalClockGreaterThan(afterLamportClock)
        .findAll();
    rows.sort(CrdtStateLog.causalCompare);
    return rows;
  }

  @override
  Future<int> currentLamportClock() async {
    final maxClock = await _isar.crdtStateLogs
        .where()
        .lamportLogicalClockProperty()
        .max();
    return maxClock ?? 0;
  }

  // -------------------------------------------------------------------------

  @override
  Future<void> dispose() async {
    await _isar.close();
  }
}
