package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-056
class BlockScreenTextCase056Test {
    @Test
    fun case056() = testCase(
        id = "CASE-056",
        file = "$KOTLIN_TESTS/BlockScreenTextCase056Test.kt",
        codeTested = "$KOTLIN_MAIN/BlockScreenText.kt",
        description = "Child opens a blocked adult site.",
        expected = "The block screen has no “Ask my parent” option for adult sites.",
    ) {
        val adult = BlockScreenText.action(false, "adult-example.com", "adult")
        assertEquals(BlockScreenText.Action.NONE, adult)
        val gambling = BlockScreenText.action(false, "bet-example.com", "gambling")
        assertEquals(BlockScreenText.Action.ASK_PARENT, gambling)
        "Adult site: button = $adult (no \"Ask my parent\"); for comparison a gambling site gets $gambling"
    }
}
