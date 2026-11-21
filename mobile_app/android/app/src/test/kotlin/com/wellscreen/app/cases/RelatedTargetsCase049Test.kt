package com.wellscreen.app.cases

import com.wellscreen.app.RelatedTargets
import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-049
class RelatedTargetsCase049Test {
    @Test
    fun case049() = testCase(
        id = "CASE-049",
        file = "$KOTLIN_TESTS/RelatedTargetsCase049Test.kt",
        codeTested = "$KOTLIN_MAIN/RelatedTargets.kt",
        description = "Guardian blocks Facebook; child opens Facebook Lite and facebook.com.",
        expected = "The Lite version and the website are also blocked.",
    ) {
        val restricted = setOf("com.facebook.katana") // Facebook blocked
        val lite = RelatedTargets.blockingPackageFor("com.facebook.lite", restricted)
        assertEquals("com.facebook.katana", lite)
        val domains = RelatedTargets.domainsFor(restricted)
        assertTrue("facebook.com" in domains)
        val site = SiteBlocker.decide(
            domain = "m.facebook.com",
            rules = SiteBlocker.WebsiteRules(emptySet(), emptySet()),
            dataset = emptyMap(),
            isAiGambling = { false },
            appDomains = domains,
        )
        assertEquals("blocked_app", site?.category)
        "Facebook Lite is blocked because Facebook ($lite) is blocked; facebook.com (m.facebook.com) is blocked as the website of a blocked app"
    }
}
