// android/app/src/main/kotlin/com/aura/omnimesh/TelemetryChannel.kt
//
// Native side of MethodChannel("aura-omnimesh/telemetry").
// Contract (must byte-match SwarmComputeGate expectations):
//   readTelemetry() -> {
//     "isCharging":  Boolean | null,
//     "batteryTemp": Double  | null,   // ACTUAL Celsius (raw / 10.0)
//     "wifiSsid":    String  | null,   // unquoted, null when unknowable
//   }
// FAIL-CLOSED: every field independently degrades to null on any
// exception, missing permission, or unavailable sensor. Null on the wire
// maps to `indeterminate` in Dart — never a fabricated reading.

package com.aura.omnimesh

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class TelemetryChannel(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val NAME = "aura-omnimesh/telemetry"
        private const val UNKNOWN_SSID = "<unknown ssid>"
    }

    /** Latest SSID from the network callback (API 31+ path). @Volatile:
     *  written on ConnectivityManager's thread, read on the platform
     *  channel thread. */
    @Volatile
    private var callbackSsid: String? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    /** Call from MainActivity.configureFlutterEngine. On S+ registers the
     *  location-aware Wi-Fi callback — the ONLY reliable SSID source on
     *  modern Android. */
    fun attach() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE)
                as ConnectivityManager
            val request = NetworkRequest.Builder()
                .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                .build()
            val callback = object : ConnectivityManager.NetworkCallback(
                FLAG_INCLUDE_LOCATION_INFO
            ) {
                override fun onCapabilitiesChanged(
                    network: android.net.Network,
                    capabilities: NetworkCapabilities,
                ) {
                    val info = capabilities.transportInfo as? WifiInfo
                    callbackSsid = normalizeSsid(info?.ssid)
                }

                override fun onLost(network: android.net.Network) {
                    callbackSsid = null
                }
            }
            cm.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (_: Exception) {
            callbackSsid = null // Fail closed; readTelemetry degrades.
        }
    }

    fun detach() {
        val callback = networkCallback ?: return
        networkCallback = null
        try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE)
                as ConnectivityManager
            cm.unregisterNetworkCallback(callback)
        } catch (_: Exception) {
            // Already unregistered / service gone — nothing to fail.
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "readTelemetry") {
            result.notImplemented()
            return
        }
        // Each field is independently fail-closed: one broken subsystem
        // must not blank out the readings the device CAN still verify.
        val payload = HashMap<String, Any?>(3)
        payload["isCharging"] = readIsCharging()
        payload["batteryTemp"] = readBatteryTempCelsius()
        payload["wifiSsid"] = readSsid()
        result.success(payload)
    }

    // -----------------------------------------------------------------
    // Battery (sticky broadcast — no receiver registration required)
    // -----------------------------------------------------------------

    private fun batteryIntent(): Intent? = try {
        context.registerReceiver(
            null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
    } catch (_: Exception) {
        null
    }

    private fun readIsCharging(): Boolean? {
        val intent = batteryIntent() ?: return null
        return when (intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
            BatteryManager.BATTERY_STATUS_CHARGING,
            BatteryManager.BATTERY_STATUS_FULL,
            -> true

            BatteryManager.BATTERY_STATUS_DISCHARGING,
            BatteryManager.BATTERY_STATUS_NOT_CHARGING,
            -> false

            else -> null // STATUS_UNKNOWN / extra missing: fail closed.
        }
    }

    private fun readBatteryTempCelsius(): Double? {
        val intent = batteryIntent() ?: return null
        val tenths = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1)
        // EXTRA_TEMPERATURE is TENTHS of a degree Celsius (e.g. 312 ==
        // 31.2°C). Values <= 0 mean the extra was absent or the sensor is
        // lying — a 0.0°C battery inside a running phone is not a reading,
        // it is a fault.
        if (tenths <= 0) return null
        return tenths / 10.0
    }

    // -----------------------------------------------------------------
    // Wi-Fi SSID (the modern Android permission matrix)
    // -----------------------------------------------------------------
    // Requirements for a non-redacted SSID:
    //   - ACCESS_FINE_LOCATION granted at runtime, AND
    //   - device location services enabled, AND
    //   - API 31+: NetworkCallback registered with
    //     FLAG_INCLUDE_LOCATION_INFO (the attach() path), OR
    //   - API 29–30: WifiManager.connectionInfo still works with the
    //     permission above.
    // Any unmet condition yields "<unknown ssid>" or null → fail closed.

    private fun readSsid(): String? {
        if (ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            return null
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            callbackSsid
        } else {
            legacySsid()
        }
    }

    @Suppress("DEPRECATION")
    private fun legacySsid(): String? = try {
        val wifi = context.applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        normalizeSsid(wifi.connectionInfo?.ssid)
    } catch (_: Exception) {
        null
    }

    private fun normalizeSsid(raw: String?): String? {
        if (raw.isNullOrEmpty() || raw == UNKNOWN_SSID) return null
        // Framework wraps real SSIDs in quotes; strip exactly one pair.
        return if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
            raw.substring(1, raw.length - 1).ifEmpty { null }
        } else {
            raw
        }
    }
}
