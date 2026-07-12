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
    private val SMS_CHANNEL = "com.orb.guard/sms"
    private val BROWSER_CHANNEL = "com.orb.guard/browser"
    private var rootAccess: RootAccess? = null
    private var spywareScanner: SpywareScanner? = null
    private var smsAnalyzer: SMSAnalyzer? = null
    private var browserMonitor: BrowserMonitor? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        rootAccess = RootAccess()
        spywareScanner = SpywareScanner(this, rootAccess!!)
        smsAnalyzer = SMSAnalyzer.getInstance(this)
        browserMonitor = BrowserMonitor.getInstance(this)

        // Setup SMS Method Channel
        setupSmsChannel(flutterEngine)

        // Setup Browser Method Channel
        setupBrowserChannel(flutterEngine)
        
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

                // Get installed certificates
                "getInstalledCertificates" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val certificates = getInstalledCertificates()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("certificates" to certificates))
                        }
                    }
                }

                // Get installed apps
                "getInstalledApps" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val apps = getInstalledApps()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("apps" to apps))
                        }
                    }
                }

                // Get enabled accessibility services
                "getEnabledAccessibilityServices" -> {
                    val services = getEnabledAccessibilityServices()
                    result.success(mapOf("services" to services))
                }

                // Get installed keyboards
                "getInstalledKeyboards" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val keyboards = getInstalledKeyboards()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("keyboards" to keyboards))
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
    // DEVICE SECURITY INFO
    // ============================================================================

    private fun getInstalledCertificates(): List<Map<String, Any>> {
        val certificates = mutableListOf<Map<String, Any>>()
        try {
            // Get user-installed certificates from KeyStore
            val keyStore = java.security.KeyStore.getInstance("AndroidCAStore")
            keyStore.load(null)

            val aliases = keyStore.aliases()
            while (aliases.hasMoreElements()) {
                val alias = aliases.nextElement()
                try {
                    val cert = keyStore.getCertificate(alias) as? java.security.cert.X509Certificate
                    if (cert != null) {
                        // Check if it's a user-installed certificate (not system)
                        val isUserInstalled = alias.startsWith("user:")

                        certificates.add(mapOf(
                            "alias" to alias,
                            "subjectDN" to (cert.subjectDN?.name ?: "Unknown"),
                            "issuerDN" to (cert.issuerDN?.name ?: "Unknown"),
                            "serialNumber" to cert.serialNumber.toString(),
                            "notBefore" to cert.notBefore.time,
                            "notAfter" to cert.notAfter.time,
                            "isUserInstalled" to isUserInstalled,
                            "type" to cert.type
                        ))
                    }
                } catch (e: Exception) {
                    // Skip invalid certificates
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("OrbGuard", "Error getting certificates: ${e.message}")
        }
        return certificates
    }

    private fun getInstalledApps(): List<Map<String, Any>> {
        val apps = mutableListOf<Map<String, Any>>()
        try {
            val pm = packageManager
            val packages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledPackages(PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledPackages(PackageManager.GET_PERMISSIONS)
            }

            for (packageInfo in packages) {
                try {
                    val appInfo = packageInfo.applicationInfo ?: continue
                    val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    val isUpdatedSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0

                    // Get installer package
                    val installerPackage = try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            pm.getInstallSourceInfo(packageInfo.packageName).installingPackageName
                        } else {
                            @Suppress("DEPRECATION")
                            pm.getInstallerPackageName(packageInfo.packageName)
                        }
                    } catch (e: Exception) {
                        null
                    }

                    apps.add(mapOf(
                        "packageName" to packageInfo.packageName,
                        "appName" to (appInfo.loadLabel(pm)?.toString() ?: packageInfo.packageName),
                        "versionName" to (packageInfo.versionName ?: "Unknown"),
                        "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageInfo.longVersionCode
                        } else {
                            @Suppress("DEPRECATION")
                            packageInfo.versionCode.toLong()
                        },
                        "isSystemApp" to isSystemApp,
                        "isUpdatedSystemApp" to isUpdatedSystemApp,
                        "installerPackage" to (installerPackage ?: "unknown"),
                        "firstInstallTime" to packageInfo.firstInstallTime,
                        "lastUpdateTime" to packageInfo.lastUpdateTime,
                        "targetSdkVersion" to appInfo.targetSdkVersion,
                        "minSdkVersion" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            appInfo.minSdkVersion
                        } else {
                            0
                        },
                        "permissions" to (packageInfo.requestedPermissions?.toList() ?: emptyList<String>()),
                        "enabled" to appInfo.enabled
                    ))
                } catch (e: Exception) {
                    // Skip problematic packages
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("OrbGuard", "Error getting installed apps: ${e.message}")
        }
        return apps
    }

    private fun getEnabledAccessibilityServices(): List<Map<String, Any>> {
        val services = mutableListOf<Map<String, Any>>()
        try {
            val settingValue = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )

            if (!settingValue.isNullOrEmpty()) {
                val enabledServices = settingValue.split(":")
                for (serviceStr in enabledServices) {
                    if (serviceStr.isNotEmpty()) {
                        try {
                            val componentName = ComponentName.unflattenFromString(serviceStr)
                            if (componentName != null) {
                                val packageName = componentName.packageName
                                val className = componentName.className

                                // Get app info
                                val appName = try {
                                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                                    appInfo.loadLabel(packageManager).toString()
                                } catch (e: Exception) {
                                    packageName
                                }

                                services.add(mapOf(
                                    "packageName" to packageName,
                                    "className" to className,
                                    "appName" to appName,
                                    "flattenedName" to serviceStr
                                ))
                            }
                        } catch (e: Exception) {
                            // Add raw string if parsing fails
                            services.add(mapOf(
                                "packageName" to serviceStr,
                                "className" to "",
                                "appName" to serviceStr,
                                "flattenedName" to serviceStr
                            ))
                        }
                    }
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("OrbGuard", "Error getting accessibility services: ${e.message}")
        }
        return services
    }

    private fun getInstalledKeyboards(): List<Map<String, Any>> {
        val keyboards = mutableListOf<Map<String, Any>>()
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as android.view.inputmethod.InputMethodManager
            val inputMethods = imm.inputMethodList

            // Get current default keyboard
            val defaultKeyboard = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.DEFAULT_INPUT_METHOD
            )

            for (inputMethod in inputMethods) {
                try {
                    val packageName = inputMethod.packageName
                    val serviceName = inputMethod.serviceName

                    // Get app info
                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                    val isSystemApp = (appInfo.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                    val isDefault = inputMethod.id == defaultKeyboard

                    keyboards.add(mapOf(
                        "id" to inputMethod.id,
                        "packageName" to packageName,
                        "serviceName" to serviceName,
                        "appName" to (inputMethod.loadLabel(packageManager)?.toString() ?: packageName),
                        "isSystemApp" to isSystemApp,
                        "isDefault" to isDefault,
                        "settingsActivity" to (inputMethod.settingsActivity ?: "")
                    ))
                } catch (e: Exception) {
                    // Skip problematic keyboards
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("OrbGuard", "Error getting keyboards: ${e.message}")
        }
        return keyboards
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

    // ============================================================================
    // SMS PROTECTION CHANNEL
    // ============================================================================

    private fun setupSmsChannel(flutterEngine: FlutterEngine) {
        val smsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SMS_CHANNEL)

        // Set the method channel for the analyzer
        smsAnalyzer?.setMethodChannel(smsChannel)

        smsChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Check SMS permission
                "checkSmsPermission" -> {
                    val hasPermission = smsAnalyzer?.hasSmsPermission() ?: false
                    result.success(mapOf("hasPermission" to hasPermission))
                }

                // Request SMS permission
                "requestSmsPermission" -> {
                    requestSmsPermission()
                    result.success(true)
                }

                // Read SMS inbox
                "readSmsInbox" -> {
                    val limit = call.argument<Int>("limit") ?: 100
                    CoroutineScope(Dispatchers.IO).launch {
                        val messages = smsAnalyzer?.readSmsInbox(limit) ?: emptyList()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("messages" to messages))
                        }
                    }
                }

                // Update SMS protection settings
                "updateSettings" -> {
                    val protectionEnabled = call.argument<Boolean>("protectionEnabled") ?: true
                    val notifyOnThreat = call.argument<Boolean>("notifyOnThreat") ?: true
                    val autoBlockDangerous = call.argument<Boolean>("autoBlockDangerous") ?: false

                    smsAnalyzer?.updateSettings(protectionEnabled, notifyOnThreat, autoBlockDangerous)
                    result.success(true)
                }

                // Handle analysis result from Flutter
                "onAnalysisComplete" -> {
                    val messageId = call.argument<String>("messageId") ?: ""
                    val resultMap = call.argument<Map<String, Any?>>("result")

                    if (resultMap != null) {
                        val analysisResult = AnalysisResult.fromMap(resultMap + ("messageId" to messageId))
                        smsAnalyzer?.onAnalysisResult(messageId, analysisResult)
                    }
                    result.success(true)
                }

                // Get analysis result for a message
                "getAnalysisResult" -> {
                    val messageId = call.argument<String>("messageId") ?: ""
                    val analysisResult = smsAnalyzer?.getAnalysisResult(messageId)
                    result.success(analysisResult?.toMap())
                }

                // Clear cache
                "clearCache" -> {
                    smsAnalyzer?.clearCache()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestSmsPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_SMS,
                    android.Manifest.permission.RECEIVE_SMS
                ),
                200
            )
        }
    }

    // ============================================================================
    // BROWSER PROTECTION CHANNEL
    // ============================================================================

    private fun setupBrowserChannel(flutterEngine: FlutterEngine) {
        val browserChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BROWSER_CHANNEL)

        // Set the method channel for the monitor
        browserMonitor?.setMethodChannel(browserChannel)

        browserChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Check browser accessibility permission
                "checkBrowserAccessibilityPermission" -> {
                    val hasPermission = checkBrowserAccessibilityPermission()
                    result.success(mapOf("hasPermission" to hasPermission))
                }

                // Request browser accessibility permission
                "requestBrowserAccessibilityPermission" -> {
                    requestBrowserAccessibilityPermission()
                    result.success(true)
                }

                // Update browser protection settings
                "updateSettings" -> {
                    val protectionEnabled = call.argument<Boolean>("protectionEnabled") ?: true
                    val notifyOnThreat = call.argument<Boolean>("notifyOnThreat") ?: true
                    val blockDangerous = call.argument<Boolean>("blockDangerous") ?: false

                    browserMonitor?.updateSettings(protectionEnabled, notifyOnThreat, blockDangerous)
                    BrowserAccessibilityService.getInstance()?.updateSettings(protectionEnabled, true)
                    result.success(true)
                }

                // Handle analysis result from Flutter
                "onAnalysisComplete" -> {
                    val url = call.argument<String>("url") ?: ""
                    val resultMap = call.argument<Map<String, Any?>>("result")
                    val browser = call.argument<String>("browser") ?: "Unknown"

                    if (resultMap != null) {
                        val analysisResult = UrlAnalysisResult.fromMap(resultMap)
                        browserMonitor?.onAnalysisResult(url, analysisResult, browser)
                    }
                    result.success(true)
                }

                // Get analyzed URLs history
                "getAnalyzedUrls" -> {
                    val urls = browserMonitor?.getAnalyzedUrls() ?: emptyList()
                    result.success(mapOf("urls" to urls))
                }

                // Whitelist management
                "addToWhitelist" -> {
                    val domain = call.argument<String>("domain") ?: ""
                    browserMonitor?.addToWhitelist(domain)
                    result.success(true)
                }

                "removeFromWhitelist" -> {
                    val domain = call.argument<String>("domain") ?: ""
                    browserMonitor?.removeFromWhitelist(domain)
                    result.success(true)
                }

                "getWhitelist" -> {
                    val whitelist = browserMonitor?.getWhitelist() ?: emptyList()
                    result.success(mapOf("domains" to whitelist))
                }

                // Blacklist management
                "addToBlacklist" -> {
                    val domain = call.argument<String>("domain") ?: ""
                    browserMonitor?.addToBlacklist(domain)
                    result.success(true)
                }

                "removeFromBlacklist" -> {
                    val domain = call.argument<String>("domain") ?: ""
                    browserMonitor?.removeFromBlacklist(domain)
                    result.success(true)
                }

                "getBlacklist" -> {
                    val blacklist = browserMonitor?.getBlacklist() ?: emptyList()
                    result.success(mapOf("domains" to blacklist))
                }

                // Clear cache
                "clearCache" -> {
                    browserMonitor?.clearCache()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun checkBrowserAccessibilityPermission(): Boolean {
        val accessibilityEnabled = Settings.Secure.getInt(
            contentResolver,
            Settings.Secure.ACCESSIBILITY_ENABLED,
            0
        )

        if (accessibilityEnabled == 1) {
            val service = "$packageName/$packageName.BrowserAccessibilityService"
            val settingValue = Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )

            return settingValue?.contains(service) == true ||
                    settingValue?.contains("$packageName/.BrowserAccessibilityService") == true ||
                    settingValue?.contains("BrowserAccessibilityService") == true
        }
        return false
    }

    private fun requestBrowserAccessibilityPermission() {
        try {
            val componentName = ComponentName(packageName, "$packageName.BrowserAccessibilityService")

            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            val bundle = Bundle()
            val componentNameString = componentName.flattenToString()
            bundle.putString(":settings:fragment_args_key", componentNameString)
            intent.putExtra(":settings:fragment_args_key", componentNameString)
            intent.putExtra(":settings:show_fragment_args", bundle)

            startActivity(intent)
        } catch (e: Exception) {
            try {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                startActivity(intent)
            } catch (e2: Exception) {
                val intent = Intent(Settings.ACTION_SETTINGS)
                startActivity(intent)
            }
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

