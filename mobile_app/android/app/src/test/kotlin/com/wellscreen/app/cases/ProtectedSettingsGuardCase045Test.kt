package com.wellscreen.app.cases

import com.wellscreen.app.BlockScreenText
import com.wellscreen.app.ProtectedSettingsGuard
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-045
class ProtectedSettingsGuardCase045Test {
    @Test
    fun case045() = testCase(
        id = "CASE-045",
        file = "$KOTLIN_TESTS/ProtectedSettingsGuardCase045Test.kt",
        codeTested = "$KOTLIN_MAIN/ProtectedSettingsGuard.kt",
        description = "Child tries to uninstall WellScreen while paired.",
        expected = "The uninstall is blocked and the “Ask your guardian” screen is shown.",
    ) {
        // Android's uninstall confirmation for WellScreen.
        val dialog = listOf("WellScreen", "Do you want to uninstall this app?", "Cancel", "OK")
        assertTrue(ProtectedSettingsGuard.isProtectedScreen(dialog, "WellScreen", ""))
        val title = BlockScreenText.title(true, false, null, null, "Package installer")
        assertEquals("Ask your guardian", title)
        "The uninstall dialog for WellScreen is detected as protected and covered by \"$title\" before OK can be tapped"
    }
}
