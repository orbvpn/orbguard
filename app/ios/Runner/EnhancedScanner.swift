// EnhancedScanner.swift
// OrbGuard iOS - Enhanced Scanner with OrbGuard Lab API Integration
// Location: ios/Runner/EnhancedScanner.swift

import Foundation
import os.log

// MARK: - Enhanced Threat

struct EnhancedThreat: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let severity: SeverityLevel
    let type: ThreatType
    let path: String
    let requiresRoot: Bool
    let source: ThreatSource
    let indicator: ThreatIndicator?
    let campaign: String?
    let threatActor: String?
    let mitreTechniques: [String]
    let confidence: Int
    let metadata: [String: String]
    let detectedAt: Date

    enum ThreatType: String, Codable {
        case network = "network"
        case process = "process"
        case file = "file"
        case database = "database"
        case memory = "memory"
        case app = "app"
        case sms = "sms"
        case url = "url"
        case certificate = "certificate"
    }

    enum ThreatSource: String, Codable {
        case local = "local"           // Local heuristic detection
        case api = "api"               // OrbGuard Lab API
        case yara = "yara"             // YARA rule match
        case behavioral = "behavioral" // Behavioral analysis
        case cache = "cache"           // Cached threat intel
    }
}

// MARK: - Enhanced Scanner

class EnhancedScanner {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.orb.guard", category: "EnhancedScanner")
    private let apiClient = OrbGuardLabClient.shared
    private let sharedData = SharedDataManager.shared
    private let blocklist = BlocklistCache.shared

    // Cached indicators for offline scanning
    private var cachedDomains: Set<String> = []
    private var cachedIPs: Set<String> = []
    private var cachedHashes: Set<String> = []
    private var cachedProcessNames: Set<String> = []
    private var lastCacheUpdate: Date?

    // MARK: - Initialization

    init() {
        loadCachedIndicators()
    }

    // MARK: - Cache Management

    private func loadCachedIndicators() {
        let defaults = UserDefaults(suiteName: AppGroupConfig.identifier) ?? UserDefaults.standard

        cachedDomains = Set(defaults.stringArray(forKey: "cached_domains") ?? [])
        cachedIPs = Set(defaults.stringArray(forKey: "cached_ips") ?? [])
        cachedHashes = Set(defaults.stringArray(forKey: "cached_hashes") ?? [])
        cachedProcessNames = Set(defaults.stringArray(forKey: "cached_processes") ?? [])

        if let lastUpdate = defaults.object(forKey: "cache_last_update") as? Date {
            lastCacheUpdate = lastUpdate
        }

        logger.info("Loaded cached indicators: \(self.cachedDomains.count) domains, \(self.cachedIPs.count) IPs, \(self.cachedProcessNames.count) processes")
    }

    /// Sync indicators from API and update cache
    func syncIndicators() async throws {
        logger.info("Syncing indicators from API")

        // Fetch indicators by type
        async let domainsResponse = apiClient.listIndicators(pageSize: 1000, type: .domain)
        async let ipsResponse = apiClient.listIndicators(pageSize: 1000, type: .ipv4)
        async let processesResponse = apiClient.listIndicators(pageSize: 500, type: .processName)
        async let hashesResponse = apiClient.listIndicators(pageSize: 1000, type: .sha256)

        let (domains, ips, processes, hashes) = try await (domainsResponse, ipsResponse, processesResponse, hashesResponse)

        // Update cache
        cachedDomains = Set(domains.indicators.map { $0.value })
        cachedIPs = Set(ips.indicators.map { $0.value })
        cachedProcessNames = Set(processes.indicators.map { $0.value.lowercased() })
        cachedHashes = Set(hashes.indicators.map { $0.value.lowercased() })

        // Persist cache
        let defaults = UserDefaults(suiteName: AppGroupConfig.identifier) ?? UserDefaults.standard
        defaults.set(Array(cachedDomains), forKey: "cached_domains")
        defaults.set(Array(cachedIPs), forKey: "cached_ips")
        defaults.set(Array(cachedHashes), forKey: "cached_hashes")
        defaults.set(Array(cachedProcessNames), forKey: "cached_processes")
        defaults.set(Date(), forKey: "cache_last_update")

        lastCacheUpdate = Date()

        logger.info("Synced indicators: \(self.cachedDomains.count) domains, \(self.cachedIPs.count) IPs, \(self.cachedProcessNames.count) processes")
    }

