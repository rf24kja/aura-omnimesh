// lib/transport/bridge_support.dart
//
// Conditional facade: on dart:io targets the factory constructs the real
// CoreNodeBridgeServer (bridge_support_native.dart); on web it returns
// null (bridge_support_stub.dart) and dart:io never gets compiled.
// PLATFORM_SETUP.md §3 is the wiring contract this implements.

export 'bridge_support_stub.dart'
    if (dart.library.io) 'bridge_support_native.dart';
