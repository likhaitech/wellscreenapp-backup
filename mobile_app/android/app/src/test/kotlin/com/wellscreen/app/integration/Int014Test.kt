package com.wellscreen.app.integration

import com.wellscreen.app.GrantClock
import com.wellscreen.app.SiteBlocker
import com.wellscreen.app.cases.KOTLIN_MAIN
import com.wellscreen.app.cases.testCase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test


class Int014Test {
    @Test
    fun int014() = testCase(
        id = "INT-014",
        file = "$INT_TESTS/Int014Test.kt",
        codeTested = "$KOTLIN_MAIN/GrantClock.kt + SiteBlocker.kt",
        description = "Child requests emergency access during a restricted period (Emergency Access -> Rule Management and Restriction).",
        expected = "The guardian is notified and approves the request for 1 to 120 minutes or denies it, and the child’s device applies the result; harmful sites stay blocked.",
    ) {
        val minute = 60_000L
        val rules = SiteBlocker.WebsiteRules(emptySet(), emptySet())
        val dataset = mapOf("pornhub.com" to "adult")


        val before = SiteBlocker.decide("tiktok.com", rules, dataset, { false },
            appDomains = setOf("tiktok.com"), limitDomains = emptySet())
        assertEquals("blocked_app", before?.category)

        // The guardian approves 15 minutes (Emergency Access).
        val approvedAt = 1_800_000_000_000L
        val until = approvedAt + 15 * minute
        val start = GrantClock.evaluate(null, until, 15 * minute, approvedAt, 100_000L, 3)
        assertTrue(start.active)

        // Rule Management while access is on: blocked apps and limits are
        // lifted (their websites are cleared) ...
        val during = SiteBlocker.decide("tiktok.com", rules, dataset, { false },
            appDomains = emptySet(), limitDomains = emptySet())
        assertNull(during)
        // ... but harmful sites stay blocked.
        val harmful = SiteBlocker.decide("pornhub.com", rules, dataset, { false },
            appDomains = emptySet(), limitDomains = emptySet())
        assertEquals("adult", harmful?.category)

        // After 15 minutes the restriction returns.
        val ended = GrantClock.evaluate(start.state, until, 15 * minute,
            approvedAt + 15 * minute, 100_000L + 15 * minute, 3)
        assertFalse(ended.active)
        "Approved for 15 minutes: TikTok's block is lifted during the approval while pornhub.com stays blocked (${harmful?.category}); at 15 minutes the restriction returns"
    }
}
