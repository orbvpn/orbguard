// BrowserMonitor.kt
// Browser URL monitoring and analysis bridge to Flutter

package com.orb.guard

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * BrowserMonitor - Manages browser URL monitoring and threat analysis
 */
class BrowserMonitor private constructor(private val context: Context) {

    companion object {
        private const val TAG = "OrbGuard.BrowserMonitor"
        private const val CHANNEL_NAME = "com.orb.guard/browser"
        private const val NOTIFICATION_CHANNEL_ID = "browser_threats"
        private const val NOTIFICATION_ID_BASE = 3000

        @Volatile
        private var instance: BrowserMonitor? = null

        fun getInstance(context: Context): BrowserMonitor {
            return instance ?: synchronized(this) {
                instance ?: BrowserMonitor(context.applicationContext).also { instance = it }
            }
        }
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // URL cache to avoid re-checking same URLs
    private val urlCache = ConcurrentHashMap<String, UrlAnalysisResult>()
    private val pendingUrls = ConcurrentHashMap<String, Long>()

    // Settings
    private var isProtectionEnabled = true
    private var notifyOnThreat = true
    private var blockDangerous = false

    // Whitelist/Blacklist
    private val whitelist = mutableSetOf<String>()
    private val blacklist = mutableSetOf<String>()

    /**
     * Set the Flutter method channel
     */
    fun setMethodChannel(channel: MethodChannel) {
        this.methodChannel = channel
        Log.d(TAG, "Method channel set")
    }

    /**
     * Update protection settings
     */
    fun updateSettings(
        protectionEnabled: Boolean,
        notifyOnThreat: Boolean,
        blockDangerous: Boolean
    ) {
        this.isProtectionEnabled = protectionEnabled
        this.notifyOnThreat = notifyOnThreat
        this.blockDangerous = blockDangerous
        Log.d(TAG, "Settings updated: protection=$protectionEnabled, notify=$notifyOnThreat, block=$blockDangerous")
    }

    /**
     * Analyze a URL from browser
     */
    fun analyzeUrl(url: String, browserName: String) {
        if (!isProtectionEnabled) return

        val domain = URLExtractor.extractDomain(url) ?: return

        // Check whitelist
        if (whitelist.contains(domain)) {
            Log.d(TAG, "URL whitelisted: $domain")
            return
        }

        // Check blacklist (immediate block)
        if (blacklist.contains(domain)) {
            Log.d(TAG, "URL blacklisted: $domain")
            handleThreat(url, UrlAnalysisResult(
                url = url,
                domain = domain,
                isThreat = true,
                threatLevel = "dangerous",
                riskScore = 0.9,
                categories = listOf("blacklisted"),
                reason = "Domain is blacklisted",
                shouldBlock = true
            ), browserName)
            return
        }

        // Check cache
        urlCache[url]?.let { cached ->
            if (cached.isThreat) {
                handleThreat(url, cached, browserName)
            }
            return
        }

        // Skip if already pending
        val now = System.currentTimeMillis()
        pendingUrls[url]?.let { lastCheck ->
            if (now - lastCheck < 5000) return
        }
        pendingUrls[url] = now

        // Send to Flutter for analysis
        mainHandler.post {
            methodChannel?.invokeMethod("analyzeUrl", mapOf(
                "url" to url,
                "domain" to domain,
                "browser" to browserName,
                "timestamp" to now
            ))
        }
    }

    /**
     * Called when analysis result is received from Flutter
     */
    fun onAnalysisResult(url: String, result: UrlAnalysisResult, browserName: String) {
        Log.d(TAG, "Analysis result for $url: ${result.threatLevel}")

        // Cache result
        urlCache[url] = result
        pendingUrls.remove(url)

        // Handle threat if detected
        if (result.isThreat) {
            handleThreat(url, result, browserName)
        }
    }

    private fun handleThreat(url: String, result: UrlAnalysisResult, browserName: String) {
        Log.w(TAG, "Threat detected: $url (${result.threatLevel})")

        // Show warning overlay
        if (result.threatLevel == "dangerous" || result.threatLevel == "critical") {
            BrowserAccessibilityService.getInstance()?.showWarningOverlay(
                url,
                UrlThreatInfo(
                    url = url,
                    isThreat = true,
                    threatLevel = result.threatLevel,
                    reason = result.reason,
                    categories = result.categories
                )
            )
        }

        // Show notification
        if (notifyOnThreat) {
            showThreatNotification(url, result, browserName)
        }

        // Notify Flutter
        mainHandler.post {
            methodChannel?.invokeMethod("onThreatDetected", mapOf(
                "url" to url,
                "domain" to result.domain,
                "threatLevel" to result.threatLevel,
                "riskScore" to result.riskScore,
                "categories" to result.categories,
                "reason" to result.reason,
                "browser" to browserName,
                "shouldBlock" to result.shouldBlock
            ))
        }
    }

    private fun showThreatNotification(url: String, result: UrlAnalysisResult, browserName: String) {
        createNotificationChannel()

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        intent?.putExtra("open_url_protection", true)
        intent?.putExtra("threat_url", url)

        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID_BASE + url.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = when (result.threatLevel) {
            "critical" -> "⛔ Critical Web Threat!"
            "dangerous" -> "🔴 Dangerous Website Detected!"
            "suspicious" -> "⚠️ Suspicious Website"
            else -> "Web Security Alert"
        }

        val body = buildString {
            append("Domain: ${result.domain}\n")
            append("Browser: $browserName\n")
            if (result.categories.isNotEmpty()) {
                append("Type: ${result.categories.joinToString(", ")}")
            }
        }

        val notification = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .build()

        val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID_BASE + url.hashCode(), notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Browser Threats",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts for detected web threats"
                enableVibration(true)
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * Add domain to whitelist
     */
    fun addToWhitelist(domain: String) {
        whitelist.add(domain.lowercase())
        urlCache.entries.removeIf { URLExtractor.extractDomain(it.key) == domain }
        Log.d(TAG, "Added to whitelist: $domain")
    }

    /**
     * Remove domain from whitelist
     */
    fun removeFromWhitelist(domain: String) {
        whitelist.remove(domain.lowercase())
        Log.d(TAG, "Removed from whitelist: $domain")
    }

    /**
     * Add domain to blacklist
     */
    fun addToBlacklist(domain: String) {
        blacklist.add(domain.lowercase())
        Log.d(TAG, "Added to blacklist: $domain")
    }

    /**
     * Remove domain from blacklist
     */
    fun removeFromBlacklist(domain: String) {
        blacklist.remove(domain.lowercase())
        Log.d(TAG, "Removed from blacklist: $domain")
    }

    /**
     * Get browsing history (analyzed URLs)
     */
    fun getAnalyzedUrls(): List<Map<String, Any?>> {
        return urlCache.entries.map { (url, result) ->
            mapOf(
                "url" to url,
                "domain" to result.domain,
                "isThreat" to result.isThreat,
                "threatLevel" to result.threatLevel,
                "riskScore" to result.riskScore,
                "categories" to result.categories
            )
        }
    }

    /**
     * Clear URL cache
     */
    fun clearCache() {
        urlCache.clear()
        pendingUrls.clear()
        Log.d(TAG, "Cache cleared")
    }

    /**
     * Get whitelist
     */
    fun getWhitelist(): List<String> = whitelist.toList()

    /**
     * Get blacklist
     */
    fun getBlacklist(): List<String> = blacklist.toList()
}

/**
 * URL analysis result data class
 */
data class UrlAnalysisResult(
    val url: String,
    val domain: String,
    val isThreat: Boolean,
    val threatLevel: String,
    val riskScore: Double,
    val categories: List<String>,
    val reason: String,
    val shouldBlock: Boolean = false
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): UrlAnalysisResult {
            return UrlAnalysisResult(
                url = map["url"] as? String ?: "",
                domain = map["domain"] as? String ?: "",
                isThreat = map["isThreat"] as? Boolean ?: false,
                threatLevel = map["threatLevel"] as? String ?: "safe",
                riskScore = (map["riskScore"] as? Number)?.toDouble() ?: 0.0,
                categories = (map["categories"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                reason = map["reason"] as? String ?: "",
                shouldBlock = map["shouldBlock"] as? Boolean ?: false
            )
        }
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "url" to url,
            "domain" to domain,
            "isThreat" to isThreat,
            "threatLevel" to threatLevel,
            "riskScore" to riskScore,
            "categories" to categories,
            "reason" to reason,
            "shouldBlock" to shouldBlock
        )
    }
}
