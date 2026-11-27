package com.orb.guard.glance

import java.time.Instant
import java.time.ZoneId
import kotlin.math.PI
import kotlin.math.roundToInt

/**
 * The glance, as Dart sends it over `com.orb.guard/glance` (`update`).
 *
 * Only the keys the Android widgets draw are kept. The Dart side decides every
 * word and every state; this side adds nothing but the time of the check.
 */
data class GlanceState(
    val moment: Moment,
    val title: String,
    val line: String?,
    val score: Int?,
    val gaps: List<Double>,
    val ring: RingStyle,
    val checkedAt: Long?,
    val staleAt: Long?,
    val staleTitle: String?,
    val staleLine: String?,
)

enum class Moment {
    FRESH, CLEAR, GAP;

    companion object {
        fun parse(raw: String?): Moment? = when (raw) {
            "fresh" -> FRESH
            "clear" -> CLEAR
            "gap" -> GAP
            else -> null
        }
    }
}

enum class RingStyle {
    /** Never checked: dots on the centre line. */
    FRESH,

    /** The band, cut at each gap. */
    OPEN,

    /** The band greyed: nothing on watch. */
    STILL;

    companion object {
        fun parse(raw: String?): RingStyle? = when (raw) {
            "fresh" -> FRESH
            "open" -> OPEN
            "still" -> STILL
            else -> null
        }
    }
}

/** One arc of the ring, in degrees clockwise from twelve o'clock. */
data class Arc(val start: Double, val sweep: Double) {
    val isWhole: Boolean get() = sweep >= 360.0
}

/**
 * What one widget shows, worked out from a [GlanceState] at one moment.
 *
 * [ring] null means the logo mark: no update has arrived yet (or what arrived
 * could not be read), so the widget says only `Open OrbGuard`.
 */
data class GlanceFace(
    val title: String,
    /** The line under the title (medium widget only): the map's line, else the check time. */
    val line: String?,
    /**
     * A second line with the check time (medium widget only): shown when a
     * stale line took the line's place, so the time still says when.
     */
    val checkedUnder: String?,
    /** The number in the ring's hole, or null for an empty hole. */
    val score: Int?,
    val ring: RingStyle?,
    val gaps: List<Double>,
    /** The amber `Open OrbGuard` chip (medium widget only). */
    val chip: Boolean,
    /** What the ring image says to a screen reader. */
    val description: String,
)

object GlanceLogic {
    const val OPEN_ORBGUARD = "Open OrbGuard"
    private const val CHECKED = "Checked"
    private const val PRIVACY_SCORE = "Privacy score"

    // The ring on its 200 unit box (app/lib/widgets/home/orb_ring.dart).
    const val BOX = 200.0
    const val OUTER = 96.0
    const val INNER = 52.0
    const val CENTRE = (OUTER + INNER) / 2 // 74
    const val THICKNESS = OUTER - INNER // 44

    /** Degrees a round end reaches past the arc it caps (17.03). */
    val CAP_DEGREES: Double = (THICKNESS / 2) / CENTRE * 180 / PI

    /** Daylight between the two round ends of a gap. */
    const val GAP_OPENING = 15.0

    /** How far either side of its centre a gap is cut on the centre line (24.53). */
    val GAP_HALF: Double = GAP_OPENING / 2 + CAP_DEGREES

    /** The face before any update has arrived. */
    val waiting = GlanceFace(
        title = OPEN_ORBGUARD,
        line = null,
        checkedUnder = null,
        score = null,
        ring = null,
        gaps = emptyList(),
        chip = false,
        description = OPEN_ORBGUARD,
    )

    /** True from [GlanceState.staleAt] on. */
    fun isStale(state: GlanceState, now: Long): Boolean {
        val staleAt = state.staleAt ?: return false
        return now >= staleAt
    }

    /**
     * What to draw for [state] at [now]. [checkedLabel] is the formatted check
     * time with its leading `Checked` (see [checkedLabel]); it is used only when
     * there is no line to show.
     */
    fun face(state: GlanceState?, now: Long, checkedLabel: (Long) -> String): GlanceFace {
        if (state == null) return waiting
        val stale = isStale(state, now)
        val swap = stale && state.staleTitle != null
        val title = if (swap) state.staleTitle!! else state.title
        val given: String? = if (swap) state.staleLine else state.line
        val checked = state.checkedAt?.let(checkedLabel)
        val score = if (stale) null else state.score
        return GlanceFace(
            title = title,
            line = given ?: checked,
            checkedUnder = if (stale && given != null) checked else null,
            score = score,
            ring = state.ring,
            gaps = if (state.ring == RingStyle.FRESH) emptyList() else state.gaps,
            chip = state.moment == Moment.GAP || state.moment == Moment.FRESH,
            // Read the way the iOS widget reads it: the words on it, in order.
            description = if (score != null) "$title. $PRIVACY_SCORE $score" else title,
        )
    }

