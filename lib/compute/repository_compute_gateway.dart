// lib/compute/repository_compute_gateway.dart
//
// Production ComputeTaskGateway backed by the same MeshRepository + MeshSyncEngine
// that Module A uses. This is the wire that connects the tested compute logic
// (worker, requester, fold) to the live signed CRDT log — offers gossip out and
// results gossip back through the ordinary engine, no new transport.
//
// Offered-task discovery is a log scan (find compute_task_* op targets, fold
// each): correct and schema-free, which keeps Module B off the fragile Isar
// codegen path for now. A persisted ComputeTask row (materializer-written,
// queryable) is the scale path when task volume warrants it — see
// docs/MODULE_B_DESIGN.md §5.

import 'dart:convert';

import '../domain/domain_models.dart';
import '../engine/mesh_sync_engine.dart';
import '../services/services.dart';
import 'compute_task.dart';
import 'swarm_compute_worker.dart' show ComputeTaskGateway;

class RepositoryComputeTaskGateway implements ComputeTaskGateway {
  RepositoryComputeTaskGateway({
    required MeshRepository repository,
    required MeshSyncEngine engine,
  })  : _repository = repository,
        _engine = engine;

  final MeshRepository _repository;
  final MeshSyncEngine _engine;

  @override
  Future<int> currentClock() => _repository.currentLamportClock();

  @override
  Future<List<CrdtStateLog>> taskLog(String taskUuid) =>
      _repository.readCausalLog(taskUuid);

  @override
  Future<void> publish(List<CrdtStateLog> ops) =>
      _engine.publishLocalDeltas(ops);

  @override
  Future<List<String>> offeredTaskUuids() async {
    // readDeltasSince is strictly-greater-than; clocks start at 0, so -1
    // selects the entire durable log.
    final all = await _repository.readDeltasSince(-1);
    final candidates = <String>{};
    for (final d in all) {
      final op = _peekOp(d.operationPayloadJson);
      if (op != null && op.startsWith('compute_task_')) {
        candidates.add(d.targetIntentUuid);
      }
    }
    final offered = <String>[];
    for (final uuid in candidates) {
      final state =
          (await foldComputeTask(await _repository.readCausalLog(uuid))).state;
      if (state?.status == ComputeTaskStatus.offered) offered.add(uuid);
    }
    return offered;
  }

  /// Cheap op-name peek without a full typed decode.
  String? _peekOp(String operationPayloadJson) {
    try {
      final decoded = jsonDecode(operationPayloadJson);
      final op = decoded is Map ? decoded['op'] : null;
      return op is String ? op : null;
    } on FormatException {
      return null;
    }
  }
}
