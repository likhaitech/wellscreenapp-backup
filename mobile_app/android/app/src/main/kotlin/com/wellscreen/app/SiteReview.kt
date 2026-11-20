package com.wellscreen.app

import android.content.Context
import android.util.Log

/**
 * What happens with an UNCERTAIN website (a "hint": Cloudflare's family
 * resolver refuses it, or the page shows some gambling/adult signs but not
 * enough to block), and the child's "Ask my parent to allow this site".
 *
 * - Ages 6 and below (age group from the guardian, PR #29): hints are
 *   blocked, because young children don't need borderline sites.
 * - Older children: NOT blocked. The guardian gets one "Review this site"
 *   alert per site per day, with Allow / Block buttons.
 * Education/health sites and guardian-allowed sites never reach this.
 */
internal object SiteReview {
    private const val TAG = "WellScreenSiteReview"
    private const val SENT_PREFS = "WellScreenSiteReview"
    const val AGE_KEY = "flutter.child_age_group"
    const val YOUNGEST = "6_and_below"

    const val REVIEW_EVENT = "site_review_needed"
    const val REQUEST_EVENT = "site_access_request"

    private val inFlight = HashSet<String>()
    // Last attempt per event, so an offline phone doesn't retry constantly.
    private val lastTry = HashMap<String, Long>()
    private const val RETRY_MS = 10 * 60 * 1000L

    /** Hints become blocks only for the youngest age group. */
    fun blocksHints(ageGroup: String?): Boolean = ageGroup == YOUNGEST

    fun ageGroup(context: Context): String? = try {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString(AGE_KEY, null)
    } catch (_: Exception) {
        null
    }

    fun reviewEventId(domain: String, nowMs: Long): String =
        MonitoringEventSender.safeId("rev", domain, RepeatedAttemptAlert.dayStamp(nowMs))

    fun requestEventId(domain: String, nowMs: Long): String =
        MonitoringEventSender.safeId("req", domain, RepeatedAttemptAlert.dayStamp(nowMs))

    /** Plain words for the guardian's alert. */
    fun reasonLabel(reason: String, category: String?): String = when (reason) {
        "cloudflare" -> "flagged by Cloudflare's family filter"
        "page" -> when (category) {
            "gambling" -> "the page shows some gambling words"
            "adult" -> "the page shows some adult words"
            else -> "the page shows some warning signs"
        }
        else -> "it may not be suitable"
    }

    /** Once per site per day; background thread. */
    fun sendReview(context: Context, domain: String, reason: String, category: String?) {
        val now = System.currentTimeMillis()
        val id = reviewEventId(domain, now)
        send(context, REVIEW_EVENT, id, domain, "$domain (${reasonLabel(reason, category)})", now, null)
    }

    /** The child's "Ask my parent to allow this site". */
    fun sendAccessRequest(context: Context, domain: String, onDone: (Boolean) -> Unit) {
        val now = System.currentTimeMillis()
        val id = requestEventId(domain, now)
        send(context, REQUEST_EVENT, id, domain, domain, now, onDone)
    }

    private fun send(
        context: Context,
        type: String,
        id: String,
        domain: String,
        label: String,
        now: Long,
        onDone: ((Boolean) -> Unit)?,
    ) {
        val app = context.applicationContext
        val sent = app.getSharedPreferences(SENT_PREFS, Context.MODE_PRIVATE)
        if (sent.getBoolean(id, false)) {
            onDone?.invoke(true)
            return
        }
        synchronized(inFlight) {
            // A child pressing "Ask" again may retry sooner; automatic
            // review alerts wait 10 minutes after a failed try.
            val last = lastTry[id]
            if (onDone == null && last != null && now - last < RETRY_MS) return
            if (!inFlight.add(id)) {
                onDone?.invoke(true)
                return
            }
            lastTry[id] = now
        }
        Thread {
            var ok = false
            try {
                ok = MonitoringEventSender.post(app, type, id, domain, label, now)
                if (ok) sent.edit().putBoolean(id, true).apply()
            } catch (e: Exception) {
                Log.w(TAG, "$type for $domain failed", e)
            } finally {
                synchronized(inFlight) { inFlight.remove(id) }
            }
            try { onDone?.invoke(ok) } catch (_: Exception) { }
        }.start()
    }
}
