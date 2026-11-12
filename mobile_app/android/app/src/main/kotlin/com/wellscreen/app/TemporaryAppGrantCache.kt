package com.wellscreen.app

import android.content.Context
import org.json.JSONObject

/**
 * App-specific temporary access: separate from emergency access and daily
 * allowances. Firestore grants are mirrored by Flutter into SharedPreferences.
 * An expired grant fails closed without any Flutter activity or network.
 */
internal object TemporaryAppGrantCache {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.temporary_access_grants_json"
    private const val CHILD = "flutter.active_child_profile_id"

    fun isActive(context: Context, targetPackage: String, nowMs: Long): Boolean {
        if (targetPackage.isBlank() || targetPackage == context.packageName) return false
        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val childId = prefs.getString(CHILD, null)
            if (childId.isNullOrBlank()) return false
            val raw = prefs.getString(KEY, null) ?: return false
            val data = JSONObject(raw)
            if (data.optString("childProfileId") != childId) return false
            val grants = data.optJSONArray("grants") ?: return false
            for (i in 0 until grants.length()) {
                val grant = grants.optJSONObject(i) ?: continue
                if (grant.optString("packageName") != targetPackage) continue
                if (grant.optString("state") != "active") return false
                val until = grant.optLong("expiresAtMs", 0L)
                return until > nowMs && until - nowMs <= 180 * 60_000L
            }
            false
        } catch (_: Exception) {
            false
        }
    }
}
