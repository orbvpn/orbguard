// MainActivity.kt - Complete Android Native Implementation
// Location: android/app/src/main/kotlin/com/orb/guard/MainActivity.kt

package com.orb.guard

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.app.AppOpsManager
import android.os.Build
import android.os.Environment
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.DataOutputStream
import java.io.File
import java.io.InputStreamReader
import android.app.ActivityManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.content.pm.PackageManager
import android.content.ComponentName
import android.os.Bundle
import android.text.TextUtils
import kotlinx.coroutines.*

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.orb.guard/system"
    private var rootAccess: RootAccess? = null
    private var spywareScanner: SpywareScanner? = null
    
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        rootAccess = RootAccess()
        spywareScanner = SpywareScanner(this, rootAccess!!)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkRootAccess" -> {
                    val hasRoot = rootAccess!!.checkRootAccess()
                    val accessLevel = if (hasRoot) "Full" else "Limited"
                    result.success(mapOf(
                        "hasRoot" to hasRoot,
                        "accessLevel" to accessLevel,
                        "method" to rootAccess!!.accessMethod
                    ))
                }
                
                // Special Permissions
                "checkUsageStatsPermission" -> {
                    val hasPermission = checkUsageStatsPermission()
                    result.success(mapOf("hasPermission" to hasPermission))
                }
                
                "requestUsageStatsPermission" -> {
                    requestUsageStatsPermission()
                    result.success(true)
                }
                
                "checkAccessibilityPermission" -> {
                    val hasPermission = checkAccessibilityPermission()
                    result.success(mapOf("hasPermission" to hasPermission))
                }
                
                "requestAccessibilityPermission" -> {
                    requestAccessibilityPermission()
                    result.success(true)
                }

                "openUsageStatsSettings" -> {
                    requestUsageStatsPermission()
                    result.success(true)
                }

                "openAccessibilitySettings" -> {
                    requestAccessibilityPermission()
                    result.success(true)
                }

                // Storage Permission (Android 11+)
                "checkStoragePermission" -> {
                    val hasPermission = checkStoragePermission()
                    result.success(mapOf("hasPermission" to hasPermission))
                }

                "requestStoragePermission" -> {
                    requestStoragePermission()
                    result.success(true)
                }

                // Access Level
                "checkAccessLevel" -> {
                    val accessInfo = getAccessLevelInfo()
                    result.success(accessInfo)
                }

                "getSetupInstructions" -> {
                    val instructions = getSetupInstructions()
                    result.success(instructions)
                }

                // Scanning
                "initializeScan" -> {
                    val deepScan = call.argument<Boolean>("deepScan") ?: false
                    val hasRoot = call.argument<Boolean>("hasRoot") ?: false
                    spywareScanner!!.initialize(deepScan, rootAccess!!.hasRootAccess())
                    result.success(true)
                }
                
                "scanNetwork" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val threats = spywareScanner!!.scanNetwork()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("threats" to threats))
                        }
                    }
                }
                
                "scanProcesses" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val threats = spywareScanner!!.scanProcesses()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("threats" to threats))
                        }
                    }
                }
                
                "scanFileSystem" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val threats = spywareScanner!!.scanFileSystem()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("threats" to threats))
                        }
                    }
                }
                
                "scanDatabases" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val threats = spywareScanner!!.scanDatabases()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("threats" to threats))
                        }
                    }
                }
                
                "scanMemory" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val threats = spywareScanner!!.scanMemory()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("threats" to threats))
                        }
                    }
                }
                
                "removeThreat" -> {
                    val id = call.argument<String>("id")
                    val type = call.argument<String>("type")
                    val path = call.argument<String>("path")
                    val requiresRoot = call.argument<Boolean>("requiresRoot") ?: false
                    
                    CoroutineScope(Dispatchers.IO).launch {
                        val success = spywareScanner!!.removeThreat(id!!, type!!, path!!, requiresRoot)
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("success" to success))
                        }
                    }
                }
                
                else -> result.notImplemented()
            }
        }
    }
    
    // ============================================================================
    // SPECIAL PERMISSIONS HANDLING
    // ============================================================================
    
    private fun checkUsageStatsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return false
        }
        
        try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }
            return mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            return false
        }
    }
    
    private fun requestUsageStatsPermission() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            // Add extras to highlight our app in the list
            val bundle = Bundle()
            bundle.putString(":settings:fragment_args_key", packageName)
            intent.putExtra(":settings:fragment_args_key", packageName)
            intent.putExtra(":settings:show_fragment_args", bundle)

            startActivity(intent)
        } catch (e: Exception) {
            // Fallback without highlight
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            startActivity(intent)
        }
    }
    
    private fun checkAccessibilityPermission(): Boolean {
        val accessibilityEnabled = Settings.Secure.getInt(
            contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0
        )

        if (accessibilityEnabled == 1) {
            val service = "$packageName/$packageName.AccessibilityMonitorService"
            val settingValue = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )

            // Log for debugging
            android.util.Log.d("OrbGuard", "Looking for service: $service")
            android.util.Log.d("OrbGuard", "Enabled services: $settingValue")

            // Check both possible formats
            val found = settingValue?.contains(service) == true ||
                        settingValue?.contains("$packageName/.AccessibilityMonitorService") == true ||
                        settingValue?.contains("AccessibilityMonitorService") == true

            android.util.Log.d("OrbGuard", "Accessibility found: $found")
            return found
        }
        return false
    }
    
    private fun requestAccessibilityPermission() {
        try {
            // Create the component name for our accessibility service
            val componentName = ComponentName(packageName, "$packageName.AccessibilityMonitorService")

            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            // Add extras to highlight our service in the list
            val bundle = Bundle()
            val componentNameString = componentName.flattenToString()
            bundle.putString(":settings:fragment_args_key", componentNameString)
            intent.putExtra(":settings:fragment_args_key", componentNameString)
            intent.putExtra(":settings:show_fragment_args", bundle)

            startActivity(intent)
        } catch (e: Exception) {
            // Fallback to general accessibility settings
            try {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                startActivity(intent)
            } catch (e2: Exception) {
                val intent = Intent(Settings.ACTION_SETTINGS)
                startActivity(intent)
            }
        }
    }

    // ============================================================================
    // STORAGE PERMISSION (Android 11+)
    // ============================================================================

    private fun checkStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ needs MANAGE_EXTERNAL_STORAGE
            Environment.isExternalStorageManager()
        } else {
            // Android 10 and below use regular storage permission
            checkSelfPermission(android.Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }
    }

    // ============================================================================
    // ACCESS LEVEL INFO
    // ============================================================================

    private fun getAccessLevelInfo(): Map<String, Any> {
        val hasRoot = rootAccess?.hasRootAccess() ?: false
        val accessMethod = rootAccess?.accessMethod ?: "Standard"

        val level: String
        val description: String
        val capabilities: List<String>

        when (accessMethod) {
            "Root" -> {
                level = "ROOT"
                description = "Full root access detected. Maximum threat detection and removal capabilities enabled."
                capabilities = listOf(
                    "Deep system file scanning",
                    "Hidden process detection",
                    "Kernel-level threat analysis",
                    "Complete threat removal",
                    "System modification detection"
                )
            }
            "Shell" -> {
                level = "SHELL"
                description = "Shell access enabled via Shizuku or ADB. Enhanced scanning capabilities available."
                capabilities = listOf(
                    "System file scanning",
                    "Process inspection",
                    "Network connection analysis",
                    "App data access",
                    "Service monitoring"
                )
            }
            "AppProcess" -> {
                level = "ELEVATED"
                description = "App process access available. Enhanced monitoring enabled."
                capabilities = listOf(
                    "Enhanced process monitoring",
                    "System service inspection",
                    "Network analysis",
                    "App behavior tracking"
                )
            }
            else -> {
                level = "STANDARD"
                description = "Standard access level. Basic threat detection active."
                capabilities = listOf(
                    "App scanning",
                    "Behavioral analysis",
                    "Network monitoring",
                    "Permission analysis"
                )
            }
        }

        return mapOf(
            "level" to level,
            "description" to description,
            "capabilities" to capabilities,
            "hasRoot" to hasRoot,
            "method" to accessMethod
        )
    }

    private fun getSetupInstructions(): Map<String, Any> {
        return mapOf(
            "title" to "Elevated Access Setup",
            "description" to "To enable deeper threat detection, you can grant elevated access using one of these methods:",
            "methods" to listOf(
                mapOf(
                    "name" to "Shizuku",
                    "description" to "Use Shizuku app for shell-level access without root",
                    "steps" to listOf(
                        "Install Shizuku from Play Store",
                        "Start Shizuku via ADB or Wireless debugging",
                        "Grant OrbGuard permission in Shizuku",
                        "Return here and tap 'Re-check Access Level'"
                    ),
                    "difficulty" to "Easy"
                ),
                mapOf(
                    "name" to "ADB Wireless",
                    "description" to "Use ADB over WiFi for temporary elevated access",
                    "steps" to listOf(
                        "Enable Developer Options on your device",
                        "Enable Wireless Debugging",
                        "Pair with a computer using ADB",
                        "Run: adb shell pm grant com.orb.guard android.permission.DUMP"
                    ),
                    "difficulty" to "Medium"
                ),
                mapOf(
                    "name" to "Root Access",
                    "description" to "If your device is rooted, grant root access to OrbGuard",
                    "steps" to listOf(
                        "Ensure your device is rooted (Magisk recommended)",
                        "Open OrbGuard and grant root access when prompted",
                        "Root manager will show permission request"
                    ),
                    "difficulty" to "Requires rooted device"
                )
            )
        )
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ - open special app access settings
            try {
                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                intent.data = Uri.parse("package:$packageName")
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

                // Add extras to highlight our app
                val bundle = Bundle()
                bundle.putString(":settings:fragment_args_key", packageName)
                intent.putExtra(":settings:fragment_args_key", packageName)
                intent.putExtra(":settings:show_fragment_args", bundle)

                startActivity(intent)
            } catch (e: Exception) {
                // Fallback to general file access settings with highlight
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

                    val bundle = Bundle()
                    bundle.putString(":settings:fragment_args_key", packageName)
                    intent.putExtra(":settings:fragment_args_key", packageName)
                    intent.putExtra(":settings:show_fragment_args", bundle)

                    startActivity(intent)
                } catch (e2: Exception) {
                    val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    startActivity(intent)
                }
            }
        } else {
            // Android 10 and below - request through standard permission flow
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_EXTERNAL_STORAGE,
                    android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                ),
                100
            )
        }
    }
}

