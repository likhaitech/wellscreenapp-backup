package com.wellscreen.app.cases

import com.wellscreen.app.ProtectedSettingsGuard
import org.junit.Assert.assertTrue
import org.junit.Test

private const val DESCRIPTION =
    "WellScreen uses accessibility access to detect when a restricted app is opened and show a restriction screen based on parent rules, and to record which websites are visited in supported browsers (Chrome, Firefox, Samsung Internet, Edge, Opera, DuckDuckGo) so a parent can review browsing activity."

// CASE-104
class ProtectedSettingsGuardCase104Test {
    @Test
    fun case104() = testCase(
        id = "CASE-104",
        file = "$KOTLIN_TESTS/ProtectedSettingsGuardCase104Test.kt",
        codeTested = "$KOTLIN_MAIN/ProtectedSettingsGuard.kt",
        description = "Child opens WellScreen’s Accessibility page to turn it off.",
        expected = "The screen is covered and the Accessibility Service stays on.",
    ) {
        val page = listOf("WellScreen", "Use WellScreen", "Off", DESCRIPTION)
        assertTrue(ProtectedSettingsGuard.isProtectedScreen(page, "WellScreen", DESCRIPTION))
        "WellScreen's Accessibility page (\"Use WellScreen\" switch) is detected as protected, so it is covered before the switch can be turned off"
    }
}