    /**
     * `Checked 09:41` when [checkedAt] falls on today's local date, otherwise
     * `Checked 22 Nov`. The two formatters come from the system so the clock
     * follows its 12 or 24 hour setting and the date its locale.
     */
    fun checkedLabel(
        checkedAt: Long,
        now: Long,
        zone: ZoneId,
        time: (Long) -> String,
        date: (Long) -> String,
    ): String {
        val day = Instant.ofEpochMilli(checkedAt).atZone(zone).toLocalDate()
        val today = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val text = if (day == today) time(checkedAt) else date(checkedAt)
        return "$CHECKED $text"
    }

    /** The first local midnight after [now], in ms since epoch. */
    fun nextMidnight(now: Long, zone: ZoneId): Long {
        val tomorrow = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1)
        return tomorrow.atStartOfDay(zone).toInstant().toEpochMilli()
    }

    /**
     * Moments after [now] at which the widget must be drawn again: [GlanceState.staleAt]
     * while it is still ahead, and the next local midnight (so "today" stays true).
     */
    fun redrawTimes(state: GlanceState?, now: Long, zone: ZoneId): List<Long> {
        if (state == null) return emptyList()
        val times = mutableListOf<Long>()
        state.staleAt?.let { if (it > now) times.add(it) }
        if (state.checkedAt != null) times.add(nextMidnight(now, zone))
        return times
    }

    /**
     * The band, broken where the gaps are: one arc from the far side of each gap
     * to the near side of the next. No gaps: one whole circle. Gaps closer than
     * a gap's width leave no band between them, so that arc is dropped.
     */
    fun arcs(gaps: List<Double>): List<Arc> {
        if (gaps.isEmpty()) return listOf(Arc(0.0, 360.0))
        val at = gaps.map { onDial(it) }.distinct().sorted()
        val arcs = mutableListOf<Arc>()
        for (i in at.indices) {
            val last = i == at.size - 1
            val next = if (last) at.first() + 360 else at[i + 1]
            val from = at[i] + GAP_HALF
            val to = next - GAP_HALF
            if (to > from) arcs.add(Arc(from, to - from))
        }
        return arcs
    }

    /** Dots on the centre line of a never-checked ring of [ringDp]: 51 at full size, about 12 at 16. */
    fun dotCount(ringDp: Double): Int {
        val full = (2 * PI * CENTRE / 9.1).roundToInt() // 51
        val scaled = (12.0 * ringDp / 16.0).roundToInt()
        return scaled.coerceIn(12, full)
    }

    private fun onDial(degrees: Double): Double = (degrees % 360 + 360) % 360
}

/** Parses the channel map, already turned into plain Kotlin values. Null if it cannot be drawn honestly. */
object GlanceParse {
    fun from(map: Map<String, Any?>): GlanceState? {
        val v = (map["v"] as? Number)?.toInt() ?: return null
        if (v != 1) return null
        val moment = Moment.parse(map["moment"] as? String) ?: return null
        val ring = RingStyle.parse(map["ring"] as? String) ?: return null
        val title = (map["title"] as? String)?.takeIf { it.isNotBlank() } ?: return null
        val gaps = (map["gaps"] as? List<*>).orEmpty().mapNotNull { (it as? Number)?.toDouble() }
        return GlanceState(
            moment = moment,
            title = title,
            line = text(map["line"]),
            score = (map["score"] as? Number)?.toInt()?.takeIf { it in 0..1000 },
            gaps = gaps.filter { it.isFinite() },
            ring = ring,
            checkedAt = (map["checkedAt"] as? Number)?.toLong(),
            staleAt = (map["staleAt"] as? Number)?.toLong(),
            staleTitle = text(map["staleTitle"]),
            staleLine = text(map["staleLine"]),
        )
    }

    private fun text(v: Any?): String? = (v as? String)?.takeIf { it.isNotEmpty() }
}
