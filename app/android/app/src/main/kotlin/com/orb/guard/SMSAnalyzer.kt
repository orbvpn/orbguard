// SMSAnalyzer.kt
// SMS analysis bridge between native Android and Flutter

package com.orb.guard

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap

/**
 * SMSAnalyzer - Singleton class for SMS analysis and platform channel communication
 */
class SMSAnalyzer private constructor(private val context: Context) {

    companion object {
        private const val TAG = "OrbGuard.SMSAnalyzer"
        private const val CHANNEL_NAME = "com.orb.guard/sms"
        private const val NOTIFICATION_CHANNEL_ID = "sms_threats"
        private const val NOTIFICATION_ID_BASE = 2000

        @Volatile
        private var instance: SMSAnalyzer? = null

        fun getInstance(context: Context): SMSAnalyzer {
            return instance ?: synchronized(this) {
                instance ?: SMSAnalyzer(context.applicationContext).also { instance = it }
            }
        }
    }

    private var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingMessages = ConcurrentHashMap<String, ParsedSmsMessage>()
    private val analyzedMessages = ConcurrentHashMap<String, AnalysisResult>()

    // Settings
    private var isProtectionEnabled = true
    private var notifyOnThreat = true
    private var autoBlockDangerous = false

    /**
     * Set the Flutter method channel
     */
    fun setMethodChannel(channel: MethodChannel) {
        this.methodChannel = channel
        Log.d(TAG, "Method channel set")

        // Process any pending messages
        processPendingMessages()
    }

    /**
     * Update settings from Flutter
     */
    fun updateSettings(
        protectionEnabled: Boolean,
        notifyOnThreat: Boolean,
        autoBlockDangerous: Boolean
    ) {
        this.isProtectionEnabled = protectionEnabled
        this.notifyOnThreat = notifyOnThreat
        this.autoBlockDangerous = autoBlockDangerous
        Log.d(TAG, "Settings updated: protection=$protectionEnabled, notify=$notifyOnThreat, autoBlock=$autoBlockDangerous")
    }

    /**
     * Analyze an incoming SMS message
     */
    fun analyzeSms(message: ParsedSmsMessage) {
        if (!isProtectionEnabled) {
            Log.d(TAG, "Protection disabled, skipping analysis")
            return
        }

        val messageId = message.generateId()
        Log.d(TAG, "Analyzing SMS: $messageId")

        // Store message
        pendingMessages[messageId] = message

        // Send to Flutter for analysis
        mainHandler.post {
            methodChannel?.let { channel ->
                channel.invokeMethod("onSmsReceived", message.toMap())
            } ?: run {
                Log.w(TAG, "Method channel not available, message queued")
            }
        }
    }

    /**
     * Process pending messages when channel becomes available
     */
    private fun processPendingMessages() {
        if (pendingMessages.isEmpty()) return

        Log.d(TAG, "Processing ${pendingMessages.size} pending messages")

        pendingMessages.values.forEach { message ->
            mainHandler.post {
                methodChannel?.invokeMethod("onSmsReceived", message.toMap())
            }
        }
    }

    /**
     * Called when analysis result is received from Flutter
     */
    fun onAnalysisResult(messageId: String, result: AnalysisResult) {
        Log.d(TAG, "Analysis result for $messageId: ${result.threatLevel}")

        // Store result
        analyzedMessages[messageId] = result

        // Remove from pending
        val message = pendingMessages.remove(messageId)

        // Handle threat notification
        if (result.isThreat && notifyOnThreat) {
            showThreatNotification(message, result)
        }

        // Handle auto-block
        if (autoBlockDangerous && result.threatLevel >= ThreatLevel.DANGEROUS) {
            message?.let { blockSender(it.sender) }
        }
    }

