package com.wellscreen.app

import android.app.AppOpsManager
import android.app.job.JobParameters
import android.app.job.JobService
import android.app.usage.UsageStatsManager
import android.content.Context
import android.os.Process
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Source
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors

/**
 * Native fallback for the child when Flutter's widget/timer is not running.
 *
 * - Refreshes limits from SERVER (Firestore), never from an untrusted FCM value.
 * - Publishes an OS-derived usage snapshot to the parent's Firestore stream.
 * - Does not touch manually restricted packages or force a UI to open.
 * - Android JobScheduler decides actual run times (15 minutes is minimum).
 * - Auth, child pairing, and Usage Access are independently verified.
 */
class ScreenTimeReportJobService : JobService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val tag = "WellScreenBackground"

    override fun onStartJob(params: JobParameters): Boolean {
        val uid = FirebaseAuth.getInstance().currentUser?.uid
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val profileId = prefs.getString("flutter.active_child_profile_id", null)
        if (uid.isNullOrBlank() || profileId.isNullOrBlank()) return false

        val firestore = FirebaseFirestore.getInstance()
        val childRef = firestore.collection("child_profiles").document(profileId)
        childRef.get(Source.SERVER).addOnCompleteListener { profileTask ->
            val child = if (profileTask.isSuccessful) profileTask.result?.data else null
            if (child == null ||
                child["childAccountId"] != uid ||
                child["pairingStatus"] != "connected" ||
                FirebaseAuth.getInstance().currentUser?.uid != uid
            ) {
                Log.w(tag, "Catch-up skipped: not paired / signed out / network error")
                jobFinished(params, false)
                return@addOnCompleteListener
            }

            childRef.collection("app_time_limits").get(Source.SERVER)
                .addOnCompleteListener { limitsTask ->
                    if (!limitsTask.isSuccessful) {
                        Log.w(tag, "Catch-up limit fetch failed", limitsTask.exception)
                        jobFinished(params, true)
                        return@addOnCompleteListener
                    }
                    executor.execute {
                        try {
                            if (FirebaseAuth.getInstance().currentUser?.uid != uid ||
                                prefs.getString("flutter.active_child_profile_id", null) != profileId
                            ) {
                                jobFinished(params, false)
                                return@execute
                            }
                            val limits = JSONArray()
                            limitsTask.result?.documents?.forEach { document ->
                                val pkg = document.getString("packageName")
                                val name = document.getString("appName")
                                val minutes = document.getLong("limitMinutes")
                                if (pkg == document.id && !name.isNullOrBlank() &&
                                    minutes != null && minutes in 1L..1440L
                                ) {
                                    limits.put(JSONObject()
                                        .put("packageName", pkg)
                                        .put("appName", name)
                                        .put("limitMinutes", minutes.toInt()))
                                }
                            }
                            val raw = JSONObject()
                                .put("childProfileId", profileId)
                                .put("limits", limits).toString()
                            val saved = prefs.edit()
                                .putString("flutter.app_time_limits_json", raw)
                                .commit()
                            if (!saved) {
                                Log.w(tag, "Catch-up could not persist limits")
                                jobFinished(params, true)
                                return@execute
                            }

                            val updates = hashMapOf<String, Any>(
                                "limitSyncAcknowledgedAt" to FieldValue.serverTimestamp(),
                                "limitSyncAcknowledgedBy" to uid,
                            )
                            // NEVER publish a zero-minute report when Usage Access
                            // is missing. That would falsely clear the parent's screen.
                            if (hasUsageAccess()) {
                                val report = readUsageReport()
                                updates["latestUsageReport.allApps"] = report.apps
                                updates["latestUsageReport.topApps"] = report.apps.take(20)
                                updates["latestUsageReport.totalUsageDurationMs"] = report.totalMs
                                updates["latestUsageReport.allAppsTotalUsageDurationMs"] = report.totalMs
                                updates["latestUsageReport.capturedAt"] = report.capturedAt
                                updates["usageReportUpdatedAt"] = FieldValue.serverTimestamp()
                                // Today's total for the guardian's 7-day chart
                                // (DailyUsageHistory in Dart); a dotted path so
                                // the other stored days are left alone.
                                val dayKey = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())
                                updates["dailyUsageTotals.$dayKey"] = report.totalMs
                            } else {
                                Log.w(tag, "Usage Access missing; no dashboard overwrite")
                            }
                            // Browsing Activity + Restriction Enforcement for
                            // Reports, even when the app itself isn't running.
                            try {
                                BackgroundLogSync.addTo(this@ScreenTimeReportJobService, updates)
                            } catch (error: Exception) {
                                Log.w(tag, "Background browsing/block logs skipped", error)
                            }
                            childRef.update(updates).addOnCompleteListener { updateTask ->
                                if (!updateTask.isSuccessful) {
                                    Log.w(tag, "Catch-up dashboard update failed", updateTask.exception)
                                } else {
                                    Log.i(tag, "Background limits and usage synchronized")
                                }
                                jobFinished(params, !updateTask.isSuccessful)
                            }
                        } catch (error: Exception) {
                            Log.w(tag, "Catch-up failed", error)
                            jobFinished(params, true)
                        }
                    }
                }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        // OS can interrupt this background job; retry at a future opportunity.
        return true
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun hasUsageAccess(): Boolean {
        val ops = getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        return ops.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }

    private data class UsageReport(
        val apps: List<Map<String, Any>>,
        val totalMs: Long,
        val capturedAt: String,
    )

    private fun readUsageReport(): UsageReport {
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val start = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val now = System.currentTimeMillis()
        val aggregated = manager.queryAndAggregateUsageStats(start, now)
        val entries = aggregated.entries.asSequence()
            .filter { (pkg, stat) -> pkg != packageName && stat.totalTimeInForeground > 0L }
            .map { (pkg, stat) ->
                val label = try {
                    val info = packageManager.getApplicationInfo(pkg, 0)
                    packageManager.getApplicationLabel(info).toString()
                } catch (_: Exception) { pkg }
                mapOf<String, Any>(
                    "packageName" to pkg,
                    "displayName" to label,
                    "usageDurationMs" to stat.totalTimeInForeground,
                    "lastTimeUsed" to SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US)
                        .format(Date(stat.lastTimeUsed)),
                )
            }
            .sortedByDescending { (it["usageDurationMs"] as Long) }
            .toList()
        val total = entries.sumOf { it["usageDurationMs"] as Long }
        val timestamp = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX", Locale.US)
            .format(Date(now))
        return UsageReport(entries, total, timestamp)
    }
}
