package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SiteBlockerDecideTest {
    private val noRules = SiteBlocker.WebsiteRules(emptySet(), emptySet())
    private val dataset = mapOf("bet365.com" to "gambling", "weed-shop.example" to "drugs")
    private val aiSaysGambling: (String) -> Boolean = { it == "lucky-bet777.ph" }

    private fun decide(domain: String, rules: SiteBlocker.WebsiteRules = noRules) =
        SiteBlocker.decide(domain, rules, dataset, aiSaysGambling)

    @Test
    fun parentRuleWins() {
        assertEquals(
            SiteBlocker.BlockReason("parent_rule", null),
            decide("www.example.com", SiteBlocker.WebsiteRules(setOf("example.com"), emptySet())),
        )
    }

    @Test
    fun parentAllowOverridesEverything() {
        val allow = SiteBlocker.WebsiteRules(emptySet(), setOf("bet365.com", "pornhub.com", "lucky-bet777.ph"))
        assertNull(decide("bet365.com", allow))
        assertNull(decide("pornhub.com", allow))
        assertNull(decide("lucky-bet777.ph", allow))
    }

    @Test
    fun adultKeywordReason() {
        assertEquals(SiteBlocker.BlockReason("keyword", "adult"), decide("freeporn-example.net"))
    }

    @Test
    fun listReasonCarriesCategoryAndCoversSubdomains() {
        assertEquals(SiteBlocker.BlockReason("list", "gambling"), decide("m.bet365.com"))
        assertEquals(SiteBlocker.BlockReason("list", "drugs"), decide("weed-shop.example"))
    }

    @Test
    fun aiReasonForNewGamblingSite() {
        assertEquals(SiteBlocker.BlockReason("ai", "gambling"), decide("lucky-bet777.ph"))
    }

    @Test
    fun normalSiteIsNotBlocked() {
        assertNull(decide("google.com"))
        assertNull(decide(""))
    }
}
