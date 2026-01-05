// AppDelegate.swift - OrbGuard iOS with VPN and API Integration
// Location: ios/Runner/AppDelegate.swift

import Flutter
import UIKit
import BackgroundTasks
import UserNotifications
import os.log

@main
@objc class AppDelegate: FlutterAppDelegate {

    // MARK: - Properties

    private let CHANNEL = "com.orb.guard/system"
    private var jailbreakAccess: JailbreakAccess?
    private var spywareScanner: IOSSpywareScanner?
    private var backgroundScanService: BackgroundScanService?

    private let logger = Logger(subsystem: "com.orb.guard", category: "AppDelegate")

    // MARK: - App Lifecycle

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
        let channel = FlutterMethodChannel(
            name: CHANNEL,
            binaryMessenger: controller.binaryMessenger)

        // Initialize services
        jailbreakAccess = JailbreakAccess()
        spywareScanner = IOSSpywareScanner(jailbreakAccess: jailbreakAccess!)
        backgroundScanService = BackgroundScanService()

        // Setup method channel handler
        channel.setMethodCallHandler({
            [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            guard let self = self else { return }
            self.handleMethodCall(call: call, result: result)
        })

        // Register background tasks
        registerBackgroundTasks()

        // Request notification permissions
        requestNotificationPermissions()

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Method Channel Handler

    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {

        // ============================================================
        // EXISTING SCANNER METHODS
        // ============================================================

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
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
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
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            }

        // ============================================================
        // VPN PROTECTION METHODS
        // ============================================================

        case "startVPNProtection":
            VPNManager.shared.startVPN { error in
                if let error = error {
                    result(FlutterError(code: "VPN_ERROR", message: error.localizedDescription, details: nil))
                } else {
                    result(["success": true])
                }
            }

        case "stopVPNProtection":
            VPNManager.shared.stopVPN()
            result(["success": true])

        case "getVPNStatus":
            let status = VPNManager.shared.currentStatus
            let statusMap: [String: Any] = [
                "status": VPNManager.shared.statusString,
                "isConnected": VPNManager.shared.isVPNConnected,
                "isEnabled": VPNManager.shared.isVPNEnabled
            ]
            result(statusMap)

        case "enableDNSFiltering":
            var settings = SharedDataManager.shared.loadSettings()
            settings.dnsFilteringEnabled = true
            SharedDataManager.shared.saveSettings(settings)
            VPNManager.shared.refreshBlocklist()
            result(["success": true])

        case "disableDNSFiltering":
            var settings = SharedDataManager.shared.loadSettings()
            settings.dnsFilteringEnabled = false
            SharedDataManager.shared.saveSettings(settings)
            result(["success": true])

        // ============================================================
        // THREAT INTELLIGENCE API METHODS
        // ============================================================

        case "syncThreatIntelligence":
            Task {
                do {
                    let syncResponse = try await OrbGuardLabClient.shared.syncThreatIntelligence()
                    let responseMap: [String: Any] = [
                        "newIndicators": syncResponse.newIndicators,
                        "updatedIndicators": syncResponse.updatedIndicators,
                        "deletedIndicators": syncResponse.deletedIndicators,
                        "success": true
                    ]
                    DispatchQueue.main.async {
                        result(responseMap)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "SYNC_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "checkURLReputation":
            guard let args = call.arguments as? [String: Any],
                  let url = args["url"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "URL required", details: nil))
                return
            }

            Task {
                do {
                    let reputation = try await OrbGuardLabClient.shared.checkURLReputation(url: url)
                    let responseMap: [String: Any] = [
                        "domain": reputation.domain,
                        "riskScore": reputation.riskScore,
                        "riskLevel": reputation.riskLevel.rawValue,
                        "isMalicious": reputation.isMalicious,
                        "isPhishing": reputation.isPhishing,
                        "categories": reputation.categories
                    ]
                    DispatchQueue.main.async {
                        result(responseMap)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "API_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "analyzeSMS":
            guard let args = call.arguments as? [String: Any],
                  let content = args["content"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Content required", details: nil))
                return
            }
            let sender = args["sender"] as? String

            Task {
                do {
                    let analysis = try await OrbGuardLabClient.shared.analyzeSMS(content: content, sender: sender)
                    let responseMap: [String: Any] = [
                        "isPhishing": analysis.isPhishing,
                        "riskScore": analysis.riskScore,
                        "riskLevel": analysis.riskLevel.rawValue,
                        "threatCount": analysis.threats.count,
                        "urlCount": analysis.urls.count,
                        "recommendations": analysis.recommendations
                    ]
                    DispatchQueue.main.async {
                        result(responseMap)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "API_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "scanQRCode":
            guard let args = call.arguments as? [String: Any],
                  let content = args["content"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Content required", details: nil))
                return
            }
            let latitude = args["latitude"] as? Double
            let longitude = args["longitude"] as? Double

            Task {
                do {
                    let scan = try await OrbGuardLabClient.shared.scanQRCode(
                        content: content,
                        latitude: latitude,
                        longitude: longitude
                    )
                    let responseMap: [String: Any] = [
                        "contentType": scan.contentType.rawValue,
                        "threatLevel": scan.threatLevel.rawValue,
                        "shouldBlock": scan.shouldBlock,
                        "threatCount": scan.threats.count,
                        "warnings": scan.warnings,
                        "recommendations": scan.recommendations
                    ]
                    DispatchQueue.main.async {
                        result(responseMap)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "API_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        case "checkIndicators":
            guard let args = call.arguments as? [String: Any],
                  let values = args["values"] as? [String] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Values array required", details: nil))
                return
            }

            Task {
                do {
                    let response = try await OrbGuardLabClient.shared.checkIndicators(values: values)
                    let responseMap: [String: Any] = [
                        "totalChecked": response.totalChecked,
                        "totalFound": response.totalFound,
                        "foundIndicators": response.found.map { indicator in
                            [
                                "value": indicator.value,
                                "type": indicator.type.rawValue,
                                "severity": indicator.severity.rawValue,
                                "description": indicator.description ?? ""
                            ]
                        }
                    ]
                    DispatchQueue.main.async {
                        result(responseMap)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "API_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        // ============================================================
        // PROTECTION STATUS METHODS
        // ============================================================

        case "getProtectionStatus":
            let vpnConnected = VPNManager.shared.isVPNConnected
            let settings = SharedDataManager.shared.loadSettings()
            let stats = SharedDataManager.shared.loadStats()

            let statusMap: [String: Any] = [
                "vpnEnabled": vpnConnected,
                "dnsFilteringEnabled": settings.dnsFilteringEnabled,
                "blockMalware": settings.blockMalware,
                "blockPhishing": settings.blockPhishing,
                "blockTrackers": settings.blockTrackers,
                "blockAds": settings.blockAds,
                "totalBlocked": stats.blockedQueries,
                "malwareBlocked": stats.malwareBlocked,
                "phishingBlocked": stats.phishingBlocked,
                "trackersBlocked": stats.trackersBlocked,
                "lastSync": settings.lastSyncTime?.timeIntervalSince1970 ?? 0
            ]
            result(statusMap)

        case "getThreatStats":
            Task {
                do {
                    let stats = try await OrbGuardLabClient.shared.getThreatStats()
                    let statsMap: [String: Any] = [
                        "totalIndicators": stats.totalIndicators,
                        "activeCampaigns": stats.activeCampaigns,
                        "threatActors": stats.threatActors,
                        "sources": stats.sources,
                        "healthyFeeds": stats.healthyFeeds
                    ]
                    DispatchQueue.main.async {
                        result(statsMap)
                    }
                } catch {
                    DispatchQueue.main.async {
                        result(FlutterError(code: "API_ERROR", message: error.localizedDescription, details: nil))
                    }
                }
            }

        // ============================================================
        // SETTINGS METHODS
        // ============================================================

        case "updateProtectionSettings":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Settings required", details: nil))
                return
            }

            var settings = SharedDataManager.shared.loadSettings()
            if let blockMalware = args["blockMalware"] as? Bool { settings.blockMalware = blockMalware }
            if let blockPhishing = args["blockPhishing"] as? Bool { settings.blockPhishing = blockPhishing }
            if let blockTrackers = args["blockTrackers"] as? Bool { settings.blockTrackers = blockTrackers }
            if let blockAds = args["blockAds"] as? Bool { settings.blockAds = blockAds }
            if let autoConnect = args["autoConnectOnUntrustedWifi"] as? Bool { settings.autoConnectOnUntrustedWifi = autoConnect }
            if let apiBaseURL = args["apiBaseURL"] as? String { settings.apiBaseURL = apiBaseURL }

            SharedDataManager.shared.saveSettings(settings)
            VPNManager.shared.updateSettings(settings)
            result(["success": true])

        case "addToBlocklist":
            guard let args = call.arguments as? [String: Any],
                  let domain = args["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Domain required", details: nil))
                return
            }
            SharedDataManager.shared.addToBlocklist(domain)
            result(["success": true])

        case "removeFromBlocklist":
            guard let args = call.arguments as? [String: Any],
                  let domain = args["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Domain required", details: nil))
                return
            }
            SharedDataManager.shared.removeFromBlocklist(domain)
            result(["success": true])

        case "addToAllowlist":
            guard let args = call.arguments as? [String: Any],
                  let domain = args["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Domain required", details: nil))
                return
            }
            SharedDataManager.shared.addToAllowlist(domain)
            VPNManager.shared.addToAllowlist(domain)
            result(["success": true])

        case "removeFromAllowlist":
            guard let args = call.arguments as? [String: Any],
                  let domain = args["domain"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "Domain required", details: nil))
                return
            }
            SharedDataManager.shared.removeFromAllowlist(domain)
            VPNManager.shared.removeFromAllowlist(domain)
            result(["success": true])

        // ============================================================
        // BACKGROUND SCANNING METHODS
        // ============================================================

        case "scheduleBackgroundScan":
            backgroundScanService?.scheduleBackgroundScan()
            result(["success": true])

        case "scheduleDeepScan":
            backgroundScanService?.scheduleDeepScan()
            result(["success": true])

        case "cancelBackgroundScans":
            backgroundScanService?.cancelAllTasks()
            result(["success": true])

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        // Register threat intelligence sync task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.orb.guard.threat-intel-sync",
            using: nil
        ) { [weak self] task in
            self?.handleThreatIntelSync(task: task as! BGAppRefreshTask)
        }

        // Register background scan task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.orb.guard.background-scan",
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundScan(task: task as! BGAppRefreshTask)
        }

        // Register deep scan task
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.orb.guard.deep-scan",
            using: nil
        ) { [weak self] task in
            self?.handleDeepScan(task: task as! BGProcessingTask)
        }

        logger.info("Background tasks registered")
    }

