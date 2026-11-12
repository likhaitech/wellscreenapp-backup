package com.wellscreen.app

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Calendar
import java.util.UUID
import java.util.concurrent.TimeUnit

/**
 * Private, durable event outbox. Recording never requires internet or SMS access.
 * The native JobScheduler job flushes accepted IDs to the authenticated backend.
 */
internal object CriticalEventJournal {
    private const val TAG = "WellScreenSecurity"
    private const val PREF_FILE = "WellScreenCriticalEvents"
    private const val OUTBOX = "pending_events_json"
    private const val MAX_QUEUED = 500
    private const val MAX_BATCH = 50
    private val lock = Any()

    fun record(context: Context, type: String, subject: String, label: String,
               cooldownMs: Long = 60L * 60_000L, nowMs: Long = System.currentTimeMillis()) {
        val uid = FirebaseAuth.getInstance().currentUser?.uid ?: return
        val profile = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.active_child_profile_id", null) ?: return
        synchronized(lock) {
            val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
            val digest = MessageDigest.getInstance("SHA-256")
                .digest("$type|$subject".toByteArray())
                .take(12).joinToString("") { "%02x".format(it) }
            val cooldownKey = "last_$digest"
            val last = prefs.getLong(cooldownKey, 0L)
            if (last != 0L && nowMs >= last && nowMs - last < cooldownMs) return
            val pending = load(prefs.getString(OUTBOX, null))
            if (pending.length() >= MAX_QUEUED) {
                Log.w(TAG, "Critical event outbox full; retaining existing events")
                return
            }
            pending.put(JSONObject()
                .put("eventId", UUID.randomUUID().toString())
                .put("type", type)
                .put("childUid", uid)
                .put("childProfileId", profile)
                .put("subject", subject.take(150))
                .put("label", label.take(150))
                .put("timestampMs", nowMs))
            if (!prefs.edit().putString(OUTBOX, pending.toString())
                    .putLong(cooldownKey, nowMs).commit()) {
                Log.w(TAG, "Critical event could not be persisted")
            }
        }
    }

    /** Detect late-night activity from actual Android foreground transitions. */
    fun noteForegroundUse(context: Context, packageName: String) {
        if (packageName == context.packageName || packageName.isBlank()) return
        // Skip system overlays/input-method windows. Count real launchable apps.
        if (context.packageManager.getLaunchIntentForPackage(packageName) == null) return
        // Default restricted window: 22:00–05:00, in device-local timezone.
        // Adjust policy here only after adding a parent-configurable window.
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        if (hour >= 22 || hour < 5) {
            record(context, "late_night_usage", "device_night_use",
                "${appLabel(context, packageName)} at ${hour.toString().padStart(2, '0')}:00",
                cooldownMs = 6L * 60 * 60_000)
        }
    }

    /** Debounced by the AccessibilityService before calling this function. */
    fun noteRestrictedAttempt(context: Context, packageName: String) {
        val now = System.currentTimeMillis()
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(packageName.toByteArray())
            .take(12).joinToString("") { "%02x".format(it) }
        val key = "attempts_$digest"
        val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        synchronized(lock) {
            val previous = load(prefs.getString(key, null))
            val history = JSONArray()
            for (i in 0 until previous.length()) {
                val timestamp = previous.optLong(i, 0L)
                if (timestamp in (now - 10 * 60_000L)..now) history.put(timestamp)
            }
            history.put(now)
            prefs.edit().putString(key, history.toString()).commit()
            if (history.length() >= 3) {
                record(context, "repeated_restricted_app_access", packageName,
                    appLabel(context, packageName), cooldownMs = 60L * 60_000L)
            }
        }
    }

    fun noteTimeLimit(context: Context, packageName: String) {
        record(context, "screen_time_limit_exceeded", packageName,
            appLabel(context, packageName), cooldownMs = 20L * 60 * 60_000)
    }

    fun noteBlockedDomain(context: Context, domain: String) {
        record(context, "restricted_content_attempt", domain, domain,
            cooldownMs = 60L * 60_000L)
    }

    private fun appLabel(context: Context, pkg: String): String = try {
        val info = context.packageManager.getApplicationInfo(pkg, 0)
        context.packageManager.getApplicationLabel(info).toString()
    } catch (_: Exception) { pkg }

    /**
     * Execute only on a background thread; never called from the UI thread.
     * Server acknowledges previously stored events by stable ID, so retrying
     * after a lost response cannot notify the parent twice for the same ID.
     */
    fun flushPending(context: Context, childProfileId: String, childUid: String) {
        val prefs = context.getSharedPreferences(PREF_FILE, Context.MODE_PRIVATE)
        val batch = JSONArray()
        synchronized(lock) {
            val pending = load(prefs.getString(OUTBOX, null))
            for (i in 0 until minOf(pending.length(), MAX_BATCH)) {
                val candidate = pending.getJSONObject(i)
                if (candidate.optString("childUid") == childUid &&
                    candidate.optString("childProfileId") == childProfileId) {
                    batch.put(candidate)
                }
            }
        }
        if (batch.length() == 0) return
        val user = FirebaseAuth.getInstance().currentUser
        if (user?.uid != childUid) return
        val host = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.backend_base_url", null)?.trimEnd('/') ?: return
        val endpoint = URL("$host/monitoring/events")
        if (endpoint.protocol != "https") return
        val idToken = Tasks.await(user.getIdToken(false), 8, TimeUnit.SECONDS).token ?: return
        val requestBody = JSONObject()
            .put("childProfileId", childProfileId)
            .put("events", batch).toString()
        val connection = endpoint.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 10000
            connection.readTimeout = 15000
            connection.doOutput = true
            connection.setRequestProperty("Authorization", "Bearer $idToken")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(requestBody.toByteArray(Charsets.UTF_8)) }
            if (connection.responseCode !in 200..299) {
                Log.w(TAG, "Critical event sync failed, HTTP ${connection.responseCode}")
                return
            }
            val result = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val acceptedRaw = result.optJSONArray("acceptedEventIds") ?: return
            val accepted = mutableSetOf<String>()
            for (i in 0 until acceptedRaw.length()) accepted.add(acceptedRaw.optString(i))
            synchronized(lock) {
                val current = load(prefs.getString(OUTBOX, null))
                val kept = JSONArray()
                for (i in 0 until current.length()) {
                    val event = current.getJSONObject(i)
                    if (event.optString("eventId") !in accepted) kept.put(event)
                }
                prefs.edit().putString(OUTBOX, kept.toString()).commit()
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun load(raw: String?): JSONArray = try {
        if (raw.isNullOrBlank()) JSONArray() else JSONArray(raw)
    } catch (_: Exception) { JSONArray() }
}
