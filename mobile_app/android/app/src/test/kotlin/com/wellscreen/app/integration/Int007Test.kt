package com.wellscreen.app.integration

import com.wellscreen.app.BlockScreenText
import com.wellscreen.app.ScheduleEnforcer
import com.wellscreen.app.SiteBlocker
import com.wellscreen.app.cases.KOTLIN_MAIN
import com.wellscreen.app.cases.testCase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// INT-007 - Rule Management and Restriction Module -> Usage Monitoring Module.
// The rules the guardian saved are applied on the child phone, and the
// restriction screen appears when a restricted app is opened.
// Run (from mobile_app\android):
//   .\gradlew.bat :app:testDebugUnitTest --tests "com.wellscreen.app.integration.Int007Test"
class Int007Test {
    @Test
    fun int007() = testCase(
        id = "INT-007",
        file = "$INT_TESTS/Int007Test.kt",
        codeTested = "$KOTLIN_MAIN/ScheduleEnforcer.kt + SiteBlocker.kt + BlockScreenText.kt",
        description = "Guardian sets an app block, time limit, or scheduled lock (Rule Management -> Usage Monitoring).",
        expected = "The rule is applied on the child device and a blocking screen appears when the restricted app is opened.",
    ) {
        // Scheduled lock the guardian saved: bedtime 9:00 PM (1260) to 6:00 AM
        // (360), the values ScheduleRules.toNativeJson() sends to the phone.
        val bedtime = ScheduleEnforcer.Schedule(
            bedtimeEnabled = true, bedtimeStart = 21 * 60, bedtimeEnd = 6 * 60,
            focusUntilMs = 0L, focusDurationMs = 0L,
            breaksEnabled = false, breakAfterMinutes = 0, breakMinutes = 0,
        )
        assertTrue(ScheduleEnforcer.isInWindow(21 * 60 + 30, bedtime.bedtimeStart, bedtime.bedtimeEnd))
        assertFalse(ScheduleEnforcer.isInWindow(20 * 60, bedtime.bedtimeStart, bedtime.bedtimeEnd))
        val bedtimeTitle = BlockScreenText.title(false, false, "bedtime", null, "YouTube")
        assertEquals("Time to rest", bedtimeTitle)
        assertEquals("Bedtime", BlockScreenText.badge(false, false, "bedtime", null, false))

        // App block the guardian saved for TikTok: the app shows the
        // restriction screen with "Request Temporary Access" ...
        val appTitle = BlockScreenText.title(false, false, null, null, "TikTok")
        assertEquals("TikTok is paused", appTitle)
        assertEquals(BlockScreenText.Action.REQUEST_TEMPORARY_ACCESS, BlockScreenText.action(false, null, null))
        // ... and its website is blocked too, so the browser is no way around it.
        val site = SiteBlocker.decide(
            domain = "tiktok.com",
            rules = SiteBlocker.WebsiteRules(emptySet(), emptySet()),
            dataset = emptyMap(),
            isAiGambling = { false },
            appDomains = setOf("tiktok.com"),
            limitDomains = emptySet(),
        )
        assertEquals("parent_rule", site?.source)
        assertEquals("blocked_app", site?.category)

        // Time limit used up for YouTube: the badge and its website.
        assertEquals("Time limit reached", BlockScreenText.badge(false, false, null, null, true))
        val limit = SiteBlocker.decide(
            domain = "youtube.com",
            rules = SiteBlocker.WebsiteRules(emptySet(), emptySet()),
            dataset = emptyMap(),
            isAiGambling = { false },
            appDomains = emptySet(),
            limitDomains = setOf("youtube.com"),
        )
        assertEquals("daily_limit_reached", limit?.category)
        "Bedtime 9 PM-6 AM locks apps at 9:30 PM (\"$bedtimeTitle\"); the blocked TikTok shows \"$appTitle\" with Request Temporary Access and tiktok.com is blocked; YouTube after its limit shows \"Time limit reached\" and youtube.com is blocked"
    }
}
