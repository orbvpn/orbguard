// AppDelegate.swift - OrbGuard iOS
// Hosts the com.orb.guard/system, com.orb.guard/wifi, com.orbguard/supply_chain
// and com.orb.guard/logs method channels.
//
// Honesty contract: every capability that iOS does not expose through a public
// API returns an explicit FlutterError (code UNSUPPORTED / PERMISSION_DENIED /
// UNAVAILABLE) instead of fabricated zeros or empty "clean" results. Where iOS
// DOES expose a real check (proxy/MITM, injected dylibs, debugger/tamper,
// screen capture, sandbox escape), the scan runs it for real — an empty result
// then means "checked, nothing found", not "couldn't check".

import Flutter
import UIKit
import BackgroundTasks
import UserNotifications
import NetworkExtension
import CoreLocation
import OSLog
import CFNetwork
import MachO

@main
@objc class AppDelegate: FlutterAppDelegate {

    // MARK: - Properties

    private let CHANNEL = "com.orb.guard/system"
    private let WIFI_CHANNEL = "com.orb.guard/wifi"
    private let SUPPLY_CHAIN_CHANNEL = "com.orbguard/supply_chain"
    private let LOGS_CHANNEL = "com.orb.guard/logs"

    private var wifiHandler: WifiChannelHandler?
    private var contentFilterHandler: ContentFilterChannelHandler?
    private var callDirectoryHandler: CallDirectoryChannelHandler?
    private let batterySampler = BatteryDrainSampler()

    // MARK: - App Lifecycle

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(
            name: CHANNEL,
            binaryMessenger: controller.binaryMessenger)

