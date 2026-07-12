// Campaign.swift
// OrbGuard iOS - Campaign and Threat Actor Models
// Location: ios/Runner/API/Models/Campaign.swift

import Foundation

// MARK: - Campaign Status

enum CampaignStatus: String, Codable {
    case active = "active"
    case inactive = "inactive"
    case dormant = "dormant"
    case unknown = "unknown"
}

// MARK: - Campaign

struct Campaign: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let status: CampaignStatus
    let firstSeen: Date?
    let lastSeen: Date?
    let targetPlatforms: [Platform]
    let targetRegions: [String]
    let targetIndustries: [String]
    let ttps: [String]  // MITRE ATT&CK techniques
    let indicators: Int  // Count of related indicators
    let threatActors: [String]  // Related threat actor IDs
    let aliases: [String]
    let references: [Reference]?
    let malwareFamilies: [String]
    let severity: SeverityLevel

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case status
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case targetPlatforms = "target_platforms"
        case targetRegions = "target_regions"
        case targetIndustries = "target_industries"
        case ttps
        case indicators
        case threatActors = "threat_actors"
        case aliases
        case references
        case malwareFamilies = "malware_families"
        case severity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Campaign, rhs: Campaign) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Reference

struct Reference: Codable {
    let source: String
    let url: String?
    let description: String?
    let date: Date?
}

// MARK: - Threat Actor Type

enum ThreatActorType: String, Codable {
    case nationState = "nation_state"
    case criminalGroup = "criminal_group"
    case hacktivistGroup = "hacktivist_group"
    case insider = "insider"
    case unknown = "unknown"
}

// MARK: - Threat Actor Motivation

enum ThreatActorMotivation: String, Codable {
    case financial = "financial"
    case espionage = "espionage"
    case disruption = "disruption"
    case ideological = "ideological"
    case revenge = "revenge"
    case unknown = "unknown"
}

// MARK: - Threat Actor

struct ThreatActor: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let type: ThreatActorType
    let motivation: ThreatActorMotivation
    let sophistication: String?
    let firstSeen: Date?
    let lastSeen: Date?
    let aliases: [String]
    let attributedTo: String?  // Country/organization
    let targetPlatforms: [Platform]
    let targetRegions: [String]
    let targetIndustries: [String]
    let ttps: [String]
    let campaigns: [String]  // Related campaign IDs
    let malwareFamilies: [String]
    let indicators: Int
    let references: [Reference]?
    let confidence: Int  // Attribution confidence 0-100

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case type
        case motivation
        case sophistication
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case aliases
        case attributedTo = "attributed_to"
        case targetPlatforms = "target_platforms"
        case targetRegions = "target_regions"
        case targetIndustries = "target_industries"
        case ttps
        case campaigns
        case malwareFamilies = "malware_families"
        case indicators
        case references
        case confidence
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ThreatActor, rhs: ThreatActor) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - MITRE ATT&CK Technique

struct MITRETechnique: Codable, Identifiable {
    let id: String  // e.g., "T1566.001"
    let name: String
    let description: String?
    let tactic: String  // e.g., "initial-access"
    let platforms: [Platform]
    let detection: String?
    let mitigation: String?
    let url: String?
    let subTechniques: [MITRETechnique]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case tactic
        case platforms
        case detection
        case mitigation
        case url
        case subTechniques = "sub_techniques"
    }
}

// MARK: - Threat Stats

struct ThreatStats: Codable {
    let totalIndicators: Int
    let indicatorsByType: [String: Int]
    let indicatorsBySeverity: [String: Int]
    let indicatorsByPlatform: [String: Int]
    let activeCampaigns: Int
    let threatActors: Int
    let lastUpdated: Date
    let sources: Int
    let healthyFeeds: Int

    enum CodingKeys: String, CodingKey {
        case totalIndicators = "total_indicators"
        case indicatorsByType = "indicators_by_type"
        case indicatorsBySeverity = "indicators_by_severity"
        case indicatorsByPlatform = "indicators_by_platform"
        case activeCampaigns = "active_campaigns"
        case threatActors = "threat_actors"
        case lastUpdated = "last_updated"
        case sources
        case healthyFeeds = "healthy_feeds"
    }
}
