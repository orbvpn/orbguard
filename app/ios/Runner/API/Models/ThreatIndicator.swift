// ThreatIndicator.swift
// OrbGuard iOS - Threat Intelligence Models
// Location: ios/Runner/API/Models/ThreatIndicator.swift

import Foundation

// MARK: - Indicator Type

enum IndicatorType: String, Codable, CaseIterable {
    case domain = "domain"
    case ipv4 = "ipv4"
    case ipv6 = "ipv6"
    case url = "url"
    case sha256 = "sha256"
    case sha1 = "sha1"
    case md5 = "md5"
    case email = "email"
    case phoneNumber = "phone_number"
    case processName = "process_name"
    case fileName = "file_name"
    case filePath = "file_path"
    case bundleId = "bundle_id"
    case certificate = "certificate"
    case mutexName = "mutex_name"
    case registryKey = "registry_key"
    case userAgent = "user_agent"
    case asn = "asn"
    case cidr = "cidr"
    case bitcoinAddress = "bitcoin_address"
    case imei = "imei"
    case androidId = "android_id"
    case iosUdid = "ios_udid"
    case unknown = "unknown"
}

// MARK: - Severity Level

enum SeverityLevel: String, Codable, CaseIterable {
    case critical = "critical"
    case high = "high"
    case medium = "medium"
    case low = "low"
    case info = "info"
    case unknown = "unknown"

    var weight: Int {
        switch self {
        case .critical: return 10
        case .high: return 8
        case .medium: return 5
        case .low: return 2
        case .info: return 1
        case .unknown: return 0
        }
    }

    var color: String {
        switch self {
        case .critical: return "#FF0000"
        case .high: return "#FF6B00"
        case .medium: return "#FFB800"
        case .low: return "#00D9FF"
        case .info: return "#808080"
        case .unknown: return "#CCCCCC"
        }
    }
}

// MARK: - Platform

enum Platform: String, Codable, CaseIterable {
    case ios = "ios"
    case android = "android"
    case windows = "windows"
    case macos = "macos"
    case linux = "linux"
    case all = "all"
}

// MARK: - Threat Indicator

struct ThreatIndicator: Codable, Identifiable, Hashable {
    let id: String
    let value: String
    let type: IndicatorType
    let severity: SeverityLevel
    let confidence: Int
    let platforms: [Platform]
    let tags: [String]
    let description: String?
    let sourceId: String?
    let sourceName: String?
    let campaignId: String?
    let campaignName: String?
    let threatActorId: String?
    let threatActorName: String?
    let firstSeen: Date?
    let lastSeen: Date?
    let expiresAt: Date?
    let metadata: [String: String]?
    let mitreTechniques: [String]?
    let yaraMatches: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case value
        case type
        case severity
        case confidence
        case platforms
        case tags
        case description
        case sourceId = "source_id"
        case sourceName = "source_name"
        case campaignId = "campaign_id"
        case campaignName = "campaign_name"
        case threatActorId = "threat_actor_id"
        case threatActorName = "threat_actor_name"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case expiresAt = "expires_at"
        case metadata
        case mitreTechniques = "mitre_techniques"
        case yaraMatches = "yara_matches"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ThreatIndicator, rhs: ThreatIndicator) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Indicator Check Request/Response

struct IndicatorCheckRequest: Codable {
    let values: [String]
    let types: [IndicatorType]?
    let platforms: [Platform]?

    enum CodingKeys: String, CodingKey {
        case values
        case types
        case platforms
    }
}

struct IndicatorCheckResponse: Codable {
    let found: [ThreatIndicator]
    let notFound: [String]
    let totalChecked: Int
    let totalFound: Int
    let checkDuration: Double

    enum CodingKeys: String, CodingKey {
        case found
        case notFound = "not_found"
        case totalChecked = "total_checked"
        case totalFound = "total_found"
        case checkDuration = "check_duration"
    }
}

// MARK: - Indicator List Response

struct IndicatorListResponse: Codable {
    let indicators: [ThreatIndicator]
    let total: Int
    let page: Int
    let pageSize: Int
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case indicators
        case total
        case page
        case pageSize = "page_size"
        case hasMore = "has_more"
    }
}

// MARK: - DNS Block Check

struct DNSBlockRequest: Codable {
    let domain: String
    let clientId: String?
    let deviceId: String?

    enum CodingKeys: String, CodingKey {
        case domain
        case clientId = "client_id"
        case deviceId = "device_id"
    }
}

struct DNSBlockResponse: Codable {
    let domain: String
    let shouldBlock: Bool
    let reason: String?
    let category: String?
    let severity: SeverityLevel?
    let matchedRule: String?
    let indicator: ThreatIndicator?

    enum CodingKeys: String, CodingKey {
        case domain
        case shouldBlock = "should_block"
        case reason
        case category
        case severity
        case matchedRule = "matched_rule"
        case indicator
    }
}

struct DNSBatchBlockRequest: Codable {
    let domains: [String]
    let clientId: String?
    let deviceId: String?

    enum CodingKeys: String, CodingKey {
        case domains
        case clientId = "client_id"
        case deviceId = "device_id"
    }
}

struct DNSBatchBlockResponse: Codable {
    let results: [DNSBlockResponse]
    let blockedCount: Int
    let totalChecked: Int

    enum CodingKeys: String, CodingKey {
        case results
        case blockedCount = "blocked_count"
        case totalChecked = "total_checked"
    }
}