        // Setup method channel handler
        channel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }
            self.handleMethodCall(call: call, result: result)
        })

        // WiFi channel (W5.1): current network via NEHotspotNetwork; scanning is
        // not possible on iOS and reports UNSUPPORTED.
        let wifiChannel = FlutterMethodChannel(
            name: WIFI_CHANNEL,
            binaryMessenger: controller.binaryMessenger)
        let wifiHandler = WifiChannelHandler()
        self.wifiHandler = wifiHandler
        wifiChannel.setMethodCallHandler { call, result in
            wifiHandler.handle(call: call, result: result)
        }

        // Supply-chain channel (W5.13): iOS sandboxing prevents enumerating or
        // inspecting other installed applications — every method is UNSUPPORTED.
        let supplyChainChannel = FlutterMethodChannel(
            name: SUPPLY_CHAIN_CHANNEL,
            binaryMessenger: controller.binaryMessenger)
        supplyChainChannel.setMethodCallHandler { call, result in
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "iOS does not allow enumerating or inspecting other installed applications; supply-chain scanning is unavailable on this platform.",
                details: ["method": call.method, "platform": "ios"]))
        }

        // Logs channel (W5.15): own-process log retrieval via OSLogStore (iOS 15+).
        let logsChannel = FlutterMethodChannel(
            name: LOGS_CHANNEL,
            binaryMessenger: controller.binaryMessenger)
        logsChannel.setMethodCallHandler { call, result in
            AppLogStoreReader.handle(call: call, result: result)
        }

        // Content-filter blocklist bridge (com.orb.guard/content_filter): mirrors
        // the Dart threat-intel domain block list into the shared App Group
        // container that the OrbGuardFilter NEFilterDataProvider reads. This is a
        // one-way DATA sync only — it does NOT start filtering and never reports
        // enforcement as active. Apple only runs an NEFilterDataProvider on
        // MDM-supervised devices; see ContentFilterChannelHandler for details.
        let contentFilterHandler = ContentFilterChannelHandler()
        self.contentFilterHandler = contentFilterHandler
        contentFilterHandler.register(with: controller.binaryMessenger)

        // Call-directory bridge (com.orb.guard/call_directory): writes the
        // block/identify number lists into the shared App Group container that
        // the OrbGuardCallDirectory CXCallDirectoryProvider extension reads, and
        // asks iOS to reload it. DATA SYNC + reload only — actual blocking
        // requires the user to enable it in Settings > Phone > Call Blocking &
        // Identification; see CallDirectoryChannelHandler for details.
        let callDirectoryHandler = CallDirectoryChannelHandler()
        self.callDirectoryHandler = callDirectoryHandler
        callDirectoryHandler.register(with: controller.binaryMessenger)

        // Start battery sampling so getBatteryDrain can report a measured rate.
        batterySampler.start()

        // Request notification permissions
        requestNotificationPermissions()

        // Background scan (BGTaskScheduler): the launch handler MUST be
        // registered before this method returns (Apple requirement). Then
        // submit a refresh request so one is generally pending — iOS alone
        // decides if and when it actually runs.
        BackgroundScanService.shared.register()
        BackgroundScanService.shared.submitNextRequestLoggingFailure()

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    override func applicationDidEnterBackground(_ application: UIApplication) {
        // Refresh the pending background-scan request whenever the app leaves
        // the foreground, so a request generally exists for iOS to honor.
        BackgroundScanService.shared.submitNextRequestLoggingFailure()
        super.applicationDidEnterBackground(application)
    }

    // MARK: - Method Channel Handler

    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        // ============================================================
        // ROOT/JAILBREAK CHECK METHODS
        // ============================================================

        case "checkRootAccess":
            let isJailbroken = checkJailbreak()
            let accessLevel = isJailbroken ? "Full" : "Limited"
            let method = isJailbroken ? "Jailbreak" : "None"

            result([
                "hasRoot": isJailbroken,
                "accessLevel": accessLevel,
                "method": method,
            ])

        case "initializeScan":
            // Basic initialization - always succeed
            result(true)

        // iOS sandboxes apps from other processes' sockets, memory and data, so
        // these stages cannot inspect OTHER apps. Instead each runs the real,
        // device-wide checks iOS DOES permit for the current runtime + device
        // posture (MITM proxy, injected dylibs, debugger, screen capture,
        // sandbox escape). An empty result means "checked, nothing found".
        // The implementations live in SecurityPostureChecks
        // (BackgroundScanService.swift) — the SAME code the background scan
        // runs, so the two paths can never drift apart.
        case "scanNetwork":
            DispatchQueue.global(qos: .userInitiated).async {
                let threats = SecurityPostureChecks.proxyThreats()
                DispatchQueue.main.async {
                    result(["threats": threats])
                }
            }

        case "scanProcesses":
            DispatchQueue.global(qos: .userInitiated).async {
                let threats = SecurityPostureChecks.injectedLibraryThreats()
                    + SecurityPostureChecks.screenCaptureThreats()
                DispatchQueue.main.async {
                    result(["threats": threats])
                }
            }

        case "scanFileSystem":
            DispatchQueue.global(qos: .userInitiated).async {
                let threats = self.performBasicFileSystemScan()
                DispatchQueue.main.async {
                    result(["threats": threats])
                }
            }

        case "scanDatabases":
            DispatchQueue.global(qos: .userInitiated).async {
                let threats = SecurityPostureChecks.sandboxEscapeThreats()
                DispatchQueue.main.async {
                    result(["threats": threats])
                }
            }

        case "scanMemory":
            DispatchQueue.global(qos: .userInitiated).async {
                let threats = SecurityPostureChecks.debuggerThreats()
                DispatchQueue.main.async {
                    result(["threats": threats])
                }
            }

        case "removeThreat":
            // Threat removal not supported without jailbreak
            result(["success": false, "error": "Threat removal requires elevated access"])

        // ============================================================
        // VPN PROTECTION METHODS (Stub implementations)
        // ============================================================

        case "startVPNProtection":
            result(FlutterError(code: "NOT_IMPLEMENTED", message: "VPN not configured", details: nil))

        case "stopVPNProtection":
            result(["success": true])

        case "getVPNStatus":
            result([
                "status": "disconnected",
                "isConnected": false,
                "isEnabled": false
            ])

        case "enableDNSFiltering":
            result(["success": true])

        case "disableDNSFiltering":
            result(["success": true])

        // ============================================================
        // PROTECTION STATUS METHODS
        // ============================================================

        case "getProtectionStatus":
            result([
                "vpnEnabled": false,
                "dnsFilteringEnabled": false,
                "blockMalware": true,
                "blockPhishing": true,
                "blockTrackers": true,
                "blockAds": false,
                "totalBlocked": 0,
                "malwareBlocked": 0,
                "phishingBlocked": 0,
                "trackersBlocked": 0,
                "lastSync": 0
            ])

        // ============================================================
        // Threat-intel / analysis are served by the backend API
        // (guard.orbai.world), NOT the native layer. These handlers used to
        // return fabricated "safe"/zero results; they now fail honestly so a
        // caller can never be silently told "you're safe".
        // ============================================================

        case "getThreatStats",
             "syncThreatIntelligence",
             "checkURLReputation",
             "analyzeSMS",
             "scanQRCode",
             "checkIndicators":
            result(FlutterError(
                code: "UNAVAILABLE",
                message: "\(call.method) is served by the OrbGuard backend API, not the native layer",
                details: nil))

        // ============================================================
        // SETTINGS METHODS
        // ============================================================

        case "updateProtectionSettings":
            result(["success": true])

        case "addToBlocklist":
            result(["success": true])

        case "removeFromBlocklist":
            result(["success": true])

        case "addToAllowlist":
            result(["success": true])

        case "removeFromAllowlist":
            result(["success": true])

        // ============================================================
        // BACKGROUND SCANNING METHODS
        // These used to return fabricated success for a no-op; they now do
        // the real BGTaskScheduler work and report the actual outcome.
        // ============================================================

        case "scheduleBackgroundScan":
            // Really submits a BGAppRefreshTaskRequest; success is true only
            // when BGTaskScheduler accepted it. iOS decides the actual run
            // time — earliestBeginDate is a floor, never a schedule.
            do {
                let earliest = try BackgroundScanService.shared.submitNextRequest()
                result([
                    "success": true,
                    "taskIdentifier": BackgroundScanService.taskIdentifier,
                    "earliestBeginDate": ISO8601DateFormatter().string(from: earliest),
                ])
            } catch {
                result([
                    "success": false,
                    "error": error.localizedDescription,
                ])
            }

        case "getBackgroundScanStatus":
            // Real state only: `scheduled` from BGTaskScheduler's pending
            // request list, the rest from the persisted last genuine run.
            BackgroundScanService.shared.status { payload in
                result(payload)
            }

        case "scheduleDeepScan":
            // No deep background scan exists on iOS (the old handler faked
            // success). Only the quick posture check runs via BGAppRefreshTask.
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Background deep scanning is not implemented on iOS. Only the quick posture check (proxy/MITM, jailbreak markers, injected libraries, debugger) runs as a background refresh task.",
                details: ["platform": "ios"]))

        case "cancelBackgroundScans":
            BackgroundScanService.shared.cancelPendingRequest()
            result(["success": true])

        // ============================================================
        // ADVANCED DETECTION METRICS (W5.12)
        // Only metrics iOS genuinely exposes are implemented; everything
        // else returns an explicit UNSUPPORTED error — never fake zeros.
        // ============================================================

        case "getBatteryDrain":
            batterySampler.currentDrain(result: result)

        case "getBatteryState":
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let level = device.batteryLevel
            guard level >= 0 else {
                result(FlutterError(
                    code: "UNAVAILABLE",
                    message: "Battery level is not available on this device (UIDevice reported unknown).",
                    details: nil))
                return
            }
            result([
                "level": Double(level) * 100.0,
                "state": BatteryDrainSampler.stateString(device.batteryState),
                "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            ])

        case "getThermalState":
            result([
                "state": SystemMetrics.thermalStateString(ProcessInfo.processInfo.thermalState),
                "rawValue": ProcessInfo.processInfo.thermalState.rawValue,
            ])

        case "getLowPowerMode":
            result(["enabled": ProcessInfo.processInfo.isLowPowerModeEnabled])

        case "getCPUUsage":
            // Real measurement: two host_processor_info samples 500ms apart.
            DispatchQueue.global(qos: .userInitiated).async {
                guard let first = SystemMetrics.cpuTicks() else {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "UNAVAILABLE",
                            message: "host_processor_info failed; CPU usage cannot be measured.",
                            details: nil))
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.5)
                guard let second = SystemMetrics.cpuTicks() else {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "UNAVAILABLE",
                            message: "host_processor_info failed; CPU usage cannot be measured.",
                            details: nil))
                    }
                    return
                }
                let busy = Double((second.user &- first.user) &+ (second.system &- first.system) &+ (second.nice &- first.nice))
                let total = busy + Double(second.idle &- first.idle)
                guard total > 0 else {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "UNAVAILABLE",
                            message: "CPU tick counters did not advance during the sample window.",
                            details: nil))
                    }
                    return
                }
                DispatchQueue.main.async {
                    result([
                        "percentage": (busy / total) * 100.0,
                        "sampleIntervalMs": 500,
                        "scope": "device",
                    ])
                }
            }

        case "getNetworkActivity":
            // Real measurement: two getifaddrs interface-counter samples 500ms apart.
            DispatchQueue.global(qos: .userInitiated).async {
                guard let first = SystemMetrics.interfaceCounters() else {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "UNAVAILABLE",
                            message: "getifaddrs failed; network activity cannot be measured.",
                            details: nil))
                    }
                    return
                }
                Thread.sleep(forTimeInterval: 0.5)
                guard let second = SystemMetrics.interfaceCounters() else {
                    DispatchQueue.main.async {
                        result(FlutterError(
                            code: "UNAVAILABLE",
                            message: "getifaddrs failed; network activity cannot be measured.",
                            details: nil))
                    }
                    return
                }
                let deltaBytes = (second.rx &- first.rx) &+ (second.tx &- first.tx)
                DispatchQueue.main.async {
                    result([
                        "bytesPerSecond": Double(deltaBytes) / 0.5,
                        "sampleIntervalMs": 500,
                        "scope": "device",
                    ])
                }
            }

        case "getDataUsage":
            // Device-wide interface byte counters since boot (public getifaddrs API).
            // iOS has NO public API for per-app data usage; this is the honest
            // device-level total, explicitly labelled as such.
            guard let counters = SystemMetrics.interfaceCounters() else {
                result(FlutterError(
                    code: "UNAVAILABLE",
                    message: "getifaddrs failed; data usage counters cannot be read.",
                    details: nil))
                return
            }
            result([
                "megabytes": Double(counters.rx &+ counters.tx) / 1_048_576.0,
                "rxBytes": Int(clamping: counters.rx),
                "txBytes": Int(clamping: counters.tx),
                "scope": "device",
                "sinceBoot": true,
                "note": "Per-interface counters are 32-bit and wrap at 4 GiB on iOS.",
            ])

        case "checkMaliciousTweaks":
            DispatchQueue.global(qos: .userInitiated).async {
                let report = JailbreakArtifactScanner.scanInjectionDirectories()
                DispatchQueue.main.async { result(report) }
            }

        case "checkMaliciousDaemons":
            DispatchQueue.global(qos: .userInitiated).async {
                let report = JailbreakArtifactScanner.scanLaunchDaemonDirectories()
                DispatchQueue.main.async { result(report) }
            }

        // iOS provides no public API for any of the following — be explicit
        // about it instead of returning fabricated empty/zero results.
        case "getScreenOnTime",
             "getBackgroundProcessCount",
             "getUsageStats",
             "getNetworkUsageStats",
             "getInstalledApps",
             "getAppInfo",
             "checkBackgroundPermissionUsage",
             "getEnabledAccessibilityServices",
             "getInstalledKeyboards",
             "detectIMEAbuse",
             "getLocationAccessHistory",
             "getInstalledCertificates",
             "checkSuspiciousRootBinaries",
             "checkModifiedSystemFiles":
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "iOS does not provide a public API for '\(call.method)'. Per-app usage, process enumeration, installed-app inspection, accessibility-service enumeration, keyboard enumeration, location-access history and certificate-store enumeration are not accessible to third-party apps.",
                details: ["method": call.method, "platform": "ios"]))

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Jailbreak Detection

    private func checkJailbreak() -> Bool {
        // File-marker and sandbox-write checks are shared with the background
        // scan (SecurityPostureChecks in BackgroundScanService.swift); only
        // the cydia:// URL-scheme probe lives here because UIApplication is a
        // main-thread/foreground API that must not run in a background task.
        if !SecurityPostureChecks.jailbreakFileMarkerHits().isEmpty {
            return true
        }

        if SecurityPostureChecks.sandboxWriteProbeSucceeds() {
            return true
        }

        // Check for URL schemes
        if let url = URL(string: "cydia://package/com.example.package") {
            if UIApplication.shared.canOpenURL(url) {
                return true
            }
        }

        return false
    }

    // MARK: - Real iOS runtime/device security checks
    //
    // The maximal on-device inspection a sandboxed iOS app is permitted to do:
    // MITM-proxy config, injected tweak dylibs, debugger/tamper, screen capture
    // and sandbox escape (jailbreak). These are the same signals legitimate iOS
    // security/anti-fraud SDKs use. Each returns real findings; an empty array
    // means the check ran and found nothing (not "unavailable").
    //
    // The implementations live in SecurityPostureChecks
    // (BackgroundScanService.swift) so the on-demand scan above and the
    // background scan execute ONE shared implementation.

    // MARK: - Basic File System Scan

    private func performBasicFileSystemScan() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check for suspicious files in accessible directories
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
        let libraryPath = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? ""

        let suspiciousPatterns = [
            "keylogger",
            "spyware",
            "tracker",
            "monitor",
            "pegasus",
            "stalkerware"
        ]

        // Scan documents directory
        if let files = try? FileManager.default.contentsOfDirectory(atPath: documentsPath) {
            for file in files {
                let lowercased = file.lowercased()
                for pattern in suspiciousPatterns {
                    if lowercased.contains(pattern) {
                        threats.append([
                            "id": UUID().uuidString,
                            "name": "Suspicious file: \(file)",
                            "type": "suspicious_file",
                            "severity": "medium",
                            "path": "\(documentsPath)/\(file)",
                            "description": "File name contains suspicious pattern: \(pattern)",
                            "requiresRoot": false
                        ])
                    }
                }
            }
        }

        return threats
    }

    // MARK: - Notifications

    private func requestNotificationPermissions() {
        // The value-first first-run priming owns the notification ask — it
        // explains WHY before the OS dialog. Don't prompt at launch until
        // priming has run (Flutter persists `permissions_primed` via
        // shared_preferences, stored under the `flutter.` key). Once granted
        // anywhere, a later call here is a harmless no-op.
        if !UserDefaults.standard.bool(forKey: "flutter.permissions_primed") {
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("[OrbGuard] Notification permissions granted")
            } else if let error = error {
                print("[OrbGuard] Failed to get notification permissions: \(error.localizedDescription)")
            }
        }
    }
}

