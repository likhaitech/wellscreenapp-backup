package com.wellscreen.app.cases

import com.wellscreen.app.SiteReview
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-033 - age 6 and below: a hint blocks right away.
class SiteReviewCase033Test {
    @Test
    fun case033() = testCase(
        id = "CASE-033",
        file = "$KOTLIN_TESTS/SiteReviewCase033Test.kt",
        codeTested = "$KOTLIN_MAIN/SiteReview.kt",
        description = "Child aged 6 and below opens phishing.testcategory.com.",
        expected = "The site is blocked with the reason “possible risk, age 6 and below”.",
    ) {
        assertTrue(SiteReview.blocksHints("6_and_below"))
        "For age group 6 and below a review-level hint blocks the site right away (reason \"hint\", shown as \"possible risk, age 6 and below\")"
    }
}
