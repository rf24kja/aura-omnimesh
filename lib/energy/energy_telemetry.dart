// lib/energy/energy_telemetry.dart
//
// Module C phase 4 — the reading → row pipeline. Decoded EnergyReadings are
// downsampled, turned into signed create_intent ops with the energyTelemetry
// category, and published through the same engine + materializer as Module A;
// the GRID tab reads the resulting rows (readIntentsByCategory). See
// docs/MODULE_C_DESIGN.md §3.
//
// Reusing ResourceIntent means every energy op carries a 384-dim zero vector
// (the schema requires it). Together with the durable, gossiped log that makes
// high-frequency telemetry expensive, so the DOWNSAMPLER is not optional — it
// is what keeps the log bounded. A vector-free energy row is the eventual
// scale fix (schema change, deferred).

import 'dart:convert';

import '../crypto/ed25519_signer.dart';
import '../domain/domain_models.dart';
import '../engine/crdt_materializer.dart' show CrdtOps;
import '../engine/mesh_sync_engine.dart';
import '../services/services.dart';
import 'modbus_registers.dart';

/// Rate-limits energy readings so the durable log stays bounded: a metric is
/// published when its whole-unit value moved by at least [changeThreshold], OR
/// [minInterval] has elapsed since it was last published (a heartbeat). Pure
/// and stateful; the "last published" clock advances only on publish, never on
/// a suppressed sample.
class EnergyDownsampler {
  EnergyDownsampler({
    this.minInterval = const Duration(minutes: 1),
    this.changeThreshold = 1,
  });

  final Duration minInterval;
  final int changeThreshold;

  final Map<String, ({int value, DateTime at})> _last = {};

  List<EnergyReading> select(List<EnergyReading> readings, DateTime now) {
    final out = <EnergyReading>[];
    for (final r in readings) {
      final prev = _last[r.metric];
      final changed =
          prev == null || (r.wholeUnits - prev.value).abs() >= changeThreshold;
      final heartbeat = prev == null || now.difference(prev.at) >= minInterval;
      if (changed || heartbeat) {
        _last[r.metric] = (value: r.wholeUnits, at: now);
        out.add(r);
      }
    }
    return out;
  }
}

/// The signed create_intent payload for an energy reading. Reuses the frozen
/// intent create op (folded by the materializer into a row) — no new op type.
/// The 384-dim zero vector satisfies the ResourceIntent schema; energy rows are
/// never semantically matched (the matcher filters to peerExchange).
Map<String, dynamic> energyCreateIntentPayload({
  required String intentUuid,
  required String authorKey,
  required EnergyReading reading,
  required int epochMs,
}) =>
    <String, dynamic>{
      'op': CrdtOps.createIntent,
      'author': authorKey,
      'intent': <String, dynamic>{
        'intentUuid': intentUuid,
        'originNodeKey': authorKey,
        'category': AllocationCategory.energyTelemetry.wireValue,
        'direction': IntentDirection.offer.wireValue,
        'rawText': reading.metric,
        'vector': List<double>.filled(kEmbeddingDimensions, 0.0),
        'quantity': reading.wholeUnits,
        'epochMs': epochMs,
      },
    };

/// Publishes downsampled energy readings as signed rows through the engine.
class EnergyTelemetryPublisher {
  EnergyTelemetryPublisher({
    required IdentitySigner signer,
    required MeshRepository repository,
    required MeshSyncEngine engine,
    EnergyDownsampler? downsampler,
  })  : _signer = signer,
        _repository = repository,
        _engine = engine,
        _downsampler = downsampler ?? EnergyDownsampler();

  final IdentitySigner _signer;
  final MeshRepository _repository;
  final MeshSyncEngine _engine;
  final EnergyDownsampler _downsampler;

  /// Downsample [readings] and publish the survivors. Returns how many rows
  /// were written. [now] is injectable for tests.
  Future<int> publish(List<EnergyReading> readings, {DateTime? now}) async {
    final clockNow = now ?? DateTime.now();
    final selected = _downsampler.select(readings, clockNow);
    if (selected.isEmpty) return 0;

    final ops = <CrdtStateLog>[];
    var clock = await _repository.currentLamportClock();
    for (final reading in selected) {
      clock += 1;
      final uuid = secureUuidV4();
      // The exact string we sign is the exact string we store, so the
      // materializer re-derives an identical preimage — no canonical ordering
      // needed here.
      final payload = jsonEncode(energyCreateIntentPayload(
        intentUuid: uuid,
        authorKey: _signer.publicKeyHex,
        reading: reading,
        epochMs: clockNow.millisecondsSinceEpoch,
      ));
      ops.add(CrdtStateLog(
        transactionUuid: secureUuidV4(),
        targetIntentUuid: uuid,
        authoritySignature:
            await _signer.signToHex(crdtSignaturePreimage(payload, clock)),
        lamportLogicalClock: clock,
        operationPayloadJson: payload,
      ));
    }
    await _engine.publishLocalDeltas(ops);
    return ops.length;
  }
}
