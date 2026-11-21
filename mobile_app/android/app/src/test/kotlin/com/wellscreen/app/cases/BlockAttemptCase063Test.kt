package com.wellscreen.app.cases

import com.wellscreen.app.BlockAttempt
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-063 - one visit with several reloads counts as one blocked attempt.
class BlockAttemptCase063Test {
    @Test
    fun case063() = testCase(
        id = "CASE-063",
        file = "$KOTLIN_TESTS/BlockAttemptCase063Test.kt",
        codeTested = "$KOTLIN_MAIN/BlockAttempt.kt",
        description = "Child opens a blocked website and the browser reloads it several times within 10 seconds.",
        expected = "The visit is counted as one blocked attempt in Restriction Enforcement.",
    ) {
        // The browser re-shows the blocked site 6 times within 0.3 s.
        val reloadsMs = listOf(0L, 50L, 100L, 150L, 200L, 300L)
        var lastDomain: String? = null
        var lastTime = 0L
        var attempts = 0
        for (t in reloadsMs) {
            if (!BlockAttempt.isSameAttempt(lastDomain, lastTime, "bet365.com", t)) attempts++
            lastDomain = "bet365.com"; lastTime = t
        }
        assertTrue(attempts == 1)
        // A new visit after 10 seconds is a new attempt.
        assertFalse(BlockAttempt.isSameAttempt("bet365.com", 300L, "bet365.com", 300L + BlockAttempt.WINDOW_MS))
        "6 reloads within 0.3 seconds were counted as 1 blocked attempt (a new visit after 10 seconds counts again)"
    }
}
