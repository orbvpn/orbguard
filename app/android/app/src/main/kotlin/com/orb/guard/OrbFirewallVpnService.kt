// OrbFirewallVpnService.kt
// Real on-device network firewall for Android (channel com.orbvpn.orbguard/firewall).
//
// Architecture: a local VpnService that intercepts DNS only. It advertises a
// virtual in-tunnel DNS server and routes just that address into the TUN, so
// every app's DNS query enters here while all other traffic flows normally over
// the real network (no userspace TCP stack, no server, nothing leaves the
// device except the forwarded upstream DNS lookups).
//
// For each DNS query:
//   - if the queried domain (or a parent domain) is on the blocklist, it is
//     sinkholed (answered 0.0.0.0 / NXDOMAIN) and a "blocked" event is emitted;
//   - otherwise the query is forwarded to a real upstream resolver over a
//     protect()ed socket and the answer is written back, with an "allowed"
//     event.
//
// This is the same DNS-content-filter design used by Blokada/RethinkDNS. Honest
// limitations (documented for the user): apps that hardcode their own resolver
// or use DoH/DoT bypass DNS filtering, and IPv6 DNS is passed through.
//
// Real-time hardening: the service survives reboots via BootReceiver +
// FirewallState (persisted enabled flag + block list), counts blocked queries
// per local day ("blocked today"), and its foreground notification doubles as
// the app's persistent "OrbGuard is protecting you" status anchor.

package com.orb.guard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicBoolean

class OrbFirewallVpnService : VpnService() {

    companion object {
        private const val TAG = "OrbFirewall"
        const val ACTION_START = "com.orb.guard.firewall.START"
        const val ACTION_STOP = "com.orb.guard.firewall.STOP"

        // Virtual TUN addressing. Only the virtual DNS server is routed into the
        // tunnel, so we intercept DNS without capturing all traffic.
        private const val TUN_ADDRESS = "10.111.222.2"
        private const val TUN_DNS = "10.111.222.1"
        private const val TUN_PREFIX = 30

        // Upstream resolvers that allowed queries are forwarded to (over a
        // protected socket, i.e. out the real network, bypassing the tunnel).
        private val UPSTREAMS = listOf("1.1.1.1", "8.8.8.8")
        private const val DNS_PORT = 53

        private const val NOTIF_CHANNEL = "orbguard_firewall"
        private const val NOTIF_ID = 4711

        /** Set by BootReceiver so a failed restore posts the re-enable prompt. */
        const val EXTRA_BOOT_RESTORE = "boot_restore"

        // The persistent status notification refreshes its "N blocked today"
        // text on this cadence. A plain main-looper Handler tick: no wakelock,
        // no alarm — when the device sleeps the tick simply runs late.
        private const val NOTIF_REFRESH_MS = 15 * 60 * 1000L

        // Live block lists, set from Dart via FirewallChannelHandler before the
        // service starts and updated while it runs. Volatile: read on the TUN
        // thread, written on the platform thread.
        @Volatile
        private var blockedDomains: Set<String> = emptySet()

        @Volatile
        var running: Boolean = false
            private set

        /** Emits firewall events (blocked/allowed DNS) up to the channel. */
        @Volatile
        var eventSink: ((Map<String, Any?>) -> Unit)? = null

        fun updateBlockedDomains(domains: Set<String>) {
            blockedDomains = domains.map { it.lowercase().trim().removeSuffix(".") }
                .filter { it.isNotEmpty() }
                .toHashSet()
            Log.i(TAG, "block list updated: ${blockedDomains.size} domains")
        }

        private fun emit(event: Map<String, Any?>) {
            eventSink?.let { sink ->
                try {
                    sink(event)
                } catch (e: Exception) {
                    Log.w(TAG, "event emit failed: ${e.message}")
                }
            }
        }
    }

