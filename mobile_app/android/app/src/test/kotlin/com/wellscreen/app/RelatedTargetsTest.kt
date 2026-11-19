package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RelatedTargetsTest {
    private val tiktok = "com.zhiliaoapp.musically"

    @Test
    fun blockedPackageCoversItself() {
        assertEquals(tiktok, RelatedTargets.blockingPackageFor(tiktok, setOf(tiktok)))
    }

    @Test
    fun liteVersionIsCoveredBySibling() {
        assertEquals(
            "com.facebook.katana",
            RelatedTargets.blockingPackageFor("com.facebook.lite", setOf("com.facebook.katana")),
        )
        assertEquals(
            tiktok,
            RelatedTargets.blockingPackageFor("com.zhiliaoapp.musically.go", setOf(tiktok)),
        )
    }

    @Test
    fun unrelatedAppsAreNotCovered() {
        assertNull(RelatedTargets.blockingPackageFor("com.android.chrome", setOf(tiktok)))
        assertNull(RelatedTargets.blockingPackageFor("com.facebook.orca", setOf("com.facebook.katana")))
        assertNull(RelatedTargets.blockingPackageFor("com.unknown.app", setOf("com.other.app")))
    }

    @Test
    fun domainsOnlyForBlockedGroups() {
        assertEquals(setOf("tiktok.com"), RelatedTargets.domainsFor(setOf(tiktok)))
        assertTrue(RelatedTargets.domainsFor(emptySet()).isEmpty())
        assertTrue(RelatedTargets.domainsFor(setOf("com.unknown.app")).isEmpty())
        assertTrue("youtu.be" in RelatedTargets.domainsFor(setOf("com.google.android.youtube")))
    }

    @Test
    fun appDomainsAreBlockedAsGuardianRule() {
        val noRules = SiteBlocker.WebsiteRules(emptySet(), emptySet())
        val appDomains = RelatedTargets.domainsFor(setOf(tiktok))
        assertEquals(
            SiteBlocker.BlockReason("parent_rule", "blocked_app"),
            SiteBlocker.decide("www.tiktok.com", noRules, emptyMap(), { false }, appDomains),
        )
        assertEquals(
            SiteBlocker.BlockReason("parent_rule", "blocked_app"),
            SiteBlocker.decide("vm.tiktok.com", noRules, emptyMap(), { false }, appDomains),
        )
        // A guardian "allow" for the website still wins.
        val allow = SiteBlocker.WebsiteRules(emptySet(), setOf("tiktok.com"))
        assertNull(SiteBlocker.decide("tiktok.com", allow, emptyMap(), { false }, appDomains))
        // Look-alike domains are not caught.
        assertNull(SiteBlocker.decide("nottiktok.com", noRules, emptyMap(), { false }, appDomains))
    }

    @Test
    fun siblingsAndDailyLimitWebsites() {
        assertEquals(setOf("com.ss.android.ugc.trill", "com.zhiliaoapp.musically.go"),
            RelatedTargets.siblingsOf(tiktok))
        assertTrue(RelatedTargets.siblingsOf("com.unknown.app").isEmpty())
        assertTrue(RelatedTargets.hasWebsites("com.google.android.youtube"))
        val noRules = SiteBlocker.WebsiteRules(emptySet(), emptySet())
        val limitDomains = RelatedTargets.domainsFor(setOf("com.google.android.youtube"))
        assertEquals(
            SiteBlocker.BlockReason("parent_rule", "daily_limit_reached"),
            SiteBlocker.decide("m.youtube.com", noRules, emptyMap(), { false }, emptySet(), limitDomains),
        )
        assertNull(SiteBlocker.decide("m.youtube.com", noRules, emptyMap(), { false }))
    }
}
