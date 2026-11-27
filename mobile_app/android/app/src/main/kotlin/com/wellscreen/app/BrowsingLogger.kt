package com.wellscreen.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Records domains captured by [BrowserUrlExtractor] into
 * `flutter.browsing_log_json`, mirroring [RestrictionLogger]'s rolling-log
 * shape/cap so child_home_screen.dart's syncUsageReport() can pick it up
 * the same way it already does for restriction/SMS/sync logs.
 *
 * SCOPE NOTE: this only records *that* a domain was visited and *when* -
 * it does not classify or act on it. Category matching against
 * data_cleaned/site_categories/cleaned_site_categories.csv, and any
 * resulting restriction/alert, is separate, not-yet-built work. This class
 * exists to make URL capture itself independently verifiable (you can see
 * real captured domains in the log) before building anything on top of it.
 */
object BrowsingLogger {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val LOG_KEY = "flutter.browsing_log_json"
    private const val MAX_LOG_ENTRIES = 50

    fun recordVisit(
        context: Context,
        packageName: String,
        domain: String,
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val log = JSONArray(prefs.getString(LOG_KEY, "[]") ?: "[]")

            val entry = JSONObject()
            entry.put("packageName", packageName)
            entry.put("domain", domain)
            entry.put("timestampMs", System.currentTimeMillis())
            log.put(entry)

            val trimmed = JSONArray()
            val start = maxOf(0, log.length() - MAX_LOG_ENTRIES)
            for (i in start until log.length()) {
                trimmed.put(log.get(i))
            }

            prefs.edit().putString(LOG_KEY, trimmed.toString()).apply()
        } catch (_: Exception) {
            // Best-effort logging only - never let this crash the caller.
        }
    }

    /**
     * Records a blocked attempt so the guardian's Browsing report shows the
     * site itself, labelled, instead of only the safe page the child was sent
     * back to. If the newest entry is already this domain from the same
     * visit (a page-word block after the page loaded), that entry is labelled
     * instead of adding a second one.
     */
    fun recordBlocked(
        context: Context,
        packageName: String,
        domain: String,
        category: String?,
        source: String,
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val log = JSONArray(prefs.getString(LOG_KEY, "[]") ?: "[]")
            val last = if (log.length() > 0) log.optJSONObject(log.length() - 1) else null
            val now = System.currentTimeMillis()
            if (!isSameVisit(last?.optString("domain"), last?.optLong("timestampMs") ?: 0L, domain, now)) {
                recordVisit(context, packageName, domain)
            }
            if (category != null) tagVisit(context, domain, category, source)
        } catch (_: Exception) {
            // Best-effort only.
        }
    }

    /** Same domain as the newest entry, within one visit's time. */
    internal fun isSameVisit(lastDomain: String?, lastMs: Long, domain: String, now: Long): Boolean =
        lastDomain == domain && now - lastMs in 0..SAME_VISIT_MS

    private const val SAME_VISIT_MS = 60_000L

    /**
     * Marks the latest visit to [domain] with what the page check found
     * (e.g. "adult" from "page" words), so Reports can flag a site whose
     * address looks harmless. Never overwrites an existing category.
     */
    fun tagVisit(context: Context, domain: String, category: String, source: String) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val log = JSONArray(prefs.getString(LOG_KEY, "[]") ?: "[]")
            for (i in log.length() - 1 downTo 0) {
                val entry = log.optJSONObject(i) ?: continue
                if (entry.optString("domain") != domain) continue
                if (entry.has("category")) return
                entry.put("category", category)
                entry.put("detectionSource", source)
                prefs.edit().putString(LOG_KEY, log.toString()).apply()
                return
            }
        } catch (_: Exception) {
            // Best-effort only.
        }
    }
}
