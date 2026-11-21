package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import com.wellscreen.app.ProtectedSettingsGuard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private const val DESCRIPTION =
    "WellScreen uses accessibility access to detect when a restricted app is opened and show a restriction screen based on parent rules, and to record which websites are visited in supported browsers (Chrome, Firefox, Samsung Internet, Edge, Opera, DuckDuckGo) so a parent can review browsing activity."

// CASE-065
class ProtectedSettingsGuardCase065Test {
    @Test
    fun case065() = testCase(
        id = "CASE-065",
        file = "$KOTLIN_TESTS/ProtectedSettingsGuardCase065Test.kt",
        codeTested = "$KOTLIN_MAIN/ProtectedSettingsGuard.kt",
        description = "Child opens WellScreen’s App info to Force stop, Clear storage, or Uninstall.",
        expected = "The screen is covered by the “Ask your guardian” screen.",
    ) {
        val appInfo = listOf("App info", "WellScreen", "Open", "Uninstall", "Force stop", "Storage & cache", "Clear storage")
        assertTrue(ProtectedSettingsGuard.isProtectedScreen(appInfo, "WellScreen", DESCRIPTION))
        val title = BlockScreenText.title(true, false, null, null, "Settings")
        assertEquals("Ask your guardian", title)
        "WellScreen's App info page (Force stop / Clear storage / Uninstall) is detected as protected and covered by \"$title\""
    }
}
