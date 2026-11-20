package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FamilyDnsCheckTest {
    /** A minimal DNS response with one A answer (compressed name pointer). */
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
    fun zeroAddressMeansRefused() {
        assertEquals(FamilyDnsCheck.Verdict.REFUSED, FamilyDnsCheck.parseVerdict(response(0, 0, 0, 0)))
    }

    @Test
    fun realAddressMeansAllowed() {
        assertEquals(FamilyDnsCheck.Verdict.ALLOWED, FamilyDnsCheck.parseVerdict(response(93, 184, 216, 34)))
    }

    @Test
    fun noAnswerOrGarbageIsUnknownNeverRefused() {
        assertEquals(FamilyDnsCheck.Verdict.UNKNOWN, FamilyDnsCheck.parseVerdict(response(answers = 0)))
        assertEquals(FamilyDnsCheck.Verdict.UNKNOWN, FamilyDnsCheck.parseVerdict(byteArrayOf(1, 2, 3)))
        assertEquals(FamilyDnsCheck.Verdict.UNKNOWN, FamilyDnsCheck.parseVerdict(ByteArray(0)))
    }

    @Test
    fun queryHasTheDomainLabels() {
        val q = FamilyDnsCheck.buildQuery("bet.ph")
        // header(12) + 3 "bet" + 2 "ph" + 0 + type/class(4)
        assertEquals(12 + 4 + 3 + 1 + 4, q.size)
        assertEquals(3, q[12].toInt())
    }

    @Test
    fun cacheExpiresAfterSixHours() {
        FamilyDnsCheck.remember("cache-test.example", FamilyDnsCheck.Verdict.REFUSED, nowMs = 1_000L)
        assertEquals(FamilyDnsCheck.Verdict.REFUSED, FamilyDnsCheck.cached("cache-test.example", nowMs = 2_000L))
        assertNull(FamilyDnsCheck.cached("cache-test.example", nowMs = 1_000L + 7 * 60 * 60 * 1000L))
    }
}
