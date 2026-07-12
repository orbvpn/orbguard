// SystemMetricsHandler.kt
// Real device-metric implementations for the com.orb.guard/system channel.
//
// Consumed by:
//   - lib/detection/advanced_detection_modules.dart
//       getBatteryDrain, getCPUUsage, getNetworkActivity, getScreenOnTime,
//       getBackgroundProcessCount, getDataUsage, getAppInfo, detectIMEAbuse,
//       checkSuspiciousRootBinaries, checkModifiedSystemFiles,
//       checkBackgroundPermissionUsage, getLocationAccessHistory
//   - lib/detection/enhanced_behavioral_detector.dart
//       getUsageStats, getNetworkUsageStats
//   - lib/providers/forensics_provider.dart (log analysis pipeline)
//       captureLogs
//
// Honesty contract: every capability that Android genuinely does not expose
// to third-party apps returns an explicit error (UNAVAILABLE /
// PERMISSION_REQUIRED) with a human-readable reason — never zeroed or
// fabricated values presented as a clean result. Partial data is flagged with
// scope/limitation fields.

package com.orb.guard

import android.app.ActivityManager
import android.app.AppOpsManager
import android.app.usage.NetworkStatsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import android.system.Os
import android.system.OsConstants
import android.util.Log
import android.view.inputmethod.InputMethodManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class SystemMetricsHandler(
    private val context: Context,
    private val rootAccess: RootAccess?
) {

    companion object {
        private const val TAG = "OrbGuard.Metrics"
        private const val MAX_LOG_LINES = 2000
        private const val DEFAULT_LOG_LINES = 500
    }

    private val packageManager: PackageManager get() = context.packageManager

    /**
     * Dispatches a method call. Returns true when the method belongs to this
     * handler (the result has been or will be completed), false otherwise.
     */
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "getBatteryDrain" -> getBatteryDrain(result)
            "getCPUUsage" -> getCpuUsage(result)
            "getNetworkActivity" -> getNetworkActivity(result)
            "getScreenOnTime" -> getScreenOnTime(result)
            "getBackgroundProcessCount" -> getBackgroundProcessCount(result)
            "getDataUsage" -> getDataUsage(result)
            "getUsageStats" -> getUsageStats(call.argument<Int>("hours") ?: 24, result)
            "getNetworkUsageStats" -> getNetworkUsageStats(call.argument<Int>("hours") ?: 24, result)
            "getPerAppNetworkUsage" -> getPerAppNetworkUsage(call.argument<Int>("hours") ?: 24, result)
            "getAppInfo" -> getAppInfo(call.argument<String>("packageName"), result)
            "detectIMEAbuse" -> detectImeAbuse(result)
            "checkSuspiciousRootBinaries" -> checkSuspiciousRootBinaries(result)
            "checkModifiedSystemFiles" -> checkModifiedSystemFiles(result)
            "checkBackgroundPermissionUsage" -> {
                // Android exposes other apps' permission/op usage only to the
                // system (privacy dashboard). There is no public API; saying
                // so is the only honest answer.
                result.error(
                    "UNAVAILABLE",
                    "Android does not expose other apps' background permission usage to third-party apps; privacy-dashboard data is system-only",
                    mapOf("capability" to "background_permission_usage", "platform_limit" to true)
                )
            }
            "getLocationAccessHistory" -> {
                // AppOpsManager historical ops (location access timeline) are
                // @SystemApi; normal apps cannot query them.
                result.error(
                    "UNAVAILABLE",
                    "Per-app location access history requires the system-only AppOpsManager historical API; not available to third-party apps",
                    mapOf("capability" to "location_access_history", "platform_limit" to true)
                )
            }
            "captureLogs" -> captureLogs(
                call.argument<Int>("lines"),
                call.argument<Int>("seconds"),
                result
            )
            else -> return false
        }
        return true
    }

    // ------------------------------------------------------------------
    // Permission helpers
    // ------------------------------------------------------------------

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    private fun usagePermissionError(result: MethodChannel.Result, capability: String) {
        result.error(
            "PERMISSION_REQUIRED",
            "PACKAGE_USAGE_STATS (Usage Access) permission is required for $capability",
            mapOf(
                "permission" to "android.permission.PACKAGE_USAGE_STATS",
                "settings_action" to Settings.ACTION_USAGE_ACCESS_SETTINGS,
                "capability" to capability
            )
        )
    }

    // ------------------------------------------------------------------
    // Battery (BatteryManager)
    // ------------------------------------------------------------------

    private fun getBatteryDrain(result: MethodChannel.Result) {
        try {
            val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
            val currentNowUa = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
            val chargeCounterUah = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
            val capacityPct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

            val sticky = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val status = sticky?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
            val temperatureC = sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                ?.takeIf { it != Int.MIN_VALUE }?.let { it / 10.0 }
            val voltageMv = sticky?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, Int.MIN_VALUE)
                ?.takeIf { it != Int.MIN_VALUE }

            val currentValid = currentNowUa != Int.MIN_VALUE && currentNowUa != 0
            val counterValid = chargeCounterUah != Int.MIN_VALUE && chargeCounterUah > 0
            val capacityValid = capacityPct in 1..100

            if (!currentValid || !counterValid || !capacityValid) {
                result.error(
                    "UNAVAILABLE",
                    "This device's fuel gauge does not report the properties needed to compute a drain rate",
                    mapOf(
                        "current_now_ua" to currentNowUa,
                        "charge_counter_uah" to chargeCounterUah,
                        "capacity_pct" to capacityPct,
                        "is_charging" to isCharging
                    )
                )
                return
            }

            // Estimate full-charge capacity from the current charge counter and
            // percentage, then express instantaneous current as %/hour.
            val estimatedFullUah = chargeCounterUah * 100.0 / capacityPct
            val drainPctPerHour = kotlin.math.abs(currentNowUa.toDouble()) / estimatedFullUah * 100.0

            result.success(
                mapOf(
                    "drainRate" to drainPctPerHour,
                    "is_charging" to isCharging,
                    "current_now_ua" to currentNowUa,
                    "charge_counter_uah" to chargeCounterUah,
                    "capacity_pct" to capacityPct,
                    "estimated_full_uah" to estimatedFullUah,
                    "temperature_c" to temperatureC,
                    "voltage_mv" to voltageMv,
                    "method" to "battery_manager_instantaneous_current"
                )
            )
        } catch (e: Exception) {
            Log.e(TAG, "getBatteryDrain failed", e)
            result.error("NATIVE_ERROR", "Battery stats read failed: ${e.message}", null)
        }
    }

    // ------------------------------------------------------------------
    // CPU (own process — /proc/stat is inaccessible to apps since Android 8)
    // ------------------------------------------------------------------

    private fun readSelfCpuTicks(): Long {
        val stat = File("/proc/self/stat").readText()
        // comm (field 2) may contain spaces/parens; fields resume after ')'.
        val close = stat.lastIndexOf(')')
        val fields = stat.substring(close + 2).trim().split(" ")
        val utime = fields[11].toLong() // overall field 14
        val stime = fields[12].toLong() // overall field 15
        return utime + stime
    }

    private fun getCpuUsage(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val clkTck = try {
                    Os.sysconf(OsConstants._SC_CLK_TCK).toDouble()
                } catch (e: Exception) {
                    100.0
                }
                val startTicks = readSelfCpuTicks()
                val startMs = SystemClock.elapsedRealtime()
                delay(400)
                val deltaTicks = readSelfCpuTicks() - startTicks
                val elapsedSec = (SystemClock.elapsedRealtime() - startMs) / 1000.0
                val percentage = if (elapsedSec > 0) {
                    (deltaTicks / clkTck) / elapsedSec * 100.0
                } else {
                    0.0
                }
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "percentage" to percentage,
                            "scope" to "app_process",
                            "cores" to Runtime.getRuntime().availableProcessors(),
                            "sample_ms" to (elapsedSec * 1000).toLong(),
                            "note" to "System-wide CPU usage (/proc/stat) is not readable by apps since Android 8; this is this app's own process usage as % of one core"
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "getCPUUsage failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "CPU sample failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Instantaneous network throughput (TrafficStats, device-wide)
    // ------------------------------------------------------------------

    private fun getNetworkActivity(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                var scope = "device"
                var startRx = TrafficStats.getTotalRxBytes()
                var startTx = TrafficStats.getTotalTxBytes()
                if (startRx == TrafficStats.UNSUPPORTED.toLong() ||
                    startTx == TrafficStats.UNSUPPORTED.toLong()
                ) {
                    // Some OEM kernels do not expose device totals; fall back
                    // to own-UID counters and say so.
                    scope = "app_uid"
                    startRx = TrafficStats.getUidRxBytes(Process.myUid())
                    startTx = TrafficStats.getUidTxBytes(Process.myUid())
                }
                if (startRx == TrafficStats.UNSUPPORTED.toLong() ||
                    startTx == TrafficStats.UNSUPPORTED.toLong()
                ) {
                    withContext(Dispatchers.Main) {
                        result.error(
                            "UNAVAILABLE",
                            "TrafficStats counters are not supported on this kernel",
                            mapOf("capability" to "network_activity")
                        )
                    }
                    return@launch
                }

                val startMs = SystemClock.elapsedRealtime()
                delay(500)
                val endRx: Long
                val endTx: Long
                if (scope == "device") {
                    endRx = TrafficStats.getTotalRxBytes()
                    endTx = TrafficStats.getTotalTxBytes()
                } else {
                    endRx = TrafficStats.getUidRxBytes(Process.myUid())
                    endTx = TrafficStats.getUidTxBytes(Process.myUid())
                }
                val elapsedSec = (SystemClock.elapsedRealtime() - startMs) / 1000.0
                val bytesPerSecond = if (elapsedSec > 0) {
                    ((endRx - startRx) + (endTx - startTx)) / elapsedSec
                } else {
                    0.0
                }

                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "bytesPerSecond" to bytesPerSecond,
                            "rx_bytes_delta" to (endRx - startRx),
                            "tx_bytes_delta" to (endTx - startTx),
                            "sample_ms" to (elapsedSec * 1000).toLong(),
                            "scope" to scope
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "getNetworkActivity failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Network activity sample failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Screen-on time (UsageStatsManager events, API 28+)
    // ------------------------------------------------------------------

    private fun getScreenOnTime(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            result.error(
                "UNAVAILABLE",
                "Screen interactive events require Android 9 (API 28) or newer",
                mapOf("capability" to "screen_on_time", "min_api" to 28)
            )
            return
        }
        if (!hasUsageStatsPermission()) {
            usagePermissionError(result, "screen-on time")
            return
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val end = System.currentTimeMillis()
                val start = end - 24L * 60 * 60 * 1000
                val events = usm.queryEvents(start, end)

                var screenOnMs = 0L
                var lastOnTs = -1L
                var sawAnyEvent = false
                var sawAnyOn = false
                val event = UsageEvents.Event()
                while (events.hasNextEvent()) {
                    events.getNextEvent(event)
                    when (event.eventType) {
                        UsageEvents.Event.SCREEN_INTERACTIVE -> {
                            sawAnyEvent = true
                            sawAnyOn = true
                            if (lastOnTs < 0) lastOnTs = event.timeStamp
                        }
                        UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                            sawAnyEvent = true
                            if (lastOnTs >= 0) {
                                screenOnMs += event.timeStamp - lastOnTs
                                lastOnTs = -1L
                            } else if (!sawAnyOn) {
                                // Screen was already on when the window began.
                                screenOnMs += event.timeStamp - start
                            }
                        }
                    }
                }
                if (lastOnTs >= 0) {
                    // Screen still on now.
                    screenOnMs += end - lastOnTs
                }

                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "minutes" to screenOnMs / 60000.0,
                            "window_hours" to 24,
                            "events_seen" to sawAnyEvent,
                            "method" to "usage_events_screen_interactive"
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "getScreenOnTime failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Screen-on time query failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Background process count
    // ------------------------------------------------------------------

    private fun getBackgroundProcessCount(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                // With shell/root access we can genuinely enumerate processes.
                if (rootAccess?.hasRootAccess() == true) {
                    val psOutput = rootAccess.getProcessList()
                    if (!psOutput.isNullOrBlank()) {
                        val lines = psOutput.lines().filter { it.isNotBlank() }
                        // First line is the ps header.
                        val count = (lines.size - 1).coerceAtLeast(0)
                        withContext(Dispatchers.Main) {
                            result.success(
                                mapOf(
                                    "count" to count,
                                    "scope" to "system",
                                    "visibility_limited" to false,
                                    "method" to "shell_ps"
                                )
                            )
                        }
                        return@launch
                    }
                }

                // Without elevated access, Android (API 22+) only reveals this
                // app's own processes via ActivityManager. Return what is
                // genuinely visible and flag the limitation explicitly.
                val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
                val processes = am.runningAppProcesses ?: emptyList()
                val backgroundCount = processes.count {
                    it.importance != ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
                }
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "count" to backgroundCount,
                            "visible_processes" to processes.size,
                            "scope" to "app_process",
                            "visibility_limited" to true,
                            "note" to "Android 5.1+ restricts process enumeration to the calling app; system-wide counts require shell/root access"
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "getBackgroundProcessCount failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Process count failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Data usage (NetworkStatsManager — requires Usage Access)
    // ------------------------------------------------------------------

    @Suppress("DEPRECATION")
    private fun deviceNetworkTotals(startMs: Long, endMs: Long): List<Map<String, Any>> {
        val nsm = context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager
        val totals = mutableListOf<Map<String, Any>>()
        val types = listOf(
            "wifi" to ConnectivityManager.TYPE_WIFI,
            "mobile" to ConnectivityManager.TYPE_MOBILE
        )
        for ((label, type) in types) {
            try {
                val bucket = nsm.querySummaryForDevice(type, null, startMs, endMs)
                if (bucket != null) {
                    totals.add(
                        mapOf(
                            "type" to label,
                            "rxBytes" to bucket.rxBytes,
                            "txBytes" to bucket.txBytes
                        )
                    )
                }
            } catch (e: Exception) {
                // e.g. no telephony on Wi-Fi-only tablets — skip honestly.
                Log.d(TAG, "Network summary for $label unavailable: ${e.message}")
            }
        }
        return totals
    }

    private fun getDataUsage(result: MethodChannel.Result) {
        if (!hasUsageStatsPermission()) {
            usagePermissionError(result, "device data usage")
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val end = System.currentTimeMillis()
                val start = end - 24L * 60 * 60 * 1000
                val totals = deviceNetworkTotals(start, end)
                if (totals.isEmpty()) {
                    withContext(Dispatchers.Main) {
                        result.error(
                            "UNAVAILABLE",
                            "NetworkStatsManager returned no buckets for the last 24h",
                            mapOf("capability" to "data_usage")
                        )
                    }
                    return@launch
                }
                val totalBytes = totals.sumOf {
                    (it["rxBytes"] as Long) + (it["txBytes"] as Long)
                }
                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "megabytes" to totalBytes / (1024.0 * 1024.0),
                            "window_hours" to 24,
                            "breakdown" to totals,
                            "method" to "network_stats_manager_device_summary"
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "getDataUsage failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Data usage query failed: ${e.message}", null)
                }
            }
        }
    }

    private fun getNetworkUsageStats(hours: Int, result: MethodChannel.Result) {
        if (!hasUsageStatsPermission()) {
            usagePermissionError(result, "network usage statistics")
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val end = System.currentTimeMillis()
                val start = end - hours.coerceIn(1, 24 * 30).toLong() * 60 * 60 * 1000
                val totals = deviceNetworkTotals(start, end)
                withContext(Dispatchers.Main) {
                    result.success(mapOf("stats" to totals, "window_hours" to hours))
                }
            } catch (e: Exception) {
                Log.e(TAG, "getNetworkUsageStats failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Network usage query failed: ${e.message}", null)
                }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getPerAppNetworkUsage(hours: Int, result: MethodChannel.Result) {
        if (!hasUsageStatsPermission()) {
            usagePermissionError(result, "per-app network usage")
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val nsm = context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager
                val end = System.currentTimeMillis()
                val start = end - hours.coerceIn(1, 24 * 30).toLong() * 60 * 60 * 1000

                // uid -> (rx, tx)
                val perUid = HashMap<Int, LongArray>()
                for (type in listOf(ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE)) {
                    try {
                        val stats = nsm.querySummary(type, null, start, end)
                        val bucket = android.app.usage.NetworkStats.Bucket()
                        while (stats.hasNextBucket()) {
                            stats.getNextBucket(bucket)
                            val entry = perUid.getOrPut(bucket.uid) { longArrayOf(0L, 0L) }
                            entry[0] += bucket.rxBytes
                            entry[1] += bucket.txBytes
                        }
                        stats.close()
                    } catch (e: Exception) {
                        Log.d(TAG, "querySummary for type $type unavailable: ${e.message}")
                    }
                }

                val apps = perUid.entries.map { (uid, bytes) ->
                    val packages = try {
                        packageManager.getPackagesForUid(uid)?.toList() ?: emptyList()
                    } catch (e: Exception) {
                        emptyList()
                    }
                    mapOf(
                        "uid" to uid,
                        "package_names" to packages,
                        "rx_bytes" to bytes[0],
                        "tx_bytes" to bytes[1]
                    )
                }.sortedByDescending { (it["rx_bytes"] as Long) + (it["tx_bytes"] as Long) }

                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "apps" to apps,
                            "window_hours" to hours,
                            "note" to "Special UIDs (-4 removed, -5 tethering, 1000 system) have no package mapping"
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "getPerAppNetworkUsage failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Per-app network usage failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Per-app usage stats (UsageStatsManager — requires Usage Access)
    // ------------------------------------------------------------------

    private fun getUsageStats(hours: Int, result: MethodChannel.Result) {
        if (!hasUsageStatsPermission()) {
            usagePermissionError(result, "app usage statistics")
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val end = System.currentTimeMillis()
                val start = end - hours.coerceIn(1, 24 * 30).toLong() * 60 * 60 * 1000
                val rawStats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
                    ?: emptyList()

                // Multiple buckets can exist per package; merge them.
                data class Agg(var foregroundMs: Long, var lastUsed: Long)

                val merged = HashMap<String, Agg>()
                for (s in rawStats) {
                    val agg = merged.getOrPut(s.packageName) { Agg(0L, 0L) }
                    agg.foregroundMs += s.totalTimeInForeground
                    if (s.lastTimeUsed > agg.lastUsed) agg.lastUsed = s.lastTimeUsed
                }

                val stats = merged.entries
                    .filter { it.value.foregroundMs > 0 }
                    .map { (pkg, agg) ->
                        val appName = try {
                            packageManager.getApplicationInfo(pkg, 0)
                                .loadLabel(packageManager).toString()
                        } catch (e: Exception) {
                            pkg
                        }
                        mapOf(
                            "packageName" to pkg,
                            "appName" to appName,
                            "totalTimeInForeground" to agg.foregroundMs,
                            "lastTimeUsed" to agg.lastUsed
                        )
                    }
                    .sortedByDescending { it["totalTimeInForeground"] as Long }

                withContext(Dispatchers.Main) {
                    result.success(mapOf("stats" to stats, "window_hours" to hours))
                }
            } catch (e: Exception) {
                Log.e(TAG, "getUsageStats failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Usage stats query failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // App info
    // ------------------------------------------------------------------

    private fun getAppInfo(packageName: String?, result: MethodChannel.Result) {
        if (packageName.isNullOrEmpty()) {
            result.error("BAD_ARGS", "packageName argument is required", null)
            return
        }
        try {
            val pkgInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
            }
            val appInfo = pkgInfo.applicationInfo
            val isSystemApp = appInfo != null &&
                (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            val installer = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    packageManager.getInstallSourceInfo(packageName).installingPackageName
                } else {
                    @Suppress("DEPRECATION")
                    packageManager.getInstallerPackageName(packageName)
                }
            } catch (e: Exception) {
                null
            }

            result.success(
                mapOf(
                    "appName" to (appInfo?.loadLabel(packageManager)?.toString() ?: packageName),
                    "packageName" to packageName,
                    "versionName" to (pkgInfo.versionName ?: "unknown"),
                    "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                        pkgInfo.longVersionCode
                    } else {
                        @Suppress("DEPRECATION")
                        pkgInfo.versionCode.toLong()
                    },
                    "isSystemApp" to isSystemApp,
                    "installerPackage" to (installer ?: "unknown"),
                    "firstInstallTime" to pkgInfo.firstInstallTime,
                    "lastUpdateTime" to pkgInfo.lastUpdateTime,
                    "targetSdkVersion" to (appInfo?.targetSdkVersion ?: 0),
                    "enabled" to (appInfo?.enabled ?: false),
                    "permissions" to (pkgInfo.requestedPermissions?.toList() ?: emptyList<String>())
                )
            )
        } catch (e: PackageManager.NameNotFoundException) {
            result.error("NOT_FOUND", "Package not installed: $packageName", null)
        } catch (e: Exception) {
            Log.e(TAG, "getAppInfo failed for $packageName", e)
            result.error("NATIVE_ERROR", "App info read failed: ${e.message}", null)
        }
    }

    // ------------------------------------------------------------------
    // IME (keyboard) abuse detection
    // ------------------------------------------------------------------

    private fun detectImeAbuse(result: MethodChannel.Result) {
        try {
            val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
            val enabledImes = imm.enabledInputMethodList
            val defaultIme = Settings.Secure.getString(
                context.contentResolver, Settings.Secure.DEFAULT_INPUT_METHOD
            )

            val threats = mutableListOf<Map<String, Any?>>()
            for (ime in enabledImes) {
                val pkg = ime.packageName
                val appInfo = try {
                    packageManager.getApplicationInfo(pkg, 0)
                } catch (e: Exception) {
                    continue
                }
                val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
                    (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
                if (isSystem) continue

                val perms = try {
                    val pi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        packageManager.getPackageInfo(
                            pkg,
                            PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong())
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        packageManager.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS)
                    }
                    pi.requestedPermissions?.toList() ?: emptyList()
                } catch (e: Exception) {
                    emptyList()
                }

                val hasInternet = perms.contains("android.permission.INTERNET")
                if (!hasInternet) continue

                val isDefault = ime.id == defaultIme
                val appName = appInfo.loadLabel(packageManager).toString()
                threats.add(
                    mapOf(
                        "id" to "ime_abuse_$pkg",
                        "name" to "Third-Party Keyboard With Network Access",
                        "description" to "Enabled non-system input method \"$appName\" can transmit keystrokes (INTERNET permission)" +
                            if (isDefault) " and is the ACTIVE default keyboard" else "",
                        "severity" to if (isDefault) "CRITICAL" else "HIGH",
                        "type" to "keylogger",
                        "path" to pkg,
                        "requiresRoot" to false,
                        "metadata" to mapOf(
                            "packageName" to pkg,
                            "appName" to appName,
                            "imeId" to ime.id,
                            "isDefault" to isDefault,
                            "permissions" to perms.map { it.removePrefix("android.permission.") }
                        )
                    )
                )
            }
            result.success(mapOf("threats" to threats))
        } catch (e: Exception) {
            Log.e(TAG, "detectIMEAbuse failed", e)
            result.error("NATIVE_ERROR", "IME abuse detection failed: ${e.message}", null)
        }
    }

    // ------------------------------------------------------------------
    // Root / system-modification indicators (real file & property checks)
    // ------------------------------------------------------------------

    private fun checkSuspiciousRootBinaries(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val suspiciousPaths = listOf(
                    "/system/xbin/su" to "su binary in /system/xbin",
                    "/system/bin/su" to "su binary in /system/bin",
                    "/sbin/su" to "su binary in /sbin",
                    "/vendor/bin/su" to "su binary in /vendor/bin",
                    "/system/bin/.ext/su" to "hidden su binary",
                    "/system/usr/we-need-root/su" to "hidden su binary",
                    "/system/xbin/daemonsu" to "SuperSU daemon",
                    "/system/xbin/busybox" to "busybox in /system/xbin",
                    "/sbin/.magisk" to "Magisk runtime directory",
                    "/cache/.disable_magisk" to "Magisk artifact",
                    "/dev/.magisk.unblock" to "Magisk artifact",
                    "/system/app/Superuser.apk" to "Superuser management app",
                    "/system/app/SuperSU.apk" to "SuperSU management app"
                )

                val threats = mutableListOf<Map<String, Any?>>()
                for ((path, label) in suspiciousPaths) {
                    val exists = try {
                        File(path).exists()
                    } catch (e: SecurityException) {
                        false
                    }
                    if (exists) {
                        threats.add(
                            mapOf(
                                "id" to "rootbin_${path.replace('/', '_')}",
                                "name" to "Root Artifact Detected",
                                "description" to "$label found at $path",
                                "severity" to "HIGH",
                                "type" to "rooting",
                                "path" to path,
                                "requiresRoot" to true,
                                "metadata" to mapOf("artifact" to label)
                            )
                        )
                    }
                }
                withContext(Dispatchers.Main) {
                    result.success(mapOf("threats" to threats, "paths_checked" to suspiciousPaths.size))
                }
            } catch (e: Exception) {
                Log.e(TAG, "checkSuspiciousRootBinaries failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Root binary check failed: ${e.message}", null)
                }
            }
        }
    }

    private fun readSystemProperty(name: String): String? {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("getprop", name))
            val value = process.inputStream.bufferedReader().readText().trim()
            process.waitFor()
            value.ifEmpty { null }
        } catch (e: Exception) {
            null
        }
    }

    private fun checkModifiedSystemFiles(result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val threats = mutableListOf<Map<String, Any?>>()

                if (Build.TAGS?.contains("test-keys") == true) {
                    threats.add(
                        mapOf(
                            "id" to "sysmod_test_keys",
                            "name" to "Custom Firmware Signature",
                            "description" to "System image is signed with test-keys (custom/modified ROM)",
                            "severity" to "MEDIUM",
                            "type" to "system_modification",
                            "path" to "ro.build.tags",
                            "requiresRoot" to false,
                            "metadata" to mapOf("build_tags" to Build.TAGS)
                        )
                    )
                }

                if (readSystemProperty("ro.debuggable") == "1") {
                    threats.add(
                        mapOf(
                            "id" to "sysmod_debuggable",
                            "name" to "Debuggable System Build",
                            "description" to "ro.debuggable=1: the OS allows debugging of any app (userdebug/eng build)",
                            "severity" to "MEDIUM",
                            "type" to "system_modification",
                            "path" to "ro.debuggable",
                            "requiresRoot" to false,
                            "metadata" to emptyMap<String, Any>()
                        )
                    )
                }

                if (readSystemProperty("ro.secure") == "0") {
                    threats.add(
                        mapOf(
                            "id" to "sysmod_insecure",
                            "name" to "Insecure ADB Root",
                            "description" to "ro.secure=0: adbd runs as root on this build",
                            "severity" to "HIGH",
                            "type" to "system_modification",
                            "path" to "ro.secure",
                            "requiresRoot" to false,
                            "metadata" to emptyMap<String, Any>()
                        )
                    )
                }

                if (try { File("/system").canWrite() } catch (e: Exception) { false }) {
                    threats.add(
                        mapOf(
                            "id" to "sysmod_system_writable",
                            "name" to "Writable /system Partition",
                            "description" to "/system is writable by this app — the partition has been remounted read-write",
                            "severity" to "CRITICAL",
                            "type" to "system_modification",
                            "path" to "/system",
                            "requiresRoot" to false,
                            "metadata" to emptyMap<String, Any>()
                        )
                    )
                }

                val frameworkArtifacts = listOf(
                    "/system/framework/XposedBridge.jar" to "Xposed framework (runtime code hooking)",
                    "/system/lib/libxposed_art.so" to "Xposed ART hook library",
                    "/system/lib64/libxposed_art.so" to "Xposed ART hook library (64-bit)",
                    "/system/bin/app_process_xposed" to "Xposed app_process replacement"
                )
                for ((path, label) in frameworkArtifacts) {
                    val exists = try { File(path).exists() } catch (e: SecurityException) { false }
                    if (exists) {
                        threats.add(
                            mapOf(
                                "id" to "sysmod_${path.replace('/', '_')}",
                                "name" to "Code-Hooking Framework Detected",
                                "description" to "$label found at $path",
                                "severity" to "HIGH",
                                "type" to "system_modification",
                                "path" to path,
                                "requiresRoot" to true,
                                "metadata" to mapOf("artifact" to label)
                            )
                        )
                    }
                }

                // /etc/hosts hijacking: a stock hosts file is ~25 bytes
                // (localhost entries only). A large file indicates redirection
                // rules were installed.
                try {
                    val hosts = File("/system/etc/hosts")
                    if (hosts.canRead() && hosts.length() > 1024) {
                        threats.add(
                            mapOf(
                                "id" to "sysmod_hosts_modified",
                                "name" to "Modified Hosts File",
                                "description" to "/system/etc/hosts is ${hosts.length()} bytes (stock is ~25 bytes); DNS redirection rules are installed",
                                "severity" to "MEDIUM",
                                "type" to "system_modification",
                                "path" to "/system/etc/hosts",
                                "requiresRoot" to true,
                                "metadata" to mapOf("size_bytes" to hosts.length())
                            )
                        )
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "hosts file not readable: ${e.message}")
                }

                withContext(Dispatchers.Main) {
                    result.success(mapOf("threats" to threats))
                }
            } catch (e: Exception) {
                Log.e(TAG, "checkModifiedSystemFiles failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "System file check failed: ${e.message}", null)
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Logcat capture (own-process scope; READ_LOGS is privileged)
    // ------------------------------------------------------------------

    private fun captureLogs(lines: Int?, seconds: Int?, result: MethodChannel.Result) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val lineCap = (lines ?: DEFAULT_LOG_LINES).coerceIn(1, MAX_LOG_LINES)
                val pid = Process.myPid()

                val cmd = mutableListOf("logcat", "-d", "-v", "threadtime")
                // --pid is supported from API 24 and scopes output to this
                // app's own process — readable without any permission.
                val pidFilterSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
                if (pidFilterSupported) {
                    cmd.add("--pid=$pid")
                }
                if (seconds != null && seconds > 0) {
                    // -T '<sectime>.0' replays from a point in time.
                    val sinceEpoch = (System.currentTimeMillis() / 1000) - seconds
                    cmd.add("-T")
                    cmd.add("$sinceEpoch.0")
                } else {
                    cmd.add("-t")
                    cmd.add(lineCap.toString())
                }

                val process = Runtime.getRuntime().exec(cmd.toTypedArray())
                var output = process.inputStream.bufferedReader().readText()
                val stderr = process.errorStream.bufferedReader().readText()
                process.waitFor()

                if (!pidFilterSupported) {
                    // Manual scoping for very old API levels.
                    output = output.lines()
                        .filter { it.contains(" $pid ") }
                        .joinToString("\n")
                }

                var resultLines = output.lines().filter { it.isNotBlank() }
                if (resultLines.size > lineCap) {
                    resultLines = resultLines.takeLast(lineCap)
                }

                if (resultLines.isEmpty() && stderr.isNotBlank()) {
                    withContext(Dispatchers.Main) {
                        result.error(
                            "CAPTURE_FAILED",
                            "logcat produced no output: ${stderr.take(300)}",
                            mapOf("scope" to "app_process")
                        )
                    }
                    return@launch
                }

                withContext(Dispatchers.Main) {
                    result.success(
                        mapOf(
                            "logs" to resultLines.joinToString("\n"),
                            "line_count" to resultLines.size,
                            "pid" to pid,
                            "scope" to "app_process",
                            "note" to "Full-device logs require the privileged READ_LOGS permission (system/ADB only); this capture covers OrbGuard's own process"
                        )
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "captureLogs failed", e)
                withContext(Dispatchers.Main) {
                    result.error("NATIVE_ERROR", "Log capture failed: ${e.message}", null)
                }
            }
        }
    }
}
