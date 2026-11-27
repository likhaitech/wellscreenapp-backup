package com.wellscreen.app.integration

import com.wellscreen.app.SmsBackupAlert
import com.wellscreen.app.cases.KOTLIN_MAIN
import com.wellscreen.app.cases.testCase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test


class Int011Test {
    @Test
    fun int011() = testCase(
        id = "INT-011",
        file = "$INT_TESTS/Int011Test.kt",
        codeTested = "$KOTLIN_MAIN/SmsBackupAlert.kt + SmsAlertSender.kt",
        description = "Child opens a blocked app while the phone has no internet (Alerts and Communication -> Offline Logging and Synchronization).",
        expected = "An SMS backup alert is sent to the guardian’s verified mobile number.",
    ) {

        val verified = "+639171234567"

        assertTrue(SmsBackupAlert.shouldSend(verified, hasPermission = true, onCooldown = false))
        val text = SmsBackupAlert.restrictedAppMessage("TikTok")
        assertEquals("WellScreen alert: \"TikTok\" was opened and blocked on your child's device.", text)

        assertFalse(SmsBackupAlert.shouldSend(verified, hasPermission = true, onCooldown = true))
        assertFalse(SmsBackupAlert.shouldSend(null, hasPermission = true, onCooldown = false))
        assertFalse(SmsBackupAlert.shouldSend(verified, hasPermission = false, onCooldown = false))
        "The blocked TikTok was opened with no internet: the SMS \"$text\" is sent to the verified number $verified (once per app per day; the result is kept on the phone and shown later in Reports > SMS Backup Alerts)"
    }
}
