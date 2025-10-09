// android/app/src/main/kotlin/com/orb/guard/PermissionHandler.kt
// Native Android code for special permission handling

package com.orb.guard

import android.app.Activity
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class PermissionHandler(
    private val activity: Activity,
    flutterEngine: FlutterEngine
) {
    companion object {
        private const val CHANNEL = "com.orb.guard/permissions"
    }

    init {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkUsageStatsPermission" -> {
                    result.success(hasUsageStatsPermission())
                }
                "openUsageStatsSettings" -> {
                    openUsageStatsSettings()
                    result.success(true)
                }
                "checkAccessibilityPermission" -> {
                    result.success(hasAccessibilityPermission())
                }
                "openAccessibilitySettings" -> {
                    openAccessibilitySettings()
                    result.success(true)
                }
                "checkNotificationListenerPermission" -> {
                    result.success(hasNotificationListenerPermission())
                }
                "openNotificationListenerSettings" -> {
                    openNotificationListenerSettings()
                    result.success(true)
                }
                "checkAllSpecialPermissions" -> {
                    result.success(mapOf(
                        "usageStats" to hasUsageStatsPermission(),
                        "accessibility" to hasAccessibilityPermission(),
                        "notificationListener" to hasNotificationListenerPermission()
                    ))
                }
                else -> result.notImplemented()
            }
        }
    }

    // ============================================================================
    // USAGE STATS PERMISSION
    // ============================================================================

    /**
     * Check if app has Usage Stats permission
     * Required for: Monitoring app behavior, detecting background activity
     */
    private fun hasUsageStatsPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            return false
        }

        val appOps = activity.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                activity.packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                activity.packageName
            )
        }

        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Open Usage Stats settings page
     */
    private fun openUsageStatsSettings() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            
            // Try to go directly to our app
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                intent.data = Uri.parse("package:${activity.packageName}")
            }
            
            activity.startActivity(intent)
        } catch (e: Exception) {
            // Fallback to general settings
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            activity.startActivity(intent)
        }
    }

    // ============================================================================
    // ACCESSIBILITY PERMISSION
    // ============================================================================

    /**
     * Check if app has Accessibility service enabled
     * Required for: Detecting malicious accessibility services
     */
    private fun hasAccessibilityPermission(): Boolean {
        val enabledServices = Settings.Secure.getString(
            activity.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val packageName = activity.packageName
        return enabledServices.contains(packageName)
    }

    /**
     * Open Accessibility settings page
     */
    private fun openAccessibilitySettings() {
        try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            activity.startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ============================================================================
    // NOTIFICATION LISTENER PERMISSION
    // ============================================================================

    /**
     * Check if app has Notification Listener permission
     * Required for: Detecting notification-based threats
     */
    private fun hasNotificationListenerPermission(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            activity.contentResolver,
            "enabled_notification_listeners"
        ) ?: return false

        val packageName = activity.packageName
        return enabledListeners.contains(packageName)
    }

    /**
     * Open Notification Listener settings page
     */
    private fun openNotificationListenerSettings() {
        try {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            activity.startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    // ============================================================================
    // HELPER METHODS
    // ============================================================================

    /**
     * Get detailed permission explanation for UI
     */
    fun getPermissionExplanation(permissionType: String): Map<String, String> {
        return when (permissionType) {
            "usageStats" -> mapOf(
                "title" to "Usage Stats Access",
                "description" to "Allows monitoring of app behavior patterns and background activity",
                "reason" to "Critical for detecting data exfiltration and suspicious app behavior",
                "required" to "true"
            )
            "accessibility" -> mapOf(
                "title" to "Accessibility Service",
                "description" to "Enables detection of malicious accessibility services",
                "reason" to "Spyware often abuses accessibility features to read screen content",
                "required" to "false"
            )
            "notificationListener" -> mapOf(
                "title" to "Notification Access",
                "description" to "Monitors notifications for suspicious patterns",
                "reason" to "Helps detect notification-based threats and phishing",
                "required" to "false"
            )
            else -> mapOf("error" to "Unknown permission type")
        }
    }

    /**
     * Check if device supports the permission
     */
    fun isPermissionSupported(permissionType: String): Boolean {
        return when (permissionType) {
            "usageStats" -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP
            "accessibility" -> true
            "notificationListener" -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR2
            else -> false
        }
    }
}

// ============================================================================
// EXTENSION FUNCTIONS
// ============================================================================

/**
 * Extension to MainActivity for easier permission handling
 */
fun Activity.requestSpecialPermission(type: String): Boolean {
    return when (type) {
        "usageStats" -> {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            startActivity(intent)
            true
        }
        "accessibility" -> {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
            startActivity(intent)
            true
        }
        "overlay" -> {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
                true
            } else {
                false
            }
        }
        else -> false
    }
}

/**
 * Check if app can draw overlays (for threat alerts)
 */
fun Context.canDrawOverlays(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        Settings.canDrawOverlays(this)
    } else {
        true
    }
}