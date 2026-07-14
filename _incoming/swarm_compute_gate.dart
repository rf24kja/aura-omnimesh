// lib/compute/swarm_compute_gate.dart
//
// Module B foundation: hardware eligibility gate. The compute worker may
// pick up edge-inference tasks ONLY while this gate reports `eligible`.
// Invariant (hard block otherwise):
//   isCharging == true && batteryTemp < 37.5°C && wifiSsid ∈ trusted set
//
// Fail-closed philosophy: any telemetry we cannot read counts AGAINST
// eligibility, never for it. A gate that guesses "probably fine" is how
// you cook a stranger's battery in their pocket.
//
// Deviation from the 4-state spec (flagged deliberately): a fifth state
// `indeterminate` covers "telemetry unreadable" — Web targets without the
// plugin, permission-denied SSID reads, transient channel errors. Mapping
// those onto `discharging` or `untrustedNetwork` would lie to the UI about
// WHY compute is blocked; both spec states remain reserved for verified
// facts. Blocking behavior is identical: only `eligible` unlocks work.

import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueListenable, ValueNotifier;
import 'package:flutter/services.dart';

/// Hard thermal ceiling per the Module B invariant.
const double kMaxBatteryTemperatureCelsius = 37.5;

enum ComputeEligibility {
  /// Telemetry could not be (fully) read — fail-closed block.
  indeterminate,

  /// Device not on external power.
  discharging,

  /// Battery at or above the thermal ceiling.
  overheating,

  /// Wi-Fi SSID missing or not in the trusted set (cellular counts as
  /// untrusted: metered links must never carry inference chunks).
  untrustedNetwork,

  /// All invariants verified — worker may accept tasks.
  eligible,
}

/// Raw reading from the native side. All fields nullable: absence of a
/// value is meaningful (permission denied, sensor unavailable, web).
class TelemetrySnapshot {
  const TelemetrySnapshot({
    required this.isCharging,
    required this.batteryTemperatureCelsius,
    required this.wifiSsid,
    required this.readAt,
  });

  final bool? isCharging;
  final double? batteryTemperatureCelsius;
  final String? wifiSsid;
  final DateTime readAt;

  static TelemetrySnapshot fromChannel(
    Map<String, dynamic> raw,
    DateTime readAt,
  ) {
    final charging = raw['isCharging'];
    final temp = raw['batteryTemp'];
    final ssid = raw['wifiSsid'];
    return TelemetrySnapshot(
      isCharging: charging is bool ? charging : null,
      batteryTemperatureCelsius: temp is num ? temp.toDouble() : null,
      // Empty SSID strings (iOS without location permission returns "")
      // normalize to null — "unknown network", not "network named ''".
      wifiSsid: ssid is String && ssid.isNotEmpty ? ssid : null,
      readAt: readAt,
    );
  }
}

// ---------------------------------------------------------------------------
// Gate
// ---------------------------------------------------------------------------

class SwarmComputeGate {
  SwarmComputeGate({
    required Set<String> trustedSsids,
    MethodChannel? channel,
    this.pollInterval = const Duration(seconds: 5),
    this.maxBatteryTemperatureCelsius = kMaxBatteryTemperatureCelsius,
  })  : _trustedSsids = Set.unmodifiable(trustedSsids),
        _channel =
            channel ?? const MethodChannel('aura-omnimesh/telemetry');

  /// Native contract — one method, one map:
  ///   readTelemetry() → {isCharging: bool, batteryTemp: double?, wifiSsid: String?}
  /// iOS: UIDevice.batteryState/batteryLevel + NEHotspotNetwork (needs
  /// location permission for SSID; thermal via ProcessInfo.thermalState
  /// mapped to °C bands). Android: BatteryManager sticky intent
  /// (EXTRA_TEMPERATURE is tenths of °C — divide by 10 native-side) +
  /// WifiManager.connectionInfo.
  final MethodChannel _channel;

  final Duration pollInterval;
  final double maxBatteryTemperatureCelsius;

  Set<String> _trustedSsids;

  final ValueNotifier<ComputeEligibility> _eligibility =
      ValueNotifier(ComputeEligibility.indeterminate);

  /// Current eligibility, listenable. Starts `indeterminate` (fail-closed)
  /// until the first successful poll.
  ValueListenable<ComputeEligibility> get eligibility => _eligibility;

  final _changesController = StreamController<ComputeEligibility>.broadcast();

