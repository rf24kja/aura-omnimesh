# PLATFORM_SETUP.md — Native Runtime Integration

Registration entry points, permission manifests, and build configuration
for the two platform channels. Dictionary keys and channel names here are
the single source of truth shared with `swarm_compute_gate.dart` and
`hybrid_transport_service.dart` — change them in lockstep or not at all.

---

## 1. Android

### 1.1 MainActivity registration
`android/app/src/main/kotlin/com/aura/omnimesh/MainActivity.kt`

```kotlin
package com.aura.omnimesh

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var telemetry: TelemetryChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        val telemetryChannel = TelemetryChannel(applicationContext)
        telemetryChannel.attach()
        MethodChannel(messenger, TelemetryChannel.NAME)
            .setMethodCallHandler(telemetryChannel)
        telemetry = telemetryChannel

        val transport = NearbyTransportChannel(applicationContext)
        MethodChannel(messenger, NearbyTransportChannel.METHOD_NAME)
            .setMethodCallHandler(transport)
        EventChannel(messenger, NearbyTransportChannel.EVENT_NAME)
            .setStreamHandler(transport)
    }

    override fun onDestroy() {
        telemetry?.detach()
        super.onDestroy()
    }
}
```

### 1.2 AndroidManifest.xml
```xml
<!-- Telemetry: SSID resolution -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />

<!-- Nearby Connections (P2P_CLUSTER) -->
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.NEARBY_WIFI_DEVICES"
    android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.CHANGE_WIFI_STATE" />
<!-- Legacy (API <= 30) Nearby prerequisites -->
<uses-permission android:name="android.permission.BLUETOOTH"
    android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
    android:maxSdkVersion="30" />
```

Runtime permission requests (`ACCESS_FINE_LOCATION`, the `BLUETOOTH_*`
trio on API 31+, `NEARBY_WIFI_DEVICES` on 33+) belong in the Dart
onboarding flow via `permission_handler` — the native channels are
deliberately permission-passive and fail closed until granted.

### 1.3 android/app/build.gradle
```gradle
dependencies {
    implementation("com.google.android.gms:play-services-nearby:19.1.0")
}
```

---

## 2. iOS

### 2.1 AppDelegate registration
`ios/Runner/AppDelegate.swift`

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    private var telemetry: TelemetryChannel?
    private var transport: MultipeerTransportChannel?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        let controller =
            window?.rootViewController as! FlutterViewController
        let messenger = controller.binaryMessenger

        telemetry = TelemetryChannel.register(with: messenger)
        transport = MultipeerTransportChannel.register(with: messenger)

        return super.application(
            application,
            didFinishLaunchingWithOptions: launchOptions)
    }
}
```

### 2.2 Info.plist
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Location access is required by iOS to read the Wi-Fi network
name, which gates compute sharing to trusted networks only.</string>

<key>NSLocalNetworkUsageDescription</key>
<string>Discovers nearby Aura mesh nodes for offline sync.</string>

<key>NSBonjourServices</key>
<array>
    <string>_aura-omnimesh._tcp</string>
    <string>_aura-omnimesh._udp</string>
</array>

<key>UIRequiresPersistentWiFi</key>
<true/>
```

### 2.3 Entitlements (`Runner.entitlements`)
```xml
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```
Requires the "Access Wi-Fi Information" capability enabled on the App ID
in the developer portal. Without it `NEHotspotNetwork.fetchCurrent`
returns nil on every device — the gate then reads `indeterminate`
forever, which is the correct fail-closed symptom to check first when
debugging "compute never eligible" on iOS.

---

## 3. Bridge server wiring (Core Node, native targets only)

`bridge_server.dart` is pure Dart — add to `bootstrap()` in `main.dart`
on non-web platforms, after `engine.start(...)`:

```dart
CoreNodeBridgeServer? bridge;
if (!kIsWeb) {
  bridge = CoreNodeBridgeServer(
    signer: signer,
    selfIdentity: selfIdentity,
    engine: engine,
    transport: transport,
    repository: repository,
  );
  await bridge.start();
  // Pairing UI: render QR of ws://<lan-ip>:7411 using
  // NetworkInterface.list() to find the Wi-Fi interface address.
}
```
Add `bridge` to `AppServices` and dispose it first in
`AppServices.dispose()` (before the engine, so relays stop cleanly).

---

## 4. Cross-OS topology (read before filing "iPhone can't see Pixel")

Multipeer Connectivity (Apple) and Nearby Connections (Google) do **not**
interoperate over the air — this is an ecosystem constraint, not a bug.
Resulting topology:

- iOS ↔ iOS: direct via Multipeer.
- Android ↔ Android: direct via Nearby.
- iOS ↔ Android: transits any Core Node's Dart WebSocket bridge over the
  shared LAN (the same bridge Light Clients use).

A future BLE-GATT custom transport can unify the radio layer behind the
existing `LocalMeshTransportService` interface without touching anything
above it.
