// BrowserAccessibilityService.kt
// Accessibility service for monitoring browser URLs in real-time

package com.orb.guard

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.widget.TextView

/**
 * BrowserAccessibilityService - Monitors browser URLs for security threats
 *
 * Supports: Chrome, Firefox, Samsung Browser, Edge, Opera, Brave
 */
class BrowserAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "OrbGuard.BrowserAS"

        // Supported browser packages
        private val BROWSER_PACKAGES = mapOf(
            "com.android.chrome" to "Chrome",
            "org.mozilla.firefox" to "Firefox",
            "com.sec.android.app.sbrowser" to "Samsung Browser",
            "com.microsoft.emmx" to "Edge",
            "com.opera.browser" to "Opera",
            "com.opera.mini.native" to "Opera Mini",
            "com.brave.browser" to "Brave",
            "com.UCMobile.intl" to "UC Browser",
            "com.duckduckgo.mobile.android" to "DuckDuckGo"
        )

        // URL bar resource IDs for different browsers
        private val URL_BAR_IDS = mapOf(
            "com.android.chrome" to listOf(
                "com.android.chrome:id/url_bar",
                "com.android.chrome:id/search_box_text",
                "com.android.chrome:id/omnibox_text"
            ),
            "org.mozilla.firefox" to listOf(
                "org.mozilla.firefox:id/url_bar_title",
                "org.mozilla.firefox:id/mozac_browser_toolbar_url_view"
            ),
            "com.sec.android.app.sbrowser" to listOf(
                "com.sec.android.app.sbrowser:id/location_bar_edit_text",
                "com.sec.android.app.sbrowser:id/url_bar"
            ),
            "com.microsoft.emmx" to listOf(
                "com.microsoft.emmx:id/url_bar",
                "com.microsoft.emmx:id/address_bar_text"
            ),
            "com.opera.browser" to listOf(
                "com.opera.browser:id/url_field"
            ),
            "com.brave.browser" to listOf(
                "com.brave.browser:id/url_bar"
            )
        )

        @Volatile
        private var instance: BrowserAccessibilityService? = null

        fun getInstance(): BrowserAccessibilityService? = instance
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var browserMonitor: BrowserMonitor? = null
    private var lastExtractedUrl: String = ""
    private var lastUrlCheckTime: Long = 0
    private val URL_CHECK_DEBOUNCE_MS = 500L

    // Settings
    private var isMonitoringEnabled = true
    private var showWarningOverlay = true

    override fun onCreate() {
        super.onCreate()
        instance = this
        browserMonitor = BrowserMonitor.getInstance(applicationContext)
        Log.d(TAG, "BrowserAccessibilityService created")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()

        val info = AccessibilityServiceInfo().apply {
            // Listen to window changes and content changes in browsers
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED

            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC

            // Only listen to browser packages
            packageNames = BROWSER_PACKAGES.keys.toTypedArray()

            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS

            notificationTimeout = 100
        }

        serviceInfo = info
        Log.d(TAG, "BrowserAccessibilityService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !isMonitoringEnabled) return

        val packageName = event.packageName?.toString() ?: return

        // Only process browser events
        if (!BROWSER_PACKAGES.containsKey(packageName)) return

        // Debounce URL checks
        val now = System.currentTimeMillis()
        if (now - lastUrlCheckTime < URL_CHECK_DEBOUNCE_MS) return
        lastUrlCheckTime = now

        // Extract URL from the event
        extractUrlFromEvent(event, packageName)
    }

    private fun extractUrlFromEvent(event: AccessibilityEvent, packageName: String) {
        try {
            val rootNode = rootInActiveWindow ?: return

            // Try known URL bar resource IDs first
            val urlBarIds = URL_BAR_IDS[packageName] ?: emptyList()
            for (urlBarId in urlBarIds) {
                val nodes = rootNode.findAccessibilityNodeInfosByViewId(urlBarId)
                if (nodes != null && nodes.isNotEmpty()) {
                    val urlText = nodes[0].text?.toString()
                    if (!urlText.isNullOrBlank()) {
                        processExtractedUrl(urlText, packageName)
                        return
                    }
                }
            }

            // Fallback: Search for EditText or TextView with URL-like content
            findUrlInNodeTree(rootNode, packageName)

        } catch (e: Exception) {
            Log.e(TAG, "Error extracting URL: ${e.message}")
        }
    }

    private fun findUrlInNodeTree(node: AccessibilityNodeInfo, packageName: String) {
        try {
            // Check current node
            val text = node.text?.toString()
            if (text != null && URLExtractor.isUrl(text)) {
                processExtractedUrl(text, packageName)
                return
            }

            // Check children
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                findUrlInNodeTree(child, packageName)
            }
        } catch (e: Exception) {
            // Node may have been recycled
        }
    }

    private fun processExtractedUrl(url: String, packageName: String) {
        // Normalize URL
        val normalizedUrl = URLExtractor.normalizeUrl(url)

        // Skip if same as last URL
        if (normalizedUrl == lastExtractedUrl) return
        lastExtractedUrl = normalizedUrl

        val browserName = BROWSER_PACKAGES[packageName] ?: "Unknown"
        Log.d(TAG, "URL detected in $browserName: $normalizedUrl")

        // Send to monitor for analysis
        browserMonitor?.analyzeUrl(normalizedUrl, browserName)
    }

    /**
     * Show warning overlay for dangerous URL
     */
    fun showWarningOverlay(url: String, threatInfo: UrlThreatInfo) {
        if (!showWarningOverlay) return

        mainHandler.post {
            try {
                // Create warning view
                val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                        WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    else
                        @Suppress("DEPRECATION")
                        WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP
                }

                // Create simple warning text view
                val warningView = TextView(applicationContext).apply {
                    text = "⚠️ Warning: This site may be dangerous!\n${threatInfo.reason}"
                    setBackgroundColor(0xFFFF5722.toInt())
                    setTextColor(0xFFFFFFFF.toInt())
                    setPadding(32, 48, 32, 48)
                    textSize = 16f
                    gravity = Gravity.CENTER
                }

                windowManager.addView(warningView, params)

                // Auto-dismiss after 5 seconds
                mainHandler.postDelayed({
                    try {
                        windowManager.removeView(warningView)
                    } catch (e: Exception) {
                        // View may already be removed
                    }
                }, 5000)

            } catch (e: Exception) {
                Log.e(TAG, "Failed to show warning overlay: ${e.message}")
            }
        }
    }

    /**
     * Update monitoring settings
     */
    fun updateSettings(enabled: Boolean, showOverlay: Boolean) {
        isMonitoringEnabled = enabled
        showWarningOverlay = showOverlay
        Log.d(TAG, "Settings updated: monitoring=$enabled, overlay=$showOverlay")
    }

    override fun onInterrupt() {
        Log.d(TAG, "BrowserAccessibilityService interrupted")
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
        Log.d(TAG, "BrowserAccessibilityService destroyed")
    }
}

