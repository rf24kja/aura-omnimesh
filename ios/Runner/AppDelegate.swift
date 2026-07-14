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
