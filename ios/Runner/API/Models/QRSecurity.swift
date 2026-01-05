// QRSecurity.swift
// OrbGuard iOS - QR Code Security Models
// Location: ios/Runner/API/Models/QRSecurity.swift

import Foundation

// MARK: - QR Content Type

enum QRContentType: String, Codable {
    case url = "url"
    case text = "text"
    case email = "email"
    case phone = "phone"
    case sms = "sms"
    case wifi = "wifi"
    case vcard = "vcard"
    case geo = "geo"
    case event = "event"
    case crypto = "crypto"
    case appLink = "app_link"
    case unknown = "unknown"
}

// MARK: - QR Threat Type

enum QRThreatType: String, Codable {
    case phishing = "phishing"
    case malware = "malware"
    case scam = "scam"
    case cryptoScam = "crypto_scam"
    case fakeLogin = "fake_login"
    case dataHarvesting = "data_harvesting"
    case maliciousRedirect = "malicious_redirect"
    case suspiciousWifi = "suspicious_wifi"
    case typosquatting = "typosquatting"
    case urlShortener = "url_shortener"
    case suspiciousTld = "suspicious_tld"
    case ipAddress = "ip_address"
    case encodedUrl = "encoded_url"
    case premiumRate = "premium_rate"
    case none = "none"
}

// MARK: - QR Scan Request

struct QRScanRequest: Codable {
    let content: String
    let deviceId: String?
    let latitude: Double?
    let longitude: Double?

    enum CodingKeys: String, CodingKey {
        case content
        case deviceId = "device_id"
        case latitude
        case longitude
    }
}

// MARK: - QR Scan Response

struct QRScanResponse: Codable {
    let content: String
    let contentType: QRContentType
    let parsedContent: ParsedQRContent?
    let threats: [QRThreat]
    let threatLevel: SeverityLevel
    let shouldBlock: Bool
    let warnings: [String]
    let recommendations: [String]
    let preview: QRPreview?

    enum CodingKeys: String, CodingKey {
        case content
        case contentType = "content_type"
        case parsedContent = "parsed_content"
        case threats
        case threatLevel = "threat_level"
        case shouldBlock = "should_block"
        case warnings
        case recommendations
        case preview
    }
}

// MARK: - Parsed QR Content

struct ParsedQRContent: Codable {
    // URL
    let url: String?
    let domain: String?
    let path: String?
    let queryParams: [String: String]?

    // Email
    let emailAddress: String?
    let emailSubject: String?
    let emailBody: String?

    // Phone/SMS
    let phoneNumber: String?
    let smsBody: String?

    // WiFi
    let wifiSSID: String?
    let wifiPassword: String?
    let wifiSecurity: String?

    // vCard
    let contactName: String?
    let contactPhone: String?
    let contactEmail: String?
    let contactOrg: String?

    // Geo
    let geoLatitude: Double?
    let geoLongitude: Double?

    // Crypto
    let cryptoAddress: String?
    let cryptoCurrency: String?
    let cryptoAmount: String?

    enum CodingKeys: String, CodingKey {
        case url
        case domain
        case path
        case queryParams = "query_params"
        case emailAddress = "email_address"
        case emailSubject = "email_subject"
        case emailBody = "email_body"
        case phoneNumber = "phone_number"
        case smsBody = "sms_body"
        case wifiSSID = "wifi_ssid"
        case wifiPassword = "wifi_password"
        case wifiSecurity = "wifi_security"
        case contactName = "contact_name"
        case contactPhone = "contact_phone"
        case contactEmail = "contact_email"
        case contactOrg = "contact_org"
        case geoLatitude = "geo_latitude"
        case geoLongitude = "geo_longitude"
        case cryptoAddress = "crypto_address"
        case cryptoCurrency = "crypto_currency"
        case cryptoAmount = "crypto_amount"
    }
}

// MARK: - QR Threat

struct QRThreat: Codable, Identifiable {
    let id: String
    let type: QRThreatType
    let description: String
    let severity: SeverityLevel
    let confidence: Double
    let details: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case description
        case severity
        case confidence
        case details
    }
}

// MARK: - QR Preview

struct QRPreview: Codable {
    let title: String
    let description: String
    let icon: String?
    let actionText: String
    let warningText: String?
}

// MARK: - YARA Scan

struct YARAScanRequest: Codable {
    let data: String  // Base64 encoded
    let fileName: String?
    let fileType: String?
    let rules: [String]?  // Specific rules to use

    enum CodingKeys: String, CodingKey {
        case data
        case fileName = "file_name"
        case fileType = "file_type"
        case rules
    }
}

struct YARAScanResponse: Codable {
    let matches: [YARAMatch]
    let riskScore: Double
    let riskLevel: SeverityLevel
    let scanDuration: Double

    enum CodingKeys: String, CodingKey {
        case matches
        case riskScore = "risk_score"
        case riskLevel = "risk_level"
        case scanDuration = "scan_duration"
    }
}

struct YARAMatch: Codable, Identifiable {
    let id: String
    let ruleName: String
    let ruleDescription: String?
    let severity: SeverityLevel
    let category: String
    let matchedStrings: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case ruleName = "rule_name"
        case ruleDescription = "rule_description"
        case severity
        case category
        case matchedStrings = "matched_strings"
    }
}
