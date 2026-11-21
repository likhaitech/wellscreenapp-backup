package com.wellscreen.app.cases

import com.wellscreen.app.BackgroundLogSync
import org.junit.Assert.assertEquals
import org.junit.Test

// CASE-131
class BackgroundLogSyncCase131Test {
    @Test
    fun case131() = testCase(
        id = "CASE-131",
        file = "$KOTLIN_TESTS/BackgroundLogSyncCase131Test.kt",
        codeTested = "$KOTLIN_MAIN/BrowsingLogger.kt",
        description = "Child is blocked from a harmful site; guardian opens Recent Browsing Activity.",
        expected = "The blocked site is listed with its reason.",
    ) {
        val browsing = mutableListOf<MutableMap<String, Any>>(
            mutableMapOf("domain" to "bet-example.com", "timestampMs" to 1_000L),
        )
        val blocks = listOf<Map<String, Any>>(
            mapOf("packageName" to "bet-example.com", "outcome" to "blocked",
                "category" to "gambling", "blockSource" to "page"),
        )
        val listed = BackgroundLogSync.categorize(browsing, blocks) { null }
        assertEquals("gambling", listed[0]["category"])
        assertEquals("page", listed[0]["detectionSource"])
        "bet-example.com is listed in Recent Browsing Activity as ${listed[0]["category"]} with reason ${listed[0]["detectionSource"]} (page words)"
    }
}
