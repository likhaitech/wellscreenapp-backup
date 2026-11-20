package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SiteReviewTest {
    @Test
    fun onlyTheYoungestGroupBlocksHints() {
        assertTrue(SiteReview.blocksHints("6_and_below"))
        assertFalse(SiteReview.blocksHints("7_12"))
        assertFalse(SiteReview.blocksHints("13_15"))
        assertFalse(SiteReview.blocksHints(null))
    }

    @Test
    fun eventIdsAreValidAndOncePerSitePerDay() {
        val pattern = Regex("^[a-zA-Z0-9_-]{8,96}$")
        val now = 1_795_000_000_000L
        val review = SiteReview.reviewEventId("lucky-games.example.com", now)
        val request = SiteReview.requestEventId("lucky-games.example.com", now)
        assertTrue(review, pattern.matches(review))
        assertTrue(request, pattern.matches(request))
        assertTrue(review.startsWith("rev_"))
        assertTrue(request.startsWith("req_"))
        assertEquals(review, SiteReview.reviewEventId("lucky-games.example.com", now + 60_000))
    }

    @Test
    fun reasonsReadAsPlainWords() {
        assertEquals("flagged by Cloudflare's family filter", SiteReview.reasonLabel("cloudflare", "unsafe"))
        assertEquals("the page shows some gambling words", SiteReview.reasonLabel("page", "gambling"))
    }
}
