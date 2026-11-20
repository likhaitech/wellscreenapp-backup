package com.wellscreen.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// Plain maps only: org.json isn't available in these JVM unit tests.
class BackgroundLogSyncTest {
    private fun visit(domain: String, vararg extra: Pair<String, Any>): MutableMap<String, Any> =
        mutableMapOf<String, Any>("packageName" to "com.android.chrome", "domain" to domain, "timestampMs" to 1L)
            .apply { putAll(extra) }

    @Test
    fun visitsGetCategoryFromAddressPageOrBlockLog() {
        val browsing = listOf(
            visit("casino-example.com"),
            visit("teenpinay-example.com"),
            visit("tagged-example.com", "category" to "adult", "detectionSource" to "hint"),
            visit("news-example.com"),
        )
        val restriction = listOf(
            mapOf<String, Any>(
                "packageName" to "teenpinay-example.com", "outcome" to "blocked",
                "blockSource" to "page", "category" to "adult",
            ),
            mapOf<String, Any>("packageName" to "com.some.game", "outcome" to "blocked"),
        )
        val out = BackgroundLogSync.categorize(browsing, restriction) { domain ->
            if (domain == "casino-example.com") SiteBlocker.BlockReason("list", "gambling") else null
        }
        assertEquals("gambling", out[0]["category"])
        assertEquals("lookup", out[0]["detectionSource"])
        assertEquals("adult", out[1]["category"])
        assertEquals("page", out[1]["detectionSource"])
        assertEquals("hint", out[2]["detectionSource"])
        assertNull(out[3]["category"])
    }

    @Test
    fun theAddressCheckRunsOncePerSite() {
        var calls = 0
        BackgroundLogSync.categorize(
            listOf(visit("a-example.com"), visit("a-example.com"), visit("b-example.com")),
            emptyList(),
        ) { calls++; null }
        assertEquals(2, calls)
    }
}