    // MARK: - Enhanced Network Scanning

    /// Scan network connections with API-backed threat intelligence
    func scanNetwork(connections: [NetworkConnection]) async -> [EnhancedThreat] {
        var threats: [EnhancedThreat] = []

        // Extract domains and IPs from connections
        let domains = connections.compactMap { $0.domain }
        let ips = connections.map { $0.remoteIP }

        // Check against API (if online)
        if let apiThreats = await checkIndicatorsWithAPI(values: domains + ips) {
            threats.append(contentsOf: apiThreats)
        }

        // Check against local cache (always)
        let cacheThreats = checkIndicatorsWithCache(domains: domains, ips: ips)
        threats.append(contentsOf: cacheThreats)

        // Check blocklist
        for domain in domains {
            let (shouldBlock, rule) = blocklist.shouldBlock(domain)
            if shouldBlock, let rule = rule {
                threats.append(EnhancedThreat(
                    id: "blocklist-\(domain)",
                    name: "Blocked Domain",
                    description: "Domain blocked by \(rule.category.rawValue) filter",
                    severity: rule.severity,
                    type: .network,
                    path: domain,
                    requiresRoot: false,
                    source: .cache,
                    indicator: nil,
                    campaign: nil,
                    threatActor: nil,
                    mitreTechniques: [],
                    confidence: 90,
                    metadata: ["category": rule.category.rawValue],
                    detectedAt: Date()
                ))
            }
        }

        return threats.uniqued(by: { $0.id })
    }

    /// Scan processes with API-backed threat intelligence
    func scanProcesses(processes: [ProcessInfo]) async -> [EnhancedThreat] {
        var threats: [EnhancedThreat] = []

        let processNames = processes.map { $0.name.lowercased() }

        // Check against API
        if let apiThreats = await checkIndicatorsWithAPI(values: processNames, type: .processName) {
            threats.append(contentsOf: apiThreats)
        }

        // Check against local cache
        for process in processes {
            if cachedProcessNames.contains(process.name.lowercased()) {
                threats.append(EnhancedThreat(
                    id: "process-\(process.pid)-\(process.name)",
                    name: "Suspicious Process: \(process.name)",
                    description: "Process matches known malicious indicator",
                    severity: .critical,
                    type: .process,
                    path: process.path ?? process.name,
                    requiresRoot: true,
                    source: .cache,
                    indicator: nil,
                    campaign: nil,
                    threatActor: nil,
                    mitreTechniques: ["T1059"],  // Command and Scripting Interpreter
                    confidence: 85,
                    metadata: ["pid": String(process.pid)],
                    detectedAt: Date()
                ))
            }
        }

        return threats.uniqued(by: { $0.id })
    }

    /// Scan file hashes with API-backed threat intelligence
    func scanFiles(hashes: [(path: String, sha256: String)]) async -> [EnhancedThreat] {
        var threats: [EnhancedThreat] = []

        let hashValues = hashes.map { $0.sha256.lowercased() }

        // Check against API
        if let apiThreats = await checkIndicatorsWithAPI(values: hashValues, type: .sha256) {
            threats.append(contentsOf: apiThreats)
        }

        // Check against local cache
        for (path, hash) in hashes {
            if cachedHashes.contains(hash.lowercased()) {
                threats.append(EnhancedThreat(
                    id: "file-\(hash)",
                    name: "Malicious File",
                    description: "File hash matches known malware",
                    severity: .critical,
                    type: .file,
                    path: path,
                    requiresRoot: false,
                    source: .cache,
                    indicator: nil,
                    campaign: nil,
                    threatActor: nil,
                    mitreTechniques: ["T1204"],  // User Execution
                    confidence: 95,
                    metadata: ["sha256": hash],
                    detectedAt: Date()
                ))
            }
        }

        return threats.uniqued(by: { $0.id })
    }

    // MARK: - SMS/URL Analysis

