package com.wellscreen.app

import android.content.Context
import org.json.JSONObject
import java.util.Calendar

/**
 * Guardian schedules on the child phone (Objective 2.5):
 * - bedtime lock: apps paused between two times every day;
 * - focus mode: apps paused until a set time;
 * - break timer ("cooldown timer"): after N minutes of non-stop use of one
 *   app, that app pauses for M minutes.
 *
 * The phone, Settings, keyboard, home screen and WellScreen are never paused
 * (AppTimeLimitEnforcer.isAlwaysAllowed). Emergency Access and approved app
 * time still work. Rules come from Flutter in flutter.wellscreen_schedules_json.
 */
internal object ScheduleEnforcer {
    private const val PREFS = "FlutterSharedPreferences"
    private const val KEY = "flutter.wellscreen_schedules_json"
    private const val BREAKS_STORE = "wellscreen_breaks"
    private const val SESSION_GAP_MS = 60_000L
    private const val WARN_BEFORE_MS = 60_000L
    private const val SESSION_CHECK_EVERY_MS = 5_000L

    data class Schedule(
        val bedtimeEnabled: Boolean,
        val bedtimeStart: Int,
        val bedtimeEnd: Int,
        val focusUntilMs: Long,
        val focusDurationMs: Long,
        val breaksEnabled: Boolean,
        val breakAfterMinutes: Int,
        val breakMinutes: Int,
    )

    /** Why an app is paused and until when (wall clock). */
    data class Block(val reason: String, val endsAtMs: Long)

    // ---- pure helpers (unit tested) ----

    fun parse(raw: String?): Schedule? {
        if (raw.isNullOrBlank()) return null
        return try {
            val json = JSONObject(raw)
            val bedtime = json.optJSONObject("bedtime")
            val focus = json.optJSONObject("focus")
            val breaks = json.optJSONObject("breaks")
            val start = bedtime?.optInt("start", -1) ?: -1
            val end = bedtime?.optInt("end", -1) ?: -1
            val after = breaks?.optInt("afterMinutes", 0) ?: 0
            val pause = breaks?.optInt("breakMinutes", 0) ?: 0
            Schedule(
                bedtimeEnabled = bedtime?.optBoolean("enabled", false) == true &&
                    start in 0..1439 && end in 0..1439 && start != end,
                bedtimeStart = start,
                bedtimeEnd = end,
                focusUntilMs = focus?.optLong("untilMs", 0L) ?: 0L,
                focusDurationMs = focus?.optLong("durationMs", 0L) ?: 0L,
                breaksEnabled = breaks?.optBoolean("enabled", false) == true &&
                    after in 15..240 && pause in 1..120,
                breakAfterMinutes = after,
                breakMinutes = pause,
            )
        } catch (_: Exception) {
            null
        }
    }

    /** True when [minuteOfDay] is inside start..end (may cross midnight). */
    fun isInWindow(minuteOfDay: Int, start: Int, end: Int): Boolean {
        if (start == end) return false
        return if (start < end) minuteOfDay in start until end
        else minuteOfDay >= start || minuteOfDay < end
    }

    /** Minutes from [minuteOfDay] until the window's end. */
    fun minutesUntilEnd(minuteOfDay: Int, end: Int): Int {
        val diff = end - minuteOfDay
        return if (diff > 0) diff else diff + 24 * 60
    }

    /**
     * Start of the app's current non-stop session from its foreground (1) /
     * background (2) events, oldest first. Gaps up to [gapMs] (switching
     * screens, a notification) do not end a session. Null if the app is not
     * in the foreground now.
     */
    /**
     * True when one app has been used non-stop (gaps under a minute join the
     * session) for the break timer's "after" minutes.
     */
    fun needsBreak(events: List<Pair<Int, Long>>, now: Long, schedule: Schedule): Boolean {
        if (!schedule.breaksEnabled) return false
        val start = sessionStart(events, SESSION_GAP_MS) ?: return false
        return now - start >= schedule.breakAfterMinutes * 60_000L
    }

    fun sessionStart(events: List<Pair<Int, Long>>, gapMs: Long): Long? {
        var start: Long? = null
        var lastBackground: Long? = null
        var inForeground = false
        for ((type, at) in events) {
            if (type == 1 && !inForeground) {
                val previous = lastBackground
                if (start == null || previous == null || at - previous > gapMs) start = at
                inForeground = true
            } else if (type == 2 && inForeground) {
                inForeground = false
                lastBackground = at
            }
        }
        return if (inForeground) start else null
    }

    // ---- Android wrapper ----

