package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import com.wellscreen.app.TenMinuteWarningPolicy
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-045
class TenMinuteWarningPolicyCase045Test {
    @Test
    fun case045() = testCase(
        id = "CASE-045",
        file = "$KOTLIN_TESTS/TenMinuteWarningPolicyCase045Test.kt",
        codeTested = "$KOTLIN_MAIN/TenMinuteWarningPolicy.kt",
        description = "Guardian sets a valid daily limit and the child uses the app until it ends.",
        expected = "Limit is saved; the child gets “Less than 10 minutes remaining”, then “Time limit reached”.",
    ) {
        val limit = 30 // minutes, saved by the guardian
        val minute = 60_000L
        // 25 minutes used: 5 minutes left -> the warning fires.
        assertTrue(TenMinuteWarningPolicy.qualifies(limit, 5 * minute))
        // 15 minutes used: 15 minutes left -> no warning yet.
        assertFalse(TenMinuteWarningPolicy.qualifies(limit, 15 * minute))
        // 30 minutes used: nothing left -> no warning, the app is blocked.
        assertFalse(TenMinuteWarningPolicy.qualifies(limit, 0L))
        val badge = BlockScreenText.badge(false, false, null, null, isDailyTimeLimitBlock = true)
        assertEquals("Time limit reached", badge)
        "30-minute limit: with 15 min left no warning; with 5 min left the \"Less than 10 minutes remaining\" warning qualifies; at 0 min the block screen shows \"$badge\""
    }
}
