package com.wellscreen.app

import android.content.Context
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * Tells the guardian straight away when the child hits the same blocked app
 * or website for the 3rd time today, without waiting for the app's next
 * usage sync (which only runs while WellScreen's screen is alive).
 *
 * Uses the same event ID as MonitoringUsageAlertService in Dart
 * ("rra_<target>_<yyyymmdd>"); the backend creates each alert once per ID,
 * so whichever path arrives first sends the push and the other is ignored.
 * Bedtime/focus/break blocks don't count: they cover every app.
 */
internal object RepeatedAttemptAlert {
    private const val TAG = "WellScreenAlerts"
    const val MIN_ATTEMPTS = 3
    private const val SENT_PREFS = "WellScreenRepeatedAttempts"

    data class Entry(
        val target: String,
        val outcome: String,
        val source: String?,
        val timestampMs: Long,
    )

    private val inFlight = mutableSetOf<String>()

    fun dayStamp(nowMs: Long): String {
        val c = Calendar.getInstance().apply { timeInMillis = nowMs }
        val m = (c.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
        val d = c.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
        return "${c.get(Calendar.YEAR)}$m$d"
    }

    /** Same shape as the Dart path's eventId so the backend de-duplicates. */
    fun eventId(target: String, nowMs: Long): String {
        val safe = target.replace(Regex("[^A-Za-z0-9]"), "_").padEnd(3, '_')
        val trimmed = if (safe.length > 60) safe.substring(0, 60) else safe
        return "rra_${trimmed}_${dayStamp(nowMs)}"
    }

    /** Today's blocked attempts on [target], schedule blocks excluded. */
    fun countToday(entries: List<Entry>, target: String, nowMs: Long): Int {
        val today = dayStamp(nowMs)
        return entries.count {
            it.target == target &&
                it.outcome == "blocked" &&
                it.source != "schedule" &&
                dayStamp(it.timestampMs) == today
        }
    }

    /** Only real apps and websites (WellScreen settings entries have a space). */
    fun isAlertable(target: String): Boolean =
        target.contains('.') && !target.contains(' ')

    /** Call right after RestrictionLogger records a "blocked" outcome. */
    fun onBlocked(context: Context, target: String, source: String?) {
        if (source == "schedule" || !isAlertable(target)) return
        try {
            val now = System.currentTimeMillis()
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val entries = parse(prefs.getString("flutter.restriction_log_json", null))
            val count = countToday(entries, target, now)
            if (count < MIN_ATTEMPTS) return
            val id = eventId(target, now)
            val sent = context.getSharedPreferences(SENT_PREFS, Context.MODE_PRIVATE)
            if (sent.getBoolean(id, false)) return
            synchronized(inFlight) { if (!inFlight.add(id)) return }
            val label = "${labelFor(context, target)} ($count attempts today)"
            val app = context.applicationContext
            Thread {
                try {
                    if (send(app, id, target, label, now)) {
                        sent.edit().putBoolean(id, true).apply()
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Repeated-attempt alert failed", e)
                } finally {
                    synchronized(inFlight) { inFlight.remove(id) }
                }
            }.start()
        } catch (e: Exception) {
            Log.w(TAG, "Repeated-attempt check failed", e)
        }
    }

    private fun parse(raw: String?): List<Entry> = try {
        val array = JSONArray(raw ?: "[]")
        (0 until array.length()).mapNotNull { i ->
            val o = array.optJSONObject(i) ?: return@mapNotNull null
            Entry(
                target = o.optString("packageName"),
                outcome = o.optString("outcome"),
                source = if (o.has("blockSource")) o.optString("blockSource") else null,
                timestampMs = o.optLong("timestampMs", 0L),
            )
        }
    } catch (_: Exception) {
        emptyList()
    }

    private fun labelFor(context: Context, target: String): String = try {
        val info = context.packageManager.getApplicationInfo(target, 0)
        context.packageManager.getApplicationLabel(info).toString()
    } catch (_: Exception) {
        target
    }

    /** Background thread only. True when the backend accepted the event. */
    private fun send(context: Context, id: String, target: String, label: String, nowMs: Long): Boolean {
        val flutter = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val profileId = flutter.getString("flutter.active_child_profile_id", null)
        if (profileId.isNullOrBlank()) return false
        val host = flutter.getString("flutter.backend_base_url", null)?.trimEnd('/') ?: return false
        val endpoint = URL("$host/monitoring/events")
        if (endpoint.protocol != "https") return false
        val user = FirebaseAuth.getInstance().currentUser ?: return false
        val token = Tasks.await(user.getIdToken(false), 10, TimeUnit.SECONDS).token ?: return false
        val event = JSONObject()
            .put("type", "repeated_restricted_app_access")
            .put("eventId", id)
            .put("timestampMs", nowMs)
            .put("subject", target.take(150))
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
                Log.w(TAG, "Repeated-attempt alert HTTP $code")
                return false
            }
            val result = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            val accepted = result.optJSONArray("acceptedEventIds") ?: return false
            val ok = (0 until accepted.length()).any { accepted.optString(it) == id }
            Log.i(TAG, "Repeated-attempt alert for $target: accepted=$ok")
            return ok
        } finally {
            connection.disconnect()
        }
    }
}
