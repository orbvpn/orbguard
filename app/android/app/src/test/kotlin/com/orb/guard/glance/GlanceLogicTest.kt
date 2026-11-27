package com.orb.guard.glance

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId

class GlanceLogicTest {
    private val zone: ZoneId = ZoneId.of("Europe/London")
    private fun ms(y: Int, mo: Int, d: Int, h: Int, mi: Int) =
        LocalDateTime.of(y, mo, d, h, mi).atZone(zone).toInstant().toEpochMilli()

    private val now = ms(2026, 11, 25, 14, 0)
    private val label: (Long) -> String = { "Checked T$it" }

    private fun state(
        moment: Moment = Moment.CLEAR,
        title: String = "All clear",
        line: String? = null,
        score: Int? = 912,
        gaps: List<Double> = emptyList(),
        ring: RingStyle = RingStyle.OPEN,
        checkedAt: Long? = ms(2026, 11, 25, 9, 41),
        staleAt: Long? = ms(2026, 11, 27, 9, 41),
        staleTitle: String? = "Nothing found last time",
        staleLine: String? = "Time for a fresh check",
    ) = GlanceState(moment, title, line, score, gaps, ring, checkedAt, staleAt, staleTitle, staleLine)

    // ---- the check time

    @Test fun checkedTodayShowsTheClock() {
        val text = GlanceLogic.checkedLabel(ms(2026, 11, 25, 9, 41), now, zone, { "09:41" }, { "25 Nov" })
        assertEquals("Checked 09:41", text)
    }

    @Test fun checkedAnotherDayShowsTheDate() {
        val text = GlanceLogic.checkedLabel(ms(2026, 11, 22, 23, 59), now, zone, { "23:59" }, { "22 Nov" })
        assertEquals("Checked 22 Nov", text)
    }

    @Test fun todayIsTheLocalDateNotUtc() {
        // 00:30 local on 25 Nov in Tokyo is still 24 Nov in UTC.
        val tokyo = ZoneId.of("Asia/Tokyo")
        val checked = LocalDateTime.of(2026, 11, 25, 0, 30).atZone(tokyo).toInstant().toEpochMilli()
        val later = LocalDateTime.of(2026, 11, 25, 20, 0).atZone(tokyo).toInstant().toEpochMilli()
        assertEquals("Checked t", GlanceLogic.checkedLabel(checked, later, tokyo, { "t" }, { "d" }))
    }

    @Test fun nextMidnightIsTheStartOfTomorrowLocally() {
        assertEquals(ms(2026, 11, 26, 0, 0), GlanceLogic.nextMidnight(now, zone))
        // At midnight exactly, the next one is a day later.
        assertEquals(ms(2026, 11, 27, 0, 0), GlanceLogic.nextMidnight(ms(2026, 11, 26, 0, 0), zone))
    }

    @Test fun nextMidnightAcrossDaylightSaving() {
        // 29 Mar 2026 London springs forward; midnight is still 00:00 local.
        val sat = ms(2026, 3, 28, 22, 0)
        assertEquals(ms(2026, 3, 29, 0, 0), GlanceLogic.nextMidnight(sat, zone))
    }

    // ---- the stale rule

    @Test fun staleFromStaleAtOn() {
        val s = state(staleAt = now)
        assertTrue(GlanceLogic.isStale(s, now))
        assertFalse(GlanceLogic.isStale(s, now - 1))
        assertFalse(GlanceLogic.isStale(state(staleAt = null), now))
    }

    @Test fun staleClearSwapsTheWordsAndHidesTheScore() {
        val checked = ms(2026, 11, 16, 9, 41)
        val f = GlanceLogic.face(state(checkedAt = checked, staleAt = now - 1), now, label)
        assertEquals("Nothing found last time", f.title)
        assertEquals("Time for a fresh check", f.line)
        // The time still says when, under the stale line.
        assertEquals("Checked T$checked", f.checkedUnder)
        assertNull(f.score)
        assertEquals("Nothing found last time", f.description)
        assertFalse(f.chip)
    }

    @Test fun staleGapKeepsItsWordsButLosesTheScore() {
        val s = state(
            moment = Moment.GAP, title = "One gap to close", line = "Your email was in a data breach",
            score = 812, gaps = listOf(150.0), staleAt = now - 1, staleTitle = null, staleLine = null,
        )
        val f = GlanceLogic.face(s, now, label)
        assertEquals("One gap to close", f.title)
        assertEquals("Your email was in a data breach", f.line)
        assertNull(f.score)
        assertTrue(f.chip)
        assertEquals(listOf(150.0), f.gaps)
        assertEquals("Checked T${ms(2026, 11, 25, 9, 41)}", f.checkedUnder)
    }

    // ---- which words to show

    @Test fun beforeAnyUpdateOnlyOpenOrbGuard() {
        val f = GlanceLogic.face(null, now, label)
        assertEquals("Open OrbGuard", f.title)
        assertNull(f.line)
        assertNull(f.score)
        assertNull(f.ring)
        assertFalse(f.chip)
        assertEquals("Open OrbGuard", f.description)
    }

    @Test fun clearShowsTheCheckTimeAndTheScore() {
        val checked = ms(2026, 11, 25, 9, 41)
        val f = GlanceLogic.face(state(checkedAt = checked), now, label)
        assertEquals("All clear", f.title)
        assertEquals("Checked T$checked", f.line)
        assertNull(f.checkedUnder)
        assertEquals(912, f.score)
        assertFalse(f.chip)
        assertEquals("All clear. Privacy score 912", f.description)
    }

    @Test fun clearWithoutACheckTimeShowsNoLine() {
        assertNull(GlanceLogic.face(state(checkedAt = null), now, label).line)
    }

