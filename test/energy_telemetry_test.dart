// Module C phase 4 — the reading → row pipeline. Verifies the downsampler
// keeps the log bounded, the create_intent payload is well-formed, and that
// publishing lands energyTelemetry rows the GRID tab can read — all through the
// REAL MeshSyncEngine + CrdtMaterializer, with no hardware.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/energy/energy_telemetry.dart';
import 'package:omnimesh/energy/modbus_registers.dart';
import 'package:omnimesh/crypto/ed25519_signer.dart';
import 'package:omnimesh/domain/domain_models.dart';
import 'package:omnimesh/engine/crdt_materializer.dart';
import 'package:omnimesh/engine/mesh_sync_engine.dart';
import 'package:omnimesh/main.dart' show InMemoryMeshRepository;
import 'package:omnimesh/services/services.dart';

class _FakeTransport implements LocalMeshTransportService {
  final _nodes = StreamController<NodeDiscoveryEvent>.broadcast();
  final _deltas = StreamController<List<CrdtStateLog>>.broadcast();
  @override
  Stream<NodeDiscoveryEvent> get onNodeDiscovered => _nodes.stream;
  @override
  Stream<List<CrdtStateLog>> get onDeltaReceived => _deltas.stream;
  @override
  Future<void> startDiscovery({required NodeIdentity selfIdentity}) async {}
  @override
  Future<void> stopDiscovery() async {}
  @override
  Future<void> broadcastDelta(List<CrdtStateLog> e) async {}
  @override
  Future<void> sendDeltaToPeer(String p, List<CrdtStateLog> e) async {}
  @override
  Future<void> dispose() async {
    await _nodes.close();
    await _deltas.close();
  }
}

EnergyReading _reading(String metric, int wholeUnits, {String unit = 'W'}) =>
    EnergyReading(
        metric: metric,
        raw: wholeUnits,
        milliValue: wholeUnits * 1000,
        unit: unit);

void main() {
  group('EnergyDownsampler', () {
    final t0 = DateTime.utc(2026, 1, 1, 12);

    test('first sample of a metric always publishes', () {
      final d = EnergyDownsampler(changeThreshold: 10);
      expect(d.select([_reading('pv', 100)], t0).length, 1);
    });

    test('a sub-threshold change within the interval is suppressed', () {
      final d = EnergyDownsampler(
          changeThreshold: 10, minInterval: const Duration(minutes: 1));
      d.select([_reading('pv', 100)], t0);
      expect(
        d.select([_reading('pv', 105)], t0.add(const Duration(seconds: 1))),
        isEmpty,
      );
    });

    test('a change at or above the threshold publishes immediately', () {
      final d = EnergyDownsampler(changeThreshold: 10);
      d.select([_reading('pv', 100)], t0);
      expect(
        d.select([_reading('pv', 120)], t0.add(const Duration(seconds: 1))),
        hasLength(1),
      );
    });

    test('an unchanged metric still publishes after the heartbeat interval',
        () {
      final d = EnergyDownsampler(
          changeThreshold: 10, minInterval: const Duration(minutes: 1));
      d.select([_reading('pv', 100)], t0);
      expect(d.select([_reading('pv', 100)], t0.add(const Duration(seconds: 5))),
          isEmpty);
      expect(
        d.select([_reading('pv', 100)], t0.add(const Duration(minutes: 2))),
        hasLength(1),
      );
    });
  });

  test('energyCreateIntentPayload has the energyTelemetry row shape', () {
    final p = energyCreateIntentPayload(
      intentUuid: 'u1',
      authorKey: 'ak',
      reading: _reading('battery_soc', 85, unit: '%'),
      epochMs: 5,
    );
    expect(p['op'], CrdtOps.createIntent);
    final intent = p['intent'] as Map<String, dynamic>;
    expect(intent['category'], 'energy_telemetry');
    expect(intent['rawText'], 'battery_soc');
    expect(intent['quantity'], 85);
    expect((intent['vector'] as List).length, kEmbeddingDimensions);
  });

  test('publish lands energyTelemetry rows through the real engine', () async {
    final repository = InMemoryMeshRepository();
    final materializer = CrdtMaterializer(repository);
    final transport = _FakeTransport();
    final engine = MeshSyncEngine(
      repository: repository,
      transport: transport,
      applier: materializer,
    );
    final signer = await Ed25519IdentitySigner.generate();
    final publisher = EnergyTelemetryPublisher(
      signer: signer,
      repository: repository,
      engine: engine,
      downsampler: EnergyDownsampler(changeThreshold: 1),
    );

    final t0 = DateTime.utc(2026, 1, 1, 12);
    final n = await publisher.publish([
      _reading('battery_soc', 85, unit: '%'),
      _reading('pv_power', 100000),
    ], now: t0);
    expect(n, 2);

    final rows =
        await repository.readIntentsByCategory(AllocationCategory.energyTelemetry);
    expect(rows.length, 2);
    final soc = rows.firstWhere((r) => r.rawTextPayload == 'battery_soc');
    expect(soc.structuralQuantity, 85);
    expect(soc.allocationCategory, AllocationCategory.energyTelemetry);

    // A repeat identical reading within the interval is downsampled away — no
    // new row, and no rejected op (the fold stays clean).
    final n2 = await publisher.publish(
        [_reading('battery_soc', 85, unit: '%')],
        now: t0.add(const Duration(seconds: 1)));
    expect(n2, 0);
    expect(
      (await repository.readIntentsByCategory(AllocationCategory.energyTelemetry))
          .length,
      2,
    );
    expect(materializer.totalRejectedSignatures, 0);
    expect(materializer.totalRejectedRule, 0);

    await engine.dispose();
    await transport.dispose();
  });
}
