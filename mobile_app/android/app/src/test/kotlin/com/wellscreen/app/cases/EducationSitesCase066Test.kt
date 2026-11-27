package com.wellscreen.app.cases

import com.wellscreen.app.EducationSites
import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-066 - education and health pages are never blocked automatically.
class EducationSitesCase066Test {
    @Test
    fun case066() = testCase(
        id = "CASE-066",
        file = "$KOTLIN_TESTS/EducationSitesCase066Test.kt",
        codeTested = "$KOTLIN_MAIN/EducationSites.kt",
        description = "Child opens a Wikipedia gambling article and a kidshealth.org puberty page.",
        expected = "Neither page is blocked (education and health allow list).",
    ) {
        val noRules = SiteBlocker.WebsiteRules(emptySet(), emptySet())
        for (site in listOf("en.wikipedia.org", "kidshealth.org")) {
            assertTrue(site, EducationSites.isProtected(site))
            // Even if a list or the AI said gambling/adult, it is not blocked.
            assertNull(site, SiteBlocker.decide(site, noRules, mapOf(site to "gambling"), isAiGambling = { true }))
        }
        "en.wikipedia.org and kidshealth.org are on the education and health allow list and were not blocked"
    }
}
