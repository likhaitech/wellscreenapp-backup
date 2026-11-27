package com.wellscreen.app.cases

import com.wellscreen.app.ProtectedSettingsGuard
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private const val DESCRIPTION =
    "WellScreen uses accessibility access to detect when a restricted app is opened and show a restriction screen based on parent rules, and to record which websites are visited in supported browsers (Chrome, Firefox, Samsung Internet, Edge, Opera, DuckDuckGo) so a parent can review browsing activity."

// CASE-105
class ProtectedSettingsGuardCase105Test {
    @Test
    fun case105() = testCase(
        id = "CASE-105",
        file = "$KOTLIN_TESTS/ProtectedSettingsGuardCase105Test.kt",
        codeTested = "$KOTLIN_MAIN/ProtectedSettingsGuard.kt",
        description = "Child opens Date & time settings to change the clock.",
        expected = "The screen is covered so the time cannot be changed to bypass limits.",
    ) {
        val page = listOf("Date & time", "Set time automatically", "Set date", "Set time", "Time zone")
        assertTrue(ProtectedSettingsGuard.isProtectedScreen(page, "WellScreen", DESCRIPTION))
        val systemList = listOf("System", "Languages", "Date & time")
        assertFalse(ProtectedSettingsGuard.isProtectedScreen(systemList, "WellScreen", DESCRIPTION))
        "The Date & time page is covered; the System list with only a \"Date & time\" row stays open"
    }
}
