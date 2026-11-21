package com.wellscreen.app.cases

import com.wellscreen.app.SiteReview
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

// CASE-040 - age 7-12: a hint is not blocked; the guardian reviews it.
class SiteReviewCase040Test {
    @Test
    fun case040() = testCase(
        id = "CASE-040",
        file = "$KOTLIN_TESTS/SiteReviewCase040Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteReview.kt",
        description = "Child aged 7–12 opens a site that reaches only the review level.",
        expected = "The site is not blocked; the guardian receives “Review this website” with Allow and Block.",
    ) {
        assertFalse(SiteReview.blocksHints("7_12"))
        val now = Calendar.getInstance().apply { set(2026, Calendar.NOVEMBER, 22, 15, 0, 0) }.timeInMillis
        val id = SiteReview.reviewEventId("lucky-games.example.com", now)
        assertTrue(id.startsWith("rev_"))
        assertEquals("the page shows some gambling words", SiteReview.reasonLabel("page", "gambling"))
        "For age group 7-12 the site was not blocked; review alert $id (\"the page shows some gambling words\") goes to the guardian"
    }
}
