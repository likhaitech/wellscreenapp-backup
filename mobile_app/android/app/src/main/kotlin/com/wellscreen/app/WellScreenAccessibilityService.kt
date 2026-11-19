
package com.wellscreen.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.util.Log
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONArray

// Debug-only tag for the browsing-capture path specifically (not restricted-
// app blocking, which already has its own real signal - the block screen
// itself). Added because remote troubleshooting hit a wall: usage-stats
// sync proved pairing/Firestore/sync all work, isolating the problem to
// this capture path specifically, with no way to see WHERE it fails short
// of reading actual logcat output. Filter with: adb logcat -s WellScreenCapture
private const val CAPTURE_LOG_TAG = "WellScreenCapture"

class WellScreenAccessibilityService : AccessibilityService() {

    private var lastBlockedPackage: String? = null
    private var lastBlockTime: Long = 0L

    // Last successfully decoded local restrictions. Do not treat a one-off
    // SharedPreferences read/JSON failure as an explicit parental unrestrict.
    // A valid [] immediately clears this snapshot as intended.
    private var lastValidRestrictedPackages: Set<String> = emptySet()

    // Separate debounce state for the emergency-access-bypass log path
    // (see checkRestrictedApp) - a restricted app can trigger many
    // TYPE_WINDOW_STATE_CHANGED/TYPE_WINDOWS_CHANGED events per minute
    // (screen/dialog/tab changes) while a bypass is active, same as it can
    // while blocked. Without this, every one of those became its own
    // restrictionLog Firestore write for the whole bypass window, instead
    // of one entry per ~2.5s like the "blocked" path already debounces to.
    private var lastBypassLoggedPackage: String? = null
    private var lastBypassLogTime: Long = 0L

    // Last domain captured per browser package, so repeated events for the
    // same still-loaded page (this fires more than once per navigation in
    // practice) don't spam BrowsingLogger with duplicate entries.
    private val lastCapturedDomain = mutableMapOf<String, String>()

    // Accessibility window events do not necessarily fire when a child stays
    // inside one app for their entire allowance. Re-check the active window
    // while this native service is alive (independent of Flutter lifecycle).
    // Only the limited app triggers a UsageStats query; others are cheap.
    // Unlike the 5-second foreground block check, this also checks apps
    // not currently on screen. Works while the AccessibilityService remains
    // enabled, even if the Flutter Activity is not open.
    private val warningPollHandler = Handler(Looper.getMainLooper())
    private val warningPollIntervalMs = 60_000L
    private val warningPoll = object : Runnable {
        override fun run() {
            AppTimeLimitNotifier.scanTenMinuteWarnings(applicationContext)
            warningPollHandler.postDelayed(this, warningPollIntervalMs)
        }
    }

