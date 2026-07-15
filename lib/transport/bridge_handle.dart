// lib/transport/bridge_handle.dart
//
// Platform-free view of the Core Node bridge for the composition root.
// bridge_server.dart is dart:io and must never enter the web compile
// graph; main.dart therefore talks to this interface and obtains an
// instance through the conditional factory in bridge_support.dart.

abstract interface class BridgeHandle {
  /// LAN endpoint to surface in the pairing UI (QR flow, Phase 1).
  Uri get advertisedEndpoint;

  /// Concrete `ws://<ip>:<port>` endpoints a Light Client on the same LAN
  /// can dial — one per non-loopback IPv4 interface, discovered via
  /// NetworkInterface.list (PLATFORM_SETUP §3). Empty when the device has
  /// no LAN address.
  Future<List<Uri>> pairingEndpoints();

  Future<void> start();

  Future<void> dispose();
}
