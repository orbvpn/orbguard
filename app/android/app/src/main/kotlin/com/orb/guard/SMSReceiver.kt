// SMSReceiver.kt
// Broadcast receiver for incoming SMS messages

package com.orb.guard

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.telephony.SmsMessage
import android.util.Log

class SMSReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "OrbGuard.SMSReceiver"
        const val SMS_RECEIVED_ACTION = "android.provider.Telephony.SMS_RECEIVED"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return

        if (intent.action != SMS_RECEIVED_ACTION) return

        Log.d(TAG, "SMS received broadcast")

        val bundle: Bundle = intent.extras ?: return
        val pdus = bundle.get("pdus") as? Array<*> ?: return
        val format = bundle.getString("format")

        // Parse SMS messages
        val messages = mutableListOf<ParsedSmsMessage>()

        for (pdu in pdus) {
            if (pdu !is ByteArray) continue

            val smsMessage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                SmsMessage.createFromPdu(pdu, format)
            } else {
                @Suppress("DEPRECATION")
                SmsMessage.createFromPdu(pdu)
            }

            smsMessage?.let { msg ->
                val parsedMessage = ParsedSmsMessage(
                    sender = msg.displayOriginatingAddress ?: msg.originatingAddress ?: "Unknown",
                    content = msg.displayMessageBody ?: msg.messageBody ?: "",
                    timestamp = msg.timestampMillis,
                    serviceCenterAddress = msg.serviceCenterAddress ?: "",
                    isReplyPathPresent = msg.isReplyPathPresent,
                    protocolIdentifier = msg.protocolIdentifier,
                    status = msg.status
                )
                messages.add(parsedMessage)
            }
        }

        // Combine multipart messages with same sender
        val combinedMessages = combineMultipartMessages(messages)

        // Send to analyzer
        for (message in combinedMessages) {
            Log.d(TAG, "Processing SMS from: ${message.sender}")
            SMSAnalyzer.getInstance(context).analyzeSms(message)
        }
    }

    private fun combineMultipartMessages(messages: List<ParsedSmsMessage>): List<ParsedSmsMessage> {
        if (messages.size <= 1) return messages

        // Group by sender and combine
        val grouped = messages.groupBy { it.sender }

        return grouped.map { (sender, msgs) ->
            if (msgs.size == 1) {
                msgs.first()
            } else {
                // Combine multipart messages
                ParsedSmsMessage(
                    sender = sender,
                    content = msgs.joinToString("") { it.content },
                    timestamp = msgs.maxOf { it.timestamp },
                    serviceCenterAddress = msgs.first().serviceCenterAddress,
                    isReplyPathPresent = msgs.first().isReplyPathPresent,
                    protocolIdentifier = msgs.first().protocolIdentifier,
                    status = msgs.first().status
                )
            }
        }
    }
}

/**
 * Parsed SMS message data class
 */
data class ParsedSmsMessage(
    val sender: String,
    val content: String,
    val timestamp: Long,
    val serviceCenterAddress: String = "",
    val isReplyPathPresent: Boolean = false,
    val protocolIdentifier: Int = 0,
    val status: Int = -1
) {
    /**
     * Generate a unique ID for this message
     */
    fun generateId(): String {
        return "${sender}_${timestamp}_${content.hashCode()}"
    }

    /**
     * Convert to map for platform channel
     */
    fun toMap(): Map<String, Any?> {
        return mapOf(
            "id" to generateId(),
            "sender" to sender,
            "content" to content,
            "timestamp" to timestamp,
            "serviceCenterAddress" to serviceCenterAddress,
            "isReplyPathPresent" to isReplyPathPresent,
            "protocolIdentifier" to protocolIdentifier,
            "status" to status
        )
    }
}
