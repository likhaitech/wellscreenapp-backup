package com.wellscreen.app.cases

import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-141
class SiteBlockerCase141Test {
    @Test
    fun case141() = testCase(
        id = "CASE-141",
        file = "$KOTLIN_TESTS/SiteBlockerCase141Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteBlocker.kt",
        description = "Child opens a harmful site during approved Emergency Access.",
        expected = "The harmful site stays blocked.",
    ) {
        // During Emergency Access the blocked-app and limit websites are
        // cleared (empty sets); harmful-site checks still run.
        val reason = SiteBlocker.decide(
            domain = "pornhub.com",
            rules = SiteBlocker.WebsiteRules(emptySet(), emptySet()),
            dataset = mapOf("pornhub.com" to "adult"),
            isAiGambling = { false },
            appDomains = emptySet(),
            limitDomains = emptySet(),
        )
        assertEquals("adult", reason?.category)
        "With Emergency Access on, pornhub.com is still blocked (${reason?.category}, by ${reason?.source})"
    }
}
