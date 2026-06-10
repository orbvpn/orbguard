// WifiChannelHandler.kt
// Native Wi-Fi inspection channel: com.orb.guard/wifi
//
// Consumed by:
//   - lib/providers/network_provider.dart   (getCurrentNetwork, scanNetworks)
//   - lib/providers/rogue_ap_provider.dart  (scanWifiNetworks)
//
// Honest-failure contract:
//   - PERMISSION_DENIED  -> ACCESS_FINE_LOCATION not granted (Dart must prompt)
//   - LOCATION_DISABLED  -> Android 9+ hides SSID/BSSID/scan results when
//                           location services are off
//   - NOT_CONNECTED      -> device is not on a Wi-Fi network
//   - THROTTLED          -> Android scan throttling (4 scans / 2 min) hit and
//                           cached results are stale; never returns stale data
//                           as if it were fresh
//   - SCAN_FAILED        -> scan completed but the OS reported failure and no
//                           usable cached results exist

package com.orb.guard

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.ScanResult
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class WifiChannelHandler(private val context: Context) {

    companion object {
        private const val TAG = "OrbGuard.Wifi"
        private const val CHANNEL_NAME = "com.orb.guard/wifi"

        // Scan results older than this are considered stale (Android throttles
        // foreground apps to 4 scans per 2 minutes; results within that window
        // are still genuinely representative).
        private const val STALE_RESULT_AGE_MS = 120_000L
        private const val SCAN_TIMEOUT_MS = 12_000L
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private val wifiManager: WifiManager
        get() = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    private val connectivityManager: ConnectivityManager
        get() = context.applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getCurrentNetwork" -> getCurrentNetwork(result)
                    // Two Dart call sites use different method names for the
                    // same capability; both are served by one implementation.
                    "scanNetworks", "scanWifiNetworks" -> performScan(result)
                    "getDnsServers" -> getDnsServers(result)
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Unhandled error in ${call.method}", e)
                result.error("NATIVE_ERROR", "Wi-Fi channel failure: ${e.message}", null)
            }
        }
    }

    // ------------------------------------------------------------------
    // Preconditions
    // ------------------------------------------------------------------

    private fun hasFineLocationPermission(): Boolean {
        return context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun isLocationEnabled(): Boolean {
        return try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                lm.isLocationEnabled
            } else {
                @Suppress("DEPRECATION")
                Settings.Secure.getInt(
                    context.contentResolver,
                    Settings.Secure.LOCATION_MODE,
                    Settings.Secure.LOCATION_MODE_OFF
                ) != Settings.Secure.LOCATION_MODE_OFF
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not determine location state: ${e.message}")
            false
        }
    }

    /**
     * Returns null when preconditions pass, otherwise sends the appropriate
     * error on [result] and returns the error code that was sent.
     */
    private fun checkPreconditions(result: MethodChannel.Result): String? {
        if (!hasFineLocationPermission()) {
            result.error(
                "PERMISSION_DENIED",
                "ACCESS_FINE_LOCATION is required to read Wi-Fi network details on Android 9+",
                mapOf(
                    "permission" to Manifest.permission.ACCESS_FINE_LOCATION,
                    "action" to "request_runtime_permission"
                )
            )
            return "PERMISSION_DENIED"
        }
        if (!isLocationEnabled()) {
            result.error(
                "LOCATION_DISABLED",
                "Location services are disabled; Android hides SSID/BSSID and scan results while location is off",
                mapOf("action" to "enable_location_services")
            )
            return "LOCATION_DISABLED"
        }
        return null
    }

    // ------------------------------------------------------------------
    // getCurrentNetwork
    // ------------------------------------------------------------------

    private fun getCurrentNetwork(result: MethodChannel.Result) {
        if (checkPreconditions(result) != null) return

        val activeNetwork = connectivityManager.activeNetwork
        val capabilities = activeNetwork?.let { connectivityManager.getNetworkCapabilities(it) }
        if (capabilities == null || !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
            result.error(
                "NOT_CONNECTED",
                "Device is not connected to a Wi-Fi network",
                null
            )
            return
        }

        Thread {
            try {
                @Suppress("DEPRECATION")
                val info = wifiManager.connectionInfo
                if (info == null || info.networkId == -1 && info.bssid == null) {
                    mainHandler.post {
                        result.error("NOT_CONNECTED", "No active Wi-Fi connection info available", null)
                    }
                    return@Thread
                }

                val rawSsid = info.ssid ?: ""
                val ssid = rawSsid.removePrefix("\"").removeSuffix("\"")
                if (ssid == "<unknown ssid>" || ssid.isEmpty()) {
                    // Honest failure: the OS refused to reveal the SSID
                    // (location permission granted but app may be backgrounded,
                    // or OEM restriction). Do not fabricate a network name.
                    mainHandler.post {
                        result.error(
                            "SSID_UNAVAILABLE",
                            "Android withheld the SSID (app must be in the foreground with location permission and location services on)",
                            mapOf("bssid" to (info.bssid ?: ""))
                        )
                    }
                    return@Thread
                }

                val bssid = info.bssid ?: ""
                val frequency = info.frequency // MHz
                val matchingScan = findScanResult(bssid)
                val security = securityFromScanOrInfo(matchingScan, info)
                val gatewayIp = resolveGatewayIp()
                val gatewayMac = gatewayIp?.let { lookupArpMac(it) }

                val payload = mutableMapOf<String, Any?>(
                    "ssid" to ssid,
                    "bssid" to bssid,
                    "signal_strength" to info.rssi,
                    "frequency" to frequency,
                    "channel" to channelFromFrequency(frequency),
                    "security" to security,
                    "link_speed_mbps" to info.linkSpeed,
                    "gateway_ip" to gatewayIp,
                    "gateway_mac" to gatewayMac,
                    "is_connected" to true
                )
                if (gatewayMac == null) {
                    // ARP table access is blocked for normal apps since
                    // Android 10; state this rather than returning a fake MAC.
                    payload["gateway_mac_note"] =
                        "ARP table not readable by third-party apps on Android 10+"
                }

                mainHandler.post { result.success(payload) }
            } catch (e: SecurityException) {
                mainHandler.post {
                    result.error(
                        "PERMISSION_DENIED",
                        "OS denied Wi-Fi info access: ${e.message}",
                        mapOf("permission" to Manifest.permission.ACCESS_FINE_LOCATION)
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "getCurrentNetwork failed", e)
                mainHandler.post {
                    result.error("NATIVE_ERROR", "Failed to read current network: ${e.message}", null)
                }
            }
        }.start()
    }

    private fun findScanResult(bssid: String): ScanResult? {
        if (bssid.isEmpty()) return null
        return try {
            @Suppress("DEPRECATION")
            wifiManager.scanResults.firstOrNull { it.BSSID.equals(bssid, ignoreCase = true) }
        } catch (e: SecurityException) {
            null
        }
    }

    private fun securityFromScanOrInfo(scan: ScanResult?, info: android.net.wifi.WifiInfo): String {
        if (scan != null) return parseSecurity(scan.capabilities ?: "")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return when (info.currentSecurityType) {
                android.net.wifi.WifiInfo.SECURITY_TYPE_OPEN -> "Open"
                android.net.wifi.WifiInfo.SECURITY_TYPE_WEP -> "WEP"
                android.net.wifi.WifiInfo.SECURITY_TYPE_PSK -> "WPA2"
                android.net.wifi.WifiInfo.SECURITY_TYPE_SAE -> "WPA3"
                android.net.wifi.WifiInfo.SECURITY_TYPE_EAP,
                android.net.wifi.WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE,
                android.net.wifi.WifiInfo.SECURITY_TYPE_EAP_WPA3_ENTERPRISE_192_BIT -> "WPA2 Enterprise"
                android.net.wifi.WifiInfo.SECURITY_TYPE_OWE -> "OWE"
                else -> "Unknown"
            }
        }
        return "Unknown"
    }

    // ------------------------------------------------------------------
    // scanNetworks / scanWifiNetworks
    // ------------------------------------------------------------------

    private fun performScan(result: MethodChannel.Result) {
        if (checkPreconditions(result) != null) return

        val finished = AtomicBoolean(false)

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                if (!finished.compareAndSet(false, true)) return
                safeUnregister(this)
                val updated = intent?.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, true) ?: true
                mainHandler.post {
                    if (updated) {
                        result.success(mapScanResults())
                    } else {
                        // OS reported the scan did not produce new results
                        // (typically throttling). Fall back to cache only if
                        // it is genuinely fresh.
                        respondWithCachedOrThrottled(result, reason = "scan_results_not_updated")
                    }
                }
            }
        }

        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // SCAN_RESULTS_AVAILABLE_ACTION is a protected system broadcast;
            // NOT_EXPORTED is correct and required for targetSdk 34+.
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, filter)
        }

        @Suppress("DEPRECATION")
        val started = try {
            wifiManager.startScan()
        } catch (e: SecurityException) {
            false
        }

        if (!started) {
            // startScan() returning false means throttled (or Wi-Fi off).
            if (finished.compareAndSet(false, true)) {
                safeUnregister(receiver)
                mainHandler.post { respondWithCachedOrThrottled(result, reason = "start_scan_rejected") }
            }
            return
        }

        mainHandler.postDelayed({
            if (finished.compareAndSet(false, true)) {
                safeUnregister(receiver)
                respondWithCachedOrThrottled(result, reason = "scan_timeout")
            }
        }, SCAN_TIMEOUT_MS)
    }

    private fun safeUnregister(receiver: BroadcastReceiver) {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // already unregistered
        }
    }

    /**
     * Returns cached scan results only when they are fresh enough to be
     * truthful; otherwise reports THROTTLED with the cache age so the caller
     * can decide to retry later.
     */
    private fun respondWithCachedOrThrottled(result: MethodChannel.Result, reason: String) {
        val cached = try {
            @Suppress("DEPRECATION")
            wifiManager.scanResults
        } catch (e: SecurityException) {
            null
        }

        if (cached.isNullOrEmpty()) {
            if (!wifiManager.isWifiEnabled) {
                result.error("WIFI_DISABLED", "Wi-Fi is turned off", mapOf("reason" to reason))
            } else {
                result.error(
                    "SCAN_FAILED",
                    "Wi-Fi scan failed and no cached results are available",
                    mapOf("reason" to reason)
                )
            }
            return
        }

        // ScanResult.timestamp is microseconds since boot.
        val newestAgeMs = cached.minOf {
            SystemClock.elapsedRealtime() - (it.timestamp / 1000)
        }

        if (newestAgeMs <= STALE_RESULT_AGE_MS) {
            result.success(mapScanResults(cached))
        } else {
            result.error(
                "THROTTLED",
                "Wi-Fi scan throttled by Android (foreground apps: 4 scans / 2 min) and cached results are stale",
                mapOf(
                    "reason" to reason,
                    "cached_age_ms" to newestAgeMs,
                    "cached_count" to cached.size,
                    "stale_threshold_ms" to STALE_RESULT_AGE_MS
                )
            )
        }
    }

    private fun mapScanResults(results: List<ScanResult>? = null): List<Map<String, Any?>> {
        val scans = results ?: try {
            @Suppress("DEPRECATION")
            wifiManager.scanResults
        } catch (e: SecurityException) {
            emptyList()
        }

        @Suppress("DEPRECATION")
        val currentBssid = try {
            wifiManager.connectionInfo?.bssid
        } catch (e: Exception) {
            null
        }

        return scans.map { scan ->
            val ssid = scanSsid(scan)
            mapOf(
                "ssid" to ssid,
                "bssid" to (scan.BSSID ?: ""),
                "signal_strength" to scan.level,
                "frequency" to scan.frequency,
                "channel" to channelFromFrequency(scan.frequency),
                "security" to parseSecurity(scan.capabilities ?: ""),
                "is_connected" to (scan.BSSID != null &&
                    scan.BSSID.equals(currentBssid, ignoreCase = true)),
                "is_hidden" to ssid.isEmpty(),
                // ScanResult.timestamp is µs since boot; expose age so callers
                // can judge freshness themselves.
                "age_ms" to (SystemClock.elapsedRealtime() - (scan.timestamp / 1000))
            )
        }
    }

    private fun scanSsid(scan: ScanResult): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            scan.wifiSsid?.toString()?.removePrefix("\"")?.removeSuffix("\"") ?: ""
        } else {
            @Suppress("DEPRECATION")
            scan.SSID ?: ""
        }
    }

    // ------------------------------------------------------------------
    // getDnsServers — configured resolvers of the active network
    // ------------------------------------------------------------------

    private fun getDnsServers(result: MethodChannel.Result) {
        try {
            val network = connectivityManager.activeNetwork
            val props = network?.let { connectivityManager.getLinkProperties(it) }
            if (props == null) {
                result.error(
                    "UNAVAILABLE",
                    "No active network or link properties available to read DNS servers from",
                    null
                )
                return
            }
            val servers = props.dnsServers.mapNotNull { it.hostAddress }
            if (servers.isEmpty()) {
                result.error(
                    "UNAVAILABLE",
                    "The active network reports no DNS servers (private DNS may be hiding them)",
                    mapOf(
                        "private_dns_active" to
                            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && props.isPrivateDnsActive)
                    )
                )
                return
            }
            result.success(servers)
        } catch (e: Exception) {
            Log.e(TAG, "getDnsServers failed", e)
            result.error("NATIVE_ERROR", "DNS server lookup failed: ${e.message}", null)
        }
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /** Parses ScanResult.capabilities flags into a coarse security label. */
    private fun parseSecurity(capabilities: String): String {
        val caps = capabilities.uppercase()
        return when {
            caps.contains("SAE") || caps.contains("WPA3") ->
                if (caps.contains("EAP")) "WPA3 Enterprise" else "WPA3"
            caps.contains("WPA2") || caps.contains("RSN") ->
                if (caps.contains("EAP")) "WPA2 Enterprise" else "WPA2"
            caps.contains("WPA") ->
                if (caps.contains("EAP")) "WPA Enterprise" else "WPA"
            caps.contains("WEP") -> "WEP"
            caps.contains("OWE") -> "OWE"
            else -> "Open"
        }
    }

    /** Converts a Wi-Fi frequency in MHz to its channel number. */
    private fun channelFromFrequency(freqMhz: Int): Int {
        return when {
            freqMhz == 2484 -> 14
            freqMhz in 2412..2472 -> (freqMhz - 2407) / 5
            freqMhz in 5180..5885 -> (freqMhz - 5000) / 5
            freqMhz in 5955..7115 -> (freqMhz - 5950) / 5 // 6 GHz (Wi-Fi 6E)
            else -> 0
        }
    }

    /** Default-route gateway IPv4 address from LinkProperties (non-deprecated path). */
    private fun resolveGatewayIp(): String? {
        return try {
            val network = connectivityManager.activeNetwork ?: return null
            val props = connectivityManager.getLinkProperties(network) ?: return null
            props.routes
                .firstOrNull { it.isDefaultRoute && it.gateway != null && it.gateway?.hostAddress?.contains('.') == true }
                ?.gateway?.hostAddress
                ?: dhcpGatewayFallback()
        } catch (e: Exception) {
            dhcpGatewayFallback()
        }
    }

    private fun dhcpGatewayFallback(): String? {
        return try {
            @Suppress("DEPRECATION")
            val gw = wifiManager.dhcpInfo?.gateway ?: return null
            if (gw == 0) return null
            String.format(
                "%d.%d.%d.%d",
                gw and 0xFF, (gw shr 8) and 0xFF, (gw shr 16) and 0xFF, (gw shr 24) and 0xFF
            )
        } catch (e: Exception) {
            null
        }
    }

    /**
     * Best-effort ARP lookup for the gateway MAC. /proc/net/arp is readable on
     * Android 9 and below; from Android 10 the kernel returns zeroed MACs (or
     * denies access) to normal apps, in which case this returns null and the
     * caller surfaces an explicit note instead of a fake address.
     */
    private fun lookupArpMac(ip: String): String? {
        try {
            val arp = File("/proc/net/arp")
            if (arp.canRead()) {
                arp.bufferedReader().useLines { lines ->
                    for (line in lines) {
                        val cols = line.trim().split(Regex("\\s+"))
                        if (cols.size >= 4 && cols[0] == ip) {
                            val mac = cols[3]
                            if (mac.matches(Regex("([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}")) &&
                                mac != "00:00:00:00:00:00"
                            ) {
                                return mac
                            }
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.d(TAG, "/proc/net/arp not accessible: ${e.message}")
        }

        // Secondary attempt via `ip neigh` (works on some Android 10 builds).
        try {
            val process = Runtime.getRuntime().exec(arrayOf("ip", "neigh", "show", ip))
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()
            val match = Regex("lladdr\\s+(([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2})").find(output)
            val mac = match?.groupValues?.get(1)
            if (mac != null && mac != "00:00:00:00:00:00") return mac
        } catch (e: Exception) {
            Log.d(TAG, "ip neigh lookup failed: ${e.message}")
        }
        return null
    }
}