    /// Analyze SMS message for phishing
    func analyzeSMS(content: String, sender: String?) async -> (isPhishing: Bool, threats: [EnhancedThreat]) {
        var threats: [EnhancedThreat] = []

        do {
            let analysis = try await apiClient.analyzeSMS(content: content, sender: sender)

            if analysis.isPhishing {
                for threat in analysis.threats {
                    threats.append(EnhancedThreat(
                        id: threat.id,
                        name: "Phishing SMS: \(threat.type.rawValue)",
                        description: threat.description,
                        severity: threat.severity,
                        type: .sms,
                        path: sender ?? "unknown",
                        requiresRoot: false,
                        source: .api,
                        indicator: threat.indicator,
                        campaign: nil,
                        threatActor: nil,
                        mitreTechniques: ["T1566"],  // Phishing
                        confidence: Int(threat.confidence * 100),
                        metadata: ["sender": sender ?? "unknown"],
                        detectedAt: Date()
                    ))
                }
            }

            return (analysis.isPhishing, threats)
        } catch {
            logger.error("Failed to analyze SMS: \(error.localizedDescription)")

            // Fallback to local pattern matching
            let localResult = localSMSAnalysis(content: content)
            return localResult
        }
    }

    /// Check URL reputation
    func checkURL(url: String) async -> (isMalicious: Bool, threat: EnhancedThreat?) {
        do {
            let reputation = try await apiClient.checkURLReputation(url: url)

            if reputation.isMalicious || reputation.isPhishing {
                let threat = EnhancedThreat(
                    id: "url-\(reputation.domain)",
                    name: reputation.isPhishing ? "Phishing URL" : "Malicious URL",
                    description: "URL reputation check flagged this as dangerous",
                    severity: reputation.riskLevel,
                    type: .url,
                    path: url,
                    requiresRoot: false,
                    source: .api,
                    indicator: reputation.indicators?.first,
                    campaign: nil,
                    threatActor: nil,
                    mitreTechniques: reputation.isPhishing ? ["T1566"] : ["T1204"],
                    confidence: Int(reputation.riskScore * 100),
                    metadata: ["categories": reputation.categories.joined(separator: ",")],
                    detectedAt: Date()
                )

                return (true, threat)
            }

            return (false, nil)
        } catch {
            logger.error("Failed to check URL reputation: \(error.localizedDescription)")

            // Check local blocklist
            if let domain = extractDomain(from: url) {
                let (shouldBlock, rule) = blocklist.shouldBlock(domain)
                if shouldBlock {
                    let threat = EnhancedThreat(
                        id: "url-blocked-\(domain)",
                        name: "Blocked URL",
                        description: "URL domain is blocked",
                        severity: rule?.severity ?? .medium,
                        type: .url,
                        path: url,
                        requiresRoot: false,
                        source: .cache,
                        indicator: nil,
                        campaign: nil,
                        threatActor: nil,
                        mitreTechniques: [],
                        confidence: 90,
                        metadata: ["category": rule?.category.rawValue ?? "unknown"],
                        detectedAt: Date()
                    )
                    return (true, threat)
                }
            }

            return (false, nil)
        }
    }

    // MARK: - QR Code Analysis

    /// Analyze QR code content
    func analyzeQRCode(content: String, location: (lat: Double, lon: Double)?) async -> (shouldBlock: Bool, threats: [EnhancedThreat]) {
        var threats: [EnhancedThreat] = []

        do {
            let scan = try await apiClient.scanQRCode(
                content: content,
                latitude: location?.lat,
                longitude: location?.lon
            )

            if scan.shouldBlock {
                for threat in scan.threats {
                    threats.append(EnhancedThreat(
                        id: threat.id,
                        name: "QR Code Threat: \(threat.type.rawValue)",
                        description: threat.description,
                        severity: threat.severity,
                        type: .url,
                        path: content,
                        requiresRoot: false,
                        source: .api,
                        indicator: nil,
                        campaign: nil,
                        threatActor: nil,
                        mitreTechniques: ["T1566"],
                        confidence: Int(threat.confidence * 100),
                        metadata: threat.details ?? [:],
                        detectedAt: Date()
                    ))
                }
            }

            return (scan.shouldBlock, threats)
        } catch {
            logger.error("Failed to analyze QR code: \(error.localizedDescription)")
            return (false, [])
        }
    }

    // MARK: - Private Helpers

