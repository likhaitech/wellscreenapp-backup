package com.wellscreen.app

import android.app.AppOpsManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Process
import android.util.Log
import android.view.inputmethod.InputMethodManager
import org.json.JSONObject
import java.util.Calendar

/**
 * Child-side enforcement of a guardian's per-app daily usage allowance.
 *
 * Reads the paired child's already-synced FlutterSharedPreferences cache.
 * Does not modify manually restricted packages or their Firestore data.
 * A limit is evaluated against Android's usage statistics since local
 * midnight; no mutable counter is stored, so the next day resets naturally.
 *
 * UsageStats access and enabled AccessibilityService are both required.
 * Without Usage Access an app that HAS a limit is treated as limit reached.
 */
internal object AppTimeLimitEnforcer {
    private const val TAG = "WellScreenLimits"
    private const val PREFS = "FlutterSharedPreferences"
    private const val ACTIVE_CHILD_KEY = "flutter.active_child_profile_id"
    private const val LIMITS_KEY = "flutter.app_time_limits_json"
    private const val MAX_DAILY_MINUTES = 24 * 60

    // Never interrupt the child's ability to reach emergency/system UI or
    // manage/accessibility settings. Do not exempt *all* preinstalled apps:
    // YouTube and Chrome are often system apps, but are intended limit targets.
    private val essentialPackages = setOf(
        "android",
        "com.android.systemui",
        "com.android.settings",
        "com.android.phone",
        "com.android.dialer",
        "com.google.android.dialer",
        "com.android.emergency",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
    )

    data class Status(
        val appName: String,
        val limitMinutes: Int,
        val remainingMilliseconds: Long,
    )

    /**
     * Apps that must always stay usable on a monitored phone: WellScreen,
     * the home screen, phone/emergency, Settings and system dialogs.
     */
    fun isAlwaysAllowed(context: Context, targetPackage: String): Boolean =
        targetPackage == context.packageName ||
            targetPackage in essentialPackages ||
            targetPackage == "com.google.android.gms" ||
            isDefaultLauncher(context, targetPackage) ||
            isKeyboard(context, targetPackage)

    /** Keyboards send their own window events while the child types. */
    private fun isKeyboard(context: Context, targetPackage: String): Boolean {
        return try {
            val manager = context.getSystemService(Context.INPUT_METHOD_SERVICE)
                as? InputMethodManager ?: return false
            manager.enabledInputMethodList.any { it.packageName == targetPackage }
        } catch (_: Exception) {
            false
        }
    }

    fun isLimitReached(context: Context, targetPackage: String): Boolean =
        getStatus(context, targetPackage)?.remainingMilliseconds?.let { it <= 0L } ?: false

    /** Query the same UsageStats measurement used for blocking and reminders. */
    fun getStatus(context: Context, targetPackage: String): Status? {
        if (targetPackage.isBlank() || targetPackage == context.packageName ||
            targetPackage in essentialPackages || isDefaultLauncher(context, targetPackage)
        ) return null

        return try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val currentChildProfile = prefs.getString(ACTIVE_CHILD_KEY, null)
            if (currentChildProfile.isNullOrBlank()) return null

            val raw = prefs.getString(LIMITS_KEY, null) ?: return null
            val cache = JSONObject(raw)
            if (cache.optString("childProfileId") != currentChildProfile) return null

            val limits = cache.optJSONArray("limits") ?: return null
            var limitMinutes: Int? = null
            var appName = targetPackage
            for (index in 0 until limits.length()) {
                val limit = limits.optJSONObject(index) ?: continue
                if (limit.optString("packageName") != targetPackage) continue
                val minutes = limit.optInt("limitMinutes", 0)
                if (minutes in 1..MAX_DAILY_MINUTES) {
                    limitMinutes = minutes
                    appName = limit.optString("appName").takeIf { it.isNotBlank() }
                        ?: targetPackage
                }
                break
            }
            val actualLimit = limitMinutes ?: return null
            // F3: without Usage Access the time used cannot be measured. Keep
            // the limited app blocked (fail closed) instead of unlocking it;
            // the guardian sees "Usage Access disabled" on the dashboard.
            if (!hasUsageAccess(context)) return Status(appName, actualLimit, 0L)

            val statsManager = context.getSystemService(Context.USAGE_STATS_SERVICE)
                as? UsageStatsManager ?: return null
            val now = System.currentTimeMillis()
            val localMidnight = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }.timeInMillis
            // UsageStats aggregates can lag during a continuous session.
            // MAX avoids double-counting events and aggregates.
            val aggregates = statsManager.queryAndAggregateUsageStats(localMidnight, now)
            val aggregateMs = aggregates[targetPackage]?.totalTimeInForeground ?: 0L
            val eventsMs = usageFromEvents(statsManager, targetPackage, localMidnight, now)
            val usedMilliseconds = maxOf(aggregateMs, eventsMs)
            Status(appName, actualLimit, actualLimit * 60_000L - usedMilliseconds)
        } catch (e: Exception) {
            Log.w(TAG, "Could not determine usage limit for $targetPackage", e)
            null
        }
    }

    /**
     * Sum foreground sessions in today's Android usage event stream. The
     * currently active session is counted through `now`, so limits work even
     * without a window switch. This remains an OS best-effort measurement,
     * not a cryptographically trustworthy stopwatch.
     */
    private fun usageFromEvents(
        manager: UsageStatsManager,
        targetPackage: String,
        dayStart: Long,
        now: Long,
    ): Long {
        val events = manager.queryEvents(dayStart, now)
        val event = UsageEvents.Event()
        var activeSince: Long? = null
        var totalMs = 0L

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            if (event.packageName != targetPackage) continue
            val at = event.timeStamp.coerceIn(dayStart, now)
            when (event.eventType) {
                // Same event IDs as Android's ACTIVITY_RESUMED/PAUSED on
                // current OS releases, with older MOVE_TO_* compatibility.
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    if (activeSince == null) activeSince = at
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val started = activeSince
                    if (started != null) {
                        totalMs += (at - started).coerceAtLeast(0L)
                        activeSince = null
                    }
                }
            }
        }
        val started = activeSince
        if (started != null) totalMs += (now - started).coerceAtLeast(0L)
        return totalMs
    }

    /**
     * The app's foreground (1) / background (2) events over the last 4 hours,
     * oldest first, for the break timer. Null without Usage Access.
     */
    fun foregroundEvents(context: Context, targetPackage: String, now: Long): List<Pair<Int, Long>>? {
        if (!hasUsageAccess(context)) return null
        return try {
            val manager = context.getSystemService(Context.USAGE_STATS_SERVICE)
                as? UsageStatsManager ?: return null
            val events = manager.queryEvents(now - 4 * 60 * 60_000L, now)
            val event = UsageEvents.Event()
            val result = ArrayList<Pair<Int, Long>>()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                if (event.packageName != targetPackage) continue
                @Suppress("DEPRECATION")
                when (event.eventType) {
                    UsageEvents.Event.MOVE_TO_FOREGROUND -> result.add(1 to event.timeStamp)
                    UsageEvents.Event.MOVE_TO_BACKGROUND -> result.add(2 to event.timeStamp)
                }
            }
            result
        } catch (e: Exception) {
            Log.w(TAG, "Could not read usage events for $targetPackage", e)
            null
        }
    }

    private fun hasUsageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
            ?: return false
        return ops.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }

    fun isDefaultLauncher(context: Context, targetPackage: String): Boolean {
        val home = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val resolved = context.packageManager.resolveActivity(home, 0)
        return resolved?.activityInfo?.packageName == targetPackage
    }
}
