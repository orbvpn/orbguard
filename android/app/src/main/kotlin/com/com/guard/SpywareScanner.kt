// SpywareScanner.kt
// Location: android/app/src/main/kotlin/com/orb/guard/SpywareScanner.kt

package com.orb.guard

import android.app.ActivityManager
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import kotlinx.coroutines.*

/**
 * Comprehensive spyware scanner that detects threats including Pegasus
 * Uses multiple detection methods and adapts to available access levels
 */
class SpywareScanner(
    private val context: Context,
    private val elevatedAccess: ElevatedAccessManager
) {
    private var deepScan = false
    private var hasElevatedAccess = false
    
    // Known malicious indicators (Pegasus-specific)
    private val maliciousPackages = listOf(
        "com.network.android",
        "com.system.framework",
        "com.google.android.update",
        "com.android.battery",
        "com.system.service",
        "com.android.providers.setting"
    )
    
    private val maliciousDomains = listOf(
        "lsgatag.com",
        "lxwo.org",
        "cloudatlasinc.com",
        "lighthouseresearch.com",
        "mynetsec.net",
        "iosmac.org",
        "updates-icloud-content.com",
        "backupios.com",
        "appcheck-store.net"
    )
    
    private val suspiciousFiles = listOf(
        "/system/xbin/daemonsu",
        "/system/bin/.ext",
        "/data/local/tmp/.pegasus",
        "/data/local/tmp/.socket",
        "/data/data/com.android.providers.telephony/databases/mmssms.db-journal",
        "/system/app/SystemUpdate",
        "/system/priv-app/SystemUpdate"
    )
    
    private val suspiciousProcesses = listOf(
        "daemonsu",
        "su",
        ".pegasus",
        "systemd-update",
        "networkd",
        "com.network.android",
        "com.system.framework"
    )
    
    /**
     * Initialize scanner with scan settings
     */
    fun initialize(deepScan: Boolean, hasElevated: Boolean) {
        this.deepScan = deepScan
        this.hasElevatedAccess = hasElevated
    }
    
    /**
     * Scan network connections for suspicious activity
     */
    fun scanNetwork(): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        
        try {
            // Standard network check (no special permissions needed)
            val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val networks = connectivityManager.allNetworks
            
            for (network in networks) {
                val capabilities = connectivityManager.getNetworkCapabilities(network)
                
                if (capabilities != null) {
                    // Check for VPN (could be malicious proxy)
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) {
                        threats.add(mapOf(
                            "id" to "network_vpn_${System.currentTimeMillis()}",
                            "name" to "Active VPN Connection Detected",
                            "description" to "VPN detected - verify if legitimate",
                            "severity" to "MEDIUM",
                            "type" to "network",
                            "path" to "VPN",
                            "requiresRoot" to false,
                            "metadata" to mapOf(
                                "networkId" to network.toString(),
                                "timestamp" to System.currentTimeMillis()
                            )
                        ))
                    }
                    
                    // Check network capabilities for suspicious patterns
                    if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)) {
                        threats.add(mapOf(
                            "id" to "network_unvalidated_${System.currentTimeMillis()}",
                            "name" to "Unvalidated Network Connection",
                            "description" to "Network connection not validated by system",
                            "severity" to "LOW",
                            "type" to "network",
                            "path" to network.toString(),
                            "requiresRoot" to false,
                            "metadata" to emptyMap<String, Any>()
                        ))
                    }
                }
            }
            
            // Elevated network analysis
            if (hasElevatedAccess) {
                // Get network connections using elevated access
                val netstat = elevatedAccess.getNetstat()
                netstat?.let {
                    val suspiciousConns = analyzeNetworkConnections(it)
                    threats.addAll(suspiciousConns)
                }
                
                // Check routing table
                val routeTable = elevatedAccess.executeCommand("cat /proc/net/route")
                routeTable?.let {
                    // Analyze for suspicious routes (e.g., traffic redirection)
                    if (it.contains("0.0.0.0") && !it.contains("wlan") && !it.contains("eth")) {
                        threats.add(mapOf(
                            "id" to "network_suspicious_route",
                            "name" to "Suspicious Network Route",
                            "description" to "Unusual routing configuration detected",
                            "severity" to "HIGH",
                            "type" to "network",
                            "path" to "/proc/net/route",
                            "requiresRoot" to true,
                            "metadata" to mapOf("details" to it.take(200))
                        ))
                    }
                }
                
                // Check iptables rules
                val iptables = elevatedAccess.executeCommand("iptables -L -n")
                iptables?.let {
                    if (it.contains("REDIRECT") || it.contains("MASQUERADE")) {
                        threats.add(mapOf(
                            "id" to "network_iptables_redirect",
                            "name" to "Network Traffic Redirection",
                            "description" to "iptables rules redirecting traffic",
                            "severity" to "CRITICAL",
                            "type" to "network",
                            "path" to "iptables",
                            "requiresRoot" to true,
                            "metadata" to mapOf("rules" to it.take(300))
                        ))
                    }
                }
            }
            
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return threats
    }
    
    /**
     * Scan running processes for suspicious activity
     */
    fun scanProcesses(): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        
        try {
            // Standard process check (limited without elevated access)
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningApps = activityManager.runningAppProcesses ?: emptyList()
            
            for (app in runningApps) {
                // Check against known malicious package names
                if (maliciousPackages.any { app.processName.contains(it) }) {
                    threats.add(mapOf(
                        "id" to app.processName,
                        "name" to "Suspicious Process: ${app.processName}",
                        "description" to "Process matches known spyware pattern",
                        "severity" to "CRITICAL",
                        "type" to "process",
                        "path" to app.processName,
                        "requiresRoot" to false,
                        "metadata" to mapOf(
                            "pid" to app.pid,
                            "uid" to app.uid,
                            "importance" to app.importance
                        )
                    ))
                }
                
                // Check for hidden processes (unusual naming)
                if (app.processName.startsWith(".") || app.processName.contains("..")) {
                    threats.add(mapOf(
                        "id" to "process_hidden_${app.pid}",
                        "name" to "Hidden Process Detected",
                        "description" to "Process with hidden naming: ${app.processName}",
                        "severity" to "HIGH",
                        "type" to "process",
                        "path" to app.processName,
                        "requiresRoot" to false,
                        "metadata" to mapOf("pid" to app.pid)
                    ))
                }
            }
            
            // Elevated process analysis
            if (hasElevatedAccess) {
                val processList = elevatedAccess.getProcessList()
                processList?.let {
                    val deepThreats = analyzeProcessTree(it)
                    threats.addAll(deepThreats)
                }
                
                // Check for hidden processes not visible to standard APIs
                val hiddenProcs = elevatedAccess.executeCommand("ps -A -o pid,ppid,name,cmd")
                hiddenProcs?.let {
                    val lines = it.split("\n")
                    for (line in lines) {
                        for (suspiciousProc in suspiciousProcesses) {
                            if (line.lowercase().contains(suspiciousProc.lowercase())) {
                                threats.add(mapOf(
                                    "id" to "process_elevated_$suspiciousProc",
                                    "name" to "Suspicious System Process",
                                    "description" to "Process detected via elevated access: $suspiciousProc",
                                    "severity" to "CRITICAL",
                                    "type" to "process",
                                    "path" to suspiciousProc,
                                    "requiresRoot" to true,
                                    "metadata" to mapOf("details" to line)
                                ))
                            }
                        }
                    }
                }
            }
            
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return threats
    }
    
    /**
     * Scan file system for suspicious files
     */
    fun scanFileSystem(): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        
        if (!hasElevatedAccess) {
            // Without elevated access, we can only check limited locations
            return threats
        }
        
        try {
            // Check suspicious file locations
            for (suspiciousFile in suspiciousFiles) {
                if (elevatedAccess.fileExists(suspiciousFile)) {
                    val fileInfo = elevatedAccess.getFileInfo(suspiciousFile)
                    
                    threats.add(mapOf(
                        "id" to suspiciousFile,
                        "name" to "Suspicious File: ${suspiciousFile.split("/").last()}",
                        "description" to "Known spyware file location: $suspiciousFile",
                        "severity" to "HIGH",
                        "type" to "file",
                        "path" to suspiciousFile,
                        "requiresRoot" to true,
                        "metadata" to mapOf("fileInfo" to (fileInfo ?: ""))
                    ))
                }
            }
            
            // Scan critical system directories
            val systemDirs = listOf(
                "/system/app",
                "/system/priv-app",
                "/data/app",
                "/data/local/tmp"
            )
            
            for (dir in systemDirs) {
                val files = elevatedAccess.listFiles(dir)
                files?.let {
                    val fileThreats = analyzeSystemFiles(it, dir)
                    threats.addAll(fileThreats)
                }
            }
            
            // Check for hidden files in suspicious locations
            val hiddenFiles = elevatedAccess.findFiles("/data/local/tmp", ".*")
            hiddenFiles?.let {
                val lines = it.split("\n")
                for (line in lines) {
                    if (line.isNotBlank() && line.startsWith("/")) {
                        threats.add(mapOf(
                            "id" to "file_hidden_${line.hashCode()}",
                            "name" to "Hidden File in Temp Directory",
                            "description" to "Hidden file: $line",
                            "severity" to "MEDIUM",
                            "type" to "file",
                            "path" to line,
                            "requiresRoot" to true,
                            "metadata" to emptyMap<String, Any>()
                        ))
                    }
                }
            }
            
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return threats
    }
    
    /**
     * Scan databases for exploit traces
     */
    fun scanDatabases(): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        
        if (!hasElevatedAccess) {
            return threats
        }
        
        try {
            // Check SMS database for Pegasus SMS exploits
            val smsDb = "/data/data/com.android.providers.telephony/databases/mmssms.db"
            if (elevatedAccess.fileExists(smsDb)) {
                // Check for suspicious SMS patterns
                val smsCount = elevatedAccess.sqliteQuery(smsDb, "SELECT COUNT(*) FROM sms")
                
                // Check for deleted SMS (potential exploit cleanup)
                val deletedSms = elevatedAccess.sqliteQuery(
                    smsDb,
                    "SELECT COUNT(*) FROM sms WHERE type=3"
                )
                
                if (deletedSms != null && deletedSms.toIntOrNull() ?: 0 > 100) {
                    threats.add(mapOf(
                        "id" to "db_sms_deleted",
                        "name" to "Suspicious SMS Deletions",
                        "description" to "Large number of deleted SMS messages",
                        "severity" to "MEDIUM",
                        "type" to "database",
                        "path" to smsDb,
                        "requiresRoot" to true,
                        "metadata" to mapOf("deletedCount" to deletedSms)
                    ))
                }
            }
            
            // Check package manager database
            val packagesXml = elevatedAccess.readSystemFile("/data/system/packages.xml")
            packagesXml?.let {
                // Check for suspicious package installations
                for (maliciousPkg in maliciousPackages) {
                    if (it.contains(maliciousPkg)) {
                        threats.add(mapOf(
                            "id" to "db_package_$maliciousPkg",
                            "name" to "Malicious Package Installation",
                            "description" to "Package found in system database: $maliciousPkg",
                            "severity" to "CRITICAL",
                            "type" to "database",
                            "path" to "/data/system/packages.xml",
                            "requiresRoot" to true,
                            "metadata" to mapOf("package" to maliciousPkg)
                        ))
                    }
                }
            }
            
            // Check for modified system settings
            val settings = elevatedAccess.sqliteQuery(
                "/data/data/com.android.providers.settings/databases/settings.db",
                "SELECT * FROM secure WHERE name LIKE '%adb%' OR name LIKE '%debug%'"
            )
            settings?.let {
                if (it.contains("1") && !it.contains("0")) {
                    threats.add(mapOf(
                        "id" to "db_settings_debug",
                        "name" to "Debug Settings Enabled",
                        "description" to "ADB or debug settings detected in system database",
                        "severity" to "MEDIUM",
                        "type" to "database",
                        "path" to "settings.db",
                        "requiresRoot" to true,
                        "metadata" to mapOf("settings" to it.take(200))
                    ))
                }
            }
            
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return threats
    }
    
    /**
     * Scan memory for malicious code
     */
    fun scanMemory(): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        
        if (!hasElevatedAccess) {
            return threats
        }
        
        try {
            // Get memory maps of suspicious processes
            val processList = elevatedAccess.getProcessList()
            processList?.let {
                val lines = it.split("\n")
                for (line in lines) {
                    for (maliciousPkg in maliciousPackages) {
                        if (line.contains(maliciousPkg)) {
                            // Extract PID
                            val pid = extractPid(line)
                            pid?.let { processId ->
                                // Dump memory maps
                                val memMaps = elevatedAccess.readSystemFile("/proc/$processId/maps")
                                memMaps?.let { maps ->
                                    // Check for executable regions in unusual locations
                                    if (maps.contains("/data/local/tmp") && maps.contains("x")) {
                                        threats.add(mapOf(
                                            "id" to "memory_exec_$processId",
                                            "name" to "Suspicious Memory Execution",
                                            "description" to "Executable code in unusual location for PID: $processId",
                                            "severity" to "CRITICAL",
                                            "type" to "memory",
                                            "path" to "/proc/$processId/maps",
                                            "requiresRoot" to true,
                                            "metadata" to mapOf(
                                                "pid" to processId,
                                                "process" to maliciousPkg
                                            )
                                        ))
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return threats
    }
    
    /**
     * Remove detected threat
     */
    fun removeThreat(id: String, type: String, path: String, requiresRoot: Boolean): Boolean {
        if (requiresRoot && !hasElevatedAccess) {
            return false
        }
        
        return when (type) {
            "process" -> killProcess(id)
            "file" -> deleteFile(path)
            "package" -> uninstallPackage(id)
            else -> false
        }
    }
    
    // ============================================================================
    // HELPER METHODS
    // ============================================================================
    
    private fun analyzeNetworkConnections(data: String): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        val lines = data.split("\n")
        
        for (line in lines) {
            // Parse /proc/net/tcp format
            // Check for connections to known malicious IPs
            // Format: sl local_address rem_address st ...
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size >= 3 && parts[0] != "sl") {
                val remoteAddr = parts[2]
                // Check if remote address is suspicious
                // (In real implementation, check against IoC database)
            }
        }
        
        return threats
    }
    
    private fun analyzeProcessTree(data: String): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        val lines = data.split("\n")
        
        for (line in lines) {
            // Check for suspicious process names
            for (suspiciousProc in suspiciousProcesses) {
                if (line.lowercase().contains(suspiciousProc.lowercase())) {
                    threats.add(mapOf(
                        "id" to suspiciousProc,
                        "name" to "Suspicious System Process: $suspiciousProc",
                        "description" to "Process detected via elevated access",
                        "severity" to "CRITICAL",
                        "type" to "process",
                        "path" to suspiciousProc,
                        "requiresRoot" to true,
                        "metadata" to mapOf("details" to line)
                    ))
                }
            }
        }
        
        return threats
    }
    
    private fun analyzeSystemFiles(data: String, dir: String): List<Map<String, Any>> {
        val threats = mutableListOf<Map<String, Any>>()
        val lines = data.split("\n")
        
        for (line in lines) {
            // Check for suspicious file characteristics
            // - Unusual permissions (777, etc.)
            // - Hidden files (starting with .)
            // - Recently modified system files
            
            if (line.contains("rwxrwxrwx") || line.contains("777")) {
                val fileName = line.split(Regex("\\s+")).lastOrNull()
                fileName?.let {
                    threats.add(mapOf(
                        "id" to "$dir/$it",
                        "name" to "Suspicious File Permissions",
                        "description" to "File with 777 permissions: $it",
                        "severity" to "HIGH",
                        "type" to "file",
                        "path" to "$dir/$it",
                        "requiresRoot" to true,
                        "metadata" to mapOf("permissions" to "777")
                    ))
                }
            }
        }
        
        return threats
    }
    
    private fun extractPid(processLine: String): String? {
        // Extract PID from process line
        val parts = processLine.trim().split(Regex("\\s+"))
        return if (parts.isNotEmpty()) parts[0] else null
    }
    
    private fun killProcess(processName: String): Boolean {
        if (!hasElevatedAccess) return false
        return elevatedAccess.killProcess(processName)
    }
    
    private fun deleteFile(path: String): Boolean {
        if (!hasElevatedAccess) return false
        return elevatedAccess.deleteFile(path)
    }
    
    private fun uninstallPackage(packageName: String): Boolean {
        if (!hasElevatedAccess) return false
        val result = elevatedAccess.pmCommand("uninstall $packageName")
        return result?.contains("Success") == true
    }
}