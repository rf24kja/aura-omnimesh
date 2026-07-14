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
