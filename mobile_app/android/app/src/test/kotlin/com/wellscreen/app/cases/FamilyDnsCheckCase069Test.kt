package com.wellscreen.app.cases

import com.wellscreen.app.FamilyDnsCheck
import com.wellscreen.app.SiteReview
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

// CASE-069 - Cloudflare family filter hint for ages 7-12 / 13-15.
class FamilyDnsCheckCase069Test {
    /** Cloudflare's DNS answer: 0.0.0.0 means "refused by the family filter". */
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
    fun case069() = testCase(
        id = "CASE-069",
        file = "$KOTLIN_TESTS/FamilyDnsCheckCase069Test.kt",
        codeTested = "$KOTLIN_MAIN/FamilyDnsCheck.kt",
        description = "Child aged 7–12 or 13–15 opens malware.testcategory.com.",
        expected = "The site is not blocked; the guardian receives “Review this website” saying “malware.testcategory.com (flagged by Cloudflare’s family filter)”, with Allow and Block.",
    ) {
        // Cloudflare answered 0.0.0.0 for malware.testcategory.com (checked live 21 Nov).
        assertEquals(FamilyDnsCheck.Verdict.REFUSED, FamilyDnsCheck.parseVerdict(response(0, 0, 0, 0)))
        // Ages 7-12 and 13-15 do not block hints - the guardian reviews.
        assertFalse(SiteReview.blocksHints("7_12"))
        assertFalse(SiteReview.blocksHints("13_15"))
        val reason = SiteReview.reasonLabel("cloudflare", "unsafe")
        assertEquals("flagged by Cloudflare's family filter", reason)
        "Cloudflare refused the site (0.0.0.0); for ages 7-12/13-15 it was not blocked and the review alert reads \"malware.testcategory.com ($reason)\""
    }
}
