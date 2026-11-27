package com.wellscreen.app.cases

import com.wellscreen.app.SmsBackupAlert
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// CASE-116
class SmsBackupAlertCase116Test {
    @Test
    fun case116() = testCase(
        id = "CASE-116",
        file = "$KOTLIN_TESTS/SmsBackupAlertCase116Test.kt",
        codeTested = "$KOTLIN_MAIN/SmsAlertSender.kt",
        description = "A critical alert occurs while the child device has no internet.",
        expected = "An SMS backup alert is sent to the guardian’s verified mobile number.",
    ) {
        val verified = "+639171234567"
        assertTrue(SmsBackupAlert.shouldSend(verified, hasPermission = true, onCooldown = false))
        assertFalse(SmsBackupAlert.shouldSend(null, hasPermission = true, onCooldown = false))
        val text = SmsBackupAlert.restrictedAppMessage("TikTok")
        assertEquals("WellScreen alert: \"TikTok\" was opened and blocked on your child's device.", text)
        "A blocked TikTok opens with no internet: the SMS \"$text\" is sent to the verified number over the mobile network (none without a number)"
    }
}
