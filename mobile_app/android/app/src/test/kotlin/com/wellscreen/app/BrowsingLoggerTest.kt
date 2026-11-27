package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BrowsingLoggerTest {
    @Test
    fun sameDomainWithinAMinuteIsOneVisit() {
        assertTrue(BrowsingLogger.isSameVisit("fakboi.xyz", 1_000L, "fakboi.xyz", 30_000L))
    }

    @Test
    fun differentDomainIsANewEntry() {
        assertFalse(BrowsingLogger.isSameVisit("google.com", 1_000L, "beeg.com", 2_000L))
    }

    @Test
    fun sameDomainLaterIsANewEntry() {
        assertFalse(BrowsingLogger.isSameVisit("beeg.com", 1_000L, "beeg.com", 120_000L))
    }

    @Test
    fun emptyLogIsANewEntry() {
        assertFalse(BrowsingLogger.isSameVisit(null, 0L, "beeg.com", 5_000L))
    }
}