/**
 * URL extraction utilities
 */
object URLExtractor {

    private val URL_PATTERN = Regex(
        """^(https?://)?([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(/.*)?$""",
        RegexOption.IGNORE_CASE
    )

    private val DOMAIN_PATTERN = Regex(
        """^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$""",
        RegexOption.IGNORE_CASE
    )

    /**
     * Check if text looks like a URL
     */
    fun isUrl(text: String): Boolean {
        val trimmed = text.trim()
        return URL_PATTERN.matches(trimmed) || DOMAIN_PATTERN.matches(trimmed)
    }

    /**
     * Normalize URL (add https:// if missing)
     */
    fun normalizeUrl(url: String): String {
        val trimmed = url.trim()
        return when {
            trimmed.startsWith("http://") || trimmed.startsWith("https://") -> trimmed
            else -> "https://$trimmed"
        }
    }

    /**
     * Extract domain from URL
     */
    fun extractDomain(url: String): String? {
        return try {
            val normalized = normalizeUrl(url)
            val uri = android.net.Uri.parse(normalized)
            uri.host
        } catch (e: Exception) {
            null
        }
    }
}

/**
 * URL threat information
 */
data class UrlThreatInfo(
    val url: String,
    val isThreat: Boolean,
    val threatLevel: String,
    val reason: String,
    val categories: List<String> = emptyList()
)
