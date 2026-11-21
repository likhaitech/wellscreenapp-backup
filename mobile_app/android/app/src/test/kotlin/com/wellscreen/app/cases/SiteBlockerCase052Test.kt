package com.wellscreen.app.cases

import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// CASE-052
class SiteBlockerCase052Test {
    @Test
    fun case052() = testCase(
        id = "CASE-052",
        file = "$KOTLIN_TESTS/SiteBlockerCase052Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteBlocker.kt",
        description = "Guardian adds a site that is flagged automatically to Allowed websites.",
        expected = "The site opens on the child device because the guardian’s Allow comes first.",
    ) {
        val dataset = mapOf("bet-example.com" to "gambling")
        val none = SiteBlocker.WebsiteRules(emptySet(), emptySet())
        val before = SiteBlocker.decide(domain = "bet-example.com", rules = none, dataset = dataset, isAiGambling = { false })
        assertEquals("gambling", before?.category)
        val allowed = SiteBlocker.WebsiteRules(emptySet(), setOf("bet-example.com"))
        val after = SiteBlocker.decide(domain = "bet-example.com", rules = allowed, dataset = dataset, isAiGambling = { true })
        assertNull(after)
        "bet-example.com was flagged (${before?.category}, by ${before?.source}); after the guardian's Allow it is not blocked (decision: open)"
    }
}