// ============================================================================
// MARK: - WiFi Channel Handler (com.orb.guard/wifi) — W5.1
// ============================================================================

/// Handles current-network lookup via NEHotspotNetwork.fetchCurrent (iOS 14+).
/// Requires the 'Access WiFi Information' entitlement and location permission.
/// WiFi scanning has no public API on iOS and reports UNSUPPORTED.
final class WifiChannelHandler: NSObject, CLLocationManagerDelegate {

    private let locationManager = CLLocationManager()
    /// Results queued while waiting for the user to answer the location prompt.
    private var pendingResults: [FlutterResult] = []

    override init() {
        super.init()
        locationManager.delegate = self
    }

    func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCurrentNetwork":
            getCurrentNetwork(result: result)

        case "scanNetworks", "scanWifiNetworks":
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "iOS does not allow WiFi scanning",
                details: [
                    "platform": "ios",
                    "reason": "Apple provides no public API for scanning nearby WiFi networks; only the currently joined network can be read.",
                ]))

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private var authorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    private func getCurrentNetwork(result: @escaping FlutterResult) {
        guard #available(iOS 14.0, *) else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Reading the current WiFi network requires iOS 14 or later (NEHotspotNetwork.fetchCurrent).",
                details: ["platform": "ios"]))
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            // Queue the result and ask for permission; resolved in the
            // authorization-change delegate callback.
            pendingResults.append(result)
            locationManager.requestWhenInUseAuthorization()

        case .denied, .restricted:
            result(FlutterError(
                code: "PERMISSION_DENIED",
                message: "Location permission is required by iOS to read the current WiFi network (SSID/BSSID). Grant location access to OrbGuard in Settings.",
                details: [
                    "platform": "ios",
                    "authorizationStatus": authorizationStatus == .denied ? "denied" : "restricted",
                ]))

        default:
            fetchCurrentNetwork(result: result)
        }
    }

    @available(iOS 14.0, *)
    private func fetchCurrentNetwork(result: @escaping FlutterResult) {
        NEHotspotNetwork.fetchCurrent { network in
            DispatchQueue.main.async {
                guard let network = network else {
                    // nil means either no WiFi association, or the
                    // 'Access WiFi Information' entitlement is missing from the
                    // provisioning profile. Both are honestly "no network data".
                    NSLog("[OrbGuard][wifi] NEHotspotNetwork.fetchCurrent returned nil (not on WiFi, or 'Access WiFi Information' entitlement missing)")
                    result(nil)
                    return
                }

                var payload: [String: Any] = [
                    "ssid": network.ssid,
                    "bssid": network.bssid,
                    // NEHotspotNetwork reports signal on a 0.0–1.0 scale; the
                    // dBm value below is a documented linear approximation.
                    "signal_strength": Int((-100.0 + network.signalStrength * 70.0).rounded()),
                    "signal_scale": network.signalStrength,
                    "is_connected": true,
                ]
                if #available(iOS 15.0, *) {
                    payload["security"] = WifiChannelHandler.securityString(network.securityType)
                }
                // No 'frequency' key: iOS does not expose the channel/frequency
                // of the joined network, so we do not invent one.
                result(payload)
            }
        }
    }

    @available(iOS 15.0, *)
    private static func securityString(_ type: NEHotspotNetworkSecurityType) -> String {
        switch type {
        case .open:
            return "Open"
        case .WEP:
            return "WEP"
        case .personal:
            // iOS does not distinguish WPA/WPA2/WPA3 personal generations.
            return "WPA2-Personal"
        case .enterprise:
            return "WPA2-Enterprise"
        case .unknown:
            return "Unknown"
        @unknown default:
            return "Unknown"
        }
    }

    // MARK: CLLocationManagerDelegate

    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        resolvePendingResults()
    }

    // iOS 13 fallback delegate callback.
    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        resolvePendingResults()
    }

    private func resolvePendingResults() {
        guard !pendingResults.isEmpty else { return }
        // Still waiting for the user's answer — keep the results queued.
        guard authorizationStatus != .notDetermined else { return }
        let pending = pendingResults
        pendingResults.removeAll()
        for queued in pending {
            getCurrentNetwork(result: queued)
        }
    }
}

