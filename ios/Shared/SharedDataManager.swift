// SharedDataManager.swift
// OrbGuard iOS - Shared Data Manager for App/Extension Communication
// Location: ios/Shared/SharedDataManager.swift

import Foundation
import os.log

// MARK: - App Group Configuration

struct AppGroupConfig {
    static let identifier = "group.com.orb.guard.shared"

    // Shared file names
    static let blocklistFileName = "blocklist.db"
    static let threatCacheFileName = "threat_cache.json"
    static let settingsFileName = "settings.plist"
    static let statsFileName = "stats.json"

    // Darwin notification names
    static let blocklistUpdatedNotification = "com.orb.guard.blocklist.updated"
    static let settingsChangedNotification = "com.orb.guard.settings.changed"
    static let vpnStatusChangedNotification = "com.orb.guard.vpn.status.changed"
    static let threatDetectedNotification = "com.orb.guard.threat.detected"
}

// MARK: - Shared Settings

struct SharedSettings: Codable {
    var vpnEnabled: Bool
    var dnsFilteringEnabled: Bool
    var blockMalware: Bool
    var blockPhishing: Bool
    var blockTrackers: Bool
    var blockAds: Bool
    var customBlocklist: [String]
    var customAllowlist: [String]
    var autoConnectOnUntrustedWifi: Bool
    var showNotifications: Bool
    var apiBaseURL: String
    var lastSyncTime: Date?
    var syncIntervalMinutes: Int

    static let `default` = SharedSettings(
        vpnEnabled: false,
        dnsFilteringEnabled: true,
        blockMalware: true,
        blockPhishing: true,
        blockTrackers: true,
        blockAds: false,
        customBlocklist: [],
        customAllowlist: [],
        autoConnectOnUntrustedWifi: true,
        showNotifications: true,
        apiBaseURL: "http://localhost:8090",
        lastSyncTime: nil,
        syncIntervalMinutes: 60
    )
}

// MARK: - Protection Stats

struct ProtectionStats: Codable {
    var totalQueries: Int
    var blockedQueries: Int
    var malwareBlocked: Int
    var phishingBlocked: Int
    var trackersBlocked: Int
    var adsBlocked: Int
    var threatsDetected: Int
    var lastUpdated: Date

    static let empty = ProtectionStats(
        totalQueries: 0,
        blockedQueries: 0,
        malwareBlocked: 0,
        phishingBlocked: 0,
        trackersBlocked: 0,
        adsBlocked: 0,
        threatsDetected: 0,
        lastUpdated: Date()
    )
}

// MARK: - VPN Status

enum VPNConnectionStatus: String, Codable {
    case disconnected = "disconnected"
    case connecting = "connecting"
    case connected = "connected"
    case disconnecting = "disconnecting"
    case error = "error"
}

struct VPNStatus: Codable {
    var connectionStatus: VPNConnectionStatus
    var connectedSince: Date?
    var serverAddress: String?
    var bytesReceived: Int64
    var bytesSent: Int64
    var lastError: String?
}

// MARK: - Shared Data Manager

class SharedDataManager {

    // MARK: - Properties

