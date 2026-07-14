// ios/Runner/TelemetryChannel.swift
//
// Native side of FlutterMethodChannel("aura-omnimesh/telemetry").
// Contract (must byte-match SwarmComputeGate expectations):
//   readTelemetry() -> {
//     "isCharging":  Bool | NSNull,
//     "batteryTemp": Double | NSNull,   // see THERMAL PROXY note
//     "wifiSsid":    String | NSNull,
//   }
// FAIL-CLOSED: unknowable fields are NSNull (→ Dart null → indeterminate).
//
// ── THERMAL PROXY (deliberate, documented deviation) ─────────────────
// iOS exposes NO public battery-temperature API. Returning null forever
// would make iOS devices permanently ineligible for compute. Instead we
// map ProcessInfo.thermalState onto conservative Celsius bands chosen so
// the Dart-side 37.5 °C ceiling produces the CORRECT gating decision:
//   .nominal  -> 25.0  (well below ceiling: eligible-compatible)
//   .fair     -> 33.0  (warm but below ceiling)
//   .serious  -> 39.0  (ABOVE ceiling -> overheating)
//   .critical -> 45.0  (far above ceiling -> overheating)
// This is a monotone proxy that errs hot, not a measurement. If Apple
// ever ships a real sensor API, replace this function and nothing else.
//
// ── SSID PREREQUISITES ────────────────────────────────────────────────
// NEHotspotNetwork.fetchCurrent (iOS 14+) returns a network ONLY when:
//   1. Entitlement: com.apple.developer.networking.wifi-info = true
//   2. CoreLocation authorization: .authorizedWhenInUse or .authorizedAlways
//      (Info.plist: NSLocationWhenInUseUsageDescription)
//   3. Location Services enabled system-wide.
// Any unmet prerequisite -> nil -> NSNull -> fail closed.

import CoreLocation
import Flutter
import Foundation
import NetworkExtension
import UIKit

final class TelemetryChannel: NSObject {

    static let name = "aura-omnimesh/telemetry"

    /// Register from AppDelegate.application(_:didFinishLaunching...).
    static func register(with messenger: FlutterBinaryMessenger) -> TelemetryChannel {
        let instance = TelemetryChannel()
        let channel = FlutterMethodChannel(
            name: name, binaryMessenger: messenger)
        channel.setMethodCallHandler(instance.handle)
        return instance
    }

    private override init() {
        super.init()
        // One-time enable; reads are free afterwards. Without this,
        // batteryState is permanently .unknown.
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "readTelemetry" else {
            result(FlutterMethodNotImplemented)
            return
        }

        let isCharging = readIsCharging()
        let batteryTemp = thermalProxyCelsius()

        // SSID resolution is asynchronous; assemble and reply in the
        // completion. FlutterResult is safe to invoke off the initial
        // call stack as long as it fires exactly once.
        fetchSsid { ssid in
            let payload: [String: Any] = [
                "isCharging": isCharging.map { $0 as Any } ?? NSNull(),
                "batteryTemp": batteryTemp.map { $0 as Any } ?? NSNull(),
                "wifiSsid": ssid.map { $0 as Any } ?? NSNull(),
            ]
            DispatchQueue.main.async { result(payload) }
        }
    }

    // -----------------------------------------------------------------
    // Power
    // -----------------------------------------------------------------

    private func readIsCharging() -> Bool? {
        switch UIDevice.current.batteryState {
        case .charging, .full:
            return true
        case .unplugged:
            return false
        case .unknown:
            return nil // Monitoring unavailable — fail closed.
        @unknown default:
            return nil
        }
    }

    // -----------------------------------------------------------------
    // Thermal proxy (see header block)
    // -----------------------------------------------------------------

    private func thermalProxyCelsius() -> Double? {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return 25.0
        case .fair:
            return 33.0
        case .serious:
            return 39.0
        case .critical:
            return 45.0
        @unknown default:
            return nil // New unmapped state — refuse to guess.
        }
    }

    // -----------------------------------------------------------------
    // Wi-Fi SSID
    // -----------------------------------------------------------------

    private func fetchSsid(_ completion: @escaping (String?) -> Void) {
        // Explicit precondition check: without location authorization,
        // fetchCurrent silently returns nil anyway — checking first makes
        // the fail-closed path intentional rather than incidental.
        let authorization: CLAuthorizationStatus
        if #available(iOS 14.0, *) {
            authorization = CLLocationManager().authorizationStatus
        } else {
            authorization = CLLocationManager.authorizationStatus()
        }
        guard authorization == .authorizedWhenInUse
            || authorization == .authorizedAlways
        else {
            completion(nil)
            return
        }

        if #available(iOS 14.0, *) {
            NEHotspotNetwork.fetchCurrent { network in
                let ssid = network?.ssid
                completion((ssid?.isEmpty ?? true) ? nil : ssid)
            }
        } else {
            // iOS 13 and below: CNCopyCurrentNetworkInfo is deprecated,
            // unreliable, and the deployment target excludes it. Fail
            // closed rather than ship a codepath nobody can test.
            completion(nil)
        }
    }
}
