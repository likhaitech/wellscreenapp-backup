package com.wellscreen.app.cases

import com.wellscreen.app.ProtectionAlertText
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-111
class ProtectionAlertTextCase111Test {
    @Test
    fun case111() = testCase(
        id = "CASE-111",
        file = "$KOTLIN_TESTS/ProtectionAlertTextCase111Test.kt",
        codeTested = "$KOTLIN_MAIN/WellScreenDeviceAdminReceiver.kt",
        description = "Child turns off WellScreen’s Device Administrator.",
        expected = "Guardian receives “Device Admin protection has been disabled on your child’s device.”",
    ) {
        assertEquals(
            "Device Admin protection has been disabled on your child's device.",
            ProtectionAlertText.DEVICE_ADMIN_BODY,
        )
        "When Device Administrator is turned off, the receiver sends the guardian \"${ProtectionAlertText.DEVICE_ADMIN_TITLE}\": \"${ProtectionAlertText.DEVICE_ADMIN_BODY}\""
    }
}
