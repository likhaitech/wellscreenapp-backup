package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EducationSitesTest {
    @Test
    fun schoolsGovernmentAndHealthSitesAreProtected() {
        for (d in listOf(
            "deped.gov.ph", "www.doh.gov.ph", "up.edu.ph", "mit.edu", "cdc.gov", "who.int",
            "en.wikipedia.org", "kidshealth.org", "www.plannedparenthood.org",
            "thetrevorproject.org", "loveyourself.ph", "amaze.org",
        )) {
            assertTrue(d, EducationSites.isProtected(d))
        }
    }

    @Test
    fun ordinaryAndLookAlikeSitesAreNot() {
        for (d in listOf("example.com", "notwikipedia.org.evil.com", "fakegov.ph", "bet365.com", "edu-casino.com")) {
            assertFalse(d, EducationSites.isProtected(d))
        }
    }

    @Test
    fun automaticChecksNeverBlockEducationButGuardianStillCan() {
        val noRules = SiteBlocker.WebsiteRules(emptySet(), emptySet())
        val dataset = mapOf("sexed.example.edu" to "adult")
        // A keyword ("sex") or a list entry can't block a protected site...
        assertNull(SiteBlocker.decide("sexed.example.edu", noRules, dataset, { true }))
        assertNull(SiteBlocker.decide("en.wikipedia.org", noRules, dataset, { true }))
        // ...but the guardian's own block still applies.
        val guardianBlock = SiteBlocker.WebsiteRules(setOf("wikipedia.org"), emptySet())
        assertTrue(SiteBlocker.decide("en.wikipedia.org", guardianBlock, dataset, { false }) != null)
    }
}
