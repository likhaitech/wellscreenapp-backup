package com.wellscreen.app.cases

import com.wellscreen.app.BootRestore
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-051
class BootRestoreCase051Test {
    @Test
    fun case051() = testCase(
        id = "CASE-051",
        file = "$KOTLIN_TESTS/BootRestoreCase051Test.kt",
        codeTested = "$KOTLIN_MAIN/ScreenTimeReportJobService.kt",
        description = "Child restarts the phone and does not open WellScreen.",
        expected = "Usage reporting resumes and the guardian’s dashboard updates.",
    ) {
        assertTrue(BootRestore.shouldRestoreReporting("android.intent.action.BOOT_COMPLETED"))
        assertFalse(BootRestore.shouldRestoreReporting("android.intent.action.SCREEN_ON"))
        "After a restart Android sends BOOT_COMPLETED and WellScreen schedules the screen-time report job again without the app being opened"
    }
}
