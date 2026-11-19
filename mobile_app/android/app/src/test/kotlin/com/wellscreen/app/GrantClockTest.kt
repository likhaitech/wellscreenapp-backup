package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class GrantClockTest {
    private val min = 60_000L
    private val wall = 1_800_000_000_000L

    @Test
    fun grantEndsAfterRealTimeEvenIfClockIsSetBack() {
        // Guardian approves 5 minutes.
        val first = GrantClock.evaluate(null, wall + 5 * min, 5 * min, wall, 1_000_000L, 3)
        assertTrue(first.active)
        // 6 real minutes later the child has set the wall clock back 1 hour.
        val later = GrantClock.evaluate(
            first.state, wall + 5 * min, 5 * min, wall - 60 * min, 1_000_000L + 6 * min, 3,
        )
        assertFalse(later.active)
    }

    @Test
    fun grantStaysActiveInsideItsTime() {
        val first = GrantClock.evaluate(null, wall + 30 * min, 30 * min, wall, 5_000L, 1)
        val later = GrantClock.evaluate(first.state, wall + 30 * min, 30 * min, wall + 10 * min, 5_000L + 10 * min, 1)
        assertTrue(later.active)
    }

    @Test
    fun clockSetBackBeforeApprovalIsLimitedByChosenDuration() {
        // Child clock is 1 hour behind when the 15-minute approval arrives.
        val first = GrantClock.evaluate(null, wall + 15 * min, 15 * min, wall - 60 * min, 0L, 1)
        assertTrue(first.active)
        val after16 = GrantClock.evaluate(first.state, wall + 15 * min, 15 * min, wall - 44 * min, 16 * min, 1)
        assertFalse(after16.active)
    }

    @Test
    fun rebootEndsTheGrant() {
        val first = GrantClock.evaluate(null, wall + 30 * min, 30 * min, wall, 50 * min, 7)
        assertFalse(GrantClock.evaluate(first.state, wall + 30 * min, 30 * min, wall + min, 2 * min, 8).active)
        // Same boot count reported but the boot clock went backwards.
        assertFalse(GrantClock.evaluate(first.state, wall + 30 * min, 30 * min, wall + min, 2 * min, 7).active)
    }

    @Test
    fun expiredOrMissingGrantIsInactive() {
        assertFalse(GrantClock.evaluate(null, 0L, 0L, wall, 0L, 1).active)
        assertFalse(GrantClock.evaluate(null, wall - min, 0L, wall, 0L, 1).active)
    }

    @Test
    fun newGrantReplacesOldState() {
        val old = GrantClock.evaluate(null, wall + min, min, wall, 0L, 1)
        val next = GrantClock.evaluate(old.state, wall + 90 * min, 30 * min, wall + 60 * min, 60 * min, 1)
        assertTrue(next.active)
    }
}