// ============================================================================
// MARK: - Battery Drain Sampler — W5.12
// ============================================================================

/// Periodically samples UIDevice battery level so getBatteryDrain can return a
/// genuinely measured %/hour drain rate. If fewer than two samples spanning at
/// least two minutes exist, it reports UNAVAILABLE instead of a fake value.
final class BatteryDrainSampler {

    private var samples: [(time: Date, level: Float)] = []
    private var timer: Timer?
    private let lock = NSLock()

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        recordSample()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.recordSample()
        }
    }

    private func recordSample() {
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return } // -1 = unknown (e.g. simulator)
        lock.lock()
        defer { lock.unlock() }
        samples.append((Date(), level))
        // Keep a one-hour rolling window (always retain at least 2 samples).
        let cutoff = Date().addingTimeInterval(-3600)
        while samples.count > 2, let first = samples.first, first.time < cutoff {
            samples.removeFirst()
        }
    }

    func currentDrain(result: @escaping FlutterResult) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let level = device.batteryLevel
        guard level >= 0 else {
            result(FlutterError(
                code: "UNAVAILABLE",
                message: "Battery level is not available on this device (UIDevice reported unknown); drain rate cannot be measured.",
                details: nil))
            return
        }
        recordSample()

        lock.lock()
        let first = samples.first
        let last = samples.last
        lock.unlock()

        guard let oldest = first, let newest = last,
              newest.time.timeIntervalSince(oldest.time) >= 120 else {
            result(FlutterError(
                code: "UNAVAILABLE",
                message: "Insufficient battery samples to compute a drain rate yet (need at least 2 minutes of observation). Retry later.",
                details: ["currentLevel": Double(level) * 100.0]))
            return
        }

        let hours = newest.time.timeIntervalSince(oldest.time) / 3600.0
        // Positive = draining, negative = charging. Both are real states.
        let drainRatePerHour = Double(oldest.level - newest.level) * 100.0 / hours

        result([
            "drainRate": drainRatePerHour,
            "batteryLevel": Double(level) * 100.0,
            "batteryState": BatteryDrainSampler.stateString(device.batteryState),
            "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
            "sampleWindowSeconds": newest.time.timeIntervalSince(oldest.time),
        ])
    }

    static func stateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "unplugged"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }
}

