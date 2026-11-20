package com.wellscreen.app

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/**
 * Posts one child event to the backend's POST /monitoring/events, which
 * creates the guardian's alert (push + Notifications history) once per
 * event ID. Background thread only. Same request shape as
 * RepeatedAttemptAlert, shared by the website review / ask-to-allow events.
 */
internal object MonitoringEventSender {
    private const val TAG = "WellScreenAlerts"

    /** Event IDs the backend accepts: [a-zA-Z0-9_-]{8,96}. */
    fun safeId(prefix: String, target: String, suffix: String): String {
        val safe = target.replace(Regex("[^A-Za-z0-9]"), "_").padEnd(3, '_')
        val trimmed = if (safe.length > 60) safe.substring(0, 60) else safe
        return "${prefix}_${trimmed}_$suffix"
    }

    /** True when the backend accepted (or already had) the event. */
    fun post(
        context: Context,
        type: String,
        eventId: String,
        subject: String,
        label: String,
        nowMs: Long,
    ): Boolean {
        val flutter = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val profileId = flutter.getString("flutter.active_child_profile_id", null)
        if (profileId.isNullOrBlank()) return false
        val host = flutter.getString("flutter.backend_base_url", null)?.trimEnd('/') ?: return false
        val endpoint = URL("$host/monitoring/events")
        if (endpoint.protocol != "https") return false
        val user = FirebaseAuth.getInstance().currentUser ?: return false
        val token = Tasks.await(user.getIdToken(false), 10, TimeUnit.SECONDS).token ?: return false
        val event = JSONObject()
            .put("type", type)
            .put("eventId", eventId)
            .put("timestampMs", nowMs)
            .put("subject", subject.take(150))
            .put("label", label.take(150))
        val body = JSONObject()
            .put("childProfileId", profileId)
            .put("events", JSONArray().put(event))
            .toString()
        val connection = endpoint.openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            // Render can take ~30 s to wake from sleep.
            connection.connectTimeout = 15_000
            connection.readTimeout = 45_000
            connection.doOutput = true
            connection.setRequestProperty("Authorization", "Bearer $token")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = connection.responseCode
            if (code !in 200..299) {
                Log.w(TAG, "$type event HTTP $code")
                return false
            }
            val result = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val accepted = result.optJSONArray("acceptedEventIds") ?: return false
            return (0 until accepted.length()).any { accepted.optString(it) == eventId }
        } finally {
            connection.disconnect()
        }
    }
}
