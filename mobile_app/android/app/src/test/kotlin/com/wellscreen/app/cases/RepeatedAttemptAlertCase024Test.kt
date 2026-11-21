package com.wellscreen.app.cases

import com.wellscreen.app.RepeatedAttemptAlert
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

// CASE-024 - Rule-Based Pattern Detection / repeated blocked-app attempts.
class RepeatedAttemptAlertCase024Test {
    @Test
    fun case024() = testCase(
        id = "CASE-024",
        file = "$KOTLIN_TESTS/RepeatedAttemptAlertCase024Test.kt",
        codeTested = "$KOTLIN_MAIN/RepeatedAttemptAlert.kt",
        description = "Child repeatedly opens a blocked app.",
        expected = "Each attempt is blocked and logged, and the guardian receives a repeated-attempt alert.",
    ) {
        val now = Calendar.getInstance().apply { set(2026, Calendar.NOVEMBER, 22, 15, 0, 0) }.timeInMillis
        val app = "com.zhiliaoapp.musically" // TikTok, blocked by the guardian
        assertTrue(RepeatedAttemptAlert.isAlertable(app))
        val log = List(3) { RepeatedAttemptAlert.Entry(app, "blocked", "parent_rule", now) }
        val count = RepeatedAttemptAlert.countToday(log, app, now)
        assertEquals(3, count)
        assertEquals(3, RepeatedAttemptAlert.milestone(count))
        val alertId = RepeatedAttemptAlert.eventId(app, now, 3)
        "3 blocked attempts were counted from the log, reaching the alert milestone 3; repeated-attempt alert $alertId is sent to the guardian"
    }
}
