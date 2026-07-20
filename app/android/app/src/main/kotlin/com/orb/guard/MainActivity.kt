// MainActivity.kt - Complete Android Native Implementation
// Location: android/app/src/main/kotlin/com/orb/guard/MainActivity.kt

package com.orb.guard

import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
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
    private val DEVICE_ADMIN_CHANNEL = "com.orb.guard/device_admin"
    // Distinct from FirewallChannelHandler.VPN_CONSENT_REQUEST (0x0F1A) and the
    // storage/SMS permission codes (100/200) so onActivityResult can tell the
    // device-admin grant apart.
    private val DEVICE_ADMIN_ENABLE_REQUEST = 0x0DA1
    // Held while the ACTION_ADD_DEVICE_ADMIN system screen is showing.
    private var pendingAdminResult: MethodChannel.Result? = null
    private var rootAccess: RootAccess? = null
    private var spywareScanner: SpywareScanner? = null
    private var apkFileScanner: ApkFileScanner? = null
    private var smsAnalyzer: SMSAnalyzer? = null
    private var browserMonitor: BrowserMonitor? = null
    private var systemMetricsHandler: SystemMetricsHandler? = null
    private var wifiChannelHandler: WifiChannelHandler? = null
    private var supplyChainChannelHandler: SupplyChainChannelHandler? = null
    private var firewallChannelHandler: FirewallChannelHandler? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        rootAccess = RootAccess()
        spywareScanner = SpywareScanner(this, rootAccess!!)
        apkFileScanner = ApkFileScanner(this)
        smsAnalyzer = SMSAnalyzer.getInstance(this)
        browserMonitor = BrowserMonitor.getInstance(this)
        systemMetricsHandler = SystemMetricsHandler(this, rootAccess)

        // Setup SMS Method Channel
        setupSmsChannel(flutterEngine)

        // Setup Browser Method Channel
        setupBrowserChannel(flutterEngine)

        // Device-administrator channel (remote anti-theft lock / wipe)
        setupDeviceAdminChannel(flutterEngine)

        // Wi-Fi inspection channel (com.orb.guard/wifi)
        wifiChannelHandler = WifiChannelHandler(this).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }

        // Supply-chain inspection channel (com.orbguard/supply_chain)
        supplyChainChannelHandler = SupplyChainChannelHandler(this).also {
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }

        // On-device firewall channel (com.orbvpn.orbguard/firewall)
        firewallChannelHandler = FirewallChannelHandler(this).also {
            it.setActivity(this)
            it.register(flutterEngine.dartExecutor.binaryMessenger)
        }

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

                // Remediation: open the system VPN settings so the user can
                // disconnect/remove a VPN (we cannot silently kill another
                // app's tunnel — Android forbids it).
                "openVpnSettings" -> {
                    result.success(openVpnSettings())
                }

                // Remediation: open a specific app's App Info screen so the
                // user can uninstall (or, for a system app like Bixby,
                // disable) it. Works on any device — no root needed.
                "openAppDetails" -> {
                    val pkg = call.argument<String>("package")
                    result.success(openAppDetails(pkg))
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
                
                // Scoped APK/file scan: analyses only the files the user picked.
                // No all-files permission needed.
                "scanApkFiles" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    CoroutineScope(Dispatchers.IO).launch {
                        val results = apkFileScanner?.scanApks(paths) ?: emptyList()
                        withContext(Dispatchers.Main) {
                            result.success(mapOf("results" to results))
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

                else -> {
                    // Device metrics, usage stats, IME/root checks, log
                    // capture, etc. live in SystemMetricsHandler.
                    if (systemMetricsHandler?.handle(call, result) != true) {
                        result.notImplemented()
                    }
                }
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
    
    /** Opens the system VPN settings screen so the user can disconnect a VPN. */
    private fun openVpnSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_VPN_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    /** Opens a package's App Info screen (uninstall / disable) — no root needed. */
    private fun openAppDetails(pkg: String?): Boolean {
        if (pkg.isNullOrBlank()) return false
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$pkg"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
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
            val enabledIds = imm.enabledInputMethodList.map { it.id }.toSet()

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

                    // Requested permissions (stripped of the android.permission.
                    // prefix — the Dart keylogger detector checks for "INTERNET").
                    val permissions = try {
                        val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                packageName,
                                PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
                        }
                        pkgInfo.requestedPermissions?.map { it.removePrefix("android.permission.") }
                            ?: emptyList()
                    } catch (e: Exception) {
                        emptyList<String>()
                    }

                    keyboards.add(mapOf(
                        "id" to inputMethod.id,
                        "packageName" to packageName,
                        "serviceName" to serviceName,
                        "appName" to (inputMethod.loadLabel(packageManager)?.toString() ?: packageName),
                        "isSystemApp" to isSystemApp,
                        "isDefault" to isDefault,
                        "isEnabled" to enabledIds.contains(inputMethod.id),
                        "permissions" to permissions,
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

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        // Forward the VPN consent-dialog result to the firewall handler.
        if (requestCode == FirewallChannelHandler.VPN_CONSENT_REQUEST) {
            firewallChannelHandler?.onVpnConsentResult(resultCode)
        } else if (requestCode == DEVICE_ADMIN_ENABLE_REQUEST) {
            // Report the real grant state back to Dart. Some OEMs return
            // RESULT_CANCELED even after a successful enable, so trust
            // isAdminActive() over resultCode.
            val pending = pendingAdminResult
            pendingAdminResult = null
            val granted = try {
                val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                dpm.isAdminActive(ComponentName(this, OrbDeviceAdminReceiver::class.java))
            } catch (e: Exception) {
                false
            }
            pending?.success(granted)
        }
    }

    // ============================================================================
    // DEVICE ADMINISTRATOR CHANNEL (remote anti-theft lock / wipe)
    // ============================================================================
    //
    // Serves com.orb.guard/device_admin for the Dart DeviceAdminBridge:
    //   isAdminActive -> Boolean: is OrbGuard an active device administrator
    //   lockNow       -> Boolean: lock the screen now (false if admin inactive)
    //   wipeData      -> Boolean: factory reset (false if admin inactive); also
    //                    wipes external storage when wipe_sd_card == true
    //   requestAdmin  -> Boolean: launch the intrusive ACTION_ADD_DEVICE_ADMIN
    //                    system screen and report whether the user granted it
    //
    // HONEST FAILURE: lock/wipe never fake success — without an active admin
    // they return false, which the bridge surfaces as a real failure so the
    // backend acks the command FAILED. WIPE is irreversible; it only ever runs
    // through a genuine remote 'wipe' command with admin already granted.

    private fun setupDeviceAdminChannel(flutterEngine: FlutterEngine) {
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_ADMIN_CHANNEL
        )
        channel.setMethodCallHandler { call, result ->
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            val component = ComponentName(this, OrbDeviceAdminReceiver::class.java)
            when (call.method) {
                "isAdminActive" -> {
                    result.success(
                        try {
                            dpm.isAdminActive(component)
                        } catch (e: Exception) {
                            false
                        }
                    )
                }

                "lockNow" -> {
                    if (!dpm.isAdminActive(component)) {
                        // Honest failure — the bridge maps false to "enable
                        // OrbGuard as a device administrator".
                        result.success(false)
                    } else {
                        try {
                            dpm.lockNow()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("LOCK_FAILED", e.message, null)
                        }
                    }
                }

                "wipeData" -> {
                    if (!dpm.isAdminActive(component)) {
                        result.success(false)
                    } else {
                        try {
                            val wipeSdCard = call.argument<Boolean>("wipe_sd_card") ?: false
                            val flags = if (wipeSdCard)
                                DevicePolicyManager.WIPE_EXTERNAL_STORAGE else 0
                            dpm.wipeData(flags)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WIPE_FAILED", e.message, null)
                        }
                    }
                }

                "requestAdmin" -> requestDeviceAdmin(result)

                else -> result.notImplemented()
            }
        }
    }

    /**
     * Launches the system ACTION_ADD_DEVICE_ADMIN screen so the user can grant
     * OrbGuard device-administrator privileges (the prerequisite for remote
     * lock/wipe). The grant outcome is delivered back through onActivityResult.
     * If admin is already active, succeeds immediately.
     */
    private fun requestDeviceAdmin(result: MethodChannel.Result) {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        val component = ComponentName(this, OrbDeviceAdminReceiver::class.java)
        if (dpm.isAdminActive(component)) {
            result.success(true)
            return
        }
        pendingAdminResult = result
        try {
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, component)
                putExtra(
                    DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                    "OrbGuard needs device-administrator access so you can " +
                        "remotely lock or factory-reset this device from the web " +
                        "if it is lost or stolen."
                )
            }
            startActivityForResult(intent, DEVICE_ADMIN_ENABLE_REQUEST)
        } catch (e: Exception) {
            pendingAdminResult = null
            result.error("ADMIN_REQUEST_FAILED", e.message, null)
        }
    }

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

            // A plain `sh` spawned by an app runs as the app's OWN unprivileged
            // uid, so "uid=" is ALWAYS present and proves nothing. Real elevated
            // shell access (Shizuku / ADB) runs as the shell user (uid 2000) or
            // root (uid 0) — only those count.
            if (output != null &&
                (output.contains("uid=0(") || output.contains("uid=2000("))) {
                return true
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    private fun checkAppProcessAccess(): Boolean {
        // A sandboxed app invoking app_process runs UNPRIVILEGED — reachable
        // `am` output is not elevation. Genuinely elevated devices are already
        // caught by the root (uid 0) and shell (uid 0/2000) checks above, so
        // this method must not claim access it does not actually have.
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

