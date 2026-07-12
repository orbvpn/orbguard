package com.orb.guard

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.regex.Pattern

/**
 * Messaging App Accessibility Service
 *
 * Monitors messaging apps (WhatsApp, Telegram, etc.) for suspicious links
 * and scam messages to protect users from phishing and fraud.
 *
 * Supported Apps:
 * - WhatsApp (Personal & Business)
 * - Telegram
 * - Viber
 * - Facebook Messenger
 * - Instagram DMs
 * - Slack
 * - Signal
 */
class MessagingAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "MessagingAccessibility"

        @Volatile
        private var instance: MessagingAccessibilityService? = null

        fun getInstance(): MessagingAccessibilityService? = instance

        // Supported messaging app packages
        private val MESSAGING_PACKAGES = mapOf(
            "com.whatsapp" to "WhatsApp",
            "com.whatsapp.w4b" to "WhatsApp Business",
            "org.telegram.messenger" to "Telegram",
            "org.telegram.plus" to "Telegram Plus",
            "org.telegram.messenger.web" to "Telegram X",
            "com.viber.voip" to "Viber",
            "com.facebook.orca" to "Messenger",
            "com.instagram.android" to "Instagram",
            "com.Slack" to "Slack",
            "org.thoughtcrime.securesms" to "Signal",
        )

        // URL extraction pattern
        private val URL_PATTERN = Pattern.compile(
            "(https?://[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]+)" +
            "|" +
            "(www\\.[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]+)" +
            "|" +
            "([\\w\\-]+\\.(com|org|net|io|co|me|info|biz|xyz|tk|ml|ga|cf)[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]*)",
            Pattern.CASE_INSENSITIVE
        )

        // Scam message patterns
        private val SCAM_PATTERNS = listOf(
            // Urgency patterns
            Pattern.compile("(urgent|immediately|act now|limited time|expires|deadline)", Pattern.CASE_INSENSITIVE),
            // Prize/lottery patterns
            Pattern.compile("(won|winner|congratulations|prize|lottery|jackpot|claim|reward)", Pattern.CASE_INSENSITIVE),
            // Financial patterns
            Pattern.compile("(bank|account.*suspended|verify.*identity|update.*payment|crypto.*invest)", Pattern.CASE_INSENSITIVE),
            // Threat patterns
            Pattern.compile("(suspended|locked|disabled|unauthorized|illegal|arrest|lawsuit)", Pattern.CASE_INSENSITIVE),
            // Package delivery scams
            Pattern.compile("(package|delivery|shipping|tracking|fedex|ups|usps|dhl|amazon.*deliver)", Pattern.CASE_INSENSITIVE),
            // Job/money scams
            Pattern.compile("(work from home|earn.*day|make money|investment opportunity|guaranteed return)", Pattern.CASE_INSENSITIVE),
            // Tech support scams
            Pattern.compile("(tech support|microsoft|apple.*support|virus detected|computer.*infected)", Pattern.CASE_INSENSITIVE),
            // Romance/relationship scams
            Pattern.compile("(dating site|lonely|single.*area|beautiful women|meet.*tonight)", Pattern.CASE_INSENSITIVE),
            // Government impersonation
            Pattern.compile("(irs|tax refund|social security|government grant|stimulus)", Pattern.CASE_INSENSITIVE),
        )

        // Suspicious TLDs
        private val SUSPICIOUS_TLDS = setOf(
            ".xyz", ".tk", ".ml", ".ga", ".cf", ".gq", ".top", ".work",
            ".click", ".link", ".loan", ".download", ".stream", ".racing"
        )

        // Known safe domains
        private val SAFE_DOMAINS = setOf(
            "whatsapp.com", "telegram.org", "t.me", "wa.me",
            "google.com", "facebook.com", "instagram.com",
            "youtube.com", "twitter.com", "linkedin.com",
            "amazon.com", "apple.com", "microsoft.com",
            "github.com", "stackoverflow.com"
        )
    }

    // Callback interface
    interface MessageAnalysisCallback {
        fun onMessageAnalyzed(analysis: MessageAnalysis)
        fun onSuspiciousMessage(analysis: MessageAnalysis)
        fun onURLDetected(url: String, appName: String)
    }

    data class MessageAnalysis(
        val packageName: String,
        val appName: String,
        val messageText: String,
        val urls: List<String>,
        val riskScore: Float,
        val threats: List<String>,
        val isSuspicious: Boolean,
        val timestamp: Long
    )

    data class AnalyzedMessage(
        val text: String,
        val packageName: String,
        val appName: String,
        val urls: List<URLAnalysis>,
        val scamPatterns: List<String>,
        val riskScore: Float,
        val timestamp: Long
    )

    data class URLAnalysis(
        val url: String,
        val domain: String,
        val isSuspicious: Boolean,
        val threatType: String?
    )

    private var callback: MessageAnalysisCallback? = null
    private var isMonitoring = false

    // Cache for analyzed messages (avoid repeated analysis)
    private val messageCache = ConcurrentHashMap<String, AnalyzedMessage>()
    private val cacheExpiry = 5 * 60 * 1000L // 5 minutes

    // Analysis history
    private val analysisHistory = mutableListOf<AnalyzedMessage>()
    private val maxHistorySize = 100

    // Statistics
    private var totalMessagesAnalyzed = 0
    private var suspiciousMessagesFound = 0
    private var urlsDetected = 0

    // Last processed text (debounce)
    private var lastProcessedText: String? = null
    private var lastProcessedTime: Long = 0
    private val debounceInterval = 500L

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.d(TAG, "Messaging Accessibility Service created")
    }

    override fun onServiceConnected() {
        super.onServiceConnected()

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED or
                        AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED or
                        AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED

            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC

            packageNames = MESSAGING_PACKAGES.keys.toTypedArray()

            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                   AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                   AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS

            notificationTimeout = 100
        }

        serviceInfo = info
        isMonitoring = true

        Log.d(TAG, "Messaging Accessibility Service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !isMonitoring) return

        val packageName = event.packageName?.toString() ?: return

        // Only process messaging app events
        if (packageName !in MESSAGING_PACKAGES.keys) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED,
            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED,
            AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> {
                processEvent(event, packageName)
            }
        }
    }

    private fun processEvent(event: AccessibilityEvent, packageName: String) {
        try {
            // Extract text from event
            val texts = mutableListOf<String>()

            // From event text
            event.text?.forEach { text ->
                if (!text.isNullOrBlank()) {
                    texts.add(text.toString())
                }
            }

            // From content description
            event.contentDescription?.toString()?.let { desc ->
                if (desc.isNotBlank()) {
                    texts.add(desc)
                }
            }

            // From node tree
            rootInActiveWindow?.let { root ->
                extractTextFromNode(root, texts)
            }

            // Process unique texts
            texts.distinct().forEach { text ->
                if (text.length > 10) { // Skip very short texts
                    analyzeMessage(text, packageName)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error processing event: ${e.message}")
        }
    }

    private fun extractTextFromNode(node: AccessibilityNodeInfo?, texts: MutableList<String>, depth: Int = 0) {
        if (node == null || depth > 10) return

        try {
            node.text?.toString()?.let { text ->
                if (text.isNotBlank() && text.length > 10) {
                    texts.add(text)
                }
            }

            for (i in 0 until node.childCount) {
                extractTextFromNode(node.getChild(i), texts, depth + 1)
            }
        } catch (e: Exception) {
            // Ignore traversal errors
        }
    }

    private fun analyzeMessage(text: String, packageName: String) {
        // Debounce
        val now = System.currentTimeMillis()
        if (text == lastProcessedText && (now - lastProcessedTime) < debounceInterval) {
            return
        }
        lastProcessedText = text
        lastProcessedTime = now

        // Check cache
        val cacheKey = "${packageName}_${text.hashCode()}"
        val cached = messageCache[cacheKey]
        if (cached != null && (now - cached.timestamp) < cacheExpiry) {
            return
        }

        totalMessagesAnalyzed++

        // Extract URLs
        val urls = extractURLs(text)
        urlsDetected += urls.size

        // Analyze URLs
        val urlAnalyses = urls.map { url -> analyzeURL(url) }

        // Detect scam patterns
        val scamPatterns = detectScamPatterns(text)

        // Calculate risk score
        val riskScore = calculateRiskScore(text, urlAnalyses, scamPatterns)

        val appName = MESSAGING_PACKAGES[packageName] ?: "Unknown"

        val analysis = AnalyzedMessage(
            text = text.take(500), // Limit stored text length
            packageName = packageName,
            appName = appName,
            urls = urlAnalyses,
            scamPatterns = scamPatterns,
            riskScore = riskScore,
            timestamp = now
        )

        // Cache result
        messageCache[cacheKey] = analysis

        // Add to history
        addToHistory(analysis)

        // Notify callbacks
        val isSuspicious = riskScore >= 0.5f

        if (isSuspicious) {
            suspiciousMessagesFound++
            Log.w(TAG, "Suspicious message detected in $appName: risk=$riskScore, patterns=$scamPatterns")
        }

        // Notify about URLs
        urls.forEach { url ->
            callback?.onURLDetected(url, appName)
        }

        // Notify about analysis
        val messageAnalysis = MessageAnalysis(
            packageName = packageName,
            appName = appName,
            messageText = text.take(200),
            urls = urls,
            riskScore = riskScore,
            threats = scamPatterns + urlAnalyses.filter { it.isSuspicious }.map { it.threatType ?: "suspicious_url" },
            isSuspicious = isSuspicious,
            timestamp = now
        )

        callback?.onMessageAnalyzed(messageAnalysis)
        if (isSuspicious) {
            callback?.onSuspiciousMessage(messageAnalysis)
        }
    }

    private fun extractURLs(text: String): List<String> {
        val urls = mutableListOf<String>()
        val matcher = URL_PATTERN.matcher(text)

        while (matcher.find()) {
            val url = matcher.group()
            if (url != null) {
                urls.add(normalizeURL(url))
            }
        }

        return urls.distinct()
    }

    private fun normalizeURL(url: String): String {
        var normalized = url.trim()
        if (!normalized.startsWith("http://") && !normalized.startsWith("https://")) {
            normalized = "https://$normalized"
        }
        return normalized
    }

    private fun analyzeURL(url: String): URLAnalysis {
        try {
            val parsed = URL(url)
            val host = parsed.host.lowercase()
            var isSuspicious = false
            var threatType: String? = null

            // Check if safe domain
            if (host in SAFE_DOMAINS || SAFE_DOMAINS.any { host.endsWith(".$it") }) {
                return URLAnalysis(url, host, false, null)
            }

            // Check suspicious TLD
            for (tld in SUSPICIOUS_TLDS) {
                if (host.endsWith(tld)) {
                    isSuspicious = true
                    threatType = "suspicious_tld"
                    break
                }
            }

            // Check for IP address
            if (host.matches(Regex("^\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}$"))) {
                isSuspicious = true
                threatType = "ip_address_url"
            }

            // Check for typosquatting
            if (hasTyposquattingPattern(host)) {
                isSuspicious = true
                threatType = "typosquatting"
            }

            // Check for URL shorteners (often used to hide malicious URLs)
            val shorteners = listOf("bit.ly", "tinyurl.com", "t.co", "goo.gl", "ow.ly", "is.gd", "buff.ly", "adf.ly")
            if (shorteners.any { host.endsWith(it) || host == it }) {
                // Not necessarily malicious, but flag for further inspection
                threatType = threatType ?: "url_shortener"
            }

            return URLAnalysis(url, host, isSuspicious, threatType)

        } catch (e: Exception) {
            return URLAnalysis(url, url, true, "invalid_url")
        }
    }

    private fun hasTyposquattingPattern(host: String): Boolean {
        val brandPatterns = mapOf(
            "whatsapp" to listOf("whatsap", "whatapp", "watsapp", "whatspp", "whatssapp"),
            "telegram" to listOf("telegam", "telgram", "teleg ram", "telegr am"),
            "paypal" to listOf("paypa1", "paypall", "payp4l", "paypaI"),
            "google" to listOf("g00gle", "googel", "gogle", "googIe"),
            "facebook" to listOf("faceb00k", "facebok", "fac ebook"),
            "instagram" to listOf("1nstagram", "instagam", "lnstagram"),
            "amazon" to listOf("amaz0n", "amazn", "arnazon"),
        )

        for ((_, typos) in brandPatterns) {
            if (typos.any { host.contains(it, ignoreCase = true) }) {
                return true
            }
        }
        return false
    }

    private fun detectScamPatterns(text: String): List<String> {
        val patterns = mutableListOf<String>()

        SCAM_PATTERNS.forEachIndexed { index, pattern ->
            if (pattern.matcher(text).find()) {
                val patternName = when (index) {
                    0 -> "urgency"
                    1 -> "prize_lottery"
                    2 -> "financial_scam"
                    3 -> "threat_intimidation"
                    4 -> "package_delivery"
                    5 -> "job_money_scam"
                    6 -> "tech_support_scam"
                    7 -> "romance_scam"
                    8 -> "government_impersonation"
                    else -> "suspicious_pattern"
                }
                patterns.add(patternName)
            }
        }

        return patterns
    }

    private fun calculateRiskScore(text: String, urls: List<URLAnalysis>, scamPatterns: List<String>): Float {
        var score = 0f

        // URL risk contribution
        val suspiciousURLs = urls.count { it.isSuspicious }
        score += suspiciousURLs * 0.25f

        // Scam pattern contribution
        score += scamPatterns.size * 0.15f

        // High-risk pattern boost
        if (scamPatterns.any { it in listOf("financial_scam", "government_impersonation", "tech_support_scam") }) {
            score += 0.2f
        }

        // Multiple patterns compound risk
        if (scamPatterns.size >= 3) {
            score += 0.15f
        }

        // Short message with URL (common in phishing)
        if (text.length < 100 && urls.isNotEmpty()) {
            score += 0.1f
        }

        return score.coerceIn(0f, 1f)
    }

    private fun addToHistory(analysis: AnalyzedMessage) {
        synchronized(analysisHistory) {
            analysisHistory.add(0, analysis)
            if (analysisHistory.size > maxHistorySize) {
                analysisHistory.removeAt(analysisHistory.lastIndex)
            }
        }
    }

    // Public methods for Flutter integration

    fun setCallback(callback: MessageAnalysisCallback?) {
        this.callback = callback
    }

    fun startMonitoring() {
        isMonitoring = true
        Log.d(TAG, "Messaging monitoring started")
    }

    fun stopMonitoring() {
        isMonitoring = false
        Log.d(TAG, "Messaging monitoring stopped")
    }

    fun isMonitoringActive(): Boolean = isMonitoring

    fun analyzeText(text: String): Map<String, Any?> {
        val urls = extractURLs(text)
        val urlAnalyses = urls.map { analyzeURL(it) }
        val scamPatterns = detectScamPatterns(text)
        val riskScore = calculateRiskScore(text, urlAnalyses, scamPatterns)

        return mapOf(
            "text" to text.take(200),
            "urls" to urls,
            "suspicious_urls" to urlAnalyses.filter { it.isSuspicious }.map { it.url },
            "scam_patterns" to scamPatterns,
            "risk_score" to riskScore,
            "is_suspicious" to (riskScore >= 0.5f)
        )
    }

    fun getHistory(): List<Map<String, Any?>> {
        return synchronized(analysisHistory) {
            analysisHistory.map { analysis ->
                mapOf(
                    "text" to analysis.text,
                    "package_name" to analysis.packageName,
                    "app_name" to analysis.appName,
                    "urls" to analysis.urls.map { it.url },
                    "scam_patterns" to analysis.scamPatterns,
                    "risk_score" to analysis.riskScore,
                    "timestamp" to analysis.timestamp
                )
            }
        }
    }

    fun getSuspiciousMessages(): List<Map<String, Any?>> {
        return synchronized(analysisHistory) {
            analysisHistory.filter { it.riskScore >= 0.5f }.map { analysis ->
                mapOf(
                    "text" to analysis.text,
                    "app_name" to analysis.appName,
                    "urls" to analysis.urls.map { it.url },
                    "scam_patterns" to analysis.scamPatterns,
                    "risk_score" to analysis.riskScore,
                    "timestamp" to analysis.timestamp
                )
            }
        }
    }

    fun getStatistics(): Map<String, Any> {
        return mapOf(
            "total_messages_analyzed" to totalMessagesAnalyzed,
            "suspicious_messages_found" to suspiciousMessagesFound,
            "urls_detected" to urlsDetected,
            "detection_rate" to if (totalMessagesAnalyzed > 0) {
                (suspiciousMessagesFound.toFloat() / totalMessagesAnalyzed * 100).toInt()
            } else 0,
            "cache_size" to messageCache.size,
            "history_size" to analysisHistory.size,
            "supported_apps" to MESSAGING_PACKAGES.values.toList()
        )
    }

    fun clearHistory() {
        synchronized(analysisHistory) {
            analysisHistory.clear()
        }
        messageCache.clear()
        totalMessagesAnalyzed = 0
        suspiciousMessagesFound = 0
        urlsDetected = 0
    }

    override fun onInterrupt() {
        Log.d(TAG, "Messaging Accessibility Service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        isMonitoring = false
        messageCache.clear()
        Log.d(TAG, "Messaging Accessibility Service destroyed")
    }
}
