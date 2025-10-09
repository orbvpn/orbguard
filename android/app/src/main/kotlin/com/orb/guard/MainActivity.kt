// android/app/src/main/kotlin/com/orb/guard/MainActivity.kt
// Updated with permission handler integration

package com.orb.guard

import android.os.Bundle
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.orb.guard/system"
    private lateinit var permissionHandler: PermissionHandler
    private lateinit var elevatedAccess: ElevatedAccessManager
    private lateinit var spywareScanner: SpywareScanner
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Initialize managers
        elevatedAccess = ElevatedAccessManager(this)
        spywareScanner = SpywareScanner(this, elevatedAccess)
    }
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize permission handler
        permissionHandler = PermissionHandler(this, flutterEngine)
        
        // Setup main method channel for scanning
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Access Level Checking
                "checkRootAccess" -> {
                    val hasElevated = elevatedAccess.checkElevatedAccess()
                    result.success(mapOf(
                        "hasRoot" to hasElevated,
                        "accessLevel" to elevatedAccess.getAccessLevelName(),
                        "method" to elevatedAccess.accessMethod
                    ))
                }
                
                // Scan Initialization
                "initializeScan" -> {
                    val deepScan = call.argument<Boolean>("deepScan") ?: false
                    val hasRoot = call.argument<Boolean>("hasRoot") ?: false
                    
                    spywareScanner.initialize(
                        deepScan,
                        elevatedAccess.hasElevatedAccess()
                    )
                    result.success(true)
                }
                
                // Scanning Methods
                "scanNetwork" -> {
                    Thread {
                        val threats = spywareScanner.scanNetwork()
                        runOnUiThread {
                            result.success(mapOf("threats" to threats))
                        }
                    }.start()
                }
                
                "scanProcesses" -> {
                    Thread {
                        val threats = spywareScanner.scanProcesses()
                        runOnUiThread {
                            result.success(mapOf("threats" to threats))
                        }
                    }.start()
                }
                
                "scanFileSystem" -> {
                    Thread {
                        val threats = spywareScanner.scanFileSystem()
                        runOnUiThread {
                            result.success(mapOf("threats" to threats))
                        }
                    }.start()
                }
                
                "scanDatabases" -> {
                    Thread {
                        val threats = spywareScanner.scanDatabases()
                        runOnUiThread {
                            result.success(mapOf("threats" to threats))
                        }
                    }.start()
                }
                
                "scanMemory" -> {
                    Thread {
                        val threats = spywareScanner.scanMemory()
                        runOnUiThread {
                            result.success(mapOf("threats" to threats))
                        }
                    }.start()
                }
                
                // Threat Removal
                "removeThreat" -> {
                    val id = call.argument<String>("id") ?: ""
                    val type = call.argument<String>("type") ?: ""
                    val path = call.argument<String>("path") ?: ""
                    val requiresRoot = call.argument<Boolean>("requiresRoot") ?: false
                    
                    Thread {
                        val success = spywareScanner.removeThreat(
                            id, type, path, requiresRoot
                        )
                        runOnUiThread {
                            result.success(mapOf("success" to success))
                        }
                    }.start()
                }
                
                // Permission Helpers (used by advanced detection modules)
                "getInstalledApps" -> {
                    Thread {
                        val apps = getInstalledAppsInfo()
                        runOnUiThread {
                            result.success(mapOf("apps" to apps))
                        }
                    }.start()
                }
                
                "getLocationAccessHistory" -> {
                    val hours = call.argument<Int>("hours") ?: 24
                    Thread {
                        val history = getLocationAccessHistory(hours)
                        runOnUiThread {
                            result.success(mapOf("accesses" to history))
                        }
                    }.start()
                }
                
                else -> result.notImplemented()
            }
        }
    }
    
    // ============================================================================
    // HELPER METHODS FOR ADVANCED DETECTION
    // ============================================================================
    
    private fun getInstalledAppsInfo(): List<Map<String, Any>> {
        val apps = mutableListOf<Map<String, Any>>()
        val packageManager = packageManager
        
        try {
            val packages = packageManager.getInstalledApplications(0)
            
            for (packageInfo in packages) {
                val appName = packageManager.getApplicationLabel(packageInfo).toString()
                val packageName = packageInfo.packageName
                
                // Get permissions
                val permissions = try {
                    val info = packageManager.getPackageInfo(
                        packageName,
                        android.content.pm.PackageManager.GET_PERMISSIONS
                    )
                    info.requestedPermissions?.toList() ?: emptyList()
                } catch (e: Exception) {
                    emptyList()
                }
                
                // Get install date
                val installDate = try {
                    val info = packageManager.getPackageInfo(packageName, 0)
                    info.firstInstallTime
                } catch (e: Exception) {
                    0L
                }
                
                apps.add(mapOf(
                    "appName" to appName,
                    "packageName" to packageName,
                    "permissions" to permissions,
                    "installDate" to installDate,
                    "isSystemApp" to ((packageInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0)
                ))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return apps
    }
    
    private fun getLocationAccessHistory(hours: Int): List<Map<String, Any>> {
        val history = mutableListOf<Map<String, Any>>()
        
        // This requires Usage Stats permission
        if (!permissionHandler.hasUsageStatsPermission()) {
            return history
        }
        
        try {
            // TODO: Implement proper location access history tracking
            // This would require a background service to monitor location requests
            
            // For now, return empty list
            // In production, you would:
            // 1. Monitor AppOpsManager for location access
            // 2. Log to local database
            // 3. Query database here
            
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return history
    }
}

// ============================================================================
// ELEVATED ACCESS MANAGER
// ============================================================================

class ElevatedAccessManager(private val context: android.content.Context) {
    var hasRoot = false
    var hasShell = false
    var accessMethod = "None"
    
    fun checkElevatedAccess(): Boolean {
        // Try root first (highest privilege)
        if (checkRootAccess()) {
            hasRoot = true
            hasShell = true
            accessMethod = "Root"
            return true
        }
        
        // Try shell access
        if (checkShellAccess()) {
            hasShell = true
            accessMethod = "Shell"
            return true
        }
        
        accessMethod = "Standard"
        return false
    }
    
    fun hasElevatedAccess(): Boolean = hasRoot || hasShell
    
    fun getAccessLevelName(): String {
        return when {
            hasRoot -> "Full"
            hasShell -> "Enhanced"
            else -> "Standard"
        }
    }
    
    private fun checkRootAccess(): Boolean {
        val paths = arrayOf(
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/vendor/bin/su"
        )
        
        for (path in paths) {
            if (java.io.File(path).exists()) {
                try {
                    val process = Runtime.getRuntime().exec("su -c id")
                    val reader = java.io.BufferedReader(
                        java.io.InputStreamReader(process.inputStream)
                    )
                    val output = reader.readLine()
                    
                    if (output?.contains("uid=0") == true) {
                        return true
                    }
                } catch (e: Exception) {
                    // Root denied
                }
            }
        }
        return false
    }
    
    private fun checkShellAccess(): Boolean {
        try {
            val process = Runtime.getRuntime().exec("sh -c id")
            val reader = java.io.BufferedReader(
                java.io.InputStreamReader(process.inputStream)
            )
            val output = reader.readLine()
            
            return output?.contains("uid=") == true
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
    
    fun executeCommand(command: String): String? {
        return try {
            val prefix = if (hasRoot) "su -c" else "sh -c"
            val process = Runtime.getRuntime().exec("$prefix \"$command\"")
            
            val reader = java.io.BufferedReader(
                java.io.InputStreamReader(process.inputStream)
            )
            val output = StringBuilder()
            var line: String?
            
            while (reader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }
            
            process.waitFor()
            output.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }
}

// ============================================================================
// SPYWARE SCANNER STUB
// ============================================================================

class SpywareScanner(
    private val context: android.content.Context,
    private val elevatedAccess: ElevatedAccessManager
) {
    private var deepScan = false
    private var hasElevatedAccess = false
    
    fun initialize(deepScan: Boolean, hasElevated: Boolean) {
        this.deepScan = deepScan
        this.hasElevatedAccess = hasElevated
    }
    
    fun scanNetwork(): List<Map<String, Any>> {
        // Implementation will be in separate SpywareScanner.kt file
        return emptyList()
    }
    
    fun scanProcesses(): List<Map<String, Any>> {
        return emptyList()
    }
    
    fun scanFileSystem(): List<Map<String, Any>> {
        return emptyList()
    }
    
    fun scanDatabases(): List<Map<String, Any>> {
        return emptyList()
    }
    
    fun scanMemory(): List<Map<String, Any>> {
        return emptyList()
    }
    
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
    
    private fun killProcess(processName: String): Boolean {
        if (!hasElevatedAccess) return false
        val result = elevatedAccess.executeCommand("killall $processName")
        return result != null
    }
    
    private fun deleteFile(path: String): Boolean {
        if (!hasElevatedAccess) return false
        val result = elevatedAccess.executeCommand("rm -rf '$path'")
        return result != null
    }
    
    private fun uninstallPackage(packageName: String): Boolean {
        if (!hasElevatedAccess) return false
        val result = elevatedAccess.executeCommand("pm uninstall $packageName")
        return result?.contains("Success") == true
    }
}