package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BreakWarningTest {
    private val min = 60_000L

    private fun schedule(after: Int, pause: Int, on: Boolean = true) =
        ScheduleEnforcer.Schedule(
            bedtimeEnabled = false, bedtimeStart = 0, bedtimeEnd = 0,
            focusUntilMs = 0L, focusDurationMs = 0L,
            breaksEnabled = on, breakAfterMinutes = after, breakMinutes = pause,
        )

    @Test
    fun warnsOnlyInTheLastMinuteBeforeTheBreak() {
        val open = listOf(1 to 0L)
        val rules = schedule(after = 10, pause = 5)
        assertFalse(ScheduleEnforcer.breakIsNear(open, 8 * min, rules))
        assertTrue(ScheduleEnforcer.breakIsNear(open, 9 * min + 30_000L, rules))
        assertFalse(ScheduleEnforcer.breakIsNear(open, 10 * min, rules))
        assertFalse(ScheduleEnforcer.breakIsNear(open, 9 * min + 30_000L, schedule(10, 5, on = false)))
    }

    @Test
    fun breakLengthReadsAsHoursAndMinutes() {
        assertEquals("5 min", ScheduleEnforcer.durationText(5))
        assertEquals("1 h", ScheduleEnforcer.durationText(60))
        assertEquals("1 h 30 min", ScheduleEnforcer.durationText(90))
    }
}
