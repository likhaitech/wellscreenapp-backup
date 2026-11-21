package com.wellscreen.app.cases

import com.wellscreen.app.SiteReview
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-071 - age 6 and below: a hint blocks right away.
class SiteReviewCase071Test {
    @Test
    fun case071() = testCase(
        id = "CASE-071",
        file = "$KOTLIN_TESTS/SiteReviewCase071Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteReview.kt",
        description = "Child aged 6 and below opens phishing.testcategory.com.",
        expected = "The site is blocked with the reason “possible risk, age 6 and below”.",
    ) {
        assertTrue(SiteReview.blocksHints("6_and_below"))
        "For age group 6 and below a review-level hint blocks the site right away (reason \"hint\", shown as \"possible risk, age 6 and below\")"
    }
}