    private val limitPollHandler = Handler(Looper.getMainLooper())
    private val limitPollIntervalMs = 5_000L
    private val limitPoll = object : Runnable {
        override fun run() {
            try {
                val activePackage = rootInActiveWindow?.packageName?.toString()
                if (!activePackage.isNullOrEmpty() && activePackage != packageName) {
                    if (activePackage in ProtectedSettingsGuard.SETTINGS_PACKAGES) {
                        maybeGuardSettings(activePackage)
                    }
                    checkRestrictedApp(activePackage)
                }
                // Split screen and picture-in-picture: a restricted app can be
                // visible without being the active window.
                for (visiblePackage in otherVisibleAppPackages(activePackage)) {
                    checkRestrictedApp(visiblePackage, notInFront = true)
                }
            } catch (e: Exception) {
                Log.w("WellScreenLimits", "Foreground limit check failed", e)
            } finally {
                limitPollHandler.postDelayed(this, limitPollIntervalMs)
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        limitPollHandler.removeCallbacks(limitPoll)
        limitPollHandler.postDelayed(limitPoll, limitPollIntervalMs)
        warningPollHandler.removeCallbacks(warningPoll)
        warningPollHandler.post(warningPoll)
        ScreenTimeReportScheduler.schedule(this)
    }

    override fun onDestroy() {
        limitPollHandler.removeCallbacks(limitPoll)
        warningPollHandler.removeCallbacks(warningPoll)
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null) return

        val currentPackage = event.packageName?.toString() ?: return

        // Do not block WellScreen itself.
        if (currentPackage == packageName) return

        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOWS_CHANGED -> {
                // Fires on app switches and new windows/tabs - covers both
                // "child opened a browser" (captures whatever's already in
                // the address bar) and restricted-app detection.
                if (BrowserUrlExtractor.isKnownBrowser(currentPackage)) {
                    val msg = "$currentPackage: window-state/windows-changed event received"
                    Log.d(CAPTURE_LOG_TAG, msg)
                    CaptureDebugLogger.log(this, msg)
                }
                if (currentPackage in ProtectedSettingsGuard.SETTINGS_PACKAGES) {
                    maybeGuardSettings(currentPackage)
                }
                maybeCaptureBrowserUrl(currentPackage)
                checkRestrictedApp(currentPackage)
            }
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                // Covers in-app navigation that DOESN'T fire a window-state
                // event - the common case of typing a new URL into an
                // already-open browser's address bar and hitting Go. This
                // was the original gap: without it, capture only ever saw
                // whatever page a browser happened to already be showing
                // at the moment it became the foreground window, and
                // silently missed every navigation after that. Content-
                // changed fires constantly across every app, so this is
                // deliberately restricted to known-browser packages only -
                // restricted-app blocking doesn't need it (that's fully
                // covered by the branch above), so it's skipped here to
                // avoid running that check on every UI update system-wide.
                // Settings often changes page without a new window.
                if (currentPackage in ProtectedSettingsGuard.SETTINGS_PACKAGES) {
                    maybeGuardSettings(currentPackage)
                }
                if (BrowserUrlExtractor.isKnownBrowser(currentPackage)) {
                    val msg = "$currentPackage: content-changed event received"
                    Log.d(CAPTURE_LOG_TAG, msg)
                    CaptureDebugLogger.log(this, msg)
                    maybeCaptureBrowserUrl(currentPackage)
                }
            }
            else -> return
        }
    }

    /**
     * Packages of other app windows on screen (the second half of split
     * screen, a picture-in-picture window), excluding the active one and
     * WellScreen itself.
     */
    private fun otherVisibleAppPackages(activePackage: String?): Set<String> {
        return try {
            windows
                .filter { it.type == AccessibilityWindowInfo.TYPE_APPLICATION }
                .mapNotNull { it.root?.packageName?.toString() }
                .filter { it.isNotEmpty() && it != activePackage && it != packageName }
                .toSet()
        } catch (_: Exception) {
            emptySet()
        }
    }

    private var lastSignInBlockTime: Long = 0L

    /**
     * F2: blocking is switched on but nobody is signed in to WellScreen (for
     * example after Settings > Apps > WellScreen > Clear storage wiped the
     * rules). Treat the phone as "needs sign-in" instead of unrestricted.
     * Fails open if Firebase cannot be read, so the phone is never locked
     * by an error.
     */
    private fun needsSignIn(): Boolean {
        return try {
            FirebaseAuth.getInstance().currentUser == null
        } catch (e: Exception) {
            Log.w("WellScreenLimits", "Could not read sign-in state", e)
            false
        }
    }

    private fun showSignInRequired(currentPackage: String): Boolean {
        if (AppTimeLimitEnforcer.isAlwaysAllowed(this, currentPackage)) return false
        if (!needsSignIn()) return false
        val now = System.currentTimeMillis()
        if (BlockedAppActivity.isShowing && now - lastSignInBlockTime < 2500) return true
        lastSignInBlockTime = now
        try {
            val intent = Intent(this, BlockedAppActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            intent.putExtra(BlockedAppActivity.EXTRA_MODE, BlockedAppActivity.MODE_SIGN_IN_REQUIRED)
            startActivity(intent)
        } catch (e: Exception) {
            Log.w("WellScreenLimits", "Could not show sign-in screen", e)
        }
        return true
    }

    private fun checkRestrictedApp(currentPackage: String, notInFront: Boolean = false) {
        if (showSignInRequired(currentPackage)) return
        // A blocked app's Lite version is blocked too (RelatedTargets).
        val blockingPackage =
            RelatedTargets.blockingPackageFor(currentPackage, getRestrictedPackages())
        val permanentlyRestricted = blockingPackage != null
        // Keep temporary daily limits completely separate from the existing
        // permanent restrictions; a limited app must remain usable below its
        // threshold. Fail open if Usage Access is missing/unavailable.
        val limitStatus = if (permanentlyRestricted) null else
            AppTimeLimitEnforcer.getStatus(this, currentPackage)
        // Silent Android notification only; does not interrupt the app.
        // Polls approximately every 5 seconds even during a long session.
        if (limitStatus != null && !isEmergencyAccessActive(System.currentTimeMillis())) {
            AppTimeLimitNotifier.maybeNotifyTenMinutes(this, currentPackage, limitStatus)
        }
        val dailyLimitReached = limitStatus?.remainingMilliseconds?.let { it <= 0L } ?: false

        if (permanentlyRestricted || dailyLimitReached) {
            val now = System.currentTimeMillis()

            // New per-app grants are independent of the global emergency bypass.
            // Keep permanent restrictions intact; expiration is checked natively.
            if (TemporaryAppGrantCache.isActive(this, currentPackage, now)) {
                return
            }
            // A grant for the blocked app also covers its Lite version.
            if (blockingPackage != null && blockingPackage != currentPackage &&
                TemporaryAppGrantCache.isActive(this, blockingPackage, now)
            ) {
                return
            }

            if (isEmergencyAccessActive(now)) {
                // Parent approved a temporary bypass (EmergencyAccessService,
                // Dart side) and it hasn't expired yet - skip blocking, but
                // still log it the same way a real block would be logged so
                // the parent's report/reports_screen.dart restrictionLog
                // shows the bypass happened rather than going silent.
                // Debounced the same way "blocked" is below - without this,
                // a single bypass session logged one Firestore write per
                // window-state event instead of ~1 per 2.5s.
                val recentlyLoggedSameBypass =
                    lastBypassLoggedPackage == currentPackage &&
                        now - lastBypassLogTime < 2500

                if (!recentlyLoggedSameBypass) {
                    lastBypassLoggedPackage = currentPackage
                    lastBypassLogTime = now

                    RestrictionLogger.recordOutcome(
                        this,
                        currentPackage,
                        "emergency_access_bypass",
                        now,
                    )
                }
                return
            }

            // Gated on BlockedAppActivity.isShowing too, not just elapsed
            // time - a bare time window let a child dismiss the block
            // screen ("Go Back", or just switching via Recents - both
            // near-instant) and land right back on the still-running
            // restricted app underneath with nothing re-blocking it until
            // the 2.5s window happened to expire on its own. Once the
            // block screen is actually gone, the very next foreground
            // event for that package must re-block it.
            val recentlyBlockedSameApp =
                lastBlockedPackage == currentPackage &&
                    now - lastBlockTime < 2500 &&
                    BlockedAppActivity.isShowing

            if (!recentlyBlockedSameApp) {
                lastBlockedPackage = currentPackage
                lastBlockTime = now

                try {
                    if (notInFront) {
                        // Leave split screen first, otherwise the block screen
                        // only covers one half. Wait for the home screen before
                        // showing the block screen so it is not hidden behind it.
                        performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
                        limitPollHandler.postDelayed({
                            try {
                                openBlockedScreen(currentPackage, timeLimitReached = dailyLimitReached)
                            } catch (e: Exception) {
                                Log.w("WellScreenLimits", "Delayed block screen failed", e)
                            }
                        }, 400L)
                    } else {
                        openBlockedScreen(currentPackage, timeLimitReached = dailyLimitReached)
                    }
                    RestrictionLogger.recordOutcome(this, currentPackage, "blocked", now)
                } catch (_: Exception) {
                    RestrictionLogger.recordOutcome(
                        this,
                        currentPackage,
                        "failed_exception",
                        now,
                    )
                }

                // Preserve SMS behavior for manually restricted apps only;
                // don't introduce new SMS traffic for daily-limit blocks.
                if (permanentlyRestricted) {
                    SmsAlertSender.maybeSendRestrictedAppAlert(
                        this,
                        currentPackage,
                        getAppLabel(currentPackage),
                        now,
                    )
                }
            }
        }
    }

    private var lastSettingsCheckTime: Long = 0L
    private var lastSettingsBlockTime: Long = 0L

    /**
     * U1: while this phone is paired, cover WellScreen's uninstall, App info,
     * Accessibility and Device Admin "Deactivate" screens. The guardian can
     * lift this by approving Emergency Access.
     */
    private fun maybeGuardSettings(settingsPackage: String) {
        val now = System.currentTimeMillis()
        if (now - lastSettingsCheckTime < 500) return
        lastSettingsCheckTime = now
        try {
            if (!isPairedChildPhone()) return
            if (isEmergencyAccessActive(now)) return
            if (BlockedAppActivity.isShowing && now - lastSettingsBlockTime < 2500) return

            val root = rootInActiveWindow ?: return
            if (root.packageName?.toString() != settingsPackage) return
            val texts = collectScreenTexts(root)
            val label = try {
                packageManager.getApplicationLabel(applicationInfo).toString()
            } catch (_: Exception) {
                "WellScreen"
            }
            val description = try {
                getString(R.string.wellscreen_accessibility_description)
            } catch (_: Exception) {
                ""
            }
            if (!ProtectedSettingsGuard.isProtectedScreen(texts, label, description)) return

            lastSettingsBlockTime = now
            val intent = Intent(this, BlockedAppActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            intent.putExtra(BlockedAppActivity.EXTRA_MODE, BlockedAppActivity.MODE_PROTECTED_SETTINGS)
            startActivity(intent)
            RestrictionLogger.recordOutcome(this, "WellScreen settings", "blocked", now)
        } catch (e: Exception) {
            Log.w("WellScreenLimits", "Settings guard check failed", e)
        }
    }

    private fun isPairedChildPhone(): Boolean {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            !prefs.getString("flutter.active_child_profile_id", null).isNullOrBlank()
        } catch (_: Exception) {
            false
        }
    }

    /** Texts and content descriptions on screen, capped to keep this cheap. */
    private fun collectScreenTexts(root: AccessibilityNodeInfo): List<String> {
        val texts = ArrayList<String>()
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.add(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < 400) {
            val node = queue.removeFirst()
            visited++
            node.text?.toString()?.takeIf { it.isNotBlank() }?.let { texts.add(it) }
            node.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let { texts.add(it) }
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let { queue.add(it) }
            }
        }
        return texts
    }

    private var lastBlockedDomain: String? = null
    private var lastWebBlockTime: Long = 0L

    private fun blockWebsite(
        browserPackage: String,
        domain: String,
        reason: SiteBlocker.BlockReason,
    ) {
        val now = System.currentTimeMillis()
        val recent = lastBlockedDomain == domain &&
            now - lastWebBlockTime < 2500 &&
            BlockedAppActivity.isShowing
        if (recent) return
        lastBlockedDomain = domain
        lastWebBlockTime = now

        val msg = "$browserPackage: BLOCKED website '$domain'"
        Log.d(CAPTURE_LOG_TAG, msg)
        CaptureDebugLogger.log(this, msg)

        // Send the browser to a safe page first, so reopening it does not land
        // on the blocked site again (that caused an endless block loop).
        SafePageRedirect.leaveBlockedPage(this, browserPackage)

        try {
            val intent = Intent(this, BlockedAppActivity::class.java)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            intent.putExtra("blocked_domain", domain)
            intent.putExtra("blocked_browser", browserPackage)
            startActivity(intent)
            RestrictionLogger.recordOutcome(
                this, domain, "blocked", now, reason.source, reason.category,
            )
        } catch (_: Exception) {
            RestrictionLogger.recordOutcome(this, domain, "failed_exception", now)
        }
    }

    override fun onInterrupt() {
        // Required override.
    }

    /**
     * Attempts to read the current URL out of [currentPackage]'s address
     * bar (only does anything for the known-browser packages listed in
     * BrowserUrlExtractor) and records it via BrowsingLogger if it's a new
     * domain since the last time this ran for that package.
     *
     * Called from two different event branches in [onAccessibilityEvent]:
     * TYPE_WINDOW_STATE_CHANGED/TYPE_WINDOWS_CHANGED (switching into a
     * browser, or a new tab/window) and TYPE_WINDOW_CONTENT_CHANGED
     * (navigating to a new URL while already inside an open browser -
     * typing an address and hitting Go doesn't change the window itself,
     * so it never fires the first two on its own). An earlier version of
     * this only listened to the first two, on the reasoning that adding
     * content-changed - which fires constantly across every app - wasn't
     * worth the noise; in practice that meant capture only ever saw
     * whatever page a browser happened to already be showing at the
     * moment it became the foreground window, and silently missed every
     * navigation after that, which is a much bigger gap than the
     * originally-scoped "misses some single-page-app route changes." The
     * dedup check below (lastCapturedDomain) plus restricting the
     * content-changed branch to known-browser packages only (see that
     * branch's comment) keeps the added event volume bounded.
     */
    private fun maybeCaptureBrowserUrl(currentPackage: String) {
        if (!BrowserUrlExtractor.isKnownBrowser(currentPackage)) return

        try {
            val root = rootInActiveWindow
            if (root == null) {
                val msg = "$currentPackage: rootInActiveWindow is null, skipping"
                Log.d(CAPTURE_LOG_TAG, msg)
                CaptureDebugLogger.log(this, msg)
                return
            }

            val domain = BrowserUrlExtractor.extractDomain(root, currentPackage, this)
            if (domain == null) {
                val msg = "$currentPackage: extractDomain found nothing (address bar view " +
                    "not found, or its text wasn't URL-shaped)"
                Log.d(CAPTURE_LOG_TAG, msg)
                CaptureDebugLogger.log(this, msg)
                return
            }

            // Block BEFORE the dedup below - a still-loaded blocked page must be
            // re-blocked after the child dismisses the block screen.
            val blockReason = SiteBlocker.blockReason(this, domain)
            if (blockReason != null) {
                blockWebsite(currentPackage, domain, blockReason)
                return
            }

            if (lastCapturedDomain[currentPackage] == domain) {
                val msg = "$currentPackage: '$domain' same as last capture, skipping"
                Log.d(CAPTURE_LOG_TAG, msg)
                CaptureDebugLogger.log(this, msg)
                return
            }

            lastCapturedDomain[currentPackage] = domain
            val msg = "$currentPackage: recording visit to '$domain'"
            Log.d(CAPTURE_LOG_TAG, msg)
            CaptureDebugLogger.log(this, msg)
            BrowsingLogger.recordVisit(this, currentPackage, domain)
        } catch (e: Exception) {
            val msg = "$currentPackage: capture threw ${e.javaClass.simpleName}: ${e.message}"
            Log.d(CAPTURE_LOG_TAG, msg)
            CaptureDebugLogger.log(this, msg)
            // Best-effort capture only - never let this interfere with the
            // restricted-app blocking logic below.
        }
    }

    /**
     * True when the parent has approved a still-unexpired Emergency Access
     * request. EmergencyAccessService.syncGrantedUntilLocally (Dart side)
     * mirrors the approval's expiry timestamp from Firestore into this same
     * local key on every status update, the same "Firestore is the source
     * of truth, SharedPreferences is the native side's local mirror of it"
     * pattern getRestrictedPackages() below already uses for rules.
     */
    @Suppress("UNUSED_PARAMETER")
    private fun isEmergencyAccessActive(now: Long): Boolean =
        // F8: checked against the phone's boot clock, not the wall clock.
        GrantClock.isEmergencyActive(this)

    private fun getRestrictedPackages(): Set<String> {
        return try {
            val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            // Flutter shared_preferences adds the "flutter." prefix on Android.
            // Missing/unreadable data is not proof that the parent removed rules.
            val raw = prefs.getString("flutter.restricted_packages_json", null)
            if (raw == null) {
                // An absent key (e.g. cleared on logout) is not a corrupt
                // value. Do not retain restrictions from a previous session.
                lastValidRestrictedPackages = emptySet()
                return emptySet()
            }
            val jsonArray = JSONArray(raw)
            val result = mutableSetOf<String>()
            for (i in 0 until jsonArray.length()) {
                val pkg = jsonArray.optString(i).trim()
                if (pkg.isNotEmpty()) result.add(pkg)
            }
            // A valid "[]" from the parent intentionally clears restrictions.
            lastValidRestrictedPackages = result
            result
        } catch (error: Exception) {
            Log.w("WellScreenLimits", "Cannot read restrictions; using last valid local set", error)
            lastValidRestrictedPackages
        }
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val info = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) {
            packageName
        }
    }

    private fun openBlockedScreen(blockedPackage: String, timeLimitReached: Boolean = false) {
        val intent = Intent(this, BlockedAppActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        intent.putExtra("blocked_package", blockedPackage)
        // Non-breaking metadata. Existing BlockedAppActivity still handles
        // the block; it may later customize the message for time limits.
        if (timeLimitReached) intent.putExtra("time_limit_reached", true)
        startActivity(intent)
    }
}
