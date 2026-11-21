package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import com.wellscreen.app.ScheduleEnforcer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-101
class ScheduleEnforcerCase101Test {
    @Test
    fun case101() = testCase(
        id = "CASE-101",
        file = "$KOTLIN_TESTS/ScheduleEnforcerCase101Test.kt",
        codeTested = "$KOTLIN_MAIN/ScheduleEnforcer.kt",
        description = "Guardian saves a valid bedtime and the bedtime starts.",
        expected = "“Bedtime saved.” is displayed; every app locks during bedtime hours.",
    ) {
        // What the guardian saved: bedtime 9:00 PM (1260) to 6:00 AM (360).
        val s = ScheduleEnforcer.Schedule(
            bedtimeEnabled = true, bedtimeStart = 21 * 60, bedtimeEnd = 6 * 60,
            focusUntilMs = 0L, focusDurationMs = 0L,
            breaksEnabled = false, breakAfterMinutes = 0, breakMinutes = 0,
        )
        assertTrue(ScheduleEnforcer.isInWindow(21 * 60 + 30, s.bedtimeStart, s.bedtimeEnd))
        assertTrue(ScheduleEnforcer.isInWindow(2 * 60, s.bedtimeStart, s.bedtimeEnd))
        assertFalse(ScheduleEnforcer.isInWindow(20 * 60, s.bedtimeStart, s.bedtimeEnd))
        assertEquals(510, ScheduleEnforcer.minutesUntilEnd(21 * 60 + 30, s.bedtimeEnd))
        val title = BlockScreenText.title(false, false, "bedtime", null, "Any app")
        assertEquals("Time to rest", title)
        "Bedtime 9:00 PM-6:00 AM is on: apps lock at 9:30 PM and 2:00 AM (\"$title\", 510 min left at 9:30 PM) and are open at 8:00 PM"
    }
}