    private func handleThreatIntelSync(task: BGAppRefreshTask) {
        logger.info("Starting background threat intel sync")

        task.expirationHandler = {
            self.logger.warning("Threat intel sync task expired")
        }

        Task {
            do {
                _ = try await OrbGuardLabClient.shared.syncThreatIntelligence()
                task.setTaskCompleted(success: true)
                logger.info("Background threat intel sync completed")
            } catch {
                task.setTaskCompleted(success: false)
                logger.error("Background threat intel sync failed: \(error.localizedDescription)")
            }
        }

        // Schedule next sync
        backgroundScanService?.scheduleThreatIntelSync()
    }

    private func handleBackgroundScan(task: BGAppRefreshTask) {
        logger.info("Starting background scan")
        backgroundScanService?.performBackgroundScan(task: task)
    }

    private func handleDeepScan(task: BGProcessingTask) {
        logger.info("Starting deep scan")
        backgroundScanService?.performDeepScan(task: task)
    }

    // MARK: - Notifications

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                self.logger.info("Notification permissions granted")
            } else if let error = error {
                self.logger.error("Failed to get notification permissions: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - App Lifecycle Callbacks

    override func applicationDidEnterBackground(_ application: UIApplication) {
        super.applicationDidEnterBackground(application)
        backgroundScanService?.scheduleBackgroundScan()
        backgroundScanService?.scheduleThreatIntelSync()
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        super.applicationWillTerminate(application)
        // Save any pending data
    }
}
