// SwarmComputeGate fail-closed hardening (CLAUDE.md invariant 4):
// telemetry we cannot fully verify counts AGAINST eligibility, never for
// it — a gate that guesses "probably fine" is how you cook a stranger's
// battery. Native telemetry is untrusted input; wrong types and errors
// must degrade to `indeterminate`, never crash and never grant work.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:omnimesh/compute/swarm_compute_gate.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('aura-omnimesh/telemetry');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Drives one gate through its immediate first poll with [handler] as
  /// the native side, and returns the resulting eligibility.
  Future<ComputeEligibility> evaluate(
    Future<Object?> Function() handler, {
    Set<String> trusted = const {'home-wifi'},
  }) async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'readTelemetry');
      return handler();
    });
    final gate = SwarmComputeGate(trustedSsids: trusted);
    await gate.start(); // start() awaits the first _poll().
    final result = gate.eligibility.value;
    await gate.dispose();
    return result;
  }

  Map<String, Object?> telemetry({
    Object? charging = true,
    Object? temp = 30.0,
    Object? ssid = 'home-wifi',
  }) =>
      {'isCharging': charging, 'batteryTemp': temp, 'wifiSsid': ssid};

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('all invariants verified -> eligible', () async {
    expect(await evaluate(() async => telemetry()),
        ComputeEligibility.eligible);
  });

  test('starts indeterminate before any poll', () {
    final gate = SwarmComputeGate(trustedSsids: const {});
    expect(gate.eligibility.value, ComputeEligibility.indeterminate);
  });

  group('verified-fact blocks', () {
    test('discharging', () async {
      expect(await evaluate(() async => telemetry(charging: false)),
          ComputeEligibility.discharging);
    });

    test('overheating at the ceiling (>= 37.5)', () async {
      expect(await evaluate(() async => telemetry(temp: 37.5)),
          ComputeEligibility.overheating);
      expect(await evaluate(() async => telemetry(temp: 37.4)),
          isNot(ComputeEligibility.overheating));
    });

    test('untrusted network', () async {
      expect(await evaluate(() async => telemetry(ssid: 'cafe-guest')),
          ComputeEligibility.untrustedNetwork);
    });

    test('thermal danger outranks power and network', () async {
      // Hot AND discharging AND untrusted -> overheating wins.
      final r = await evaluate(
        () async => telemetry(temp: 40.0, charging: false, ssid: 'x'),
      );
      expect(r, ComputeEligibility.overheating);
    });
  });

  group('fail-closed on unverifiable telemetry', () {
    test('missing temperature -> indeterminate, not eligible', () async {
      expect(await evaluate(() async => telemetry(temp: null)),
          ComputeEligibility.indeterminate);
    });

    test('missing charging flag -> indeterminate', () async {
      expect(await evaluate(() async => telemetry(charging: null)),
          ComputeEligibility.indeterminate);
    });

    test('empty SSID normalizes to unknown -> indeterminate', () async {
      expect(await evaluate(() async => telemetry(ssid: '')),
          ComputeEligibility.indeterminate);
    });

    test('wrong-typed native values coerce to null, never crash', () async {
      // Hostile / buggy native side: strings where bool/num expected.
      final r = await evaluate(() async => <String, Object?>{
            'isCharging': 'yes',
            'batteryTemp': 'hot',
            'wifiSsid': 12345,
          });
      expect(r, ComputeEligibility.indeterminate);
    });

    test('null channel result -> indeterminate', () async {
      expect(await evaluate(() async => null),
          ComputeEligibility.indeterminate);
    });

    test('MissingPluginException (web / no handler) -> indeterminate',
        () async {
      expect(
        await evaluate(() async =>
            throw MissingPluginException('no telemetry handler')),
        ComputeEligibility.indeterminate,
      );
    });

    test('PlatformException (permission revoked) -> indeterminate',
        () async {
      expect(
        await evaluate(
            () async => throw PlatformException(code: 'PERM_DENIED')),
        ComputeEligibility.indeterminate,
      );
    });
  });

  test('stop() reverts to indeterminate — monitoring off means unknown',
      () async {
    messenger.setMockMethodCallHandler(
        channel, (call) async => telemetry());
    final gate = SwarmComputeGate(trustedSsids: const {'home-wifi'});
    await gate.start();
    expect(gate.eligibility.value, ComputeEligibility.eligible);
    gate.stop();
    expect(gate.eligibility.value, ComputeEligibility.indeterminate);
    await gate.dispose();
  });

  test('updateTrustedSsids re-derives against the last snapshot', () async {
    messenger.setMockMethodCallHandler(
        channel, (call) async => telemetry(ssid: 'new-office'));
    final gate = SwarmComputeGate(trustedSsids: const {'home-wifi'});
    await gate.start();
    expect(gate.eligibility.value, ComputeEligibility.untrustedNetwork);
    gate.updateTrustedSsids({'home-wifi', 'new-office'});
    expect(gate.eligibility.value, ComputeEligibility.eligible);
    await gate.dispose();
  });

  group('TelemetrySnapshot.fromChannel coercion', () {
    test('valid values pass through', () {
      final s = TelemetrySnapshot.fromChannel(
        {'isCharging': true, 'batteryTemp': 33, 'wifiSsid': 'net'},
        DateTime(2026),
      );
      expect(s.isCharging, true);
      expect(s.batteryTemperatureCelsius, 33.0);
      expect(s.wifiSsid, 'net');
    });

    test('int temperature widens to double', () {
      final s = TelemetrySnapshot.fromChannel(
          {'batteryTemp': 30}, DateTime(2026));
      expect(s.batteryTemperatureCelsius, 30.0);
    });

    test('wrong types and empties become null', () {
      final s = TelemetrySnapshot.fromChannel(
        {'isCharging': 1, 'batteryTemp': 'x', 'wifiSsid': ''},
        DateTime(2026),
      );
      expect(s.isCharging, isNull);
      expect(s.batteryTemperatureCelsius, isNull);
      expect(s.wifiSsid, isNull);
    });
  });
}