    @Volatile private var cachedRaw: String? = null
    @Volatile private var cached: Schedule? = null
    private val lastSessionCheck = HashMap<String, Long>()

    private fun load(context: Context): Schedule? {
        val raw = try {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null)
        } catch (_: Exception) {
            null
        }
        if (raw != cachedRaw) {
            cachedRaw = raw
            cached = parse(raw)
        }
        return cached
    }

    /** The schedule pausing [packageName] now, or null. */
    fun activeBlock(context: Context, packageName: String, now: Long): Block? {
        val schedule = load(context) ?: return null

        // Focus mode. The boot-clock check keeps it on if the clock is moved
        // forward (GrantClock); the wall-clock check keeps it on if moved back.
        val until = schedule.focusUntilMs
        if (until > 0L) {
            val onBootClock = GrantClock.isActive(context, "focus", until, schedule.focusDurationMs)
            if (onBootClock || until > now) return Block("focus", until)
        }

        if (schedule.bedtimeEnabled) {
            val calendar = Calendar.getInstance().apply { timeInMillis = now }
            val minute = calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
            if (isInWindow(minute, schedule.bedtimeStart, schedule.bedtimeEnd)) {
                val endsAt = now + minutesUntilEnd(minute, schedule.bedtimeEnd) * 60_000L -
                    calendar.get(Calendar.SECOND) * 1_000L
                return Block("bedtime", endsAt)
            }
        }

        if (schedule.breaksEnabled) return breakBlock(context, packageName, now, schedule)
        return null
    }

    private fun breakBlock(context: Context, packageName: String, now: Long, schedule: Schedule): Block? {
        val breakMs = schedule.breakMinutes * 60_000L
        val store = context.getSharedPreferences(BREAKS_STORE, Context.MODE_PRIVATE)
        val until = store.getLong(packageName, 0L)
        if (until > 0L &&
            (until > now || GrantClock.isActive(context, "break_$packageName", until, breakMs))
        ) {
            return Block("break", until)
        }

        // Reading usage events is not free: at most once per 5 s per app.
        synchronized(lastSessionCheck) {
            val last = lastSessionCheck[packageName]
            if (last != null && now - last in 0 until SESSION_CHECK_EVERY_MS) return null
            lastSessionCheck[packageName] = now
        }
        val events = AppTimeLimitEnforcer.foregroundEvents(context, packageName, now) ?: return null
        maybeWarnBeforeBreak(context, packageName, events, now, schedule)
        if (!needsBreak(events, now, schedule)) return null

        val newUntil = now + breakMs
        store.edit().putLong(packageName, newUntil).apply()
        GrantClock.isActive(context, "break_$packageName", newUntil, breakMs)
        AppTimeLimitNotifier.showBreakNotice(
            context,
            "break_$packageName",
            "Break time",
            "${appLabel(context, packageName)} is paused for " +
                "${durationText(schedule.breakMinutes)}. Try something else for a bit.",
        )
        return Block("break", newUntil)
    }

    /** True when the break is at most a minute away in this session. */
    fun breakIsNear(events: List<Pair<Int, Long>>, now: Long, schedule: Schedule): Boolean {
        if (!schedule.breaksEnabled) return false
        val start = sessionStart(events, SESSION_GAP_MS) ?: return false
        val left = schedule.breakAfterMinutes * 60_000L - (now - start)
        return left in 1..WARN_BEFORE_MS
    }

    /** One "Break in 1 min" notice per non-stop session of an app. */
    private fun maybeWarnBeforeBreak(
        context: Context,
        packageName: String,
        events: List<Pair<Int, Long>>,
        now: Long,
        schedule: Schedule,
    ) {
        if (!breakIsNear(events, now, schedule)) return
        val start = sessionStart(events, SESSION_GAP_MS) ?: return
        val store = context.getSharedPreferences(BREAKS_STORE, Context.MODE_PRIVATE)
        val key = "warned_$packageName"
        if (store.getLong(key, 0L) == start) return
        store.edit().putLong(key, start).apply()
        AppTimeLimitNotifier.showBreakNotice(
            context,
            "break_$packageName",
            "Break in 1 minute",
            "${appLabel(context, packageName)} will pause for " +
                "${durationText(schedule.breakMinutes)} in about a minute.",
        )
    }

    /** "5 min", "1 h", "1 h 30 min". */
    fun durationText(minutes: Int): String {
        val h = minutes / 60
        val m = minutes % 60
        return when {
            h == 0 -> "$m min"
            m == 0 -> "$h h"
            else -> "$h h $m min"
        }
    }

    private fun appLabel(context: Context, packageName: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(packageName, 0)).toString()
    } catch (_: Exception) {
        "This app"
    }
}
