package com.wellscreen.app.cases

import com.wellscreen.app.GrantClock
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-139
class GrantClockCase139Test {
    @Test
    fun case139() = testCase(
        id = "CASE-139",
        file = "$KOTLIN_TESTS/GrantClockCase139Test.kt",
        codeTested = "$KOTLIN_MAIN/GrantClock.kt",
        description = "Guardian approves the request.",
        expected = "Child sees “Urgent Access Approved”; blocked apps, schedules, and used-up limits open until the time ends.",
    ) {
        val minute = 60_000L
        val approvedAt = 1_800_000_000_000L
        val until = approvedAt + 15 * minute
        val start = GrantClock.evaluate(null, until, 15 * minute, approvedAt, 100_000L, 3)
        assertTrue(start.active)
        val later = GrantClock.evaluate(start.state, until, 15 * minute, approvedAt + 14 * minute, 100_000L + 14 * minute, 3)
        assertTrue(later.active)
        val ended = GrantClock.evaluate(start.state, until, 15 * minute, approvedAt + 15 * minute, 100_000L + 15 * minute, 3)
        assertFalse(ended.active)
        "15-minute approval: apps open at the start and at 14 min, and lock again at 15 min (the phone's own clock is used, so changing the time does not extend it)"
    }
}
