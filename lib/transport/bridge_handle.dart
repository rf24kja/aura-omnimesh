// lib/transport/bridge_handle.dart
//
// Platform-free view of the Core Node bridge for the composition root.
// bridge_server.dart is dart:io and must never enter the web compile
// graph; main.dart therefore talks to this interface and obtains an
// instance through the conditional factory in bridge_support.dart.

abstract interface class BridgeHandle {
  /// LAN endpoint to surface in the pairing UI (QR flow, Phase 1).
  Uri get advertisedEndpoint;

  Future<void> start();

  Future<void> dispose();
}
