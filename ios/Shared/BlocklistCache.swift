// BlocklistCache.swift
// OrbGuard iOS - SQLite-based Blocklist Cache for Fast DNS Lookups
// Location: ios/Shared/BlocklistCache.swift

import Foundation
import SQLite3
import os.log

// MARK: - Block Rule

struct BlockRule: Codable {
    let id: Int64
    let domain: String
    let ruleType: RuleType
    let category: BlockCategory
    let severity: SeverityLevel
    let source: String?
    let addedAt: Date
    let expiresAt: Date?

    enum RuleType: String, Codable {
        case exact = "exact"
        case wildcard = "wildcard"
        case regex = "regex"
    }

    enum BlockCategory: String, Codable {
        case malware = "malware"
        case phishing = "phishing"
        case scam = "scam"
        case tracker = "tracker"
        case ads = "ads"
        case adult = "adult"
        case gambling = "gambling"
        case custom = "custom"
        case unknown = "unknown"
    }
}

// MARK: - Blocklist Cache

class BlocklistCache {

    // MARK: - Properties

    private var db: OpaquePointer?
    private let dbPath: String
    private let queue = DispatchQueue(label: "com.orb.guard.blocklist", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.orb.guard", category: "BlocklistCache")

    // In-memory bloom filter for fast negative lookups
    private var bloomFilter: Set<Int> = Set()
    private let bloomFilterSize = 100000

    // Singleton
    static let shared: BlocklistCache = {
        let manager = SharedDataManager.shared
        let dbPath: String
        if let url = manager.getSharedFileURL(fileName: AppGroupConfig.blocklistFileName) {
            dbPath = url.path
        } else {
            // Fallback to documents directory
            let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            dbPath = docsPath.appendingPathComponent(AppGroupConfig.blocklistFileName).path
        }
        return BlocklistCache(dbPath: dbPath)
    }()

    // MARK: - Initialization

    init(dbPath: String) {
        self.dbPath = dbPath
        openDatabase()
        createTables()
        buildBloomFilter()
    }

    deinit {
        closeDatabase()
    }

    // MARK: - Database Operations

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            logger.error("Failed to open database at \(self.dbPath)")
        }

        // Enable WAL mode for better concurrent read/write
        executeSQL("PRAGMA journal_mode=WAL;")
        executeSQL("PRAGMA synchronous=NORMAL;")
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    private func createTables() {
        let createBlocklistSQL = """
            CREATE TABLE IF NOT EXISTS blocklist (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain TEXT NOT NULL UNIQUE,
                rule_type TEXT NOT NULL DEFAULT 'exact',
                category TEXT NOT NULL DEFAULT 'unknown',
                severity TEXT NOT NULL DEFAULT 'medium',
                source TEXT,
                added_at TEXT NOT NULL,
                expires_at TEXT,
                hit_count INTEGER DEFAULT 0,
                last_hit TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_blocklist_domain ON blocklist(domain);
            CREATE INDEX IF NOT EXISTS idx_blocklist_category ON blocklist(category);
            CREATE INDEX IF NOT EXISTS idx_blocklist_expires ON blocklist(expires_at);
        """

        let createAllowlistSQL = """
            CREATE TABLE IF NOT EXISTS allowlist (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain TEXT NOT NULL UNIQUE,
                added_at TEXT NOT NULL,
                reason TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_allowlist_domain ON allowlist(domain);
        """

        let createStatsSQL = """
            CREATE TABLE IF NOT EXISTS block_stats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain TEXT NOT NULL,
                category TEXT NOT NULL,
                blocked_at TEXT NOT NULL,
                client_id TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_stats_blocked_at ON block_stats(blocked_at);
            CREATE INDEX IF NOT EXISTS idx_stats_category ON block_stats(category);
        """

        executeSQL(createBlocklistSQL)
        executeSQL(createAllowlistSQL)
        executeSQL(createStatsSQL)
    }

