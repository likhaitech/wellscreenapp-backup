package com.wellscreen.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * Enforces guardian website overrides before the bundled harmful-site dataset.
 * The Flutter rules service mirrors one complete, family-scoped rules object
 * into SharedPreferences. A single JSON value avoids mixing two rule versions.
 */
object SiteBlocker {
    private const val CSV_PATH = "flutter_assets/assets/site_categories/cleaned_site_categories.csv"
    private const val RULES_KEY = "flutter.website_rules_json"
    private const val LEGACY_BLOCKED_KEY = "flutter.blocked_domains_json"

    @Volatile
    private var datasetDomains: Set<String>? = null

    private data class WebsiteRules(
        val blocked: Set<String>,
        val allowed: Set<String>
    )

    private fun normalize(domain: String): String =
        domain.trim().lowercase(Locale.ROOT).trimEnd('.')

    private fun loadDataset(context: Context): Set<String> {
        datasetDomains?.let { return it }
        val result = HashSet<String>()
        try {
            context.assets.open(CSV_PATH).bufferedReader().useLines { lines ->
                lines.drop(1).forEach { line ->
                    val comma = line.indexOf(',')
                    if (comma > 0) result.add(normalize(line.substring(0, comma)))
                }
            }
        } catch (_: Exception) {
            // Dataset unavailable: explicit guardian rules can still work.
        }
        datasetDomains = result
        return result
    }

    private fun readDomains(array: JSONArray): Set<String> {
        val result = HashSet<String>()
        for (index in 0 until array.length()) {
            val value = normalize(array.getString(index)).removePrefix("www.")
            if (value.isNotEmpty()) result.add(value)
        }
        return result
    }

    private fun parentRules(context: Context): WebsiteRules {
        return try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val raw = prefs.getString(RULES_KEY, null)
            if (raw != null) {
                val rules = JSONObject(raw)
                // A reset on logout or unpair intentionally has no parent.
                if (rules.optString("parentId").isBlank() ||
                    rules.optString("childUid").isBlank()) {
                    return WebsiteRules(emptySet(), emptySet())
                }
                WebsiteRules(
                    readDomains(rules.getJSONArray("blockedDomains")),
                    readDomains(rules.getJSONArray("allowedDomains"))
                )
            } else {
                // Keep the existing legacy blocked list until the new sync
                // has initialized its authoritative cache.
                WebsiteRules(
                    readDomains(JSONArray(
                        prefs.getString(LEGACY_BLOCKED_KEY, "[]") ?: "[]"
                    )),
                    emptySet()
                )
            }
        } catch (_: Exception) {
            // Never grant an allow exception from malformed cached data.
            WebsiteRules(emptySet(), emptySet())
        }
    }

    private fun matchesDomain(domain: String, domains: Set<String>): Boolean {
        val labels = domain.split('.')
        for (start in 0..(labels.size - 2)) {
            val candidate = labels.subList(start, labels.size).joinToString(".")
            if (candidate in domains) return true
        }
        return false
    }

    fun isBlocked(context: Context, domain: String): Boolean {
        val normalized = normalize(domain)
        if (normalized.isEmpty()) return false

        val rules = parentRules(context)
        val customDomain = normalized.removePrefix("www.")
        if (matchesDomain(customDomain, rules.allowed)) return false
        if (matchesDomain(customDomain, rules.blocked)) return true

        return matchesDomain(normalized, loadDataset(context))
    }
}
