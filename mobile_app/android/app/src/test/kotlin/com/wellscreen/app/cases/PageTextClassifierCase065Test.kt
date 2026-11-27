package com.wellscreen.app.cases

import com.wellscreen.app.PageTextClassifier
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-065 - unlisted gambling site blocked by its page words.
class PageTextClassifierCase065Test {
    @Test
    fun case065() = testCase(
        id = "CASE-065",
        file = "$KOTLIN_TESTS/PageTextClassifierCase065Test.kt",
        codeTested = "$KOTLIN_MAIN/PageTextClassifier.kt",
        description = "Child opens a gambling site that is not on any list and shows Deposit, Bet, and Withdraw.",
        expected = "The site is blocked by the page-word check and labelled “page words” in Reports.",
    ) {
        val r = PageTextClassifier.classify(listOf(
            "Best Games Online", "Login", "Register",
            "Deposit bonus 100%", "Free spins every day", "Place your bet",
            "Withdraw", "Jackpot",
        ))
        assertEquals(PageTextClassifier.Level.BLOCK, r.level)
        assertEquals("gambling", r.category)
        "The page words (Deposit, Place your bet, Withdraw, Jackpot) gave level BLOCK, category gambling - blocked with reason \"page\" (shown as \"page words\" in Reports)"
    }
}
