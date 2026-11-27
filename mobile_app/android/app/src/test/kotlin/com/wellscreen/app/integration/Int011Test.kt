package com.wellscreen.app.integration

import com.wellscreen.app.SmsBackupAlert
import com.wellscreen.app.cases.KOTLIN_MAIN
import com.wellscreen.app.cases.testCase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// INT-011 - Alerts and Communication Module -> Offline Logging and Synchronization Module.
// The child opens a blocked app while the phone has no internet: the SMS
// backup alert goes to the guardian's verified number over the mobile network.
// Run (from mobile_app\android):
//   .\gradlew.bat :app:testDebugUnitTest --tests "com.wellscreen.app.integration.Int011Test"
class Int011Test {
    @Test
    fun int011() = testCase(
        id = "INT-011",
        file = "$INT_TESTS/Int011Test.kt",
        codeTested = "$KOTLIN_MAIN/SmsBackupAlert.kt + SmsAlertSender.kt",
        description = "Child opens a blocked app while the phone has no internet (Alerts and Communication -> Offline Logging and Synchronization).",
        expected = "An SMS backup alert is sent to the guardian’s verified mobile number.",
    ) {
        // The guardian's verified number, synced to the child phone earlier.
        val verified = "+639171234567"
        // First time today the blocked TikTok is opened: an SMS is sent.
        // No internet is needed - it goes over the mobile network.
        assertTrue(SmsBackupAlert.shouldSend(verified, hasPermission = true, onCooldown = false))
        val text = SmsBackupAlert.restrictedAppMessage("TikTok")
        assertEquals("WellScreen alert: \"TikTok\" was opened and blocked on your child's device.", text)
        // Once per app per day, and never without a number or permission.
        assertFalse(SmsBackupAlert.shouldSend(verified, hasPermission = true, onCooldown = true))
        assertFalse(SmsBackupAlert.shouldSend(null, hasPermission = true, onCooldown = false))
        assertFalse(SmsBackupAlert.shouldSend(verified, hasPermission = false, onCooldown = false))
        "The blocked TikTok was opened with no internet: the SMS \"$text\" is sent to the verified number $verified (once per app per day; the result is kept on the phone and shown later in Reports > SMS Backup Alerts)"
    }
}
