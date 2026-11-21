package com.wellscreen.app.cases

import com.wellscreen.app.TenMinuteWarningPolicy
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-114
class TenMinuteWarningPolicyCase114Test {
    @Test
    fun case114() = testCase(
        id = "CASE-114",
        file = "$KOTLIN_TESTS/TenMinuteWarningPolicyCase114Test.kt",
        codeTested = "$KOTLIN_MAIN/TenMinuteWarningPolicy.kt",
        description = "Child has less than 10 minutes left on a limited app.",
        expected = "The child receives “Less than 10 minutes remaining”.",
    ) {
        val minute = 60_000L
        assertTrue(TenMinuteWarningPolicy.qualifies(60, 9 * minute))
        assertTrue(TenMinuteWarningPolicy.qualifies(60, 10 * minute))
        assertFalse(TenMinuteWarningPolicy.qualifies(60, 11 * minute))
        "1-hour limit: at 11 min left no warning; at 10 and 9 min left the \"Less than 10 minutes remaining\" notification qualifies"
    }
}
