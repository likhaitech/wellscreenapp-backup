package com.wellscreen.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

/**
 * Enforces guardian website overrides before adult keyword matching and the
 * bundled harmful-site dataset.
 * The Flutter rules service mirrors one complete, family-scoped rules object
 * into SharedPreferences. A single JSON value avoids mixing two rule versions.
 */
object SiteBlocker {
    private const val CSV_PATH = "flutter_assets/assets/site_categories/cleaned_site_categories.csv"
    private const val RULES_KEY = "flutter.website_rules_json"
    private const val LEGACY_BLOCKED_KEY = "flutter.blocked_domains_json"

    @Volatile
    private var datasetDomains: Map<String, String>? = null

    /**
     * Why a website was blocked, saved with each blocked attempt so the
     * parent's report can explain it. [source] is one of "parent_rule",
     * "keyword", "list" or "ai"; [category] is the harmful-site category
     * when known (null for a parent's own block).
     */
    data class BlockReason(val source: String, val category: String?)

    internal data class WebsiteRules(
        val blocked: Set<String>,
        val allowed: Set<String>
    )

    private fun normalize(domain: String): String =
        domain.trim().lowercase(Locale.ROOT).trimEnd('.')

    private fun loadDataset(context: Context): Map<String, String> {
        datasetDomains?.let { return it }
        val result = HashMap<String, String>()
        try {
            context.assets.open(CSV_PATH).bufferedReader().useLines { lines ->
                lines.drop(1).forEach { line ->
                    val comma = line.indexOf(',')
                    if (comma > 0) {
                        result[normalize(line.substring(0, comma))] =
                            line.substring(comma + 1).trim()
                    }
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

    /** The matching entry's category, also matching parent domains. */
    private fun categoryFor(domain: String, dataset: Map<String, String>): String? {
        val labels = domain.split('.')
        for (start in 0..(labels.size - 2)) {
            val candidate = labels.subList(start, labels.size).joinToString(".")
            dataset[candidate]?.let { return it }
        }
        return null
    }

    /**
     * The blocking decision, in order: guardian allow, guardian block,
     * education/health allow list, adult keywords, bundled list, gambling AI. Pure (no Android types)
     * so it can be unit tested.
     */
    internal fun decide(
        domain: String,
        rules: WebsiteRules,
        dataset: Map<String, String>,
        isAiGambling: (String) -> Boolean,
        appDomains: Set<String> = emptySet(),
        limitDomains: Set<String> = emptySet(),
    ): BlockReason? {
        val normalized = normalize(domain)
        if (normalized.isEmpty()) return null

        val customDomain = normalized.removePrefix("www.")
        if (matchesDomain(customDomain, rules.allowed)) return null
        if (matchesDomain(customDomain, rules.blocked)) {
            return BlockReason("parent_rule", null)
        }
        // Website of an app the guardian blocked (tiktok.com for TikTok).
        if (matchesDomain(customDomain, appDomains)) {
            return BlockReason("parent_rule", "blocked_app")
        }
        // Website of an app whose daily time limit is used up (youtube.com
        // after YouTube's limit) - otherwise the browser is a way around it.
        if (matchesDomain(customDomain, limitDomains)) {
            return BlockReason("parent_rule", "daily_limit_reached")
        }

        // Education and health sites are never blocked by the automatic
        // checks below (a guardian's own block above still applies).
        if (EducationSites.isProtected(customDomain)) return null

        // Adult keywords catch porn sites missing from the bundled list.
        if (AdultKeywordMatcher.matches(normalized)) return BlockReason("keyword", "adult")

        categoryFor(normalized, dataset)?.let { return BlockReason("list", it) }

        // New gambling sites not in the list: the trained name model, only
        // at its 90% confidence bar.
        if (isAiGambling(normalized)) return BlockReason("ai", "gambling")
        return null
    }

    fun blockReason(context: Context, domain: String): BlockReason? =
        decide(
            domain = domain,
            rules = parentRules(context),
            dataset = loadDataset(context),
            isAiGambling = { GamblingNameClassifier.isGambling(context, it) },
            appDomains = blockedAppDomains(context),
            limitDomains = limitReachedDomains(context),
        )

    @Volatile private var limitDomainsCache: Set<String> = emptySet()
    @Volatile private var limitDomainsCachedAt: Long = 0L

    /**
     * Websites of apps whose daily limit is used up. Checking a limit reads
     * Android's usage records, so the result is reused for 30 seconds
     * (browsers send many events while a page loads).
     */
    private fun limitReachedDomains(context: Context): Set<String> {
        val now = System.currentTimeMillis()
        if (now - limitDomainsCachedAt in 0..30_000L) return limitDomainsCache
        val result = try {
            if (GrantClock.isEmergencyActive(context)) {
                emptySet()
            } else {
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences", Context.MODE_PRIVATE
                )
                val raw = prefs.getString("flutter.app_time_limits_json", null)
                if (raw == null) {
                    emptySet()
                } else {
                    val limits = JSONObject(raw).optJSONArray("limits")
                    val reached = HashSet<String>()
                    if (limits != null) {
                        for (index in 0 until limits.length()) {
                            val pkg = limits.optJSONObject(index)?.optString("packageName")
                                ?: continue
                            if (!RelatedTargets.hasWebsites(pkg)) continue
                            if (TemporaryAppGrantCache.isActive(context, pkg, now)) continue
                            if (AppTimeLimitEnforcer.isLimitReached(context, pkg)) reached.add(pkg)
                        }
                    }
                    RelatedTargets.domainsFor(reached)
                }
            }
        } catch (_: Exception) {
            emptySet()
        }
        limitDomainsCache = result
        limitDomainsCachedAt = now
        return result
    }

    /**
     * Websites of apps the guardian blocked. An app with an active temporary
     * grant or an active Emergency Access keeps its website open too.
     */
    private fun blockedAppDomains(context: Context): Set<String> {
        return try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val now = System.currentTimeMillis()
            if (GrantClock.isEmergencyActive(context)) return emptySet()
            val raw = prefs.getString("flutter.restricted_packages_json", null)
                ?: return emptySet()
            val array = JSONArray(raw)
            val restricted = HashSet<String>()
            for (index in 0 until array.length()) {
                val pkg = array.optString(index).trim()
                if (pkg.isNotEmpty() && !TemporaryAppGrantCache.isActive(context, pkg, now)) {
                    restricted.add(pkg)
                }
            }
            RelatedTargets.domainsFor(restricted)
        } catch (_: Exception) {
            emptySet()
        }
    }

    /**
     * True when no automatic check (page words, Cloudflare) should look at
     * [domain]: the guardian allowed it, or it's an education/health site.
     */
    fun skipsContentChecks(context: Context, domain: String): Boolean {
        val custom = normalize(domain).removePrefix("www.")
        if (custom.isEmpty()) return true
        return matchesDomain(custom, parentRules(context).allowed) ||
            EducationSites.isProtected(custom)
    }

    fun isBlocked(context: Context, domain: String): Boolean =
        blockReason(context, domain) != null
}
