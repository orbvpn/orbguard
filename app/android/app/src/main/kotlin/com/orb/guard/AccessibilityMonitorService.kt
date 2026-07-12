// AccessibilityMonitorService.kt
// Accessibility service for detecting malicious accessibility services

package com.orb.guard

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent

class AccessibilityMonitorService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()

        // Configure the service to receive minimal events
        // We only need this service to be registered so we can detect
        // other potentially malicious accessibility services
        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS
            notificationTimeout = 100
        }

        serviceInfo = info
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // We don't need to process events
        // This service exists to detect malicious accessibility services
    }

    override fun onInterrupt() {
        // Required override
    }
}