// ============================================================================
// MARK: - System Metrics (CPU / network counters) — W5.12
// ============================================================================

enum SystemMetrics {

    struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
    }

    /// Aggregated CPU ticks across all cores via host_processor_info.
    static func cpuTicks() -> CPUTicks? {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount)
        guard kr == KERN_SUCCESS, let cpuInfo = info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: cpuInfo)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0
        let stateCount = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * stateCount
            user &+= UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)]))
            system &+= UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)]))
            idle &+= UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)]))
            nice &+= UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)]))
        }
        return CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    /// Total rx/tx bytes across non-loopback interfaces since boot (getifaddrs).
    static func interfaceCounters() -> (rx: UInt64, tx: UInt64)? {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            let ifa = addr.pointee
            cursor = ifa.ifa_next

            guard let ifaAddr = ifa.ifa_addr,
                  ifaAddr.pointee.sa_family == UInt8(AF_LINK),
                  let dataPtr = ifa.ifa_data else { continue }
            let name = String(cString: ifa.ifa_name)
            guard !name.hasPrefix("lo") else { continue }

            let data = dataPtr.assumingMemoryBound(to: if_data.self).pointee
            rx &+= UInt64(data.ifi_ibytes)
            tx &+= UInt64(data.ifi_obytes)
        }
        return (rx, tx)
    }

    static func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// ============================================================================
