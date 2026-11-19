package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class AdultKeywordMatcherTest {

    @Test
    fun blocksKeywordDomains() {
        assertTrue(AdultKeywordMatcher.matches("pornhub.com"))
        assertTrue(AdultKeywordMatcher.matches("www.youporn.com"))
        assertTrue(AdultKeywordMatcher.matches("randomfreeporn-site.net"))
        assertTrue(AdultKeywordMatcher.matches("xvideos.com"))
        assertTrue(AdultKeywordMatcher.matches("hot.xxx"))
        assertTrue(AdultKeywordMatcher.matches("SEX.COM."))
    }

    @Test
    fun keepsKnownSafeDomainsAndTheirSubdomainsOpen() {
        assertFalse(AdultKeywordMatcher.matches("youtube.com"))
        assertFalse(AdultKeywordMatcher.matches("www.youtube.com"))
        assertFalse(AdultKeywordMatcher.matches("m.youtube.com"))
        assertFalse(AdultKeywordMatcher.matches("music.youtube.com"))
        assertFalse(AdultKeywordMatcher.matches("www.youtubekids.com"))
        assertFalse(AdultKeywordMatcher.matches("essex.ac.uk"))
        assertFalse(AdultKeywordMatcher.matches("www.sussex.ac.uk"))
    }

    @Test
    fun blocksAddedExplicitKeywords() {
        assertTrue(AdultKeywordMatcher.matches("free-hentai-site.net"))
        assertTrue(AdultKeywordMatcher.matches("xnxx.com"))
        assertTrue(AdultKeywordMatcher.matches("xhamster.com"))
        assertTrue(AdultKeywordMatcher.matches("nsfwclips.example"))
        assertTrue(AdultKeywordMatcher.matches("local-escort-ads.ph"))
    }

    @Test
    fun keepsWordsThatOnlyContainAKeywordOpen() {
        assertFalse(AdultKeywordMatcher.matches("milfordschools.org"))
        assertFalse(AdultKeywordMatcher.matches("googleanalytics.com"))
        assertFalse(AdultKeywordMatcher.matches("nakedwines.com"))
        assertFalse(AdultKeywordMatcher.matches("skylinewebcams.com"))
    }

    @Test
    fun leavesOrdinaryDomainsOpen() {
        assertFalse(AdultKeywordMatcher.matches("google.com"))
        assertFalse(AdultKeywordMatcher.matches("x.com"))
        assertFalse(AdultKeywordMatcher.matches("roblox.com"))
        assertFalse(AdultKeywordMatcher.matches("facebook.com"))
        assertFalse(AdultKeywordMatcher.matches(""))
    }

    /**
     * The bundled CSV must list the big adult sites that have no keyword in
     * their name, and must not list mainstream sites that the raw Block List
     * Project list wrongly tags as porn.
     */
    @Test
    fun bundledDatasetCoversAdultSitesWithoutKeywords() {
        val csv = File("../../assets/site_categories/cleaned_site_categories.csv")
        if (!csv.exists()) return // Run from mobile_app/android; skip elsewhere.
        val adult = HashSet<String>()
        val all = HashSet<String>()
        csv.useLines { lines ->
            lines.drop(1).forEach { line ->
                val parts = line.split(',')
                if (parts.size == 2) {
                    all.add(parts[0])
                    if (parts[1].trim() == "adult") adult.add(parts[0])
                }
            }
        }
        for (domain in listOf("xnxx.com", "xhamster.com", "onlyfans.com",
                "chaturbate.com", "stripchat.com", "spankbang.com")) {
            assertTrue("$domain should be in the adult list", domain in adult)
        }
        for (domain in listOf("youtube.com", "cosmopolitan.com", "camscanner.com",
                "period-calendar.com", "character.ai", "essex.ac.uk")) {
            assertFalse("$domain must not be blocked", domain in all)
        }
    }
}
