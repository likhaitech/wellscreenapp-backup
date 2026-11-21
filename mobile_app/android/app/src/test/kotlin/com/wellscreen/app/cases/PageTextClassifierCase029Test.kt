package com.wellscreen.app.cases

import com.wellscreen.app.PageTextClassifier
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-029 - a few adult words: labelled, not blocked.
class PageTextClassifierCase029Test {
    @Test
    fun case029() = testCase(
        id = "CASE-029",
        file = "$KOTLIN_TESTS/PageTextClassifierCase029Test.kt",
        codeTested = "$KOTLIN_MAIN/PageTextClassifier.kt",
        description = "Child opens a page that shows only a few adult words.",
        expected = "The site is not blocked but is labelled adult in Recent Browsing Activity.",
    ) {
        val r = PageTextClassifier.classify(listOf("Pinay Teen", "Viral", "Milf", "Creampie", "Latest videos"))
        assertEquals(PageTextClassifier.Level.LABEL, r.level)
        assertEquals("adult", r.category)
        "The page gave level LABEL (not BLOCK), category adult - not blocked, labelled adult"
    }
}