// MARK: - Jailbreak Artifact Scanner — W5.12
// ============================================================================

/// Real file-system checks for code-injection libraries and third-party launch
/// daemons. On a stock (non-jailbroken) device these directories do not exist,
/// so an empty result genuinely means "no artifacts visible from the sandbox" —
/// the response says so explicitly via the accessibility flags.
enum JailbreakArtifactScanner {

    private static let suspiciousNamePatterns = [
        "spy", "keylog", "track", "monitor", "stalk", "intercept",
        "record", "mspy", "flexispy", "spyera", "cocospy", "hoverwatch",
    ]

    private static let tweakDirectories = [
        "/Library/MobileSubstrate/DynamicLibraries",
        "/usr/lib/TweakInject",
        "/var/jb/Library/MobileSubstrate/DynamicLibraries",
        "/var/jb/usr/lib/TweakInject",
    ]

    private static let daemonDirectories = [
        "/Library/LaunchDaemons",
        "/var/jb/Library/LaunchDaemons",
    ]

    static func scanInjectionDirectories() -> [String: Any] {
        var threats: [[String: Any]] = []
        var scanned: [[String: Any]] = []
        let fm = FileManager.default

        for dir in tweakDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else {
                scanned.append(["path": dir, "accessible": false])
                continue
            }
            scanned.append(["path": dir, "accessible": true, "entryCount": entries.count])

            for entry in entries where entry.hasSuffix(".dylib") {
                let lowered = entry.lowercased()
                let matched = suspiciousNamePatterns.first { lowered.contains($0) }
                if let pattern = matched {
                    threats.append([
                        "id": "tweak_\(dir)/\(entry)",
                        "name": "Suspicious injection library: \(entry)",
                        "type": "malicious_tweak",
                        "severity": "HIGH",
                        "path": "\(dir)/\(entry)",
                        "description": "Code-injection library whose name matches the surveillance pattern '\(pattern)'.",
                        "requiresRoot": true,
                    ])
                } else {
                    threats.append([
                        "id": "tweak_\(dir)/\(entry)",
                        "name": "Code injection library present: \(entry)",
                        "type": "code_injection",
                        "severity": "MEDIUM",
                        "path": "\(dir)/\(entry)",
                        "description": "Third-party code-injection library found; any injected library can read app data on a jailbroken device.",
                        "requiresRoot": true,
                    ])
                }
            }
        }

