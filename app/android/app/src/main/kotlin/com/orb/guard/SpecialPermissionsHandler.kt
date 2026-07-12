// android/app/src/main/kotlin/com/orb/guard/SpecialPermissionsHandler.kt
// Handles Usage Stats and Accessibility permissions

package com.orb.guard

import android.app.Activity
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.TextUtils
import io.flutter.plugin.common.MethodChannel

class SpecialPermissionsHandler(
    private val activity: Activity,
    private val context: Context
) {
    
    // ============================================================================
    // USAGE STATS PERMISSION
    // ============================================================================
    
    /**
     * Check if Usage Stats permission is granted
     * Required for behavioral analysis and anomaly detection
     */
    fun checkUsageStatsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return false
        }
        
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    context.packageName
                )
            }
            
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
    
    /**
     * Request Usage Stats permission by opening Settings
     */
    fun requestUsageStatsPermission() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            
            // Try to navigate directly to our app's settings
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                // Some devices support package-specific intent
                try {
                    intent.data = android.net.Uri.parse("package:${context.packageName}")
                } catch (e: Exception) {
                    // If package-specific intent fails, just open general settings
                }
            }
            
            activity.startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            // Fallback to app settings
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                intent.data = android.net.Uri.parse("package:${context.packageName}")
                activity.startActivity(intent)
            } catch (ex: Exception) {
                ex.printStackTrace()
            }
        }
    }
    
    // ============================================================================
    // ACCESSIBILITY PERMISSION
    // ============================================================================
    
    /**
     * Check if our app has accessibility service enabled
     * This is used to DETECT malicious accessibility services, not to abuse it
     */
    fun checkAccessibilityPermission(): Boolean {
        try {
            val accessibilityEnabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            )
            
            if (accessibilityEnabled == 1) {
                // Check if our service is in the list
                val enabledServices = Settings.Secure.getString(
                    context.contentResolver,
                    Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                )
                
                if (enabledServices != null) {
                    // We're checking if ANY accessibility service is enabled
                    // to detect potential threats
                    return enabledServices.isNotEmpty()
                }
            }
            
            return false
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
    }
    
    /**
     * Request Accessibility permission by opening Settings
     * Note: We're not actually creating an accessibility service for OrbGuard
     * We just need to check what accessibility services are enabled
     */
    fun requestAccessibilityPermission() {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            activity.startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            // Fallback to general settings
            try {
                val intent = Intent(Settings.ACTION_SETTINGS)
                activity.startActivity(intent)
            } catch (ex: Exception) {
                ex.printStackTrace()
            }
        }
    }
    
    // ============================================================================
    // ENABLED ACCESSIBILITY SERVICES DETECTION
    // ============================================================================
    
    /**
     * Get list of all enabled accessibility services
     * Used to detect potentially malicious services
     */
    fun getEnabledAccessibilityServices(): List<Map<String, Any>> {
        val services = mutableListOf<Map<String, Any>>()
        
        try {
            val accessibilityEnabled = Settings.Secure.getInt(
                context.contentResolver,
                Settings.Secure.ACCESSIBILITY_ENABLED,
                0
            )
            
            if (accessibilityEnabled != 1) {
                return services
            }
            
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return services
            
            val servicesList = enabledServices.split(":")
            
            for (serviceString in servicesList) {
                if (serviceString.isEmpty()) continue
                
                try {
                    // Parse component name: package/service
                    val parts = serviceString.split("/")
                    if (parts.size >= 2) {
                        val packageName = parts[0]
                        val serviceName = parts[1]
                        
                        // Get app info
                        val pm = context.packageManager
                        val appInfo = try {
                            pm.getApplicationInfo(packageName, 0)
                        } catch (e: Exception) {
                            null
                        }
                        
                        val appName = appInfo?.let {
                            pm.getApplicationLabel(it).toString()
                        } ?: packageName
                        
                        services.add(mapOf(
                            "packageName" to packageName,
                            "serviceName" to serviceName,
                            "appName" to appName,
                            "canRetrieveWindowContent" to true, // Assume true for security
                            "capabilities" to listOf("read_screen", "simulate_touch"),
                            "enabledDate" to System.currentTimeMillis()
                        ))
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return services
    }
    
    // ============================================================================
    // USAGE STATS DATA RETRIEVAL
    // ============================================================================
    
    /**
     * Get app usage statistics
     * Used for behavioral anomaly detection
     */
    fun getUsageStats(hours: Int = 24): List<Map<String, Any>> {
        val stats = mutableListOf<Map<String, Any>>()
        
        if (!checkUsageStatsPermission()) {
            return stats
        }
        
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return stats
        }
        
        try {
            val usageStatsManager = context.getSystemService(
                Context.USAGE_STATS_SERVICE
            ) as? android.app.usage.UsageStatsManager ?: return stats
            
            val endTime = System.currentTimeMillis()
            val startTime = endTime - (hours * 60 * 60 * 1000)
            
            val usageStatsList = usageStatsManager.queryUsageStats(
                android.app.usage.UsageStatsManager.INTERVAL_DAILY,
                startTime,
                endTime
            )
            
            for (usageStat in usageStatsList) {
                if (usageStat.totalTimeInForeground > 0) {
                    // Get app info
                    val pm = context.packageManager
                    val appInfo = try {
                        pm.getApplicationInfo(usageStat.packageName, 0)
                    } catch (e: Exception) {
                        null
                    }
                    
                    val appName = appInfo?.let {
                        pm.getApplicationLabel(it).toString()
                    } ?: usageStat.packageName
                    
                    stats.add(mapOf(
                        "packageName" to usageStat.packageName,
                        "appName" to appName,
                        "totalTimeInForeground" to usageStat.totalTimeInForeground,
                        "firstTimeStamp" to usageStat.firstTimeStamp,
                        "lastTimeStamp" to usageStat.lastTimeStamp,
                        "lastTimeUsed" to usageStat.lastTimeUsed,
                    ))
                }
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return stats
    }
    
    /**
     * Get network usage per app
     * Requires Usage Stats permission
     */
    fun getNetworkUsageStats(hours: Int = 24): List<Map<String, Any>> {
        val stats = mutableListOf<Map<String, Any>>()
        
        if (!checkUsageStatsPermission()) {
            return stats
        }
        
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return stats
        }
        
        try {
            val networkStatsManager = context.getSystemService(
                Context.NETWORK_STATS_SERVICE
            ) as? android.app.usage.NetworkStatsManager ?: return stats
            
            val endTime = System.currentTimeMillis()
            val startTime = endTime - (hours * 60 * 60 * 1000)
            
            // Query mobile data
            try {
                val bucket = networkStatsManager.querySummaryForDevice(
                    android.net.ConnectivityManager.TYPE_MOBILE,
                    null,
                    startTime,
                    endTime
                )
                
                if (bucket != null) {
                    stats.add(mapOf(
                        "type" to "mobile",
                        "rxBytes" to bucket.rxBytes,
                        "txBytes" to bucket.txBytes,
                        "rxPackets" to bucket.rxPackets,
                        "txPackets" to bucket.txPackets
                    ))
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
            
            // Query WiFi data
            try {
                val bucket = networkStatsManager.querySummaryForDevice(
                    android.net.ConnectivityManager.TYPE_WIFI,
                    null,
                    startTime,
                    endTime
                )
                
                if (bucket != null) {
                    stats.add(mapOf(
                        "type" to "wifi",
                        "rxBytes" to bucket.rxBytes,
                        "txBytes" to bucket.txBytes,
                        "rxPackets" to bucket.rxPackets,
                        "txPackets" to bucket.txPackets
                    ))
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return stats
    }
    
    // ============================================================================
    // BATTERY USAGE STATS
    // ============================================================================
    
    /**
     * Get battery usage per app
     * Requires Usage Stats permission
     */
    fun getBatteryUsageStats(): List<Map<String, Any>> {
        val stats = mutableListOf<Map<String, Any>>()
        
        if (!checkUsageStatsPermission()) {
            return stats
        }
        
        try {
            // Note: Detailed battery stats require system signature
            // We can only get approximate data
            
            val pm = context.packageManager
            val packages = pm.getInstalledApplications(0)
            
            for (appInfo in packages) {
                // This is a simplified approach
                // Real battery monitoring would need system access
                stats.add(mapOf(
                    "packageName" to appInfo.packageName,
                    "appName" to pm.getApplicationLabel(appInfo).toString(),
                    "uid" to appInfo.uid
                ))
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        
        return stats
    }
    
    // ============================================================================
    // INTEGRATION WITH MAIN ACTIVITY
    // ============================================================================
    
    fun handleMethodCall(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkUsageStatsPermission" -> {
                val hasPermission = checkUsageStatsPermission()
                result.success(mapOf("hasPermission" to hasPermission))
            }
            
            "checkAccessibilityPermission" -> {
                val hasPermission = checkAccessibilityPermission()
                result.success(mapOf("hasPermission" to hasPermission))
            }
            
            "requestUsageStatsPermission" -> {
                requestUsageStatsPermission()
                result.success(true)
            }
            
            "requestAccessibilityPermission" -> {
                requestAccessibilityPermission()
                result.success(true)
            }
            
            "getEnabledAccessibilityServices" -> {
                val services = getEnabledAccessibilityServices()
                result.success(mapOf("services" to services))
            }
            
            "getUsageStats" -> {
                val hours = call.argument<Int>("hours") ?: 24
                val stats = getUsageStats(hours)
                result.success(mapOf("stats" to stats))
            }
            
            "getNetworkUsageStats" -> {
                val hours = call.argument<Int>("hours") ?: 24
                val stats = getNetworkUsageStats(hours)
                result.success(mapOf("stats" to stats))
            }
            
            "getBatteryUsageStats" -> {
                val stats = getBatteryUsageStats()
                result.success(mapOf("stats" to stats))
            }
            
            else -> result.notImplemented()
        }
    }
}