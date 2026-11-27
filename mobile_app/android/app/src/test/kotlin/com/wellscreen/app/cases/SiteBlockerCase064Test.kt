package com.wellscreen.app.cases

import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

// CASE-064 - known adult site is blocked by the site list.
class SiteBlockerCase064Test {
    @Test
    fun case064() = testCase(
        id = "CASE-064",
        file = "$KOTLIN_TESTS/SiteBlockerCase064Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteBlocker.kt",
        description = "Child opens a known adult site in a supported browser.",
        expected = "The site is blocked (“Website blocked”) and logged in Recent Browsing Activity.",
    ) {
        val noRules = SiteBlocker.WebsiteRules(emptySet(), emptySet())
        val knownSites = mapOf("xvideos.com" to "adult")
        val reason = SiteBlocker.decide("www.xvideos.com", noRules, knownSites, isAiGambling = { false })
        assertNotNull(reason)
        assertEquals("adult", reason!!.category)
        "www.xvideos.com was blocked as adult (caught by the ${reason.source} check); this reason is what the block screen and Recent Browsing Activity show"
    }
}
