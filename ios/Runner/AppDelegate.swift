// AppDelegate.swift - Updated with proper class references
// Location: ios/Runner/AppDelegate.swift

import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private let CHANNEL = "com.defense.antispyware/system"
    private var jailbreakAccess: JailbreakAccess?
    private var spywareScanner: IOSSpywareScanner?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(
            name: CHANNEL,
            binaryMessenger: controller.binaryMessenger)

        // Initialize jailbreak access
        jailbreakAccess = JailbreakAccess()

        // Initialize spyware scanner
        spywareScanner = IOSSpywareScanner(jailbreakAccess: jailbreakAccess!)

        channel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }

            switch call.method {
            case "checkRootAccess":
                let isJailbroken = self.jailbreakAccess!.isJailbroken()
                let accessLevel = isJailbroken ? "Full" : "Limited"
                let method = self.jailbreakAccess!.getJailbreakMethod()

                result([
                    "hasRoot": isJailbroken,
                    "accessLevel": accessLevel,
                    "method": method,
                ])

            case "initializeScan":
                if let args = call.arguments as? [String: Any],
                    let deepScan = args["deepScan"] as? Bool,
                    let hasRoot = args["hasRoot"] as? Bool
                {
                    self.spywareScanner!.initialize(deepScan: deepScan, hasRoot: hasRoot)
                    result(true)
                } else {
                    result(
                        FlutterError(
                            code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                }

            case "scanNetwork":
                DispatchQueue.global(qos: .userInitiated).async {
                    let threats = self.spywareScanner!.scanNetwork()
                    DispatchQueue.main.async {
                        result(["threats": threats])
                    }
                }

            case "scanProcesses":
                DispatchQueue.global(qos: .userInitiated).async {
                    let threats = self.spywareScanner!.scanProcesses()
                    DispatchQueue.main.async {
                        result(["threats": threats])
                    }
                }

            case "scanFileSystem":
                DispatchQueue.global(qos: .userInitiated).async {
                    let threats = self.spywareScanner!.scanFileSystem()
                    DispatchQueue.main.async {
                        result(["threats": threats])
                    }
                }

            case "scanDatabases":
                DispatchQueue.global(qos: .userInitiated).async {
                    let threats = self.spywareScanner!.scanDatabases()
                    DispatchQueue.main.async {
                        result(["threats": threats])
                    }
                }

            case "scanMemory":
                DispatchQueue.global(qos: .userInitiated).async {
                    let threats = self.spywareScanner!.scanMemory()
                    DispatchQueue.main.async {
                        result(["threats": threats])
                    }
                }

            case "removeThreat":
                if let args = call.arguments as? [String: Any],
                    let id = args["id"] as? String,
                    let type = args["type"] as? String,
                    let path = args["path"] as? String,
                    let requiresRoot = args["requiresRoot"] as? Bool
                {

                    DispatchQueue.global(qos: .userInitiated).async {
                        let success = self.spywareScanner!.removeThreat(
                            id: id,
                            type: type,
                            path: path,
                            requiresRoot: requiresRoot
                        )
                        DispatchQueue.main.async {
                            result(["success": success])
                        }
                    }
                } else {
                    result(
                        FlutterError(
                            code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                }

            default:
                result(FlutterMethodNotImplemented)
            }
        })

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