// ============================================================================
// ROOT ACCESS MANAGER
// ============================================================================

class RootAccess {
    var hasRoot = false
    var hasShell = false
    var accessMethod = "None"
    
    fun checkRootAccess(): Boolean {
        // Try multiple methods in order of preference
        
        // Method 1: Check for root access (highest privilege)
        if (checkRootBinaries()) {
            hasRoot = true
            hasShell = true
            accessMethod = "Root"
            return true
        }
        
        // Method 2: Use shell user access (Shizuku method)
        if (checkShellAccess()) {
            hasShell = true
            accessMethod = "Shell"
            return true
        }
        
        // Method 3: Use app_process for system services
        if (checkAppProcessAccess()) {
            hasShell = true
            accessMethod = "AppProcess"
            return true
        }
        
        accessMethod = "Standard"
        return false
    }
    
    fun hasRootAccess(): Boolean = hasRoot || hasShell
    
    private fun checkRootBinaries(): Boolean {
        val paths = arrayOf(
            "/system/xbin/su",
            "/system/bin/su",
            "/sbin/su",
            "/vendor/bin/su"
        )
        
        for (path in paths) {
            if (File(path).exists()) {
                try {
                    val process = Runtime.getRuntime().exec("su")
                    val writer = DataOutputStream(process.outputStream)
                    writer.writeBytes("id\n")
                    writer.writeBytes("exit\n")
                    writer.flush()
                    
                    val reader = BufferedReader(InputStreamReader(process.inputStream))
                    val output = reader.readLine()
                    
                    if (output?.contains("uid=0") == true) {
                        return true
                    }
                } catch (e: Exception) {
                    // Root access denied
                }
            }
        }
        return false
    }
    