  /// Distinct transitions only — the worker scheduler subscribes here and
  /// reacts exactly once per state change, not once per poll tick.
  Stream<ComputeEligibility> get onEligibilityChanged =>
      _changesController.stream;

  final _telemetryController =
      StreamController<TelemetrySnapshot>.broadcast();

  /// Raw snapshot per successful poll tick (every [pollInterval]), even
  /// when eligibility did not transition — drives live metric readouts
  /// (34.1 °C → 35.5 °C) that the distinct eligibility stream would hide.
  /// Failed polls emit nothing here: no reading is not a reading.
  Stream<TelemetrySnapshot> get onTelemetryRaw =>
      _telemetryController.stream;

  TelemetrySnapshot? _lastSnapshot;

  /// Most recent raw reading, for the diagnostics UI. Null before the
  /// first successful poll.
  TelemetrySnapshot? get lastSnapshot => _lastSnapshot;

  Timer? _timer;
  bool _running = false;
  bool _pollInFlight = false;
  bool _disposed = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> start() async {
    _checkNotDisposed();
    if (_running) return;
    _running = true;
    await _poll(); // Immediate first reading — no 5 s blind window.
    _timer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  void stop() {
    _checkNotDisposed();
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    _timer = null;
    // Stopping monitoring means we no longer KNOW the invariants hold.
    _setEligibility(ComputeEligibility.indeterminate);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    if (_running) stop();
    _disposed = true;
    await _changesController.close();
    await _telemetryController.close();
    _eligibility.dispose();
  }

  /// Live-update the trusted network set (settings screen). Re-derives
  /// against the last snapshot immediately — no wait for the next tick.
  void updateTrustedSsids(Set<String> ssids) {
    _checkNotDisposed();
    _trustedSsids = Set.unmodifiable(ssids);
    final snapshot = _lastSnapshot;
    if (snapshot != null) {
      _setEligibility(_derive(snapshot));
    }
  }

  // -------------------------------------------------------------------------
  // Polling
  // -------------------------------------------------------------------------

  Future<void> _poll() async {
    if (!_running || _disposed || _pollInFlight) return;
    _pollInFlight = true;
    try {
      final raw = await _channel
          .invokeMapMethod<String, dynamic>('readTelemetry');
      if (!_running || _disposed) return;

      if (raw == null) {
        _setEligibility(ComputeEligibility.indeterminate);
        return;
      }
      final snapshot = TelemetrySnapshot.fromChannel(raw, DateTime.now());
      _lastSnapshot = snapshot;
      if (!_telemetryController.isClosed) {
        _telemetryController.add(snapshot);
      }
      _setEligibility(_derive(snapshot));
    } on MissingPluginException {
      // Web target / platform without the native handler. Swallowed by
      // design: the gate simply never grants eligibility here.
      _setEligibility(ComputeEligibility.indeterminate);
    } on PlatformException {
      // Transient native fault (permission revoked mid-session, sensor
      // hiccup). Fail closed, keep polling — it may recover next tick.
      _setEligibility(ComputeEligibility.indeterminate);
    } finally {
      _pollInFlight = false;
    }
  }

  /// Priority order mirrors physical urgency: thermal danger outranks
  /// power state outranks network trust. Every branch requires a VERIFIED
  /// fact; unknowns fall through to indeterminate at the end.
  ComputeEligibility _derive(TelemetrySnapshot s) {
    final temp = s.batteryTemperatureCelsius;
    if (temp != null && temp >= maxBatteryTemperatureCelsius) {
      return ComputeEligibility.overheating;
    }
    if (s.isCharging == false) {
      return ComputeEligibility.discharging;
    }
    if (s.wifiSsid != null && !_trustedSsids.contains(s.wifiSsid)) {
      return ComputeEligibility.untrustedNetwork;
    }

    // Eligibility demands all three POSITIVELY verified.
    final verified = s.isCharging == true &&
        temp != null &&
        temp < maxBatteryTemperatureCelsius &&
        s.wifiSsid != null &&
        _trustedSsids.contains(s.wifiSsid);

    return verified
        ? ComputeEligibility.eligible
        : ComputeEligibility.indeterminate;
  }

  void _setEligibility(ComputeEligibility next) {
    if (_disposed) return;
    if (_eligibility.value == next) return; // Distinct transitions only.
    _eligibility.value = next;
    if (!_changesController.isClosed) {
      _changesController.add(next);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('SwarmComputeGate used after dispose()');
    }
  }
}
