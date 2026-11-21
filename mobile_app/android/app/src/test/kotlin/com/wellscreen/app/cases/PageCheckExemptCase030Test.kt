package com.wellscreen.app.cases

import com.wellscreen.app.PageCheckExempt
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-030 - search engines and big platforms are not page-checked.
class PageCheckExemptCase030Test {
    @Test
    fun case030() = testCase(
        id = "CASE-030",
        file = "$KOTLIN_TESTS/PageCheckExemptCase030Test.kt",
        codeTested = "$KOTLIN_MAIN/PageCheckExempt.kt",
        description = "Child searches Google or opens YouTube and Facebook.",
        expected = "Search engines and big platforms are not page-checked and are not blocked by page words.",
    ) {
        val sites = listOf("www.google.com", "google.com.ph", "m.youtube.com", "web.facebook.com")
        for (d in sites) assertTrue(d, PageCheckExempt.isExempt(d))
        "${sites.joinToString()} are exempt from the page-word check, so page words never block them"
    }
}
