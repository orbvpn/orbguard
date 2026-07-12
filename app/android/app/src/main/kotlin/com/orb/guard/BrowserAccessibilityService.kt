package com.orb.guard

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

/**
 * Browser Accessibility Service for URL Monitoring
 *
 * Monitors browser URL bars to detect and warn about malicious URLs.
 * Supports: Chrome, Firefox, Samsung Browser, Edge, Opera, Brave, DuckDuckGo
 */
class BrowserAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "BrowserAccessibility"

        @Volatile
        private var instance: BrowserAccessibilityService? = null

        fun getInstance(): BrowserAccessibilityService? = instance

        private val BROWSER_PACKAGES = setOf(
            "com.android.chrome", "com.chrome.beta", "org.mozilla.firefox",
            "org.mozilla.fenix", "com.sec.android.app.sbrowser", "com.microsoft.emmx",
            "com.opera.browser", "com.brave.browser", "com.duckduckgo.mobile.android",
            "com.vivaldi.browser", "com.kiwibrowser.browser"
        )

        private val URL_BAR_IDS = mapOf(
            "com.android.chrome" to listOf("url_bar", "omnibox_url_field"),
            "org.mozilla.firefox" to listOf("url_bar_title", "mozac_browser_toolbar_url_view"),
            "org.mozilla.fenix" to listOf("mozac_browser_toolbar_url_view"),
            "com.sec.android.app.sbrowser" to listOf("location_bar_edit_text"),
            "com.microsoft.emmx" to listOf("url_bar"),
            "com.brave.browser" to listOf("url_bar", "omnibox_url_field"),
            "com.duckduckgo.mobile.android" to listOf("omnibarTextInput")
        )

        private val SUSPICIOUS_TLDS = setOf(
            ".xyz", ".tk", ".ml", ".ga", ".cf", ".gq", ".top", ".work",
            ".click", ".link", ".info", ".biz"
        )

        private val PHISHING_KEYWORDS = setOf(
            "login", "signin", "account", "verify", "secure", "update",
            "confirm", "banking", "password", "credential", "wallet"
        )

        private val SAFE_DOMAINS = setOf(
            "google.com", "facebook.com", "twitter.com", "instagram.com",
            "linkedin.com", "amazon.com", "apple.com", "microsoft.com",
            "github.com", "youtube.com", "netflix.com", "paypal.com"
        )
    }

    interface URLCheckCallback {
        fun onURLDetected(url: String, packageName: String)
        fun onMaliciousURL(url: String, threatType: String, riskScore: Float)
        fun onSafeURL(url: String)
    }

    private var callback: URLCheckCallback? = null
    private val urlCache = ConcurrentHashMap<String, URLCheckResult>()
    private val urlHistory = mutableListOf<URLHistoryEntry>()
    private var lastDetectedURL: String? = null
    private var lastDetectionTime: Long = 0
    private var isMonitoring = false

    data class URLCheckResult(
        val url: String, val isMalicious: Boolean, val threatType: String?,
        val riskScore: Float, val checkedAt: Long
    )

    data class URLHistoryEntry(
        val url: String, val domain: String, val packageName: String,
        val timestamp: Long, val isMalicious: Boolean, val threatType: String?
    )

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            packageNames = BROWSER_PACKAGES.toTypedArray()
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 100
        }
        serviceInfo = info
        isMonitoring = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !isMonitoring) return
        val packageName = event.packageName?.toString() ?: return
        if (packageName !in BROWSER_PACKAGES) return
        extractURLFromEvent(event, packageName)
    }

    private fun extractURLFromEvent(event: AccessibilityEvent, packageName: String) {
        try {
            val rootNode = rootInActiveWindow ?: return
            val urlBarIds = URL_BAR_IDS[packageName] ?: listOf("url_bar")
            for (urlBarId in urlBarIds) {
                val urlNodes = rootNode.findAccessibilityNodeInfosByViewId("\$packageName:id/\$urlBarId")
                if (urlNodes.isNotEmpty()) {
                    val urlText = urlNodes[0].text?.toString()
                    if (!urlText.isNullOrBlank()) {
                        processDetectedURL(urlText, packageName)
                        return
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error extracting URL: \${e.message}")
        }
    }

    private fun processDetectedURL(urlText: String, packageName: String) {
        val normalizedURL = normalizeURL(urlText) ?: return
        val now = System.currentTimeMillis()
        if (normalizedURL == lastDetectedURL && (now - lastDetectionTime) < 1000) return
        lastDetectedURL = normalizedURL
        lastDetectionTime = now
        callback?.onURLDetected(normalizedURL, packageName)
        checkURLSafety(normalizedURL, packageName)
    }

    private fun normalizeURL(urlText: String): String? {
        var url = urlText.trim()
        if (!url.startsWith("http://") && !url.startsWith("https://")) {
            url = "https://\$url"
        }
        return try {
            val parsed = URL(url)
            "\${parsed.protocol}://\${parsed.host}\${parsed.path}"
        } catch (e: Exception) { null }
    }

    private fun checkURLSafety(url: String, packageName: String) {
        val cached = urlCache[url]
        if (cached != null && (System.currentTimeMillis() - cached.checkedAt) < 300000) {
            handleCheckResult(cached, packageName)
            return
        }
        val result = analyzeURLLocally(url)
        urlCache[url] = result
        handleCheckResult(result, packageName)
    }

    private fun analyzeURLLocally(url: String): URLCheckResult {
        try {
            val parsed = URL(url)
            val host = parsed.host.lowercase()
            var riskScore = 0f
            val threatTypes = mutableListOf<String>()

            if (SAFE_DOMAINS.any { host == it || host.endsWith(".\$it") }) {
                return URLCheckResult(url, false, null, 0f, System.currentTimeMillis())
            }

            SUSPICIOUS_TLDS.forEach { if (host.endsWith(it)) { riskScore += 0.3f; threatTypes.add("suspicious_tld") } }
            if (host.matches(Regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$"))) { riskScore += 0.4f; threatTypes.add("ip_url") }
            PHISHING_KEYWORDS.forEach { if (host.contains(it)) { riskScore += 0.2f; threatTypes.add("phishing_keyword") } }

            riskScore = riskScore.coerceIn(0f, 1f)
            return URLCheckResult(url, riskScore >= 0.5f, threatTypes.joinToString(",").ifEmpty { null }, riskScore, System.currentTimeMillis())
        } catch (e: Exception) {
            return URLCheckResult(url, false, null, 0f, System.currentTimeMillis())
        }
    }

    private fun handleCheckResult(result: URLCheckResult, packageName: String) {
        if (result.isMalicious) {
            callback?.onMaliciousURL(result.url, result.threatType ?: "unknown", result.riskScore)
        } else {
            callback?.onSafeURL(result.url)
        }
    }

    fun setCallback(cb: URLCheckCallback?) { callback = cb }
    fun startMonitoring() { isMonitoring = true }
    fun stopMonitoring() { isMonitoring = false }
    fun isMonitoringActive(): Boolean = isMonitoring

    /**
     * Update monitoring settings
     */
    fun updateSettings(protectionEnabled: Boolean, monitoringEnabled: Boolean) {
        isMonitoring = protectionEnabled && monitoringEnabled
        Log.d(TAG, "Settings updated: protection=$protectionEnabled, monitoring=$monitoringEnabled, active=$isMonitoring")
    }

    /**
     * Show warning overlay for detected threat
     * Note: In a full implementation, this would show an overlay window.
     * For now, we log the threat and could integrate with Flutter for UI.
     */
    fun showWarningOverlay(url: String, threatInfo: UrlThreatInfo) {
        Log.w(TAG, "⚠️ THREAT DETECTED: $url")
        Log.w(TAG, "  Level: ${threatInfo.threatLevel}")
        Log.w(TAG, "  Reason: ${threatInfo.reason}")
        Log.w(TAG, "  Categories: ${threatInfo.categories.joinToString(", ")}")

        // Notify callback about malicious URL
        callback?.onMaliciousURL(
            url,
            threatInfo.threatLevel,
            when (threatInfo.threatLevel) {
                "critical" -> 1.0f
                "dangerous" -> 0.8f
                "suspicious" -> 0.6f
                else -> 0.4f
            }
        )
    }

    override fun onInterrupt() {}
    override fun onDestroy() { super.onDestroy(); instance = null; isMonitoring = false }
}
