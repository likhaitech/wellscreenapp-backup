package com.wellscreen.app.cases

import com.wellscreen.app.PageCheckExempt
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-068 - search engines and big platforms are not page-checked.
class PageCheckExemptCase068Test {
    @Test
    fun case068() = testCase(
        id = "CASE-068",
        file = "$KOTLIN_TESTS/PageCheckExemptCase068Test.kt",
        codeTested = "$KOTLIN_MAIN/PageCheckExempt.kt",
        description = "Child searches Google or opens YouTube and Facebook.",
        expected = "Search engines and big platforms are not page-checked and are not blocked by page words.",
    ) {
        val sites = listOf("www.google.com", "google.com.ph", "m.youtube.com", "web.facebook.com")
        for (d in sites) assertTrue(d, PageCheckExempt.isExempt(d))
        "${sites.joinToString()} are exempt from the page-word check, so page words never block them"
    }
}
