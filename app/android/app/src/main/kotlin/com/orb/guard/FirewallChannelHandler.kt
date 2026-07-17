// FirewallChannelHandler.kt
// Bridges the Dart NetworkFirewallService to the native OrbFirewallVpnService.
//
// MethodChannel  com.orbvpn.orbguard/firewall
//   initialize        -> report engine availability (always available here)
//   updateBlockLists  -> push the threat-intel + user domain block list to native
//                        (also persisted via FirewallState for boot restore)
//   enable            -> request VPN consent if needed, then start the service
//   disable           -> stop the service
//   status            -> whether the firewall is currently running
//   getBlockedToday   -> Int: DNS queries blocked so far today (local date)
//   survivesReboot    -> Bool: enabled flag persisted AND VPN consent still
//                        valid, i.e. BootReceiver can restore without the user
//
// EventChannel   com.orbvpn.orbguard/firewall_events
//   streams connection/block events emitted by the VpnService.
//
// VPN consent: VpnService.prepare() returns a consent Intent the first time.
// It is launched via the Activity and the result is delivered back through
// MainActivity.onActivityResult -> onVpnConsentResult.

package com.orb.guard

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.os.Handler
import android.os.Looper

class FirewallChannelHandler(private val context: Context) {

    companion object {
        private const val TAG = "OrbFirewallChannel"
        private const val METHOD_CHANNEL = "com.orbvpn.orbguard/firewall"
        private const val EVENT_CHANNEL = "com.orbvpn.orbguard/firewall_events"
        const val VPN_CONSENT_REQUEST = 0x0F1A
    }

    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Pending enable() result held while the consent dialog is showing.
    private var pendingEnableResult: MethodChannel.Result? = null

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> result.success(mapOf("available" to true))

                "updateBlockLists" -> {
                    @Suppress("UNCHECKED_CAST")
                    val domains = (call.argument<List<String>>("domains") ?: emptyList())
                    OrbFirewallVpnService.updateBlockedDomains(domains.toSet())
                    // Persist so a reboot/process-death restore enforces the
                    // same list instead of an empty one.
                    FirewallState.saveBlocklist(context, domains)
                    result.success(true)
                }

                "enable" -> enable(result)

                "disable" -> {
                    // The user's intent is now "off": never auto-restore it.
                    FirewallState.setEnabled(context, false)
                    val intent = Intent(context, OrbFirewallVpnService::class.java)
                        .setAction(OrbFirewallVpnService.ACTION_STOP)
                    context.startService(intent)
                    result.success(true)
                }

                "status" -> result.success(
                    mapOf("running" to OrbFirewallVpnService.running)
                )

                "getBlockedToday" -> result.success(
                    FirewallState.blockedToday(context)
                )

                "survivesReboot" -> {
                    val consentValid = try {
                        VpnService.prepare(context) == null
                    } catch (e: Exception) {
                        false
                    }
                    result.success(FirewallState.isEnabled(context) && consentValid)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    OrbFirewallVpnService.eventSink = { event ->
                        mainHandler.post { eventSink?.success(event) }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    OrbFirewallVpnService.eventSink = null
                    eventSink = null
                }
            },
        )
    }

    private fun enable(result: MethodChannel.Result) {
        val consent = try {
            VpnService.prepare(context)
        } catch (e: Exception) {
            result.error("VPN_PREPARE_FAILED", e.message, null)
            return
        }

        if (consent != null) {
            // Consent required — launch the system dialog via the Activity.
            val act = activity
            if (act == null) {
                result.error(
                    "NO_ACTIVITY",
                    "VPN consent requires a foreground activity; open the app and retry.",
                    null,
                )
                return
            }
            pendingEnableResult = result
            try {
                act.startActivityForResult(consent, VPN_CONSENT_REQUEST)
            } catch (e: Exception) {
                pendingEnableResult = null
                result.error("VPN_CONSENT_FAILED", e.message, null)
            }
            return
        }

        // Already consented — start immediately.
        startService()
        result.success(true)
    }

    /** Called from MainActivity.onActivityResult for the consent dialog. */
    fun onVpnConsentResult(resultCode: Int) {
        val pending = pendingEnableResult ?: return
        pendingEnableResult = null
        if (resultCode == Activity.RESULT_OK) {
            startService()
            pending.success(true)
        } else {
            pending.error(
                "VPN_CONSENT_DENIED",
                "The user declined the VPN permission needed for the firewall.",
                null,
            )
        }
    }

    private fun startService() {
        val intent = Intent(context, OrbFirewallVpnService::class.java)
            .setAction(OrbFirewallVpnService.ACTION_START)
        try {
            context.startService(intent)
            // Persist the user's "on" intent so BootReceiver restores the
            // firewall after a reboot (covers both the already-consented and
            // the consent-just-granted enable paths).
            FirewallState.setEnabled(context, true)
            Log.i(TAG, "firewall service start requested")
        } catch (e: Exception) {
            Log.e(TAG, "failed to start firewall service: ${e.message}")
        }
    }
}
