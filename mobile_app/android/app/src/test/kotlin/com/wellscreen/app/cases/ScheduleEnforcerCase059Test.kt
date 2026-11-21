package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import com.wellscreen.app.ScheduleEnforcer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-059
class ScheduleEnforcerCase059Test {
    @Test
    fun case059() = testCase(
        id = "CASE-059",
        file = "$KOTLIN_TESTS/ScheduleEnforcerCase059Test.kt",
        codeTested = "$KOTLIN_MAIN/ScheduleEnforcer.kt",
        description = "Guardian turns on the break timer; child uses one app non-stop.",
        expected = "“Break timer saved.” is displayed; the child’s apps pause for a short break.",
    ) {
        // What the guardian saved: break after 30 minutes, for 5 minutes.
        val schedule = ScheduleEnforcer.Schedule(
            bedtimeEnabled = false, bedtimeStart = -1, bedtimeEnd = -1,
            focusUntilMs = 0L, focusDurationMs = 0L,
            breaksEnabled = true, breakAfterMinutes = 30, breakMinutes = 5,
        )
        val min = 60_000L
        val opened = 1_000_000L
        val events = listOf(1 to opened, 2 to opened + 10 * min, 1 to opened + 10 * min + 20_000L)
        assertFalse(ScheduleEnforcer.needsBreak(events, opened + 29 * min, schedule))
        assertTrue(ScheduleEnforcer.needsBreak(events, opened + 30 * min, schedule))
        val title = BlockScreenText.title(false, false, "break", null, "YouTube")
        assertEquals("Take a break", title)
        "Break after 30 min for 5 min: at 29 min of non-stop use (a 20-second switch away does not reset it) no break; at 30 min the app pauses and shows \"$title\""
    }
}
