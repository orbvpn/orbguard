// SMSAnalysis.swift
// OrbGuard iOS - SMS/Smishing Analysis Models
// Location: ios/Runner/API/Models/SMSAnalysis.swift

import Foundation

// MARK: - SMS Analysis Request

struct SMSAnalysisRequest: Codable {
    let content: String
    let sender: String?
    let timestamp: Date?
    let deviceId: String?

    enum CodingKeys: String, CodingKey {
        case content
        case sender
        case timestamp
        case deviceId = "device_id"
    }
}

// MARK: - SMS Analysis Response

struct SMSAnalysisResponse: Codable {
    let isPhishing: Bool
    let riskScore: Double
    let riskLevel: SeverityLevel
    let threats: [SMSThreat]
    let urls: [ExtractedURL]
    let intents: [SuspiciousIntent]
    let senderAnalysis: SenderAnalysis?
    let recommendations: [String]

    enum CodingKeys: String, CodingKey {
        case isPhishing = "is_phishing"
        case riskScore = "risk_score"
        case riskLevel = "risk_level"
        case threats
        case urls
        case intents
        case senderAnalysis = "sender_analysis"
        case recommendations
    }
}

// MARK: - SMS Threat

struct SMSThreat: Codable, Identifiable {
    let id: String
    let type: SMSThreatType
    let description: String
    let severity: SeverityLevel
    let confidence: Double
    let matchedPattern: String?
    let indicator: ThreatIndicator?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case description
        case severity
        case confidence
        case matchedPattern = "matched_pattern"
        case indicator
    }
}

enum SMSThreatType: String, Codable {
    case phishing = "phishing"
    case smishing = "smishing"
    case bankingFraud = "banking_fraud"
    case packageScam = "package_scam"
    case techSupport = "tech_support"
    case irs = "irs"
    case lottery = "lottery"
    case romance = "romance"
    case jobScam = "job_scam"
    case cryptoScam = "crypto_scam"
    case executiveImpersonation = "executive_impersonation"
    case brandImpersonation = "brand_impersonation"
    case malwareLink = "malware_link"
    case dataHarvesting = "data_harvesting"
    case urgentAction = "urgent_action"
    case unknown = "unknown"
}

// MARK: - Extracted URL

struct ExtractedURL: Codable, Identifiable {
    let id: String
    let url: String
    let domain: String
    let isMalicious: Bool
    let threatType: String?
    let reputation: URLReputation?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case domain
        case isMalicious = "is_malicious"
        case threatType = "threat_type"
        case reputation
    }
}

// MARK: - URL Reputation

struct URLReputation: Codable {
    let domain: String
    let riskScore: Double
    let riskLevel: SeverityLevel
    let categories: [String]
    let isMalicious: Bool
    let isPhishing: Bool
    let isSuspicious: Bool
    let firstSeen: Date?
    let lastSeen: Date?
    let indicators: [ThreatIndicator]?

    enum CodingKeys: String, CodingKey {
        case domain
        case riskScore = "risk_score"
        case riskLevel = "risk_level"
        case categories
        case isMalicious = "is_malicious"
        case isPhishing = "is_phishing"
        case isSuspicious = "is_suspicious"
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case indicators
    }
}

// MARK: - Suspicious Intent

struct SuspiciousIntent: Codable, Identifiable {
    let id: String
    let type: IntentType
    let description: String
    let confidence: Double
    let matchedText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case description
        case confidence
        case matchedText = "matched_text"
    }
}

enum IntentType: String, Codable {
    case urgency = "urgency"
    case fear = "fear"
    case reward = "reward"
    case authority = "authority"
    case scarcity = "scarcity"
    case socialProof = "social_proof"
    case reciprocity = "reciprocity"
    case unknown = "unknown"
}

// MARK: - Sender Analysis

struct SenderAnalysis: Codable {
    let sender: String
    let type: SenderType
    let isSuspicious: Bool
    let suspiciousReasons: [String]
    let brandMatch: BrandMatch?
    let reputation: SenderReputation?

    enum CodingKeys: String, CodingKey {
        case sender
        case type
        case isSuspicious = "is_suspicious"
        case suspiciousReasons = "suspicious_reasons"
        case brandMatch = "brand_match"
        case reputation
    }
}

enum SenderType: String, Codable {
    case shortCode = "short_code"
    case alphanumeric = "alphanumeric"
    case phoneNumber = "phone_number"
    case email = "email"
    case unknown = "unknown"
}

struct BrandMatch: Codable {
    let matchedBrand: String
    let confidence: Double
    let isLegitimate: Bool
    let spoofingIndicators: [String]

    enum CodingKeys: String, CodingKey {
        case matchedBrand = "matched_brand"
        case confidence
        case isLegitimate = "is_legitimate"
        case spoofingIndicators = "spoofing_indicators"
    }
}

struct SenderReputation: Codable {
    let score: Double
    let totalMessages: Int
    let spamReports: Int
    let phishingReports: Int
    let lastReported: Date?

    enum CodingKeys: String, CodingKey {
        case score
        case totalMessages = "total_messages"
        case spamReports = "spam_reports"
        case phishingReports = "phishing_reports"
        case lastReported = "last_reported"
    }
}
