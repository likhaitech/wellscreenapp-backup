package com.wellscreen.app

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtectedSettingsGuardTest {
    private val label = "WellScreen"
    private val description = "WellScreen uses accessibility access to detect when a restricted app is opened"

    private fun guarded(vararg texts: String) =
        ProtectedSettingsGuard.isProtectedScreen(texts.toList(), label, description)

    @Test
    fun wellScreenAppInfoIsProtected() {
        assertTrue(guarded("App info", "WellScreen", "Open", "Uninstall", "Force stop"))
        assertTrue(guarded("WellScreen", "Storage", "Clear storage", "Clear cache"))
    }

    @Test
    fun uninstallDialogIsProtected() {
        assertTrue(guarded("WellScreen", "Do you want to uninstall this app?", "Cancel", "OK"))
    }

    @Test
    fun accessibilityDetailPageIsProtected() {
        assertTrue(guarded("Use WellScreen", "Off"))
        assertTrue(guarded("Some title", description + " and show a restriction screen"))
    }

    @Test
    fun deviceAdminDeactivationIsProtected() {
        assertTrue(
            guarded(
                "WellScreen Uninstall Protection",
                "Deactivate this device admin app",
                "Cancel",
            )
        )
    }

    @Test
    fun setupScreensStayOpen() {
        // Device Admin activation from the setup checklist.
        assertFalse(
            guarded("WellScreen Uninstall Protection", "Activate this device admin app", "Cancel")
        )
        // Device admin list only shows the name.
        assertFalse(guarded("Device admin apps", "WellScreen Uninstall Protection", "Find My Device"))
        // Accessibility list, usage access, battery pages.
        assertFalse(guarded("Accessibility", "Downloaded apps", "WellScreen", "On"))
        assertFalse(guarded("Usage access", "WellScreen", "Permit usage access"))
        assertFalse(guarded("Battery optimization", "WellScreen", "Not optimized"))
    }

    @Test
    fun otherAppsAreNotProtected() {
        assertFalse(guarded("App info", "TikTok", "Uninstall", "Force stop"))
        assertFalse(guarded("Do you want to uninstall this app?", "Roblox"))
    }

    @Test
    fun dateAndTimePageIsProtected() {
        // Pixel / Android One
        assertTrue(guarded("Date & time", "Set time automatically", "Time zone", "Asia/Manila"))
        // Samsung
        assertTrue(guarded("Date and time", "Automatic date and time", "Set date", "Set time"))
    }

    @Test
    fun systemListAndClockStayOpen() {
        // Settings > System only lists the row.
        assertFalse(guarded("System", "Languages & input", "Date & time", "GMT+08:00 Philippine Standard Time", "Backup"))
        // Any page that only mentions time.
        assertFalse(guarded("Screen time", "Digital Wellbeing", "Bedtime mode"))
    }
}