    @Test fun gapShowsItsLineAndTheChip() {
        val s = state(
            moment = Moment.GAP, title = "One gap to close", line = "Your email was in a data breach",
            score = 812, gaps = listOf(150.0), staleTitle = null,
        )
        val f = GlanceLogic.face(s, now, label)
        assertEquals("Your email was in a data breach", f.line)
        assertEquals(812, f.score)
        assertTrue(f.chip)
        assertNull(f.checkedUnder)
        assertEquals("One gap to close. Privacy score 812", f.description)
    }

    @Test fun freshShowsItsLineTheChipAndNoTime() {
        val s = state(
            moment = Moment.FRESH, title = "Not checked yet", line = "One tap. The check runs on this phone.",
            score = null, ring = RingStyle.FRESH, checkedAt = null, staleAt = null, staleTitle = null, staleLine = null,
        )
        val f = GlanceLogic.face(s, now, label)
        assertEquals("Not checked yet", f.title)
        assertEquals("One tap. The check runs on this phone.", f.line)
        assertNull(f.score)
        assertTrue(f.chip)
        assertEquals(RingStyle.FRESH, f.ring)
    }

    // ---- redraw times

    @Test fun redrawsAtStaleAtAndMidnight() {
        val s = state(staleAt = ms(2026, 11, 27, 9, 41))
        assertEquals(listOf(ms(2026, 11, 27, 9, 41), ms(2026, 11, 26, 0, 0)), GlanceLogic.redrawTimes(s, now, zone))
        assertEquals(listOf(ms(2026, 11, 26, 0, 0)), GlanceLogic.redrawTimes(state(staleAt = now - 1), now, zone))
        assertTrue(GlanceLogic.redrawTimes(null, now, zone).isEmpty())
    }

    // ---- gap arcs

    @Test fun geometryMatchesTheBrief() {
        assertEquals(74.0, GlanceLogic.CENTRE, 0.0)
        assertEquals(44.0, GlanceLogic.THICKNESS, 0.0)
        assertEquals(17.03, GlanceLogic.CAP_DEGREES, 0.01)
        assertEquals(24.53, GlanceLogic.GAP_HALF, 0.01)
    }

    @Test fun noGapsIsOneWholeCircle() {
        val arcs = GlanceLogic.arcs(emptyList())
        assertEquals(1, arcs.size)
        assertTrue(arcs[0].isWhole)
    }

    @Test fun oneGapLeavesOneArcFromItsFarSideRoundToItsNearSide() {
        val arcs = GlanceLogic.arcs(listOf(150.0))
        assertEquals(1, arcs.size)
        assertEquals(150 + GlanceLogic.GAP_HALF, arcs[0].start, 1e-9)
        assertEquals(360 - 2 * GlanceLogic.GAP_HALF, arcs[0].sweep, 1e-9)
    }

    @Test fun severalGapsRunFromEachFarSideToTheNextNearSide() {
        val h = GlanceLogic.GAP_HALF
        val arcs = GlanceLogic.arcs(listOf(270.0, 30.0, -210.0)) // -210 is 150 on the dial
        assertEquals(3, arcs.size)
        assertEquals(30 + h, arcs[0].start, 1e-9)
        assertEquals(120 - 2 * h, arcs[0].sweep, 1e-9)
        assertEquals(150 + h, arcs[1].start, 1e-9)
        assertEquals(120 - 2 * h, arcs[1].sweep, 1e-9)
        assertEquals(270 + h, arcs[2].start, 1e-9)
        assertEquals(120 - 2 * h, arcs[2].sweep, 1e-9)
    }

    @Test fun gapsTooCloseLeaveNoSliver() {
        val arcs = GlanceLogic.arcs(listOf(100.0, 120.0))
        assertEquals(1, arcs.size)
        assertEquals(120 + GlanceLogic.GAP_HALF, arcs[0].start, 1e-9)
    }

    @Test fun dotsThinOutAtSmallSizes() {
        assertEquals(51, GlanceLogic.dotCount(92.0))
        assertEquals(12, GlanceLogic.dotCount(16.0))
        assertEquals(12, GlanceLogic.dotCount(8.0))
    }

    // ---- parsing the channel map

    private fun map(vararg extra: Pair<String, Any?>): Map<String, Any?> = mapOf(
        "v" to 1, "moment" to "gap", "title" to "One gap to close", "line" to "Your email was in a data breach",
        "score" to 812, "gaps" to listOf(150.0), "ring" to "open", "checkedAt" to 1764063660000L,
        "staleAt" to null, "staleTitle" to null, "staleLine" to null,
    ) + extra

    @Test fun parsesTheContract() {
        val s = GlanceParse.from(map())!!
        assertEquals(Moment.GAP, s.moment)
        assertEquals(RingStyle.OPEN, s.ring)
        assertEquals(812, s.score)
        assertEquals(listOf(150.0), s.gaps)
        assertEquals(1764063660000L, s.checkedAt)
        assertNull(s.staleAt)
    }

    @Test fun refusesWhatItCannotDrawHonestly() {
        assertNull(GlanceParse.from(map("v" to 2)))
        assertNull(GlanceParse.from(map("moment" to "unknown")))
        assertNull(GlanceParse.from(map("ring" to "spinning")))
        assertNull(GlanceParse.from(map("title" to "")))
        // Empty words count as none, as on iOS.
        assertNull(GlanceParse.from(map("line" to ""))!!.line)
        assertNull(GlanceParse.from(map("score" to 4000))!!.score)
        // Ints arrive as Int or Long; gaps may arrive as ints.
        assertEquals(listOf(150.0), GlanceParse.from(map("gaps" to listOf(150)))!!.gaps)
    }
}