    private func executeSQL(_ sql: String) {
        var errorMessage: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            if let error = errorMessage {
                logger.error("SQL error: \(String(cString: error))")
                sqlite3_free(error)
            }
        }
    }

    // MARK: - Bloom Filter

    private func buildBloomFilter() {
        queue.async { [weak self] in
            guard let self = self else { return }

            var statement: OpaquePointer?
            let sql = "SELECT domain FROM blocklist"

            if sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK {
                while sqlite3_step(statement) == SQLITE_ROW {
                    if let domain = sqlite3_column_text(statement, 0) {
                        let domainStr = String(cString: domain)
                        self.addToBloomFilter(domainStr)
                    }
                }
            }
            sqlite3_finalize(statement)

            self.logger.info("Built bloom filter with \(self.bloomFilter.count) entries")
        }
    }

    private func addToBloomFilter(_ domain: String) {
        // Simple hash-based bloom filter simulation
        let hash1 = abs(domain.hashValue) % bloomFilterSize
        let hash2 = abs(domain.lowercased().hashValue) % bloomFilterSize
        bloomFilter.insert(hash1)
        bloomFilter.insert(hash2)
    }

    private func mightContain(_ domain: String) -> Bool {
        let hash1 = abs(domain.hashValue) % bloomFilterSize
        let hash2 = abs(domain.lowercased().hashValue) % bloomFilterSize
        return bloomFilter.contains(hash1) && bloomFilter.contains(hash2)
    }

    // MARK: - Blocklist Operations

    func shouldBlock(_ domain: String) -> (shouldBlock: Bool, rule: BlockRule?) {
        // Quick check with bloom filter
        if !mightContain(domain) && !mightContain(domain.lowercased()) {
            return (false, nil)
        }

        // Check allowlist first
        if isAllowlisted(domain) {
            return (false, nil)
        }

        // Check exact match
        if let rule = findExactMatch(domain) {
            incrementHitCount(for: domain)
            return (true, rule)
        }

        // Check wildcard matches (*.example.com)
        if let rule = findWildcardMatch(domain) {
            incrementHitCount(for: rule.domain)
            return (true, rule)
        }

        return (false, nil)
    }

    private func findExactMatch(_ domain: String) -> BlockRule? {
        var statement: OpaquePointer?
        let sql = """
            SELECT id, domain, rule_type, category, severity, source, added_at, expires_at
            FROM blocklist
            WHERE domain = ? OR domain = ?
            AND (expires_at IS NULL OR expires_at > datetime('now'))
            LIMIT 1
        """

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        let lowercased = domain.lowercased()
        sqlite3_bind_text(statement, 1, domain, -1, nil)
        sqlite3_bind_text(statement, 2, lowercased, -1, nil)

        var rule: BlockRule?
        if sqlite3_step(statement) == SQLITE_ROW {
            rule = parseBlockRule(statement)
        }

        sqlite3_finalize(statement)
        return rule
    }

    private func findWildcardMatch(_ domain: String) -> BlockRule? {
        // Check parent domains for wildcard rules
        let parts = domain.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var statement: OpaquePointer?
        let sql = """
            SELECT id, domain, rule_type, category, severity, source, added_at, expires_at
            FROM blocklist
            WHERE rule_type = 'wildcard'
            AND (expires_at IS NULL OR expires_at > datetime('now'))
        """

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        var rule: BlockRule?
        while sqlite3_step(statement) == SQLITE_ROW {
            if let foundRule = parseBlockRule(statement) {
                // Check if domain matches wildcard pattern
                let pattern = foundRule.domain.replacingOccurrences(of: "*.", with: "")
                if domain.lowercased().hasSuffix(pattern) || domain.lowercased() == pattern {
                    rule = foundRule
                    break
                }
            }
        }

        sqlite3_finalize(statement)
        return rule
    }

    private func parseBlockRule(_ statement: OpaquePointer?) -> BlockRule? {
        guard let statement = statement else { return nil }

        let id = sqlite3_column_int64(statement, 0)
        guard let domainPtr = sqlite3_column_text(statement, 1) else { return nil }
        let domain = String(cString: domainPtr)

        let ruleTypeStr = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? "exact"
        let categoryStr = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? "unknown"
        let severityStr = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? "medium"
        let source = sqlite3_column_text(statement, 5).map { String(cString: $0) }
        let addedAtStr = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
        let expiresAtStr = sqlite3_column_text(statement, 7).map { String(cString: $0) }

        let formatter = ISO8601DateFormatter()

        return BlockRule(
            id: id,
            domain: domain,
            ruleType: BlockRule.RuleType(rawValue: ruleTypeStr) ?? .exact,
            category: BlockRule.BlockCategory(rawValue: categoryStr) ?? .unknown,
            severity: SeverityLevel(rawValue: severityStr) ?? .medium,
            source: source,
            addedAt: formatter.date(from: addedAtStr) ?? Date(),
            expiresAt: expiresAtStr.flatMap { formatter.date(from: $0) }
        )
    }

    // MARK: - Add/Remove Rules

    func addRule(
        domain: String,
        ruleType: BlockRule.RuleType = .exact,
        category: BlockRule.BlockCategory,
        severity: SeverityLevel = .medium,
        source: String? = nil,
        expiresAt: Date? = nil
    ) -> Bool {
        var statement: OpaquePointer?
        let sql = """
            INSERT OR REPLACE INTO blocklist (domain, rule_type, category, severity, source, added_at, expires_at)
            VALUES (?, ?, ?, ?, ?, datetime('now'), ?)
        """

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, domain.lowercased(), -1, nil)
        sqlite3_bind_text(statement, 2, ruleType.rawValue, -1, nil)
        sqlite3_bind_text(statement, 3, category.rawValue, -1, nil)
        sqlite3_bind_text(statement, 4, severity.rawValue, -1, nil)
        sqlite3_bind_text(statement, 5, source, -1, nil)

        if let expires = expiresAt {
            let formatter = ISO8601DateFormatter()
            sqlite3_bind_text(statement, 6, formatter.string(from: expires), -1, nil)
        } else {
            sqlite3_bind_null(statement, 6)
        }

        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)

        if success {
            addToBloomFilter(domain)
        }

        return success
    }

    func removeRule(domain: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "DELETE FROM blocklist WHERE domain = ?"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, domain.lowercased(), -1, nil)

        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return success
    }

    func bulkAddRules(_ rules: [(domain: String, category: BlockRule.BlockCategory, source: String?)]) {
        executeSQL("BEGIN TRANSACTION")

        for rule in rules {
            _ = addRule(domain: rule.domain, category: rule.category, source: rule.source)
        }

        executeSQL("COMMIT")
        buildBloomFilter()
    }

    // MARK: - Allowlist Operations

    func isAllowlisted(_ domain: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM allowlist WHERE domain = ? LIMIT 1"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, domain.lowercased(), -1, nil)

        let exists = sqlite3_step(statement) == SQLITE_ROW
        sqlite3_finalize(statement)
        return exists
    }

    func addToAllowlist(_ domain: String, reason: String? = nil) -> Bool {
        var statement: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO allowlist (domain, added_at, reason) VALUES (?, datetime('now'), ?)"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, domain.lowercased(), -1, nil)
        sqlite3_bind_text(statement, 2, reason, -1, nil)

        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return success
    }

    func removeFromAllowlist(_ domain: String) -> Bool {
        var statement: OpaquePointer?
        let sql = "DELETE FROM allowlist WHERE domain = ?"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(statement, 1, domain.lowercased(), -1, nil)

        let success = sqlite3_step(statement) == SQLITE_DONE
        sqlite3_finalize(statement)
        return success
    }

    // MARK: - Statistics

    private func incrementHitCount(for domain: String) {
        executeSQL("UPDATE blocklist SET hit_count = hit_count + 1, last_hit = datetime('now') WHERE domain = '\(domain)'")
    }

    func recordBlock(domain: String, category: BlockRule.BlockCategory, clientId: String? = nil) {
        var statement: OpaquePointer?
        let sql = "INSERT INTO block_stats (domain, category, blocked_at, client_id) VALUES (?, ?, datetime('now'), ?)"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return
        }

        sqlite3_bind_text(statement, 1, domain, -1, nil)
        sqlite3_bind_text(statement, 2, category.rawValue, -1, nil)
        sqlite3_bind_text(statement, 3, clientId, -1, nil)

        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    func getBlockStats() -> [String: Int] {
        var stats: [String: Int] = [:]
        var statement: OpaquePointer?
        let sql = "SELECT category, COUNT(*) FROM block_stats GROUP BY category"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return stats
        }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let categoryPtr = sqlite3_column_text(statement, 0) {
                let category = String(cString: categoryPtr)
                let count = Int(sqlite3_column_int(statement, 1))
                stats[category] = count
            }
        }

        sqlite3_finalize(statement)
        return stats
    }

    func getTotalBlocked() -> Int {
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM block_stats"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }

        sqlite3_finalize(statement)
        return count
    }

    func getRuleCount() -> Int {
        var statement: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM blocklist"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        var count = 0
        if sqlite3_step(statement) == SQLITE_ROW {
            count = Int(sqlite3_column_int(statement, 0))
        }

        sqlite3_finalize(statement)
        return count
    }

    // MARK: - Cleanup

    func cleanExpiredRules() {
        executeSQL("DELETE FROM blocklist WHERE expires_at IS NOT NULL AND expires_at < datetime('now')")
        buildBloomFilter()
    }

    func clearAllRules() {
        executeSQL("DELETE FROM blocklist")
        executeSQL("DELETE FROM allowlist")
        executeSQL("DELETE FROM block_stats")
        bloomFilter.removeAll()
    }
}
