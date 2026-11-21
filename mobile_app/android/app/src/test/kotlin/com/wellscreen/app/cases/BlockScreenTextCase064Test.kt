package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-064
class BlockScreenTextCase064Test {
    @Test
    fun case064() = testCase(
        id = "CASE-064",
        file = "$KOTLIN_TESTS/BlockScreenTextCase064Test.kt",
        codeTested = "$KOTLIN_MAIN/BlockScreenText.kt",
        description = "Child opens an app during bedtime or after its time limit is used up.",
        expected = "The restriction screen shows the reason and a “Request Temporary Access” button.",
    ) {
        val bedtime = BlockScreenText.badge(false, false, "bedtime", null, false)
        val limit = BlockScreenText.badge(false, false, null, null, true)
        assertEquals("Bedtime", bedtime)
        assertEquals("Time limit reached", limit)
        assertEquals(BlockScreenText.Action.REQUEST_TEMPORARY_ACCESS, BlockScreenText.action(false, null, null))
        assertEquals("Request Temporary Access", BlockScreenText.REQUEST_BUTTON)
        "Reason shown: \"$bedtime\" (bedtime) or \"$limit\" (time limit); both screens offer the \"${BlockScreenText.REQUEST_BUTTON}\" button"
    }
}
