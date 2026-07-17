// BootReceiver.kt
// Restores the on-device firewall after a reboot (and after an app update,
// which also kills the VpnService).
//
// Decision tree when the user left the firewall enabled (FirewallState):
//   - VpnService.prepare() == null  -> the system still honours our VPN
//     consent: restart OrbFirewallVpnService exactly as the channel handler
//     does (foreground start; the service reloads the persisted block list).
//   - consent needed / anything fails -> post ONE normal-priority
//     "tap to re-enable" notification opening the app. Android only shows the
//     consent dialog from an Activity, so the notification IS the honest
//     path — protection is never silently claimed or silently absent.

package com.orb.guard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "OrbGuardBoot"
        private const val ALERT_CHANNEL = "orbguard_guard_alerts"
        private const val REENABLE_NOTIF_ID = 4712

        /**
         * The honest fallback: the firewall should be on but cannot start
         * without the user — one tap opens the app to re-enable it.
         */
        fun postReEnableNotification(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val channel = NotificationChannel(
                    ALERT_CHANNEL,
                    "Protection alerts",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = "Alerts when OrbGuard protection needs your attention"
                }
                nm.createNotificationChannel(channel)
            }

            val launch = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            val pending = if (launch != null) {
                PendingIntent.getActivity(
                    context, 0, launch,
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                        PendingIntent.FLAG_IMMUTABLE else 0,
                )
            } else null

            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                Notification.Builder(context, ALERT_CHANNEL) else
                @Suppress("DEPRECATION") Notification.Builder(context)
            val notification = builder
                .setContentTitle("Tracker firewall is off")
                .setContentText("Tap to re-enable your tracker firewall")
                .setSmallIcon(context.applicationInfo.icon)
                .setAutoCancel(true)
                .apply { if (pending != null) setContentIntent(pending) }
                .build()
            try {
                nm.notify(REENABLE_NOTIF_ID, notification)
            } catch (e: Exception) {
                // Notifications blocked (POST_NOTIFICATIONS denied): nothing
                // more can be done headlessly; the app shows the real state
                // (firewall off) on next open.
                Log.w(TAG, "re-enable notification failed: ${e.message}")
            }
        }

        /** Clears the re-enable prompt once the firewall is actually running. */
        fun cancelReEnableNotification(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
            nm.cancel(REENABLE_NOTIF_ID)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) return

        if (!FirewallState.isEnabled(context)) {
            Log.i(TAG, "$action: firewall not enabled, nothing to restore")
            return
        }

        val consent = try {
            VpnService.prepare(context)
        } catch (e: Exception) {
            Log.w(TAG, "VpnService.prepare failed: ${e.message}")
            postReEnableNotification(context)
            return
        }
        if (consent != null) {
            Log.i(TAG, "$action: VPN consent no longer valid, asking the user")
            postReEnableNotification(context)
            return
        }

        val service = Intent(context, OrbFirewallVpnService::class.java)
            .setAction(OrbFirewallVpnService.ACTION_START)
            .putExtra(OrbFirewallVpnService.EXTRA_BOOT_RESTORE, true)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(service)
            } else {
                context.startService(service)
            }
            Log.i(TAG, "$action: firewall restore requested")
        } catch (e: Exception) {
            Log.e(TAG, "failed to restore firewall: ${e.message}")
            postReEnableNotification(context)
        }
    }
}