    private var tun: ParcelFileDescriptor? = null
    private var worker: Thread? = null
    private val active = AtomicBoolean(false)
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Periodic "N blocked today" refresh of the ongoing status notification. */
    private val notifRefresh: Runnable = object : Runnable {
        override fun run() {
            if (!active.get()) return
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, buildStatusNotification())
            mainHandler.postDelayed(this, NOTIF_REFRESH_MS)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopFirewall()
                return START_NOT_STICKY
            }
            else -> {
                // Enter the foreground immediately: a boot restore starts us
                // with startForegroundService(), which requires a prompt
                // startForeground() even if establishing the tunnel fails.
                startForegroundNotification()
                startFirewall(intent?.getBooleanExtra(EXTRA_BOOT_RESTORE, false) ?: false)
            }
        }
        return START_STICKY
    }

    private fun startFirewall(fromBootRestore: Boolean) {
        if (active.get()) return

        // After a reboot or process-death restart the Dart side has not pushed
        // the block list yet — reload the last persisted one so the firewall
        // actually enforces instead of running empty (a placebo).
        if (blockedDomains.isEmpty()) {
            updateBlockedDomains(FirewallState.loadBlocklist(this))
        }

        val builder = Builder()
            .setSession("OrbGuard Firewall")
            .addAddress(TUN_ADDRESS, TUN_PREFIX)
            .addDnsServer(TUN_DNS)
            // Route ONLY the virtual DNS server into the tunnel; every other
            // destination keeps using the real network untouched.
            .addRoute(TUN_DNS, 32)
            .setBlocking(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            builder.setMtu(1500)
        }

        val pfd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "failed to establish VPN: ${e.message}")
            null
        }
        if (pfd == null) {
            emit(mapOf("type" to "engine_error", "reason" to "VPN establish failed"))
            if (fromBootRestore) {
                // Nobody is watching at boot — never fail silently: tell the
                // user protection is off and how to bring it back.
                BootReceiver.postReEnableNotification(this)
            }
            stopForegroundCompat()
            stopSelf()
            return
        }

        tun = pfd
        active.set(true)
        running = true
        // Rebuild the notification now that we are running (shows the current
        // "N blocked today"), clear any stale re-enable prompt, and start the
        // 15-minute text refresh.
        startForegroundNotification()
        BootReceiver.cancelReEnableNotification(this)
        mainHandler.removeCallbacks(notifRefresh)
        mainHandler.postDelayed(notifRefresh, NOTIF_REFRESH_MS)

        worker = Thread({ runLoop(pfd) }, "orb-firewall-dns").also { it.start() }
        emit(mapOf("type" to "engine_state", "enabled" to true))
        Log.i(TAG, "firewall started")
    }

    private fun stopFirewall() {
        active.set(false)
        running = false
        mainHandler.removeCallbacks(notifRefresh)
        FirewallState.flush(this)
        worker?.interrupt()
        worker = null
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
        emit(mapOf("type" to "engine_state", "enabled" to false))
        stopForegroundCompat()
        stopSelf()
        Log.i(TAG, "firewall stopped")
    }

    /** Reads DNS queries from the TUN, filters, and writes answers back. */
    private fun runLoop(pfd: ParcelFileDescriptor) {
        val input = FileInputStream(pfd.fileDescriptor)
        val output = FileOutputStream(pfd.fileDescriptor)
        val packet = ByteArray(32767)

        while (active.get()) {
            val length = try {
                input.read(packet)
            } catch (e: Exception) {
                if (active.get()) Log.w(TAG, "tun read error: ${e.message}")
                break
            }
            if (length <= 0) continue

            try {
                handlePacket(packet, length, output)
            } catch (e: Exception) {
                Log.w(TAG, "packet handling error: ${e.message}")
            }
        }
    }

    private fun handlePacket(packet: ByteArray, length: Int, output: FileOutputStream) {
        if (length < 20) return // smaller than a minimal IPv4 header
        val ipVersion = (packet[0].toInt() and 0xF0) shr 4
        if (ipVersion != 4) return // IPv6 DNS is passed through (documented limit)

        val ihl = (packet[0].toInt() and 0x0F) * 4
        if (ihl < 20 || length < ihl + 8) return // need a full IPv4 + UDP header
        val protocol = packet[9].toInt() and 0xFF
        if (protocol != 17) return // UDP only (DNS)

        val udpStart = ihl
        val dstPort = ((packet[udpStart + 2].toInt() and 0xFF) shl 8) or
            (packet[udpStart + 3].toInt() and 0xFF)
        if (dstPort != DNS_PORT) return

        val udpPayloadStart = udpStart + 8
        val dnsLen = length - udpPayloadStart
        if (dnsLen <= 12) return

        val dns = packet.copyOfRange(udpPayloadStart, length)
        val domain = parseDnsQuestion(dns) ?: return

        if (isBlocked(domain)) {
            val response = buildSinkholeResponse(packet, length, ihl, udpStart, dns)
            if (response != null) output.write(response)
            // "Blocked today" proof-of-work counter: in-memory bump, flushed
            // to prefs every few blocks (see FirewallState) — no per-packet IO.
            FirewallState.recordBlocked(this)
            emit(dnsEvent(domain, blocked = true, remoteAddress = "0.0.0.0"))
        } else {
            forwardUpstream(packet, length, ihl, udpStart, dns, domain, output)
        }
    }

    /** True if the domain or any of its parent domains is on the block list. */
    private fun isBlocked(domain: String): Boolean {
        val set = blockedDomains
        if (set.isEmpty()) return false
        if (set.contains(domain)) return true
        var idx = domain.indexOf('.')
        while (idx != -1) {
            val parent = domain.substring(idx + 1)
            if (set.contains(parent)) return true
            idx = domain.indexOf('.', idx + 1)
        }
        return false
    }

    /** Forwards an allowed DNS query to an upstream resolver and writes back. */
    private fun forwardUpstream(
        packet: ByteArray,
        length: Int,
        ihl: Int,
        udpStart: Int,
        dns: ByteArray,
        domain: String,
        output: FileOutputStream,
    ) {
        var socket: DatagramSocket? = null
        try {
            socket = DatagramSocket()
            protect(socket)
            socket.soTimeout = 5000
            for (upstream in UPSTREAMS) {
                try {
                    val server = InetSocketAddress(InetAddress.getByName(upstream), DNS_PORT)
                    socket.send(DatagramPacket(dns, dns.size, server))
                    val buf = ByteArray(4096)
                    val reply = DatagramPacket(buf, buf.size)
                    socket.receive(reply)
                    val answer = buf.copyOfRange(0, reply.length)
                    val response = buildForwardedResponse(packet, ihl, udpStart, answer)
                    if (response != null) output.write(response)
                    emit(dnsEvent(domain, blocked = false, remoteAddress = upstream))
                    return
                } catch (_: Exception) {
                    // try the next upstream
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "upstream forward failed for $domain: ${e.message}")
        } finally {
            socket?.close()
        }
    }

    // ---- DNS + IP/UDP packet construction ---------------------------------

    /** Extracts the queried domain (QNAME) from a DNS query payload. */
    private fun parseDnsQuestion(dns: ByteArray): String? {
        if (dns.size < 13) return null
        val qdcount = ((dns[4].toInt() and 0xFF) shl 8) or (dns[5].toInt() and 0xFF)
        if (qdcount < 1) return null
        val sb = StringBuilder()
        var pos = 12
        while (pos < dns.size) {
            val len = dns[pos].toInt() and 0xFF
            if (len == 0) break
            if (len and 0xC0 != 0) return null // compression not expected in a question
            pos++
            if (pos + len > dns.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            sb.append(String(dns, pos, len, Charsets.US_ASCII))
            pos += len
        }
        val domain = sb.toString().lowercase()
        return domain.ifEmpty { null }
    }

    /** Builds an A 0.0.0.0 sinkhole answer for a blocked query. */
    private fun buildSinkholeResponse(
        packet: ByteArray,
        length: Int,
        ihl: Int,
        udpStart: Int,
        dns: ByteArray,
    ): ByteArray? {
        // Question section is everything after the 12-byte DNS header up to the
        // first null label + 4 bytes (QTYPE+QCLASS).
        var qEnd = 12
        while (qEnd < dns.size && (dns[qEnd].toInt() and 0xFF) != 0) {
            qEnd += (dns[qEnd].toInt() and 0xFF) + 1
        }
        qEnd += 1 + 4 // null byte + QTYPE + QCLASS
        if (qEnd > dns.size) return null

        val answer = ByteArray(16)
        answer[0] = 0xC0.toByte(); answer[1] = 0x0C // pointer to the question name
        answer[2] = 0x00; answer[3] = 0x01           // TYPE A
        answer[4] = 0x00; answer[5] = 0x01           // CLASS IN
        answer[6] = 0x00; answer[7] = 0x00; answer[8] = 0x00; answer[9] = 0x00 // TTL 0
        answer[10] = 0x00; answer[11] = 0x04         // RDLENGTH 4
        answer[12] = 0x00; answer[13] = 0x00; answer[14] = 0x00; answer[15] = 0x00 // 0.0.0.0

        val response = ByteArray(qEnd + answer.size)
        System.arraycopy(dns, 0, response, 0, qEnd)
        // Flags: response, recursion available, no error.
        response[2] = 0x81.toByte()
        response[3] = 0x80.toByte()
        response[6] = 0x00; response[7] = 0x01 // ANCOUNT = 1
        response[8] = 0x00; response[9] = 0x00 // NSCOUNT = 0
        response[10] = 0x00; response[11] = 0x00 // ARCOUNT = 0
        System.arraycopy(answer, 0, response, qEnd, answer.size)

        return wrapInIpUdp(packet, ihl, udpStart, response)
    }

    private fun buildForwardedResponse(
        packet: ByteArray,
        ihl: Int,
        udpStart: Int,
        dnsAnswer: ByteArray,
    ): ByteArray? = wrapInIpUdp(packet, ihl, udpStart, dnsAnswer)

    /**
     * Wraps a DNS response payload in an IPv4+UDP packet addressed back to the
     * querying app (src/dst swapped from the request), with fresh checksums.
     */
    private fun wrapInIpUdp(
        request: ByteArray,
        ihl: Int,
        udpStart: Int,
        dnsPayload: ByteArray,
    ): ByteArray {
        val udpLen = 8 + dnsPayload.size
        val totalLen = ihl + udpLen
        val out = ByteArray(totalLen)

        // Copy + fix the IPv4 header, swapping source and destination.
        System.arraycopy(request, 0, out, 0, ihl)
        out[2] = ((totalLen shr 8) and 0xFF).toByte()
        out[3] = (totalLen and 0xFF).toByte()
        // src <-> dst (bytes 12..15 and 16..19)
        for (i in 0 until 4) {
            out[12 + i] = request[16 + i]
            out[16 + i] = request[12 + i]
        }
        // Zero then recompute the IP header checksum.
        out[10] = 0; out[11] = 0
        val ipChecksum = checksum(out, 0, ihl)
        out[10] = ((ipChecksum shr 8) and 0xFF).toByte()
        out[11] = (ipChecksum and 0xFF).toByte()

        // UDP header: swap ports, set length, payload.
        val srcPort = ((request[udpStart].toInt() and 0xFF) shl 8) or
            (request[udpStart + 1].toInt() and 0xFF)
        val dstPort = ((request[udpStart + 2].toInt() and 0xFF) shl 8) or
            (request[udpStart + 3].toInt() and 0xFF)
        val uStart = ihl
        out[uStart] = ((dstPort shr 8) and 0xFF).toByte()
        out[uStart + 1] = (dstPort and 0xFF).toByte()
        out[uStart + 2] = ((srcPort shr 8) and 0xFF).toByte()
        out[uStart + 3] = (srcPort and 0xFF).toByte()
        out[uStart + 4] = ((udpLen shr 8) and 0xFF).toByte()
        out[uStart + 5] = (udpLen and 0xFF).toByte()
        out[uStart + 6] = 0; out[uStart + 7] = 0 // UDP checksum optional (0) for IPv4
        System.arraycopy(dnsPayload, 0, out, uStart + 8, dnsPayload.size)

        return out
    }

    /** One's-complement 16-bit checksum over a byte range. */
    private fun checksum(data: ByteArray, offset: Int, len: Int): Int {
        var sum = 0L
        var i = offset
        val end = offset + len
        while (i + 1 < end) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }
        if (i < end) sum += (data[i].toInt() and 0xFF) shl 8
        while (sum shr 16 != 0L) sum = (sum and 0xFFFF) + (sum shr 16)
        return (sum.inv() and 0xFFFF).toInt()
    }

    private fun dnsEvent(domain: String, blocked: Boolean, remoteAddress: String): Map<String, Any?> =
        mapOf(
            "type" to "connection",
            "id" to "dns_${System.nanoTime()}",
            "app_id" to "dns",
            "app_name" to "DNS query",
            "local_address" to TUN_ADDRESS,
            "local_port" to 0,
            "remote_address" to remoteAddress,
            "remote_port" to DNS_PORT,
            "remote_domain" to domain,
            "direction" to "outbound",
            "protocol" to "udp",
            "blocked" to blocked,
            "bytes_in" to 0,
            "bytes_out" to 0,
        )

    // ---- Foreground notification ------------------------------------------
    //
    // This ONE ongoing low-priority notification is the app's "OrbGuard is
    // protecting you" anchor. It is deliberately the firewall's own foreground
    // notification (enriched with the live "N blocked today" count) rather
    // than a second GuardStatusService: the VpnService IS the protection, so
    // a separate always-on service would only add a duplicate persistent
    // notification and a second foreground-service footprint for zero truth.

    /** The persistent status notification, with today's blocked count. */
    private fun buildStatusNotification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = if (launch != null) {
            PendingIntent.getActivity(
                this, 0, launch,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                    PendingIntent.FLAG_IMMUTABLE else 0,
            )
        } else null

        val blocked = FirewallState.blockedToday(this)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, NOTIF_CHANNEL) else
            @Suppress("DEPRECATION") Notification.Builder(this)
        return builder
            .setContentTitle("OrbGuard is protecting you")
            .setContentText("Firewall active · $blocked blocked today")
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .apply { if (pending != null) setContentIntent(pending) }
            .build()
    }

    private fun startForegroundNotification() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIF_CHANNEL,
                "Network Firewall",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "OrbGuard on-device firewall is active" }
            nm.createNotificationChannel(channel)
        }
        startForeground(NOTIF_ID, buildStatusNotification())
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
    }

    override fun onDestroy() {
        stopFirewall()
        super.onDestroy()
    }

    override fun onRevoke() {
        // The user or another VPN app revoked our tunnel; shut down cleanly.
        stopFirewall()
        super.onRevoke()
    }
}
