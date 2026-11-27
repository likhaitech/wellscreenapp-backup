package com.wellscreen.app

import android.content.Context
import org.json.JSONArray

/**
 * True when the browser app itself is blocked: restricted by the guardian,
 * out of daily time, or inside a schedule block.
 *
 * Then the app block screen handles the browser, and a website block must
 * not send the child back to it. Opening a safe page in a blocked browser
 * showed the browser again, which was blocked again: an endless loop.
 */
object BrowserAppBlock {
    private const val PREFS = "FlutterSharedPreferences"
    private const val RESTRICTED_KEY = "flutter.restricted_packages_json"
    private const val CACHE_MS = 2000L

    private var cachedPackage: String? = null
    private var cachedAt = 0L
    private var cachedResult = false

    fun isBlockedAsApp(context: Context, browserPackage: String): Boolean {
        val now = System.currentTimeMillis()
        if (cachedPackage == browserPackage && now - cachedAt < CACHE_MS) {
            return cachedResult
        }
        val result = check(context, browserPackage, now)
        cachedPackage = browserPackage
        cachedAt = now
        cachedResult = result
        return result
    }

    private fun check(context: Context, browserPackage: String, now: Long): Boolean {
        if (AppTimeLimitEnforcer.isAlwaysAllowed(context, browserPackage)) return false
        if (GrantClock.isEmergencyActive(context)) return false
        if (TemporaryAppGrantCache.isActive(context, browserPackage, now)) return false
        if (RelatedTargets.blockingPackageFor(browserPackage, restricted(context)) != null) {
            return true
        }
        if (AppTimeLimitEnforcer.isLimitReached(context, browserPackage)) return true
        return try {
            ScheduleEnforcer.activeBlock(context, browserPackage, now) != null
        } catch (_: Exception) {
            false
        }
    }

    private fun restricted(context: Context): Set<String> = try {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(RESTRICTED_KEY, null) ?: "[]"
        val array = JSONArray(raw)
        (0 until array.length()).map { array.optString(it).trim() }
            .filter { it.isNotEmpty() }.toSet()
    } catch (_: Exception) {
        emptySet()
    }
}
