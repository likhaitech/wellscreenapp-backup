package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleEnforcerTest {
    private val min = 60_000L

    @Test
    fun bedtimeWindowAcrossMidnight() {
        val start = 21 * 60
        val end = 6 * 60
        assertTrue(ScheduleEnforcer.isInWindow(22 * 60, start, end))
        assertTrue(ScheduleEnforcer.isInWindow(2 * 60, start, end))
        assertFalse(ScheduleEnforcer.isInWindow(6 * 60, start, end))
        assertFalse(ScheduleEnforcer.isInWindow(15 * 60, start, end))
        assertEquals(8 * 60, ScheduleEnforcer.minutesUntilEnd(22 * 60, end))
        assertEquals(4 * 60, ScheduleEnforcer.minutesUntilEnd(2 * 60, end))
    }

    @Test
    fun daytimeWindowAndEmptyWindow() {
        assertTrue(ScheduleEnforcer.isInWindow(13 * 60, 12 * 60, 14 * 60))
        assertFalse(ScheduleEnforcer.isInWindow(14 * 60, 12 * 60, 14 * 60))
        assertFalse(ScheduleEnforcer.isInWindow(10 * 60, 10 * 60, 10 * 60))
    }

    @Test
    fun sessionJoinsShortGapsAndRestartsAfterLongOnes() {
        // Opened at 0, left for 30 s, back, still open.
        val joined = listOf(1 to 0L, 2 to 10 * min, 1 to 10 * min + 30_000L)
        assertEquals(0L, ScheduleEnforcer.sessionStart(joined, min))
        // Left for 5 min: a new session starts on return.
        val restarted = listOf(1 to 0L, 2 to 10 * min, 1 to 15 * min)
        assertEquals(15 * min, ScheduleEnforcer.sessionStart(restarted, min))
        // Not in the foreground now.
        assertNull(ScheduleEnforcer.sessionStart(listOf(1 to 0L, 2 to 5 * min), min))
        assertNull(ScheduleEnforcer.sessionStart(emptyList(), min))
    }
}
