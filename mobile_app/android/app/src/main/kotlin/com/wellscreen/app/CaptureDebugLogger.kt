package com.wellscreen.app

import android.content.Context
import android.content.pm.ApplicationInfo
import org.json.JSONArray
import org.json.JSONObject

/**
 * In-app-visible mirror of the WellScreenCapture logcat trace (see the
 * Log.d calls throughout WellScreenAccessibilityService.kt and
 * BrowserUrlExtractor.kt). Exists because remote troubleshooting
 * repeatedly hit a wall getting ADB/USB debugging recognized on the actual
 * test device - this makes the same trace readable from a screen inside
 * the app itself instead, no computer or cable required. Same rolling-log
 * shape/pattern as BrowsingLogger/RestrictionLogger.
 *
 * Deliberately best-effort and silent on failure, same as those - a
 * logging call must never be what breaks real capture.
 *
 * Debug builds only: a release APK writes nothing here, so the child's
 * captured domains are never kept in this extra plain-text log.
 */
object CaptureDebugLogger {
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val LOG_KEY = "flutter.capture_debug_log_json"
    private const val MAX_LOG_ENTRIES = 200

    fun log(context: Context, message: String) {
        val debuggable =
            (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!debuggable) return
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val log = JSONArray(prefs.getString(LOG_KEY, "[]") ?: "[]")

            val entry = JSONObject()
            entry.put("message", message)
            entry.put("timestampMs", System.currentTimeMillis())
            log.put(entry)

            val trimmed = JSONArray()
            val start = maxOf(0, log.length() - MAX_LOG_ENTRIES)
            for (i in start until log.length()) {
                trimmed.put(log.get(i))
            }

            prefs.edit().putString(LOG_KEY, trimmed.toString()).apply()
        } catch (_: Exception) {
            // Best-effort only.
        }
    }
}
