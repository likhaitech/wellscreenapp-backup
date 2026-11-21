package com.wellscreen.app.cases

import com.wellscreen.app.FamilyDnsCheck
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-072 - offline: no Cloudflare answer means no hint and no block.
class FamilyDnsCheckCase072Test {
    private fun response(vararg ip: Int, answers: Int = 1): ByteArray {
        val query = FamilyDnsCheck.buildQuery("example.com")
        val header = byteArrayOf(0, 0, 0x81.toByte(), 0x80.toByte(), 0, 1, 0, answers.toByte(), 0, 0, 0, 0)
        val question = query.copyOfRange(12, query.size)
        val answer = if (answers == 0) ByteArray(0) else byteArrayOf(
            0xc0.toByte(), 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4,
            ip[0].toByte(), ip[1].toByte(), ip[2].toByte(), ip[3].toByte(),
        )
        return header + question + answer
    }

    @Test
    fun case072() = testCase(
        id = "CASE-072",
        file = "$KOTLIN_TESTS/FamilyDnsCheckCase072Test.kt",
        codeTested = "$KOTLIN_MAIN/FamilyDnsCheck.kt",
        description = "Child phone is offline (airplane mode) and the child opens a new website.",
        expected = "No Cloudflare hint is given, nothing is blocked because of it, and the app does not crash.",
    ) {
        // Offline: no answer at all, a broken answer, or an answer with no address.
        assertEquals(FamilyDnsCheck.Verdict.UNKNOWN, FamilyDnsCheck.parseVerdict(ByteArray(0)))
        assertEquals(FamilyDnsCheck.Verdict.UNKNOWN, FamilyDnsCheck.parseVerdict(byteArrayOf(1, 2, 3)))
        assertEquals(FamilyDnsCheck.Verdict.UNKNOWN, FamilyDnsCheck.parseVerdict(response(answers = 0)))
        "With no or broken Cloudflare answers the verdict was UNKNOWN (never REFUSED): no hint, nothing blocked, no crash"
    }
}
