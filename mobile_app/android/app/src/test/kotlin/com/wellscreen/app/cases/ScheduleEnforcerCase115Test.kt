package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import com.wellscreen.app.ScheduleEnforcer
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-115
class ScheduleEnforcerCase115Test {
    @Test
    fun case115() = testCase(
        id = "CASE-115",
        file = "$KOTLIN_TESTS/ScheduleEnforcerCase115Test.kt",
        codeTested = "$KOTLIN_MAIN/ScheduleEnforcer.kt",
        description = "Child reaches the break timer while using one app.",
        expected = "The child sees a break reminder.",
    ) {
        val schedule = ScheduleEnforcer.Schedule(
            bedtimeEnabled = false, bedtimeStart = -1, bedtimeEnd = -1,
            focusUntilMs = 0L, focusDurationMs = 0L,
            breaksEnabled = true, breakAfterMinutes = 45, breakMinutes = 10,
        )
        val start = 5_000_000L
        assertTrue(ScheduleEnforcer.needsBreak(listOf(1 to start), start + 45 * 60_000L, schedule))
        val title = BlockScreenText.title(false, false, "break", null, "TikTok")
        assertEquals("Take a break", title)
        "After 45 minutes non-stop in one app the break timer is reached and the child sees \"$title\""
    }
}