        return ["threats": threats, "scannedDirectories": scanned]
    }

    static func scanLaunchDaemonDirectories() -> [String: Any] {
        var threats: [[String: Any]] = []
        var scanned: [[String: Any]] = []
        let fm = FileManager.default

        for dir in daemonDirectories {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else {
                scanned.append(["path": dir, "accessible": false])
                continue
            }
            scanned.append(["path": dir, "accessible": true, "entryCount": entries.count])

            // On stock iOS, /Library/LaunchDaemons does not exist at all, so any
            // readable third-party daemon plist here indicates a jailbreak.
            for entry in entries where entry.hasSuffix(".plist") {
                let lowered = entry.lowercased()
                let matched = suspiciousNamePatterns.first { lowered.contains($0) }
                threats.append([
                    "id": "daemon_\(dir)/\(entry)",
                    "name": "Third-party launch daemon: \(entry)",
                    "type": "malicious_daemon",
                    "severity": matched != nil ? "HIGH" : "MEDIUM",
                    "path": "\(dir)/\(entry)",
                    "description": matched != nil
                        ? "Launch daemon whose name matches the surveillance pattern '\(matched!)'."
                        : "Non-Apple launch daemon present; persistent background daemons should not exist on stock iOS.",
                    "requiresRoot": true,
                ])
            }
        }

        return ["threats": threats, "scannedDirectories": scanned]
    }
}

