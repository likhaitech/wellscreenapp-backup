package com.wellscreen.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import java.util.Calendar
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONObject

/** Quiet, drawer-only Android notifications for the child device. */
internal object AppTimeLimitNotifier {
    const val CHANNEL_ID = "wellscreen_limit_updates"
    private const val CHANNEL_NAME = "App time limits"
    private const val PREFS = "FlutterSharedPreferences"
    private const val TAG = "WellScreenLimitNotice"
    private val warningLock = Any()
    private val scanRunning = AtomicBoolean(false)
    private val warningExecutor = Executors.newSingleThreadExecutor()

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Quiet notices about your daily app allowances"
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun canNotify(context: Context): Boolean {
        return Build.VERSION.SDK_INT < 33 ||
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED
    }

    fun showAssignedLimit(context: Context, appPackage: String, title: String, body: String): Boolean =
        post(context, "assigned:$appPackage", title, body)

    /** Triggered on foreground activity changes and by the background scan. */
    fun maybeNotifyTenMinutes(
        context: Context,
        targetPackage: String,
        status: AppTimeLimitEnforcer.Status,
    ) {
        if (!TenMinuteWarningPolicy.qualifies(status.limitMinutes, status.remainingMilliseconds)) return
        if (!canNotify(context)) return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val childId = prefs.getString("flutter.active_child_profile_id", null)
        if (childId.isNullOrBlank()) return
        val now = Calendar.getInstance()
        val date = "${now.get(Calendar.YEAR)}-${now.get(Calendar.DAY_OF_YEAR)}"
        // Per-child, per-package, per-limit-value, per-local-day idempotency.
        val key = "flutter.limit_warning_10_${childId.hashCode()}_${targetPackage.hashCode()}_${status.limitMinutes}"
        synchronized(warningLock) {
            if (prefs.getString(key, null) == date) return
            val appName = status.appName.ifBlank { targetPackage }
            val title = if (status.remainingMilliseconds >= 540_000L) {
                "10 minutes of app time remaining"
            } else {
                "Less than 10 minutes remaining"
            }
            val body = "Your daily $appName allowance is nearly used up."
            if (post(context, "ten:$childId:$targetPackage", title, body)) {
                Log.i(TAG, "Ten-minute warning posted for $targetPackage")
                // commit() makes de-duplication durable before a process restart.
                if (!prefs.edit().putString(key, date).commit()) {
                    Log.w(TAG, "Could not persist ten-minute warning marker")
                }
            }
        }
    }

    /**
     * Runs independently of the WellScreen Flutter UI. The AccessibilityService
     * schedules this once each minute. It covers apps that were left earlier
     * and prevents warning delivery from depending on a new window event.
     * Queries usage in a worker thread to avoid blocking accessibility events.
     */
    fun scanTenMinuteWarnings(context: Context) {
        if (!scanRunning.compareAndSet(false, true)) return
        val appContext = context.applicationContext
        warningExecutor.execute {
            try {
                val prefs = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                val activeChild = prefs.getString("flutter.active_child_profile_id", null)
                val raw = prefs.getString("flutter.app_time_limits_json", null)
                if (activeChild.isNullOrBlank() || raw.isNullOrBlank()) return@execute
                val cache = JSONObject(raw)
                if (cache.optString("childProfileId") != activeChild) return@execute
                val limits = cache.optJSONArray("limits") ?: return@execute
                for (i in 0 until limits.length()) {
                    val item = limits.optJSONObject(i) ?: continue
                    val pkg = item.optString("packageName")
                    if (pkg.isBlank()) continue
                    val status = AppTimeLimitEnforcer.getStatus(appContext, pkg) ?: continue
                    maybeNotifyTenMinutes(appContext, pkg, status)
                }
            } catch (error: Exception) {
                Log.w(TAG, "Ten-minute warning scan failed", error)
            } finally {
                scanRunning.set(false)
            }
        }
    }

    /** Break timer notices on the child's phone (ScheduleEnforcer). */
    fun showBreakNotice(context: Context, key: String, title: String, body: String): Boolean =
        post(context, key, title, body)

    private fun post(context: Context, key: String, title: String, body: String): Boolean {
        if (!canNotify(context)) return false
        return try {
            ensureChannel(context)
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as? NotificationManager ?: return false
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .build()
            manager.notify(key.hashCode(), notification)
            true
        } catch (error: Exception) {
            Log.w(TAG, "Failed to post time-limit notification", error)
            false
        }
    }
}
