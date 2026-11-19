package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class RepeatedAttemptAlertTest {
    private val now = Calendar.getInstance().apply { set(2026, Calendar.NOVEMBER, 19, 21, 0, 0) }.timeInMillis
    private val yesterday = now - 24L * 60 * 60 * 1000

    private fun e(target: String, at: Long = now, outcome: String = "blocked", source: String? = null) =
        RepeatedAttemptAlert.Entry(target, outcome, source, at)

    @Test
    fun countsOnlyTodaysBlocksForThatTarget() {
        val log = listOf(
            e("youtube.com", source = "parent_rule"),
            e("youtube.com", source = "parent_rule"),
            e("youtube.com", at = yesterday, source = "parent_rule"),
            e("youtube.com", outcome = "emergency_access_bypass"),
            e("tiktok.com", source = "parent_rule"),
            e("youtube.com", source = "parent_rule"),
        )
        assertEquals(3, RepeatedAttemptAlert.countToday(log, "youtube.com", now))
        assertEquals(1, RepeatedAttemptAlert.countToday(log, "tiktok.com", now))
    }

    @Test
    fun scheduleBlocksDoNotCount() {
        val log = List(5) { e("com.google.android.youtube", source = "schedule") }
        assertEquals(0, RepeatedAttemptAlert.countToday(log, "com.google.android.youtube", now))
    }

    @Test
    fun eventIdMatchesTheDartFormat() {
        // Dart: 'rra_' + target with non-alphanumerics as '_' + '_' + yyyymmdd
        assertEquals("rra_youtube_com_20261119", RepeatedAttemptAlert.eventId("youtube.com", now))
        assertEquals(
            "rra_com_zhiliaoapp_musically_20261119",
            RepeatedAttemptAlert.eventId("com.zhiliaoapp.musically", now),
        )
    }

    @Test
    fun onlyAppsAndWebsitesAreAlertable() {
        assertTrue(RepeatedAttemptAlert.isAlertable("youtube.com"))
        assertTrue(RepeatedAttemptAlert.isAlertable("com.roblox.client"))
        assertFalse(RepeatedAttemptAlert.isAlertable("WellScreen settings"))
    }

    @Test
    fun milestonesAre3And5And10() {
        assertEquals(0, RepeatedAttemptAlert.milestone(2))
        assertEquals(3, RepeatedAttemptAlert.milestone(4))
        assertEquals(5, RepeatedAttemptAlert.milestone(9))
        assertEquals(10, RepeatedAttemptAlert.milestone(30))
        assertEquals("rra_youtube_com_20261119_5", RepeatedAttemptAlert.eventId("youtube.com", now, 5))
        assertEquals("rra_youtube_com_20261119", RepeatedAttemptAlert.eventId("youtube.com", now, 3))
    }
}