    private let appGroupIdentifier = AppGroupConfig.identifier
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: "com.orb.guard", category: "SharedData")

    // UserDefaults for app group
    private lazy var sharedDefaults: UserDefaults? = {
        UserDefaults(suiteName: appGroupIdentifier)
    }()

    // Container URL for shared files
    private lazy var containerURL: URL? = {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }()

    // Singleton
    static let shared = SharedDataManager()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Container Access

    func getSharedContainerURL() -> URL? {
        return containerURL
    }

    func getSharedFileURL(fileName: String) -> URL? {
        return containerURL?.appendingPathComponent(fileName)
    }

    // MARK: - Settings Management

    func saveSettings(_ settings: SharedSettings) {
        guard let data = try? encoder.encode(settings) else {
            logger.error("Failed to encode settings")
            return
        }

        sharedDefaults?.set(data, forKey: "shared_settings")
        sharedDefaults?.synchronize()

        // Notify extensions of settings change
        postDarwinNotification(AppGroupConfig.settingsChangedNotification)
    }

    func loadSettings() -> SharedSettings {
        guard let data = sharedDefaults?.data(forKey: "shared_settings"),
              let settings = try? decoder.decode(SharedSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    // MARK: - Protection Stats

    func saveStats(_ stats: ProtectionStats) {
        guard let data = try? encoder.encode(stats) else {
            logger.error("Failed to encode stats")
            return
        }

        sharedDefaults?.set(data, forKey: "protection_stats")
        sharedDefaults?.synchronize()
    }

    func loadStats() -> ProtectionStats {
        guard let data = sharedDefaults?.data(forKey: "protection_stats"),
              let stats = try? decoder.decode(ProtectionStats.self, from: data) else {
            return .empty
        }
        return stats
    }

    func incrementStat(_ keyPath: WritableKeyPath<ProtectionStats, Int>) {
        var stats = loadStats()
        stats[keyPath: keyPath] += 1
        stats.lastUpdated = Date()
        saveStats(stats)
    }

    // MARK: - VPN Status

    func saveVPNStatus(_ status: VPNStatus) {
        guard let data = try? encoder.encode(status) else {
            logger.error("Failed to encode VPN status")
            return
        }

        sharedDefaults?.set(data, forKey: "vpn_status")
        sharedDefaults?.synchronize()

        // Notify main app of VPN status change
        postDarwinNotification(AppGroupConfig.vpnStatusChangedNotification)
    }

    func loadVPNStatus() -> VPNStatus? {
        guard let data = sharedDefaults?.data(forKey: "vpn_status"),
              let status = try? decoder.decode(VPNStatus.self, from: data) else {
            return nil
        }
        return status
    }

    // MARK: - Blocklist Cache

    func saveBlocklist(_ domains: [String]) {
        guard let url = getSharedFileURL(fileName: "blocklist.txt") else {
            logger.error("Failed to get blocklist file URL")
            return
        }

        let content = domains.joined(separator: "\n")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            logger.info("Saved \(domains.count) domains to blocklist")

            // Update last sync time
            var settings = loadSettings()
            settings.lastSyncTime = Date()
            saveSettings(settings)

            // Notify extensions
            postDarwinNotification(AppGroupConfig.blocklistUpdatedNotification)
        } catch {
            logger.error("Failed to save blocklist: \(error.localizedDescription)")
        }
    }

    func loadBlocklist() -> Set<String> {
        guard let url = getSharedFileURL(fileName: "blocklist.txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return Set()
        }

        let domains = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return Set(domains)
    }

    func addToBlocklist(_ domain: String) {
        var domains = Array(loadBlocklist())
        if !domains.contains(domain) {
            domains.append(domain)
            saveBlocklist(domains)
        }
    }

    func removeFromBlocklist(_ domain: String) {
        var domains = Array(loadBlocklist())
        domains.removeAll { $0 == domain }
        saveBlocklist(domains)
    }

    // MARK: - Allowlist Management

    func saveAllowlist(_ domains: [String]) {
        var settings = loadSettings()
        settings.customAllowlist = domains
        saveSettings(settings)
    }

    func loadAllowlist() -> Set<String> {
        return Set(loadSettings().customAllowlist)
    }

    func addToAllowlist(_ domain: String) {
        var settings = loadSettings()
        if !settings.customAllowlist.contains(domain) {
            settings.customAllowlist.append(domain)
            saveSettings(settings)
        }
    }

    func removeFromAllowlist(_ domain: String) {
        var settings = loadSettings()
        settings.customAllowlist.removeAll { $0 == domain }
        saveSettings(settings)
    }

    // MARK: - Threat Cache

    struct CachedThreat: Codable {
        let indicator: ThreatIndicator
        let cachedAt: Date
    }

    func cacheThreat(_ indicator: ThreatIndicator) {
        var cache = loadThreatCache()
        cache[indicator.value] = CachedThreat(indicator: indicator, cachedAt: Date())

        // Limit cache size
        if cache.count > 10000 {
            // Remove oldest entries
            let sorted = cache.sorted { $0.value.cachedAt < $1.value.cachedAt }
            cache = Dictionary(uniqueKeysWithValues: Array(sorted.suffix(8000)))
        }

        saveThreatCache(cache)
    }

    func getCachedThreat(_ value: String) -> ThreatIndicator? {
        let cache = loadThreatCache()
        guard let cached = cache[value] else { return nil }

        // Check if cache is still valid (24 hours)
        if Date().timeIntervalSince(cached.cachedAt) > 86400 {
            return nil
        }

        return cached.indicator
    }

    private func saveThreatCache(_ cache: [String: CachedThreat]) {
        guard let url = getSharedFileURL(fileName: AppGroupConfig.threatCacheFileName),
              let data = try? encoder.encode(cache) else {
            return
        }

        try? data.write(to: url)
    }

    private func loadThreatCache() -> [String: CachedThreat] {
        guard let url = getSharedFileURL(fileName: AppGroupConfig.threatCacheFileName),
              let data = try? Data(contentsOf: url),
              let cache = try? decoder.decode([String: CachedThreat].self, from: data) else {
            return [:]
        }
        return cache
    }

    // MARK: - Darwin Notifications

    private func postDarwinNotification(_ name: String) {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(notificationCenter, CFNotificationName(name as CFString), nil, nil, true)
    }

    func observeDarwinNotification(_ name: String, callback: @escaping () -> Void) {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()

        // Note: In real implementation, you'd need to store the callback and observer properly
        CFNotificationCenterAddObserver(
            notificationCenter,
            Unmanaged.passUnretained(self).toOpaque(),
            { (_, observer, name, _, _) in
                // This callback runs on a background thread
                DispatchQueue.main.async {
                    // Would need to look up the callback here
                }
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    // MARK: - Cleanup

    func clearAllData() {
        // Clear UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            sharedDefaults?.removePersistentDomain(forName: bundleId)
        }

        // Clear files
        if let container = containerURL {
            try? fileManager.removeItem(at: container.appendingPathComponent("blocklist.txt"))
            try? fileManager.removeItem(at: container.appendingPathComponent(AppGroupConfig.threatCacheFileName))
        }

        logger.info("Cleared all shared data")
    }

    // MARK: - Device ID

    func getDeviceId() -> String {
        if let deviceId = sharedDefaults?.string(forKey: "device_id") {
            return deviceId
        }

        let newId = UUID().uuidString
        sharedDefaults?.set(newId, forKey: "device_id")
        return newId
    }
}
