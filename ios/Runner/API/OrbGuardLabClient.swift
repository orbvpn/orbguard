// OrbGuardLabClient.swift
// OrbGuard iOS - Native Swift API Client for OrbGuard Lab Backend
// Location: ios/Runner/API/OrbGuardLabClient.swift

import Foundation

// MARK: - API Configuration

struct OrbGuardLabConfig {
    let baseURL: String
    let apiKey: String?
    let timeout: TimeInterval
    let retryCount: Int
    let cacheEnabled: Bool

    static let `default` = OrbGuardLabConfig(
        baseURL: "http://localhost:8090",
        apiKey: nil,
        timeout: 30,
        retryCount: 3,
        cacheEnabled: true
    )

    static let production = OrbGuardLabConfig(
        baseURL: "https://api.orbguard.com",
        apiKey: nil,
        timeout: 30,
        retryCount: 3,
        cacheEnabled: true
    )
}

// MARK: - API Error

enum OrbGuardLabError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int, String?)
    case decodingError(Error)
    case encodingError(Error)
    case unauthorized
    case notFound
    case serverError
    case timeout
    case offline
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message ?? "Unknown error")"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized - invalid API key"
        case .notFound:
            return "Resource not found"
        case .serverError:
            return "Server error"
        case .timeout:
            return "Request timed out"
        case .offline:
            return "Device is offline"
        case .unknown:
            return "Unknown error occurred"
        }
    }
}

// MARK: - OrbGuard Lab API Client

class OrbGuardLabClient {

    // MARK: - Properties

    private let config: OrbGuardLabConfig
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let cache: URLCache

    // App Group for sharing with extensions
    private let appGroupIdentifier = "group.com.orb.guard.shared"

    // Singleton instance
    static let shared = OrbGuardLabClient()

    // MARK: - Initialization

    init(config: OrbGuardLabConfig = .default) {
        self.config = config

        // Configure URL session
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeout
        sessionConfig.timeoutIntervalForResource = config.timeout * 2
        sessionConfig.waitsForConnectivity = true

        // Configure cache
        let cacheSizeMemory = 10 * 1024 * 1024  // 10 MB
        let cacheSizeDisk = 50 * 1024 * 1024  // 50 MB
        self.cache = URLCache(memoryCapacity: cacheSizeMemory, diskCapacity: cacheSizeDisk)
        sessionConfig.urlCache = cache
        sessionConfig.requestCachePolicy = config.cacheEnabled ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: sessionConfig)

        // Configure JSON decoder
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Try ISO8601 without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        // Configure JSON encoder
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Base Request Method

