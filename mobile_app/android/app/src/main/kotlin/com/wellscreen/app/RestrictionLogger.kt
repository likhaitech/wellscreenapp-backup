package com.wellscreen.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Records the outcome of every restriction enforcement attempt (blocking a
 * restricted app via [WellScreenAccessibilityService]) into
 * `flutter.restriction_log_json`, which child_home_screen.dart's
 * syncUsageReport() pushes to Firestore alongside the SMS/usage logs so the
 * parent dashboard can show a real restriction success/failure rate instead
 * of just assuming the block always works.
 *
 * Mirrors SmsAlertSender's recordOutcome pattern (same rolling-log shape,
 * same MAX_LOG_ENTRIES cap) for consistency across the app's outcome logs.
 *
 * responseTimeMs is the time from the accessibility event that detected the
 * restricted app being opened to the block screen actually being launched -
 * near-instantaneous in practice (it's a local Activity launch, not a
 * network call), but it's a real measurement, not a placeholder, and it's
 * what lets a failed launch (e.g. a SecurityException from a locked-down
 * device) show up as a distinct "failed" outcome instead of being silently
 * swallowed.
 */
object RestrictionLogger {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val LOG_KEY = "flutter.restriction_log_json"
    private const val MAX_LOG_ENTRIES = 50

    fun recordOutcome(
        context: Context,
        packageName: String,
        outcome: String,
        triggeredAtMs: Long,
        blockSource: String? = null,
        category: String? = null,
    ) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val log = JSONArray(prefs.getString(LOG_KEY, "[]") ?: "[]")

            val now = System.currentTimeMillis()

            val entry = JSONObject()
            entry.put("packageName", packageName)
            entry.put("outcome", outcome)
            entry.put("responseTimeMs", now - triggeredAtMs)
            entry.put("timestampMs", now)
            // Website blocks also say WHY (parent rule, keyword, list or AI)
            // and the harmful-site category, for the parent's report.
            if (blockSource != null) entry.put("blockSource", blockSource)
            if (category != null) entry.put("category", category)
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
}
