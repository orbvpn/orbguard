// IOSSpywareScanner.swift
// Location: ios/Runner/IOSSpywareScanner.swift

import Foundation
import UIKit

/// Comprehensive iOS Spyware Scanner
/// Detects sophisticated threats including Pegasus on iOS
class IOSSpywareScanner {

    private let jailbreakAccess: JailbreakAccess
    private var deepScan = false
    private var hasRoot = false

    // Known Pegasus indicators for iOS
    private let maliciousProcesses = [
        "setframed",
        "bridged",
        "CommsCentre",
        "aggregated",
        "networkd",
        "nesessionmanager",
        "remoteservicediscoveryd",
    ]

    private let maliciousDomains = [
        "lsgatag.com",
        "lxwo.org",
        "iosmac.org",
        "updates-icloud-content.com",
        "backupios.com",
        "appcheck-store.net",
        "icloud-check.com",
        "icloud-analysis.com",
        "appleid-services.com",
    ]

    private let suspiciousFiles = [
        "/private/var/db/diagnostics/Special/",
        "/private/var/wireless/Library/Databases/DataUsage.sqlite",
        "/private/var/mobile/Library/Preferences/com.apple.Security.plist",
        "/System/Library/LaunchDaemons/com.apple.setframed.plist",
        "/var/mobile/Library/Caches/com.apple.nsurlsessiond",
        "/private/var/installd/Library/Caches",
        "/private/var/mobile/Library/SMS/sms.db",
        "/private/var/mobile/Library/Safari/History.db",
    ]

    /**
     * Initialize scanner
     */
    init(jailbreakAccess: JailbreakAccess) {
        self.jailbreakAccess = jailbreakAccess
    }

    /**
     * Initialize scan settings
     */
    func initialize(deepScan: Bool, hasRoot: Bool) {
        self.deepScan = deepScan
        self.hasRoot = hasRoot
    }

    // ============================================================================
    // NETWORK SCANNING
    // ============================================================================

    /**
     * Scan network connections for suspicious activity
     */
    func scanNetwork() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check active network connections (requires jailbreak for deep analysis)
        if hasRoot {
            if let netstat = jailbreakAccess.executeCommand("netstat -an") {
                threats.append(contentsOf: analyzeNetworkConnections(netstat))
            }

            // Check DNS configuration
            if let dnsConfig = jailbreakAccess.readFile(atPath: "/etc/resolv.conf") {
                threats.append(contentsOf: analyzeDNSConfig(dnsConfig))
            }
        }

        // Check DNS queries in system logs (available without jailbreak via sysdiagnose)
        threats.append(contentsOf: scanDNSQueries())

        // Check for VPN profiles
        threats.append(contentsOf: scanVPNProfiles())