    private fun checkShellAccess(): Boolean {
        try {
            val process = Runtime.getRuntime().exec("sh")
            val writer = DataOutputStream(process.outputStream)
            writer.writeBytes("id\n")
            writer.writeBytes("exit\n")
            writer.flush()
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readLine()
            
            if (output?.contains("uid=") == true) {
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
    
    private fun checkAppProcessAccess(): Boolean {
        try {
            val process = Runtime.getRuntime().exec(arrayOf(
                "sh", "-c",
                "CLASSPATH=/system/framework/am.jar app_process /system/bin com.android.commands.am.Am"
            ))
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readLine()
            
            if (output != null) {
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }
    
    fun executeCommand(command: String): String? {
        try {
            if (hasRoot) {
                return executeRootCommand(command)
            } else if (hasShell) {
                return executeShellCommand(command)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }
    
    private fun executeRootCommand(command: String): String? {
        try {
            val process = Runtime.getRuntime().exec("su")
            val writer = DataOutputStream(process.outputStream)
            writer.writeBytes("$command\n")
            writer.writeBytes("exit\n")
            writer.flush()
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = StringBuilder()
            var line: String?
            
            while (reader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }
            
            process.waitFor()
            return output.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
    
    private fun executeShellCommand(command: String): String? {
        try {
            val process = Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = StringBuilder()
            var line: String?
            
            while (reader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }
            
            process.waitFor()
            return output.toString()
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
    
    fun readSystemFile(path: String): String? = executeCommand("cat '$path'")
    fun pmCommand(args: String): String? = executeCommand("pm $args")
    fun dumpsys(service: String): String? = executeCommand("dumpsys $service")
    fun getProcessList(): String? = executeCommand("ps -A")
    fun getNetstat(): String? = executeCommand("cat /proc/net/tcp")
    fun listFiles(path: String): String? = executeCommand("ls -la '$path'")
    fun deleteFile(path: String): Boolean = executeCommand("rm -rf '$path'") != null
    fun killProcess(processName: String): Boolean = executeCommand("killall '$processName'") != null
}

