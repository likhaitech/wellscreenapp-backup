package com.wellscreen.app.cases

import com.wellscreen.app.RelatedTargets
import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-150
class SiteBlockerCase150Test {
    @Test
    fun case150() = testCase(
        id = "CASE-150",
        file = "$KOTLIN_TESTS/SiteBlockerCase150Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteBlocker.kt",
        description = "Child turns on airplane mode and opens a blocked app and a harmful site.",
        expected = "Both stay blocked while offline and the app does not crash.",
    ) {
        // Both checks use only what is saved on the phone - no internet.
        val app = RelatedTargets.blockingPackageFor("com.zhiliaoapp.musically", setOf("com.zhiliaoapp.musically"))
        assertEquals("com.zhiliaoapp.musically", app)
        val site = SiteBlocker.decide(
            domain = "bet-example.com",
            rules = SiteBlocker.WebsiteRules(emptySet(), emptySet()),
            dataset = mapOf("bet-example.com" to "gambling"),
            isAiGambling = { false },
        )
        assertEquals("gambling", site?.category)
        "Offline: TikTok is still blocked from the saved list and bet-example.com is still blocked (${site?.category}) from the on-phone list; nothing needs the internet"
    }
}