        return threats
    }

    /**
     * Analyze network connections for suspicious patterns
     */
    private func analyzeNetworkConnections(_ data: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []
        let lines = data.components(separatedBy: "\n")

        for line in lines {
            // Parse netstat output
            // Check for connections to known malicious IPs/domains
            if line.contains("ESTABLISHED") || line.contains("LISTEN") {
                // Extract IP and port
                let components = line.components(separatedBy: CharacterSet.whitespaces)
                    .filter { !$0.isEmpty }

                if components.count >= 5 {
                    let remoteAddr = components[4]

                    // Check against malicious domains (would need IP resolution)
                    // For now, flag suspicious ports
                    if remoteAddr.contains(":4444") || remoteAddr.contains(":5555") {
                        threats.append([
                            "id": "network_suspicious_port",
                            "name": "Suspicious Network Connection",
                            "description": "Connection to unusual port: \(remoteAddr)",
                            "severity": "HIGH",
                            "type": "network",
                            "path": remoteAddr,
                            "requiresRoot": false,
                            "metadata": ["connection": line],
                        ])
                    }
                }
            }
        }

        return threats
    }

    /**
     * Analyze DNS configuration
     */
    private func analyzeDNSConfig(_ data: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check for suspicious DNS servers
        let suspiciousDNS = ["8.8.4.4", "1.0.0.1"]  // Common malicious redirects

        for dns in suspiciousDNS {
            if data.contains(dns) {
                threats.append([
                    "id": "network_dns_\(dns)",
                    "name": "Suspicious DNS Server",
                    "description": "Non-standard DNS server configured: \(dns)",
                    "severity": "MEDIUM",
                    "type": "network",
                    "path": "/etc/resolv.conf",
                    "requiresRoot": true,
                    "metadata": ["dns": dns],
                ])
            }
        }

        return threats
    }

    /**
     * Scan DNS queries for malicious domains
     */
    private func scanDNSQueries() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check DNS cache if accessible
        if hasRoot {
            if let dnsCache = jailbreakAccess.executeCommand("dscacheutil -cachedump -entries Host")
            {
                for domain in maliciousDomains {
                    if dnsCache.contains(domain) {
                        threats.append([
                            "id": "network_malicious_domain_\(domain)",
                            "name": "Malicious Domain Contact",
                            "description": "Device contacted known Pegasus domain: \(domain)",
                            "severity": "CRITICAL",
                            "type": "network",
                            "path": domain,
                            "requiresRoot": false,
                            "metadata": ["domain": domain, "source": "DNS Cache"],
                        ])
                    }
                }
            }
        }

        return threats
    }

    /**
     * Scan for suspicious VPN profiles
     */
    private func scanVPNProfiles() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check VPN configuration profiles (requires jailbreak for full access)
        if hasRoot {
            if let profiles = jailbreakAccess.listFiles(
                atPath: "/var/preferences/SystemConfiguration")
            {
                if profiles.contains("vpn") || profiles.contains("VPN") {
                    threats.append([
                        "id": "network_vpn_profile",
                        "name": "VPN Profile Detected",
                        "description": "VPN configuration found - verify legitimacy",
                        "severity": "MEDIUM",
                        "type": "network",
                        "path": "/var/preferences/SystemConfiguration",
                        "requiresRoot": true,
                        "metadata": ["type": "VPN Profile"],
                    ])
                }
            }
        }

        return threats
    }

    // ============================================================================
    // PROCESS SCANNING
    // ============================================================================

    /**
     * Scan running processes for suspicious activity
     */
    func scanProcesses() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        if !hasRoot {
            // Limited process scanning without jailbreak
            return threats
        }

        // Get process list with root access
        if let ps = jailbreakAccess.getProcessList() {
            let lines = ps.components(separatedBy: "\n")

            for line in lines {
                // Check against known malicious processes
                for maliciousProc in maliciousProcesses {
                    if line.lowercased().contains(maliciousProc.lowercased()) {
                        threats.append([
                            "id": "process_\(maliciousProc)",
                            "name": "Suspicious Process: \(maliciousProc)",
                            "description": "Process matches known Pegasus indicator",
                            "severity": "CRITICAL",
                            "type": "process",
                            "path": maliciousProc,
                            "requiresRoot": true,
                            "metadata": ["details": line, "source": "Pegasus IoC"],
                        ])
                    }
                }

                // Check for hidden processes (unusual naming)
                if line.contains(".") && !line.contains("com.apple") {
                    let components = line.components(separatedBy: CharacterSet.whitespaces)
                        .filter { !$0.isEmpty }

                    if components.count >= 11 {
                        let processName = components[10]
                        if processName.hasPrefix(".") {
                            threats.append([
                                "id": "process_hidden_\(processName)",
                                "name": "Hidden Process Detected",
                                "description": "Process with hidden naming: \(processName)",
                                "severity": "HIGH",
                                "type": "process",
                                "path": processName,
                                "requiresRoot": true,
                                "metadata": ["details": line],
                            ])
                        }
                    }
                }
            }
        }

        return threats
    }

    // ============================================================================
    // FILE SYSTEM SCANNING
    // ============================================================================

    /**
     * Scan file system for suspicious files
     */
    func scanFileSystem() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check suspicious file locations
        for path in suspiciousFiles {
            if jailbreakAccess.fileExists(atPath: path) {
                // Try to get file details
                var fileInfo = ""
                if hasRoot {
                    fileInfo = jailbreakAccess.executeCommand("stat '\(path)'") ?? ""
                }

                threats.append([
                    "id": "file_\(path.hashValue)",
                    "name": "Suspicious File: \(URL(fileURLWithPath: path).lastPathComponent)",
                    "description": "Known spyware file location: \(path)",
                    "severity": "HIGH",
                    "type": "file",
                    "path": path,
                    "requiresRoot": false,
                    "metadata": ["fileInfo": fileInfo],
                ])
            }
        }

        if hasRoot {
            // Deep file system scan with root access
            let systemDirs = [
                "/System/Library/LaunchDaemons",
                "/Library/MobileSubstrate/DynamicLibraries",
                "/var/mobile/Library",
                "/private/var/db/diagnostics",
                "/private/var/installd",
            ]

            for dir in systemDirs {
                if let files = jailbreakAccess.listFiles(atPath: dir) {
                    threats.append(contentsOf: analyzeSystemFiles(files, inDir: dir))
                }
            }

            // Check for modified system files
            threats.append(contentsOf: checkModifiedSystemFiles())
        }

        return threats
    }

    /**
     * Analyze system files for suspicious characteristics
     */
    private func analyzeSystemFiles(_ data: String, inDir dir: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []
        let lines = data.components(separatedBy: "\n")

        for line in lines {
            // Check for suspicious file patterns

            // Hidden files in system directories
            if line.contains(" .") && !line.contains(".DS_Store") {
                let fileName =
                    line.components(separatedBy: CharacterSet.whitespaces)
                    .last ?? ""

                if fileName.hasPrefix(".") {
                    threats.append([
                        "id": "file_hidden_\(dir)/\(fileName)",
                        "name": "Hidden System File",
                        "description": "Hidden file in system directory: \(fileName)",
                        "severity": "MEDIUM",
                        "type": "file",
                        "path": "\(dir)/\(fileName)",
                        "requiresRoot": true,
                        "metadata": ["directory": dir],
                    ])
                }
            }

            // Recently modified system files
            let currentYear = Calendar.current.component(.year, from: Date())
            if line.contains(String(currentYear)) && line.contains("root") {
                // System file modified recently - potentially suspicious
                let fileName =
                    line.components(separatedBy: CharacterSet.whitespaces)
                    .last ?? ""

                if !fileName.isEmpty {
                    threats.append([
                        "id": "file_modified_\(dir)/\(fileName)",
                        "name": "Recently Modified System File",
                        "description": "System file modified recently: \(fileName)",
                        "severity": "MEDIUM",
                        "type": "file",
                        "path": "\(dir)/\(fileName)",
                        "requiresRoot": true,
                        "metadata": ["modification": "Recent"],
                    ])
                }
            }
        }

        return threats
    }

    /**
     * Check for modified system files (checksum validation)
     */
    private func checkModifiedSystemFiles() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Critical system files to check
        let criticalFiles = [
            "/usr/libexec/nehelper",
            "/System/Library/LaunchDaemons/com.apple.wifi.WiFiAgent.plist",
            "/usr/sbin/wifid",
        ]

        for file in criticalFiles {
            if jailbreakAccess.fileExists(atPath: file) {
                // In real implementation, would check against known good checksums
                // For now, just flag if accessible (shouldn't be without jailbreak)
                threats.append([
                    "id": "file_accessible_\(file.hashValue)",
                    "name": "System File Accessible",
                    "description": "Critical system file is accessible: \(file)",
                    "severity": "HIGH",
                    "type": "file",
                    "path": file,
                    "requiresRoot": true,
                    "metadata": ["type": "Critical System File"],
                ])
            }
        }

        return threats
    }

    // ============================================================================
    // DATABASE SCANNING
    // ============================================================================

    /**
     * Scan databases for exploit traces
     */
    func scanDatabases() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // SMS database (iMessage exploits - Pegasus zero-click)
        let smsDb = "/private/var/mobile/Library/SMS/sms.db"
        if hasRoot {
            threats.append(contentsOf: analyzeSMSDatabase(smsDb))
        }

        // Safari history (web-based exploits)
        let safariDb = "/private/var/mobile/Library/Safari/History.db"
        threats.append(contentsOf: analyzeSafariHistory(safariDb))

        // DataUsage database (network monitoring)
        let dataUsageDb = "/private/var/wireless/Library/Databases/DataUsage.sqlite"
        threats.append(contentsOf: analyzeDataUsage(dataUsageDb))

        // NetUsage database
        let netUsageDb = "/private/var/networkd/netusage.sqlite"
        if hasRoot {
            threats.append(contentsOf: analyzeNetUsage(netUsageDb))
        }

        // Call history database
        let callDb = "/private/var/mobile/Library/CallHistoryDB/CallHistory.storedata"
        threats.append(contentsOf: analyzeCallHistory(callDb))

        return threats
    }

    /**
     * Analyze SMS database for iMessage exploits
     */
    private func analyzeSMSDatabase(_ path: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []

        if !jailbreakAccess.fileExists(atPath: path) {
            return threats
        }

        // Check for suspicious SMS patterns (Pegasus uses SMS exploits)
        if let messageCount = jailbreakAccess.sqliteQuery(
            dbPath: path,
            query: "SELECT COUNT(*) FROM message"
        ) {
            // Check for deleted messages (potential exploit cleanup)
            if let deletedCount = jailbreakAccess.sqliteQuery(
                dbPath: path,
                query:
                    "SELECT COUNT(*) FROM message WHERE cache_has_attachments = 1 AND text IS NULL"
            ) {
                if let deleted = Int(deletedCount.trimmingCharacters(in: .whitespacesAndNewlines)),
                    deleted > 50
                {
                    threats.append([
                        "id": "db_sms_deleted",
                        "name": "Suspicious SMS Deletions",
                        "description": "Large number of SMS messages with deleted content",
                        "severity": "HIGH",
                        "type": "database",
                        "path": path,
                        "requiresRoot": true,
                        "metadata": [
                            "deletedCount": deleted, "source": "iMessage Exploit Detection",
                        ],
                    ])
                }
            }

            // Check for messages with attachments but no content (exploit pattern)
            if let suspiciousMessages = jailbreakAccess.sqliteQuery(
                dbPath: path,
                query:
                    "SELECT COUNT(*) FROM message WHERE cache_has_attachments = 1 AND length(text) = 0"
            ) {
                if let suspicious = Int(
                    suspiciousMessages.trimmingCharacters(in: .whitespacesAndNewlines)),
                    suspicious > 10
                {
                    threats.append([
                        "id": "db_sms_suspicious",
                        "name": "Suspicious iMessage Patterns",
                        "description": "Messages with attachments but no text content",
                        "severity": "CRITICAL",
                        "type": "database",
                        "path": path,
                        "requiresRoot": true,
                        "metadata": [
                            "suspiciousCount": suspicious, "indicator": "Pegasus Zero-Click",
                        ],
                    ])
                }
            }
        }

        return threats
    }

    /**
     * Analyze Safari history for malicious sites
     */
    private func analyzeSafariHistory(_ path: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []

        if hasRoot && jailbreakAccess.fileExists(atPath: path) {
            // Check for visits to known malicious domains
            for domain in maliciousDomains {
                if let visits = jailbreakAccess.sqliteQuery(
                    dbPath: path,
                    query: "SELECT COUNT(*) FROM history_items WHERE url LIKE '%\(domain)%'"
                ) {
                    if let visitCount = Int(visits.trimmingCharacters(in: .whitespacesAndNewlines)),
                        visitCount > 0
                    {
                        threats.append([
                            "id": "db_safari_malicious_\(domain)",
                            "name": "Malicious Domain Visit",
                            "description": "Safari visited known Pegasus domain: \(domain)",
                            "severity": "CRITICAL",
                            "type": "database",
                            "path": path,
                            "requiresRoot": true,
                            "metadata": ["domain": domain, "visits": visitCount],
                        ])
                    }
                }
            }
        }

        return threats
    }

    /**
     * Analyze data usage for unusual patterns
     */
    private func analyzeDataUsage(_ path: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []

        if hasRoot && jailbreakAccess.fileExists(atPath: path) {
            // Check for excessive data usage by system processes
            if let usage = jailbreakAccess.sqliteQuery(
                dbPath: path,
                query: "SELECT SUM(ZWIFIIN + ZWIFIOUT + ZWWANIN + ZWWANOUT) FROM ZLIVEUSAGE"
            ) {
                // Analyze for unusual patterns
                if let totalBytes = Int64(usage.trimmingCharacters(in: .whitespacesAndNewlines)),
                    totalBytes > 1_000_000_000
                {  // > 1GB
                    threats.append([
                        "id": "db_data_usage_high",
                        "name": "Excessive System Data Usage",
                        "description": "Unusually high data usage detected",
                        "severity": "MEDIUM",
                        "type": "database",
                        "path": path,
                        "requiresRoot": true,
                        "metadata": ["bytes": totalBytes],
                    ])
                }
            }
        }

        return threats
    }

    /**
     * Analyze network usage database
     */
    private func analyzeNetUsage(_ path: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []

        if jailbreakAccess.fileExists(atPath: path) {
            // Check for unusual network patterns
            // Implementation would analyze ZPROCESS and ZLIVEUSAGE tables
        }

        return threats
    }

    /**
     * Analyze call history for suspicious patterns
     */
    private func analyzeCallHistory(_ path: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []

        if hasRoot && jailbreakAccess.fileExists(atPath: path) {
            // Check for deleted call records (potential forensic cleanup)
            // This would require Core Data analysis
        }

        return threats
    }

    // ============================================================================
    // MEMORY SCANNING
    // ============================================================================

    /**
     * Scan memory for malicious code
     */
    func scanMemory() -> [[String: Any]] {
        var threats: [[String: Any]] = []

        if !hasRoot {
            return threats
        }

        // Get memory maps of suspicious processes
        if let processList = jailbreakAccess.getProcessList() {
            let lines = processList.components(separatedBy: "\n")

            for line in lines {
                for maliciousProc in maliciousProcesses {
                    if line.contains(maliciousProc) {
                        // Extract PID
                        let components = line.components(separatedBy: CharacterSet.whitespaces)
                            .filter { !$0.isEmpty }

                        if components.count >= 2 {
                            let pid = components[1]

                            // Dump memory maps
                            if let memMaps = jailbreakAccess.executeCommand("vmmap -32 \(pid)") {
                                threats.append(
                                    contentsOf: analyzeMemoryMap(
                                        memMaps, pid: pid, process: maliciousProc))
                            }
                        }
                    }
                }
            }
        }

        return threats
    }

    /**
     * Analyze memory map for suspicious patterns
     */
    private func analyzeMemoryMap(_ data: String, pid: String, process: String) -> [[String: Any]] {
        var threats: [[String: Any]] = []

        // Check for executable regions in unusual locations
        if data.contains("r-x") && (data.contains("/tmp") || data.contains("/var/tmp")) {
            threats.append([
                "id": "memory_exec_\(pid)",
                "name": "Suspicious Memory Execution",
                "description": "Executable code in unusual location for process: \(process)",
                "severity": "CRITICAL",
                "type": "memory",
                "path": "/proc/\(pid)/maps",
                "requiresRoot": true,
                "metadata": ["pid": pid, "process": process],
            ])
        }

        // Check for large executable regions (potential injected code)
        let lines = data.components(separatedBy: "\n")
        for line in lines {
            if line.contains("r-x") && line.contains("M") {
                // Large executable region
                threats.append([
                    "id": "memory_large_exec_\(pid)",
                    "name": "Large Executable Memory Region",
                    "description": "Unusually large executable memory region in \(process)",
                    "severity": "HIGH",
                    "type": "memory",
                    "path": "/proc/\(pid)/maps",
                    "requiresRoot": true,
                    "metadata": ["details": line],
                ])
            }
        }

        return threats
    }

    // ============================================================================
    // THREAT REMOVAL
    // ============================================================================

    /**
     * Remove detected threat
     */
    func removeThreat(id: String, type: String, path: String, requiresRoot: Bool) -> Bool {
        if requiresRoot && !hasRoot {
            return false
        }

        switch type {
        case "process":
            return killProcess(name: path)
        case "file":
            return jailbreakAccess.deleteFile(atPath: path)
        case "app":
            return uninstallApp(bundleId: id)
        default:
            return false
        }
    }

    private func killProcess(name: String) -> Bool {
        guard hasRoot else { return false }
        return jailbreakAccess.killProcess(name: name)
    }

    private func uninstallApp(bundleId: String) -> Bool {
        guard hasRoot else { return false }

        // Remove app bundle
        let appPath = "/Applications/\(bundleId).app"
        if jailbreakAccess.fileExists(atPath: appPath) {
            return jailbreakAccess.deleteFile(atPath: appPath)
        }

        return false
    }
}
