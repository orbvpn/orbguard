// BackgroundScanService.swift
// OrbGuard iOS - Background Scanning Service using BGTaskScheduler
// Location: ios/Runner/BackgroundScanService.swift

import Foundation
import BackgroundTasks
import UserNotifications
import os.log

// MARK: - Background Task Identifiers

struct BackgroundTaskIdentifiers {
    static let threatIntelSync = "com.orb.guard.threat-intel-sync"
    static let backgroundScan = "com.orb.guard.background-scan"
    static let deepScan = "com.orb.guard.deep-scan"
}

// MARK: - Scan Result

struct BackgroundScanResult {
    let scanType: ScanType
    let startTime: Date
    let endTime: Date
    let threatsFound: Int
    let threats: [[String: Any]]
    let success: Bool
    let error: String?

    enum ScanType: String {
        case quick = "quick"
        case background = "background"
        case deep = "deep"
    }
}

// MARK: - Background Scan Service

class BackgroundScanService {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.orb.guard", category: "BackgroundScan")
    private let sharedData = SharedDataManager.shared
    private let notificationCenter = UNUserNotificationCenter.current()

    // Scan intervals
    private let threatIntelSyncInterval: TimeInterval = 3600  // 1 hour
    private let backgroundScanInterval: TimeInterval = 14400   // 4 hours
    private let deepScanInterval: TimeInterval = 86400         // 24 hours

    // MARK: - Task Scheduling

