package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-137
class BlockScreenTextCase137Test {
    @Test
    fun case137() = testCase(
        id = "CASE-137",
        file = "$KOTLIN_TESTS/BlockScreenTextCase137Test.kt",
        codeTested = "$KOTLIN_MAIN/BlockedAppActivity.kt",
        description = "Child taps “Request Temporary Access” on the block screen.",
        expected = "The Emergency Access request form opens directly.",
    ) {
        val action = BlockScreenText.action(false, null, null)
        assertEquals(BlockScreenText.Action.REQUEST_TEMPORARY_ACCESS, action)
        "A blocked app's screen offers \"${BlockScreenText.REQUEST_BUTTON}\"; tapping it opens WellScreen straight on the Emergency Access request form"
    }
}