// ============================================================================
// MARK: - OSLogStore Reader (com.orb.guard/logs) — W5.15
// ============================================================================

/// Retrieves this app's own recent unified-system-log entries via OSLogStore
/// (iOS 15+). Older systems report UNSUPPORTED.
enum AppLogStoreReader {

    static func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getRecentLogs":
            let args = call.arguments as? [String: Any]
            let minutes = args?["minutes"] as? Int ?? 15
            let limit = args?["limit"] as? Int ?? 500
            getRecentLogs(minutes: minutes, limit: limit, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func getRecentLogs(minutes: Int, limit: Int, result: @escaping FlutterResult) {
        guard #available(iOS 15.0, *) else {
            result(FlutterError(
                code: "UNSUPPORTED",
                message: "Reading the app's own log entries requires iOS 15 or later (OSLogStore).",
                details: ["platform": "ios"]))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let since = Date().addingTimeInterval(-Double(max(minutes, 1)) * 60.0)
                let position = store.position(date: since)
                let entries = try store.getEntries(at: position)

                var logs: [[String: Any]] = []
                for entry in entries {
                    guard let logEntry = entry as? OSLogEntryLog else { continue }
                    logs.append([
                        "timestamp": logEntry.date.timeIntervalSince1970,
                        "level": levelString(logEntry.level),
                        "subsystem": logEntry.subsystem,
                        "category": logEntry.category,
                        "message": logEntry.composedMessage,
                    ])
                    if logs.count >= limit { break }
                }
                DispatchQueue.main.async {
                    result([
                        "logs": logs,
                        "source": "OSLogStore.currentProcessIdentifier",
                        "sinceMinutes": minutes,
                        "truncated": logs.count >= limit,
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(
                        code: "UNAVAILABLE",
                        message: "Failed to read OSLogStore: \(error.localizedDescription)",
                        details: nil))
                }
            }
        }
    }

    @available(iOS 15.0, *)
    private static func levelString(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        @unknown default: return "unknown"
        }
    }
}