    private func checkIndicatorsWithAPI(values: [String], type: IndicatorType? = nil) async -> [EnhancedThreat]? {
        guard !values.isEmpty else { return nil }

        do {
            let types = type != nil ? [type!] : nil
            let response = try await apiClient.checkIndicators(values: values, types: types)

            return response.found.map { indicator in
                EnhancedThreat(
                    id: indicator.id,
                    name: "Threat Indicator Match",
                    description: indicator.description ?? "Matches known threat indicator",
                    severity: indicator.severity,
                    type: mapIndicatorType(indicator.type),
                    path: indicator.value,
                    requiresRoot: false,
                    source: .api,
                    indicator: indicator,
                    campaign: indicator.campaignName,
                    threatActor: indicator.threatActorName,
                    mitreTechniques: indicator.mitreTechniques ?? [],
                    confidence: indicator.confidence,
                    metadata: indicator.metadata ?? [:],
                    detectedAt: Date()
                )
            }
        } catch {
            logger.error("API indicator check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func checkIndicatorsWithCache(domains: [String], ips: [String]) -> [EnhancedThreat] {
        var threats: [EnhancedThreat] = []

        for domain in domains {
            if cachedDomains.contains(domain.lowercased()) {
                threats.append(EnhancedThreat(
                    id: "cached-domain-\(domain)",
                    name: "Malicious Domain",
                    description: "Domain matches cached threat indicator",
                    severity: .high,
                    type: .network,
                    path: domain,
                    requiresRoot: false,
                    source: .cache,
                    indicator: nil,
                    campaign: nil,
                    threatActor: nil,
                    mitreTechniques: [],
                    confidence: 80,
                    metadata: [:],
                    detectedAt: Date()
                ))
            }
        }

        for ip in ips {
            if cachedIPs.contains(ip) {
                threats.append(EnhancedThreat(
                    id: "cached-ip-\(ip)",
                    name: "Malicious IP",
                    description: "IP matches cached threat indicator",
                    severity: .high,
                    type: .network,
                    path: ip,
                    requiresRoot: false,
                    source: .cache,
                    indicator: nil,
                    campaign: nil,
                    threatActor: nil,
                    mitreTechniques: [],
                    confidence: 80,
                    metadata: [:],
                    detectedAt: Date()
                ))
            }
        }

        return threats
    }

    private func localSMSAnalysis(content: String) -> (isPhishing: Bool, threats: [EnhancedThreat]) {
        var threats: [EnhancedThreat] = []
        let lowercased = content.lowercased()

        // Basic phishing patterns
        let phishingPatterns = [
            "verify your account",
            "suspended",
            "click here",
            "urgent",
            "limited time",
            "claim your prize",
            "congratulations",
            "you've won",
            "bitcoin",
            "crypto",
            "bank of",
            "paypal",
            "amazon",
            "confirm your identity"
        ]

        for pattern in phishingPatterns {
            if lowercased.contains(pattern) {
                threats.append(EnhancedThreat(
                    id: "local-sms-\(pattern.hashValue)",
                    name: "Suspicious SMS Pattern",
                    description: "Message contains phishing indicator: \(pattern)",
                    severity: .medium,
                    type: .sms,
                    path: "local-analysis",
                    requiresRoot: false,
                    source: .local,
                    indicator: nil,
                    campaign: nil,
                    threatActor: nil,
                    mitreTechniques: ["T1566"],
                    confidence: 60,
                    metadata: ["pattern": pattern],
                    detectedAt: Date()
                ))
            }
        }

        return (!threats.isEmpty, threats)
    }

    private func mapIndicatorType(_ type: IndicatorType) -> EnhancedThreat.ThreatType {
        switch type {
        case .domain, .ipv4, .ipv6, .url, .asn, .cidr:
            return .network
        case .processName:
            return .process
        case .sha256, .sha1, .md5, .fileName, .filePath:
            return .file
        case .bundleId:
            return .app
        case .certificate:
            return .certificate
        default:
            return .network
        }
    }

    private func extractDomain(from url: String) -> String? {
        guard let urlObj = URL(string: url) else { return nil }
        return urlObj.host
    }
}

// MARK: - Supporting Types

struct NetworkConnection {
    let remoteIP: String
    let remotePort: Int
    let localPort: Int
    let domain: String?
    let state: String
}

struct ProcessInfo {
    let pid: Int
    let name: String
    let path: String?
    let user: String?
}

// MARK: - Array Extension

extension Array {
    func uniqued<T: Hashable>(by keyPath: (Element) -> T) -> [Element] {
        var seen = Set<T>()
        return filter { seen.insert(keyPath($0)).inserted }
    }
}