    /**
     * Show threat notification
     */
    private fun showThreatNotification(message: ParsedSmsMessage?, result: AnalysisResult) {
        if (message == null) return

        createNotificationChannel()

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        intent?.putExtra("open_sms_protection", true)
        intent?.putExtra("message_id", message.generateId())

        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID_BASE + message.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val title = when (result.threatLevel) {
            ThreatLevel.CRITICAL -> "⛔ Critical SMS Threat Detected!"
            ThreatLevel.DANGEROUS -> "🔴 Dangerous SMS Detected!"
            ThreatLevel.SUSPICIOUS -> "⚠️ Suspicious SMS Detected"
            else -> "SMS Security Alert"
        }

        val body = buildString {
            append("From: ${message.sender}\n")
            if (result.threatTypes.isNotEmpty()) {
                append("Threats: ${result.threatTypes.joinToString(", ")}")
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
        notificationManager.notify(NOTIFICATION_ID_BASE + message.hashCode(), notification)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "SMS Threats",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerts for detected SMS threats"
                enableVibration(true)
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    /**
     * Block a sender
     */
    private fun blockSender(sender: String) {
        Log.d(TAG, "Blocking sender: $sender")
        mainHandler.post {
            methodChannel?.invokeMethod("blockSender", mapOf("sender" to sender))
        }
    }

    /**
     * Read SMS messages from device inbox
     */
    fun readSmsInbox(limit: Int = 100): List<Map<String, Any?>> {
        val messages = mutableListOf<Map<String, Any?>>()

        try {
            val uri: Uri = Telephony.Sms.Inbox.CONTENT_URI
            val projection = arrayOf(
                Telephony.Sms._ID,
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.READ,
                Telephony.Sms.SEEN,
                Telephony.Sms.TYPE
            )

            val cursor: Cursor? = context.contentResolver.query(
                uri,
                projection,
                null,
                null,
                "${Telephony.Sms.DATE} DESC LIMIT $limit"
            )

            cursor?.use {
                while (it.moveToNext()) {
                    val id = it.getLong(it.getColumnIndexOrThrow(Telephony.Sms._ID))
                    val address = it.getString(it.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)) ?: "Unknown"
                    val body = it.getString(it.getColumnIndexOrThrow(Telephony.Sms.BODY)) ?: ""
                    val date = it.getLong(it.getColumnIndexOrThrow(Telephony.Sms.DATE))
                    val read = it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.READ)) == 1
                    val seen = it.getInt(it.getColumnIndexOrThrow(Telephony.Sms.SEEN)) == 1

                    val message = ParsedSmsMessage(
                        sender = address,
                        content = body,
                        timestamp = date
                    )

                    messages.add(message.toMap() + mapOf(
                        "dbId" to id,
                        "isRead" to read,
                        "isSeen" to seen
                    ))
                }
            }

            Log.d(TAG, "Read ${messages.size} messages from inbox")
        } catch (e: SecurityException) {
            Log.e(TAG, "Permission denied reading SMS: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Error reading SMS: ${e.message}")
        }

        return messages
    }

    /**
     * Check if SMS permission is granted
     */
    fun hasSmsPermission(): Boolean {
        return context.checkSelfPermission(android.Manifest.permission.READ_SMS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED &&
                context.checkSelfPermission(android.Manifest.permission.RECEIVE_SMS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
    }

    /**
     * Get analysis result for a message
     */
    fun getAnalysisResult(messageId: String): AnalysisResult? {
        return analyzedMessages[messageId]
    }

    /**
     * Clear cached data
     */
    fun clearCache() {
        pendingMessages.clear()
        analyzedMessages.clear()
    }
}

/**
 * SMS threat level enum
 */
enum class ThreatLevel(val value: Int) {
    SAFE(0),
    SUSPICIOUS(1),
    DANGEROUS(2),
    CRITICAL(3);

    companion object {
        fun fromValue(value: Int): ThreatLevel {
            return entries.find { it.value == value } ?: SAFE
        }

        fun fromString(str: String): ThreatLevel {
            return when (str.lowercase()) {
                "safe" -> SAFE
                "suspicious" -> SUSPICIOUS
                "dangerous" -> DANGEROUS
                "critical" -> CRITICAL
                else -> SAFE
            }
        }
    }
}

/**
 * Analysis result data class
 */
data class AnalysisResult(
    val messageId: String,
    val threatLevel: ThreatLevel,
    val isThreat: Boolean,
    val confidence: Double,
    val threatTypes: List<String>,
    val indicators: List<String>,
    val recommendations: List<String>
) {
    companion object {
        fun fromMap(map: Map<String, Any?>): AnalysisResult {
            return AnalysisResult(
                messageId = map["messageId"] as? String ?: "",
                threatLevel = ThreatLevel.fromString(map["threatLevel"] as? String ?: "safe"),
                isThreat = map["isThreat"] as? Boolean ?: false,
                confidence = (map["confidence"] as? Number)?.toDouble() ?: 0.0,
                threatTypes = (map["threatTypes"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                indicators = (map["indicators"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
                recommendations = (map["recommendations"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
            )
        }
    }

    fun toMap(): Map<String, Any?> {
        return mapOf(
            "messageId" to messageId,
            "threatLevel" to threatLevel.name.lowercase(),
            "isThreat" to isThreat,
            "confidence" to confidence,
            "threatTypes" to threatTypes,
            "indicators" to indicators,
            "recommendations" to recommendations
        )
    }
}