    private func request<T: Decodable>(
        method: String,
        path: String,
        body: Data? = nil,
        queryParams: [String: String]? = nil
    ) async throws -> T {
        // Build URL
        var urlComponents = URLComponents(string: config.baseURL + path)
        if let params = queryParams {
            urlComponents?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        guard let url = urlComponents?.url else {
            throw OrbGuardLabError.invalidURL
        }

        // Build request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OrbGuard-iOS/1.0", forHTTPHeaderField: "User-Agent")

        if let apiKey = config.apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = body
        }

        // Execute request with retry
        var lastError: Error?
        for attempt in 0..<config.retryCount {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OrbGuardLabError.unknown
                }

                switch httpResponse.statusCode {
                case 200...299:
                    return try decoder.decode(T.self, from: data)
                case 401:
                    throw OrbGuardLabError.unauthorized
                case 404:
                    throw OrbGuardLabError.notFound
                case 500...599:
                    throw OrbGuardLabError.serverError
                default:
                    let message = String(data: data, encoding: .utf8)
                    throw OrbGuardLabError.httpError(httpResponse.statusCode, message)
                }
            } catch let error as OrbGuardLabError {
                throw error
            } catch let error as DecodingError {
                throw OrbGuardLabError.decodingError(error)
            } catch {
                lastError = error
                // Wait before retry (exponential backoff)
                if attempt < config.retryCount - 1 {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                }
            }
        }

        throw OrbGuardLabError.networkError(lastError ?? OrbGuardLabError.unknown)
    }

    private func get<T: Decodable>(path: String, queryParams: [String: String]? = nil) async throws -> T {
        try await request(method: "GET", path: path, queryParams: queryParams)
    }

    private func post<T: Decodable, B: Encodable>(path: String, body: B) async throws -> T {
        let bodyData = try encoder.encode(body)
        return try await request(method: "POST", path: path, body: bodyData)
    }

    // MARK: - Health Check

    struct HealthResponse: Codable {
        let status: String
        let version: String?
        let uptime: Int?
    }

    func healthCheck() async throws -> HealthResponse {
        try await get(path: "/health")
    }

    // MARK: - Indicators API

    func listIndicators(
        page: Int = 1,
        pageSize: Int = 100,
        type: IndicatorType? = nil,
        severity: SeverityLevel? = nil,
        platform: Platform? = nil
    ) async throws -> IndicatorListResponse {
        var params: [String: String] = [
            "page": String(page),
            "page_size": String(pageSize)
        ]
        if let type = type { params["type"] = type.rawValue }
        if let severity = severity { params["severity"] = severity.rawValue }
        if let platform = platform { params["platform"] = platform.rawValue }

        return try await get(path: "/api/v1/indicators", queryParams: params)
    }

    func checkIndicators(values: [String], types: [IndicatorType]? = nil) async throws -> IndicatorCheckResponse {
        let request = IndicatorCheckRequest(values: values, types: types, platforms: [.ios])
        return try await post(path: "/api/v1/indicators/check", body: request)
    }

    func getIndicator(id: String) async throws -> ThreatIndicator {
        try await get(path: "/api/v1/indicators/\(id)")
    }

    // MARK: - DNS Blocking API (OrbNet)

    func checkDNSBlock(domain: String, deviceId: String? = nil) async throws -> DNSBlockResponse {
        let request = DNSBlockRequest(domain: domain, clientId: nil, deviceId: deviceId)
        return try await post(path: "/api/v1/orbnet/dns/check", body: request)
    }

    func checkDNSBlockBatch(domains: [String], deviceId: String? = nil) async throws -> DNSBatchBlockResponse {
        let request = DNSBatchBlockRequest(domains: domains, clientId: nil, deviceId: deviceId)
        return try await post(path: "/api/v1/orbnet/dns/check/batch", body: request)
    }

    // MARK: - URL Reputation API

    func checkURLReputation(url: String) async throws -> URLReputation {
        var params: [String: String] = ["url": url]
        return try await get(path: "/api/v1/url/reputation", queryParams: params)
    }

    func checkURLReputationBatch(urls: [String]) async throws -> [URLReputation] {
        struct BatchRequest: Codable { let urls: [String] }
        struct BatchResponse: Codable { let results: [URLReputation] }

        let response: BatchResponse = try await post(path: "/api/v1/url/check/batch", body: BatchRequest(urls: urls))
        return response.results
    }

    // MARK: - SMS Analysis API

    func analyzeSMS(content: String, sender: String? = nil) async throws -> SMSAnalysisResponse {
        let request = SMSAnalysisRequest(content: content, sender: sender, timestamp: Date(), deviceId: getDeviceId())
        return try await post(path: "/api/v1/sms/analyze", body: request)
    }

    func analyzeSMSBatch(messages: [(content: String, sender: String?)]) async throws -> [SMSAnalysisResponse] {
        struct BatchRequest: Codable {
            let messages: [SMSAnalysisRequest]
        }
        struct BatchResponse: Codable {
            let results: [SMSAnalysisResponse]
        }

        let requests = messages.map { SMSAnalysisRequest(content: $0.content, sender: $0.sender, timestamp: Date(), deviceId: getDeviceId()) }
        let response: BatchResponse = try await post(path: "/api/v1/sms/analyze/batch", body: BatchRequest(messages: requests))
        return response.results
    }

    // MARK: - QR Code Security API

    func scanQRCode(content: String, latitude: Double? = nil, longitude: Double? = nil) async throws -> QRScanResponse {
        let request = QRScanRequest(content: content, deviceId: getDeviceId(), latitude: latitude, longitude: longitude)
        return try await post(path: "/api/v1/qr/scan", body: request)
    }

    // MARK: - YARA Scanning API

    func yaraScannData(data: Data, fileName: String? = nil, fileType: String? = nil) async throws -> YARAScanResponse {
        let request = YARAScanRequest(data: data.base64EncodedString(), fileName: fileName, fileType: fileType, rules: nil)
        return try await post(path: "/api/v1/yara/scan", body: request)
    }

    // MARK: - Campaigns API

    func listCampaigns(page: Int = 1, pageSize: Int = 50, status: CampaignStatus? = nil) async throws -> [Campaign] {
        struct Response: Codable { let campaigns: [Campaign] }
        var params: [String: String] = [
            "page": String(page),
            "page_size": String(pageSize)
        ]
        if let status = status { params["status"] = status.rawValue }

        let response: Response = try await get(path: "/api/v1/campaigns", queryParams: params)
        return response.campaigns
    }

    func getCampaign(id: String) async throws -> Campaign {
        try await get(path: "/api/v1/campaigns/\(id)")
    }

    // MARK: - Threat Actors API

    func listThreatActors(page: Int = 1, pageSize: Int = 50) async throws -> [ThreatActor] {
        struct Response: Codable { let actors: [ThreatActor] }
        let params: [String: String] = [
            "page": String(page),
            "page_size": String(pageSize)
        ]

        let response: Response = try await get(path: "/api/v1/actors", queryParams: params)
        return response.actors
    }

    func getThreatActor(id: String) async throws -> ThreatActor {
        try await get(path: "/api/v1/actors/\(id)")
    }

    // MARK: - MITRE ATT&CK API

    func listMITRETechniques(tactic: String? = nil, platform: Platform? = nil) async throws -> [MITRETechnique] {
        struct Response: Codable { let techniques: [MITRETechnique] }
        var params: [String: String] = [:]
        if let tactic = tactic { params["tactic"] = tactic }
        if let platform = platform { params["platform"] = platform.rawValue }

        let response: Response = try await get(path: "/api/v1/mitre/techniques", queryParams: params)
        return response.techniques
    }

    func getMITRETechnique(id: String) async throws -> MITRETechnique {
        try await get(path: "/api/v1/mitre/techniques/\(id)")
    }

    // MARK: - Stats API

    func getThreatStats() async throws -> ThreatStats {
        try await get(path: "/api/v1/stats")
    }

    // MARK: - Sync API (for background updates)

    struct SyncResponse: Codable {
        let newIndicators: Int
        let updatedIndicators: Int
        let deletedIndicators: Int
        let lastSyncTime: Date
        let nextSyncTime: Date

        enum CodingKeys: String, CodingKey {
            case newIndicators = "new_indicators"
            case updatedIndicators = "updated_indicators"
            case deletedIndicators = "deleted_indicators"
            case lastSyncTime = "last_sync_time"
            case nextSyncTime = "next_sync_time"
        }
    }

    func syncThreatIntelligence(since: Date? = nil) async throws -> SyncResponse {
        var params: [String: String] = [:]
        if let since = since {
            let formatter = ISO8601DateFormatter()
            params["since"] = formatter.string(from: since)
        }
        return try await get(path: "/api/v1/sync", queryParams: params)
    }

    // MARK: - Helper Methods

    private func getDeviceId() -> String {
        // Get or create device ID from UserDefaults (shared with App Group)
        let defaults = UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
        if let deviceId = defaults.string(forKey: "orbguard_device_id") {
            return deviceId
        }
        let newDeviceId = UUID().uuidString
        defaults.set(newDeviceId, forKey: "orbguard_device_id")
        return newDeviceId
    }

    // MARK: - Cache Management

    func clearCache() {
        cache.removeAllCachedResponses()
    }

    func getCacheSize() -> Int {
        return cache.currentDiskUsage
    }
}

// MARK: - Convenience Extensions

extension OrbGuardLabClient {

    /// Quick check if a domain should be blocked
    func shouldBlockDomain(_ domain: String) async -> Bool {
        do {
            let response = try await checkDNSBlock(domain: domain)
            return response.shouldBlock
        } catch {
            return false
        }
    }

    /// Quick check if a URL is malicious
    func isURLMalicious(_ url: String) async -> Bool {
        do {
            let response = try await checkURLReputation(url: url)
            return response.isMalicious
        } catch {
            return false
        }
    }

    /// Quick check if SMS is phishing
    func isSMSPhishing(_ content: String, sender: String? = nil) async -> (isPhishing: Bool, riskScore: Double) {
        do {
            let response = try await analyzeSMS(content: content, sender: sender)
            return (response.isPhishing, response.riskScore)
        } catch {
            return (false, 0)
        }
    }
}
