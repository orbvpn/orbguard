// FirewallState.kt
// Persisted state for the on-device firewall, shared by FirewallChannelHandler,
// OrbFirewallVpnService and BootReceiver. Its own SharedPreferences file
// ("orbguard_firewall" — deliberately NOT the flutter.-prefixed file, which is
// owned by the shared_preferences plugin):
//
//   enabled                     Boolean   the user's firewall on/off intent;
//                                         written by the channel handler, read
//                                         by BootReceiver to restore protection
//                                         after a reboot.
//   blocklist                   StringSet the last block list pushed from Dart,
//                                         so a reboot/process-death restart
//                                         enforces the real list instead of
//                                         running an empty (placebo) firewall.
//   blocked_count_<yyyy-MM-dd>  Int       per-local-day blocked-DNS counters
//                                         ("N blocked today"); keys older than
//                                         7 days are pruned on day rollover.
//
// Counting stays cheap: a block bumps an in-memory counter (@Synchronized —
// blocked DNS queries are rare relative to packets) and is flushed to prefs
// every FLUSH_EVERY blocks, on day rollover and when the service stops. At
// most FLUSH_EVERY-1 counts are lost if the process is killed hard.

package com.orb.guard

import android.content.Context
import android.content.SharedPreferences
import java.time.LocalDate

object FirewallState {

    private const val PREFS = "orbguard_firewall"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_BLOCKLIST = "blocklist"
    private const val KEY_COUNT_PREFIX = "blocked_count_"
    private const val FLUSH_EVERY = 10
    private const val KEEP_DAYS = 7L

    // In-memory "blocked today" counter (all access is @Synchronized).
    private var dateKey = ""
    private var count = 0
    private var lastFlushed = 0

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ---- Enabled flag (the user's on/off intent) ---------------------------

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, false)

    // ---- Persisted block list ----------------------------------------------

    fun saveBlocklist(context: Context, domains: Collection<String>) {
        prefs(context).edit().putStringSet(KEY_BLOCKLIST, HashSet(domains)).apply()
    }

    fun loadBlocklist(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_BLOCKLIST, null) ?: emptySet()

    // ---- "Blocked today" counter -------------------------------------------

    /** Records one blocked DNS query (called from the TUN worker thread). */
    @Synchronized
    fun recordBlocked(context: Context) {
        val p = ensureToday(context)
        count++
        if (count - lastFlushed >= FLUSH_EVERY) flushLocked(p)
    }

    /**
     * Today's blocked count. Real work done today is reported even while the
     * firewall is currently off (it counted while it ran); 0 when nothing was
     * ever blocked today.
     */
    @Synchronized
    fun blockedToday(context: Context): Int {
        ensureToday(context)
        return count
    }

    /** Persists any unflushed counts (service stop / destroy). */
    @Synchronized
    fun flush(context: Context) {
        if (dateKey.isEmpty()) return
        flushLocked(prefs(context))
    }

    /** Rolls the in-memory counter over to today, persisting + pruning. */
    private fun ensureToday(context: Context): SharedPreferences {
        val p = prefs(context)
        val today = LocalDate.now().toString() // local date, yyyy-MM-dd
        if (dateKey != today) {
            if (dateKey.isNotEmpty() && count != lastFlushed) {
                p.edit().putInt(KEY_COUNT_PREFIX + dateKey, count).apply()
            }
            dateKey = today
            count = p.getInt(KEY_COUNT_PREFIX + today, 0)
            lastFlushed = count
            pruneOldCounts(p, today)
        }
        return p
    }

    private fun flushLocked(p: SharedPreferences) {
        p.edit().putInt(KEY_COUNT_PREFIX + dateKey, count).apply()
        lastFlushed = count
    }

    /** Drops counter keys older than KEEP_DAYS (yyyy-MM-dd sorts naturally). */
    private fun pruneOldCounts(p: SharedPreferences, today: String) {
        val cutoff = KEY_COUNT_PREFIX +
            LocalDate.parse(today).minusDays(KEEP_DAYS).toString()
        val stale = p.all.keys.filter { it.startsWith(KEY_COUNT_PREFIX) && it < cutoff }
        if (stale.isEmpty()) return
        val editor = p.edit()
        stale.forEach { editor.remove(it) }
        editor.apply()
    }
}
