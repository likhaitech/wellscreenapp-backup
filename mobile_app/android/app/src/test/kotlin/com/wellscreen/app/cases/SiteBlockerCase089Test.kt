package com.wellscreen.app.cases

import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// CASE-089
class SiteBlockerCase089Test {
    @Test
    fun case089() = testCase(
        id = "CASE-089",
        file = "$KOTLIN_TESTS/SiteBlockerCase089Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteBlocker.kt",
        description = "Guardian adds a website to Blocked websites.",
        expected = "The site and its subdomains are blocked on the child device.",
    ) {
        // The guardian's Blocked websites list, as synced to the child phone.
        val rules = SiteBlocker.WebsiteRules(setOf("example.com"), emptySet())
        fun decide(domain: String) = SiteBlocker.decide(
            domain = domain, rules = rules, dataset = emptyMap(), isAiGambling = { false },
        )
        val site = decide("example.com")
        val www = decide("www.example.com")
        val sub = decide("m.example.com")
        assertEquals("parent_rule", site?.source)
        assertEquals("parent_rule", www?.source)
        assertEquals("parent_rule", sub?.source)
        assertNull(decide("notexample.com"))
        "example.com, www.example.com and m.example.com are blocked (reason: ${site?.source}); notexample.com is not affected"
    }
}
