// lib/ui/permission_gate.dart
//
// Phase 0 minimal onboarding: the Nearby Connections radio stack is
// permission-passive and fails closed (PLATFORM_SETUP.md §1.2), so the
// runtime permission requests live here in Dart, in front of the
// composition root. Android only: web has no Nearby radios, and iOS
// surfaces its Local Network / Bluetooth prompts on first radio use.
//
// Deliberately nothing more than the permission gate — alias selection
// and public-key display are the rest of the ROADMAP Phase 0 onboarding
// and are not part of the boot-unblock scope.

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_theme.dart';

/// Builds [builder] only once the Nearby-prerequisite runtime permissions
/// are granted; on platforms that need none at boot it is transparent.
/// The deferred builder matters: the app root reads its lazy bootstrap
/// future inside it, so the mesh node must not boot before the radios are
/// allowed to start.
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  // PLATFORM_SETUP.md §1.2: ACCESS_FINE_LOCATION, the BLUETOOTH_* trio on
  // API 31+, NEARBY_WIFI_DEVICES on 33+. permission_handler reports the
  // API-gated ones as granted on OS versions that predate them.
  static final Map<Permission, String> _required = {
    Permission.location: 'LOCATION',
    Permission.bluetoothScan: 'BLUETOOTH SCAN',
    Permission.bluetoothAdvertise: 'BLUETOOTH ADVERTISE',
    Permission.bluetoothConnect: 'BLUETOOTH CONNECT',
    Permission.nearbyWifiDevices: 'NEARBY WI-FI DEVICES',
    // Ring lifecycle notifications; auto-granted below API 33.
    Permission.notification: 'NOTIFICATIONS',
  };

  static bool get _gateApplies =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Map<Permission, PermissionStatus>? _statuses;
  bool _requesting = false;

  bool get _allGranted =>
      _statuses != null && _statuses!.values.every((s) => s.isGranted);

  bool get _anyPermanentlyDenied =>
      _statuses != null &&
      _statuses!.values.any((s) => s.isPermanentlyDenied);

  @override
  void initState() {
    super.initState();
    if (_gateApplies) {
      _refreshStatuses();
    }
  }

  Future<void> _refreshStatuses() async {
    final statuses = <Permission, PermissionStatus>{
      for (final permission in _required.keys)
        permission: await permission.status,
    };
    if (!mounted) return;
    setState(() => _statuses = statuses);
  }

  Future<void> _requestAll() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      await _required.keys.toList().request();
    } finally {
      if (mounted) {
        setState(() => _requesting = false);
      }
    }
    await _refreshStatuses();
  }

  @override
  Widget build(BuildContext context) {
    if (!_gateApplies || _allGranted) {
      return widget.builder(context);
    }
    final statuses = _statuses;
    return Scaffold(
      backgroundColor: AuraColors.obsidian,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AuraSpace.s3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Text('MESH RADIO ACCESS', style: AuraType.label),
              const SizedBox(height: AuraSpace.s2),
              const Text(
                'Aura discovers peers over Bluetooth and local Wi-Fi. '
                'Android requires these permissions before the radios '
                'may start. Nothing leaves the local mesh.',
                style: AuraType.bodyDim,
              ),
              const SizedBox(height: AuraSpace.s3),
              if (statuses == null)
                const Text('CHECKING…', style: AuraType.label)
              else
                for (final entry in _required.entries)
                  _PermissionRow(
                    label: entry.value,
                    status: statuses[entry.key],
                  ),
              const SizedBox(height: AuraSpace.s4),
              _GateButton(
                label: _requesting ? 'REQUESTING…' : 'GRANT ACCESS',
                onTap: _requesting ? null : _requestAll,
              ),
              if (_anyPermanentlyDenied) ...[
                const SizedBox(height: AuraSpace.s2),
                _GateButton(
                  label: 'OPEN SYSTEM SETTINGS',
                  onTap: openAppSettings,
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.label, required this.status});

  final String label;
  final PermissionStatus? status;

  @override
  Widget build(BuildContext context) {
    final granted = status?.isGranted ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.s1 / 2),
      child: Row(
        children: [
          // Accent as information: emerald indicator stroke once granted,
          // slate while pending (AuraStroke.indicator width, per spec).
          Container(
            width: AuraStroke.indicator,
            height: AuraSpace.s2,
            color: granted ? AuraColors.emerald : AuraColors.slate,
          ),
          const SizedBox(width: AuraSpace.s2),
          Expanded(child: Text(label, style: AuraType.metric)),
          Text(
            granted ? 'GRANTED' : 'REQUIRED',
            style: AuraType.label,
          ),
        ],
      ),
    );
  }
}

class _GateButton extends StatelessWidget {
  const _GateButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: AuraSpace.s2),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                onTap == null ? AuraColors.hairline : AuraColors.slate,
            width: AuraStroke.line,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: onTap == null
                ? AuraType.label
                : AuraType.label.copyWith(color: AuraColors.type),
          ),
        ),
      ),
    );
  }
}
