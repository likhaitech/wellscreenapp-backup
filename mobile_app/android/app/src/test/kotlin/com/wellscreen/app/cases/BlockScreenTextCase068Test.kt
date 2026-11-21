package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-068
class BlockScreenTextCase068Test {
    @Test
    fun case068() = testCase(
        id = "CASE-068",
        file = "$KOTLIN_TESTS/BlockScreenTextCase068Test.kt",
        codeTested = "$KOTLIN_MAIN/BlockScreenText.kt",
        description = "Child signs out of WellScreen and opens a blocked app.",
        expected = "The app stays blocked and a “Sign in to WellScreen” notice is shown.",
    ) {
        val title = BlockScreenText.title(false, true, null, null, "TikTok")
        assertEquals("Sign in to WellScreen", title)
        assertEquals(BlockScreenText.Action.SIGN_IN, BlockScreenText.action(true, null, null))
        "Signed out: the blocked app still shows the block screen, titled \"$title\", with a button to open WellScreen and sign in"
    }
}
