package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-094
class BlockScreenTextCase094Test {
    @Test
    fun case094() = testCase(
        id = "CASE-094",
        file = "$KOTLIN_TESTS/BlockScreenTextCase094Test.kt",
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
