package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PageCheckExemptTest {
    @Test
    fun searchEnginesAndBigPlatformsAreExempt() {
        for (d in listOf(
            "google.com", "www.google.com", "google.com.ph", "google.co.uk",
            "news.google.com", "bing.com", "duckduckgo.com", "m.youtube.com",
            "web.facebook.com", "x.com", "www.reddit.com",
        )) assertTrue(d, PageCheckExempt.isExempt(d))
    }

    @Test
    fun lookAlikesAndOtherSitesAreNotExempt() {
        for (d in listOf(
            "", "lodiupdates.com", "google-casino.com", "googlecasino.ph",
            "google.casino-site.com", "notyoutube.com", "xx.com",
        )) assertFalse(d, PageCheckExempt.isExempt(d))
    }
}