    /// Schedule threat intelligence sync task
    func scheduleThreatIntelSync() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifiers.threatIntelSync)
        request.earliestBeginDate = Date(timeIntervalSinceNow: threatIntelSyncInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled threat intel sync for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            logger.error("Failed to schedule threat intel sync: \(error.localizedDescription)")
        }
    }

    /// Schedule background scan task
    func scheduleBackgroundScan() {
        let request = BGAppRefreshTaskRequest(identifier: BackgroundTaskIdentifiers.backgroundScan)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundScanInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background scan for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            logger.error("Failed to schedule background scan: \(error.localizedDescription)")
        }
    }

    /// Schedule deep scan task (processing task - requires power)
    func scheduleDeepScan() {
        let request = BGProcessingTaskRequest(identifier: BackgroundTaskIdentifiers.deepScan)
        request.earliestBeginDate = Date(timeIntervalSinceNow: deepScanInterval)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = true  // Only run when charging

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled deep scan for \(request.earliestBeginDate?.description ?? "unknown")")
        } catch {
            logger.error("Failed to schedule deep scan: \(error.localizedDescription)")
        }
    }

    /// Cancel all scheduled tasks
    func cancelAllTasks() {
        BGTaskScheduler.shared.cancelAllTaskRequests()
        logger.info("Cancelled all background tasks")
    }

    // MARK: - Task Execution

    /// Perform background scan (quick scan, 30s limit)
    func performBackgroundScan(task: BGAppRefreshTask) {
        let startTime = Date()
        logger.info("Starting background scan")

        // Set expiration handler
        task.expirationHandler = { [weak self] in
            self?.logger.warning("Background scan expired")
            task.setTaskCompleted(success: false)
        }

        // Perform quick network and process scan
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else {
                task.setTaskCompleted(success: false)
                return
            }

            var allThreats: [[String: Any]] = []

            // Quick network scan using cached indicators
            let networkThreats = self.quickNetworkScan()
            allThreats.append(contentsOf: networkThreats)

            // Check for known malicious domains in DNS cache
            let dnsThreats = self.checkDNSCache()
            allThreats.append(contentsOf: dnsThreats)

            let result = BackgroundScanResult(
                scanType: .background,
                startTime: startTime,
                endTime: Date(),
                threatsFound: allThreats.count,
                threats: allThreats,
                success: true,
                error: nil
            )

            // Save result
            self.saveScanResult(result)

            // Notify if threats found
            if !allThreats.isEmpty {
                self.sendThreatNotification(threatCount: allThreats.count, scanType: .background)
            }

            // Schedule next scan
            self.scheduleBackgroundScan()

            task.setTaskCompleted(success: true)
            self.logger.info("Background scan completed. Found \(allThreats.count) threats")
        }
    }

    /// Perform deep scan (processing task, minutes allowed)
    func performDeepScan(task: BGProcessingTask) {
        let startTime = Date()
        logger.info("Starting deep scan")

        // Set expiration handler
        task.expirationHandler = { [weak self] in
            self?.logger.warning("Deep scan expired")
            task.setTaskCompleted(success: false)
        }

        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else {
                task.setTaskCompleted(success: false)
                return
            }

            var allThreats: [[String: Any]] = []

            // Full network scan
            let networkThreats = self.fullNetworkScan()
            allThreats.append(contentsOf: networkThreats)

            // File system scan
            let fileThreats = self.fileSystemScan()
            allThreats.append(contentsOf: fileThreats)

            // Database scan
            let dbThreats = self.databaseScan()
            allThreats.append(contentsOf: dbThreats)

            // Sync with threat intelligence
            Task {
                do {
                    _ = try await OrbGuardLabClient.shared.syncThreatIntelligence()
                } catch {
                    self.logger.error("Failed to sync threat intel during deep scan: \(error.localizedDescription)")
                }
            }

            let result = BackgroundScanResult(
                scanType: .deep,
                startTime: startTime,
                endTime: Date(),
                threatsFound: allThreats.count,
                threats: allThreats,
                success: true,
                error: nil
            )

            // Save result
            self.saveScanResult(result)

            // Notify if threats found
            if !allThreats.isEmpty {
                self.sendThreatNotification(threatCount: allThreats.count, scanType: .deep)
            }

            // Schedule next deep scan
            self.scheduleDeepScan()

            task.setTaskCompleted(success: true)
            self.logger.info("Deep scan completed. Found \(allThreats.count) threats")
        }
    }

    // MARK: - Scan Methods

    private func quickNetworkScan() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check current network configuration
        // This is limited without jailbreak but can check some DNS settings

        return threats
    }

    private func checkDNSCache() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check blocklist cache for any domains that were recently contacted
        // and match known malicious indicators

        return threats
    }

    private func fullNetworkScan() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Comprehensive network scan
        // - Check VPN profiles
        // - Check proxy settings
        // - Analyze network extensions

        return threats
    }

    private func fileSystemScan() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Scan accessible file locations
        let suspiciousPaths = [
            "/private/var/mobile/Library/Caches",
            "/private/var/mobile/Library/Preferences",
        ]

        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) {
                // Check for suspicious files
                // This is limited without jailbreak
            }
        }

        return threats
    }

    private func databaseScan() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Database analysis is limited without jailbreak
        // Can check some app-specific databases if accessible

        return threats
    }

    // MARK: - Results Management

    private func saveScanResult(_ result: BackgroundScanResult) {
        let defaults = UserDefaults(suiteName: AppGroupConfig.identifier) ?? UserDefaults.standard

        var history = defaults.array(forKey: "scan_history") as? [[String: Any]] ?? []

        let resultDict: [String: Any] = [
            "scanType": result.scanType.rawValue,
            "startTime": result.startTime.timeIntervalSince1970,
            "endTime": result.endTime.timeIntervalSince1970,
            "threatsFound": result.threatsFound,
            "success": result.success,
            "error": result.error ?? ""
        ]

        history.append(resultDict)

        // Keep last 50 results
        if history.count > 50 {
            history = Array(history.suffix(50))
        }

        defaults.set(history, forKey: "scan_history")

        // Update stats
        var stats = sharedData.loadStats()
        stats.threatsDetected += result.threatsFound
        stats.lastUpdated = Date()
        sharedData.saveStats(stats)
    }

    func getScanHistory() -> [[String: Any]] {
        let defaults = UserDefaults(suiteName: AppGroupConfig.identifier) ?? UserDefaults.standard
        return defaults.array(forKey: "scan_history") as? [[String: Any]] ?? []
    }

    func getLastScanResult() -> [String: Any]? {
        return getScanHistory().last
    }

    // MARK: - Notifications

    private func sendThreatNotification(threatCount: Int, scanType: BackgroundScanResult.ScanType) {
        let content = UNMutableNotificationContent()
        content.title = "Threats Detected"
        content.body = "\(threatCount) potential threat\(threatCount > 1 ? "s" : "") found during \(scanType.rawValue) scan. Tap to review."
        content.sound = .default
        content.badge = NSNumber(value: threatCount)
        content.categoryIdentifier = "THREAT_DETECTED"

        // Add actions
        content.userInfo = [
            "threatCount": threatCount,
            "scanType": scanType.rawValue
        ]

        let request = UNNotificationRequest(
            identifier: "threat-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil  // Deliver immediately
        )

        notificationCenter.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send threat notification: \(error.localizedDescription)")
            }
        }
    }

    /// Send sync completion notification
    func sendSyncNotification(newIndicators: Int) {
        guard newIndicators > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Threat Intelligence Updated"
        content.body = "\(newIndicators) new threat indicators synced."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "sync-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        notificationCenter.add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to send sync notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Notification Categories Setup

    static func setupNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_THREATS",
            title: "View Threats",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: []
        )

        let threatCategory = UNNotificationCategory(
            identifier: "THREAT_DETECTED",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([threatCategory])
    }
}
