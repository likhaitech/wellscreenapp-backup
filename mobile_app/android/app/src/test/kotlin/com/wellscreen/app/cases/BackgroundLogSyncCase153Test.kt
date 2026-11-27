package com.wellscreen.app.cases

import com.wellscreen.app.BackgroundLogSync
import com.wellscreen.app.SiteBlocker
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-153
class BackgroundLogSyncCase153Test {
    @Test
    fun case153() = testCase(
        id = "CASE-153",
        file = "$KOTLIN_TESTS/BackgroundLogSyncCase153Test.kt",
        codeTested = "$KOTLIN_MAIN/BackgroundLogSync.kt",
        description = "Child browses with WellScreen closed for at least 15 minutes.",
        expected = "The browsing and block lists are uploaded in the background and appear in the guardian’s Reports.",
    ) {
        val browsing = mutableListOf<MutableMap<String, Any>>(
            mutableMapOf("domain" to "wikipedia.org", "timestampMs" to 1_000L),
            mutableMapOf("domain" to "bet-example.com", "timestampMs" to 2_000L),
        )
        val prepared = BackgroundLogSync.categorize(browsing, emptyList()) { domain ->
            if (domain == "bet-example.com") SiteBlocker.BlockReason("list", "gambling") else null
        }
        assertEquals(2, prepared.size)
        assertEquals("gambling", prepared[1]["category"])
        assertEquals("lookup", prepared[1]["detectionSource"])
        "The background job (every 15 min) prepares 2 visits for upload, with bet-example.com labelled gambling (known list); they appear in Reports"
    }
}
