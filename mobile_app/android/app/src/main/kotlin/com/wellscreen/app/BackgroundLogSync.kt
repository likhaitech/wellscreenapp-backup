package com.wellscreen.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lets ScreenTimeReportJobService upload the Browsing Activity and
 * Restriction Enforcement lists in the background, the same way it already
 * uploads screen time - so Reports stays current even when the child never
 * opens WellScreen (Android pauses the app's own 5-minute sync).
 *
 * Same fields and format the app's own sync (child_home_screen.dart
 * syncUsageReport) writes, so whichever ran last, Reports reads the same.
 */
object BackgroundLogSync {
    private const val BROWSING_KEY = "flutter.browsing_log_json"
    private const val RESTRICTION_KEY = "flutter.restriction_log_json"

    /** Same source names the app's own sync writes (see Reports labels). */
    private fun sourceName(blockSource: String): String = when (blockSource) {
        "list" -> "lookup"
        "ai" -> "ml"
        else -> blockSource
    }

    internal fun parse(raw: String?): List<MutableMap<String, Any>> {
        if (raw.isNullOrBlank()) return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { i ->
                val obj = array.optJSONObject(i) ?: return@mapNotNull null
                val map = LinkedHashMap<String, Any>()
                for (key in obj.keys()) {
                    when (val value = obj.get(key)) {
                        is String, is Boolean -> map[key] = value
                        is Number -> map[key] = if (value is Double || value is Float) value.toDouble() else value.toLong()
                        JSONObject.NULL -> Unit
                        else -> map[key] = value.toString()
                    }
                }
                map
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    /**
     * Adds category + detectionSource to each visit: what the page check
     * already saved on it, else the address check, else the block log.
     */
    internal fun categorize(
        browsing: List<MutableMap<String, Any>>,
        restriction: List<Map<String, Any>>,
        addressCheck: (String) -> SiteBlocker.BlockReason?,
    ): List<MutableMap<String, Any>> {
        val blocked = HashMap<String, Map<String, Any>>()
        for (entry in restriction) {
            val target = entry["packageName"] as? String ?: continue
            if (entry["outcome"] == "blocked" && entry["category"] != null && target.contains('.')) {
                blocked[target] = entry
            }
        }
        val addressCache = HashMap<String, SiteBlocker.BlockReason?>()
        for (entry in browsing) {
            if (entry["category"] != null) continue
            val domain = entry["domain"] as? String ?: continue
            // (getOrPut would re-check sites whose answer is "nothing".)
            val reason = if (addressCache.containsKey(domain)) {
                addressCache[domain]
            } else {
                addressCheck(domain).also { addressCache[domain] = it }
            }
            if (reason?.category != null) {
                entry["category"] = reason.category
                entry["detectionSource"] = sourceName(reason.source)
                continue
            }
            blocked[domain]?.let {
                entry["category"] = it["category"] as Any
                (it["blockSource"] as? String)?.let { s -> entry["detectionSource"] = s }
            }
        }
        return browsing
    }

    /** Adds both lists to the background job's Firestore update. */
    fun addTo(context: Context, updates: MutableMap<String, Any>) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val restriction = parse(prefs.getString(RESTRICTION_KEY, null))
        val browsing = categorize(
            parse(prefs.getString(BROWSING_KEY, null)),
            restriction,
        ) { SiteBlocker.harmfulCategory(context, it) }
        if (restriction.isNotEmpty()) updates["restrictionLog"] = restriction
        if (browsing.isNotEmpty()) updates["browsingLog"] = browsing
    }
}
