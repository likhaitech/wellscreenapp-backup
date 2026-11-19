package com.wellscreen.app

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

/**
 * F8: makes temporary access (Emergency Access and per-app grants) end on
 * time even if the child changes the phone's clock.
 *
 * The first time a grant is seen, its remaining time is turned into a
 * deadline on the phone's "time since boot" clock, which the child cannot
 * change. Later checks use that deadline. After a reboot that clock starts
 * again, so the grant ends (fails closed) and the child asks again.
 */
internal object GrantClock {
    private const val MAX_GRANT_MS = 24L * 60 * 60 * 1000

    data class State(
        val until: Long,
        val deadlineElapsed: Long,
        val observedElapsed: Long,
        val bootCount: Int,
    )

    data class Result(val active: Boolean, val state: State?)

    /**
     * Pure decision, unit tested.
     * @param until grant end time (wall clock, ms) from Firestore.
     * @param durationMs the length the guardian chose, or 0 if unknown.
     */
    fun evaluate(
        saved: State?,
        until: Long,
        durationMs: Long,
        wallNow: Long,
        elapsedNow: Long,
        bootCount: Int,
    ): Result {
        if (until <= 0L) return Result(false, null)
        if (saved != null && saved.until == until) {
            val rebooted = saved.bootCount != bootCount || elapsedNow < saved.observedElapsed
            if (rebooted) return Result(false, saved)
            return Result(elapsedNow < saved.deadlineElapsed, saved)
        }
        var remaining = until - wallNow
        if (durationMs > 0L) remaining = minOf(remaining, durationMs)
        remaining = remaining.coerceIn(0L, MAX_GRANT_MS)
        val state = State(until, elapsedNow + remaining, elapsedNow, bootCount)
        return Result(remaining > 0L, state)
    }

    private const val STORE = "wellscreen_grant_clock"

    /** Android wrapper: reads and saves [State] under [key]. */
    fun isActive(context: Context, key: String, until: Long, durationMs: Long): Boolean {
        return try {
            val store = context.getSharedPreferences(STORE, Context.MODE_PRIVATE)
            val saved = if (store.contains("${key}_until")) {
                State(
                    store.getLong("${key}_until", 0L),
                    store.getLong("${key}_deadline", 0L),
                    store.getLong("${key}_observed", 0L),
                    store.getInt("${key}_boot", -1),
                )
            } else {
                null
            }
            val result = evaluate(
                saved,
                until,
                durationMs,
                System.currentTimeMillis(),
                SystemClock.elapsedRealtime(),
                bootCount(context),
            )
            val state = result.state
            if (state != null && state != saved) {
                store.edit()
                    .putLong("${key}_until", state.until)
                    .putLong("${key}_deadline", state.deadlineElapsed)
                    .putLong("${key}_observed", state.observedElapsed)
                    .putInt("${key}_boot", state.bootCount)
                    .apply()
            }
            result.active
        } catch (_: Exception) {
            // Cannot verify the time: do not grant access.
            false
        }
    }

    /**
     * Emergency Access approved by the guardian and still running. Flutter
     * mirrors grantedUntil (and the chosen duration) into SharedPreferences.
     */
    fun isEmergencyActive(context: Context): Boolean {
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val until = prefs.getLong("flutter.emergency_access_granted_until_ms", 0L)
            if (until <= System.currentTimeMillis()) return false
            val durationMs = try {
                prefs.getLong("flutter.emergency_access_duration_ms", 0L)
            } catch (_: Exception) {
                0L
            }
            isActive(context, "emergency", until, durationMs)
        } catch (_: Exception) {
            false
        }
    }

    private fun bootCount(context: Context): Int {
        return try {
            Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
        } catch (_: Exception) {
            -1
        }
    }
}
