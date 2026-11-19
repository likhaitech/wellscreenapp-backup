package com.wellscreen.app

import android.widget.ImageView
import android.graphics.drawable.GradientDrawable
import android.graphics.Typeface
import android.graphics.Color
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Block screen for manually restricted apps, blocked websites and daily limits.
 *
 * Only a DAILY LIMIT screen automatically dismisses when a refreshed local
 * allowance exceeds today's actual app usage. Other restriction paths retain
 * their existing behavior.
 */
class BlockedAppActivity : Activity() {

    companion object {
        @Volatile
        var isShowing: Boolean = false
            private set

        private const val TAG = "WellScreenLimits"
        private const val PREFS = "FlutterSharedPreferences"
        private const val LIMITS_CACHE_KEY = "flutter.app_time_limits_json"
        private const val PROFILE_KEY = "flutter.active_child_profile_id"
        private const val RESTRICTED_KEY = "flutter.restricted_packages_json"
        private const val RECHECK_INTERVAL_MS = 5_000L

        /** Which kind of screen to show; absent for app and website blocks. */
        const val EXTRA_MODE = "block_mode"

        /** U1: WellScreen's uninstall / Accessibility / Device Admin screens. */
        const val MODE_PROTECTED_SETTINGS = "protected_settings"

        /** F2: blocking is on but nobody is signed in (e.g. storage cleared). */
        const val MODE_SIGN_IN_REQUIRED = "sign_in_required"
    }

    private var isDailyTimeLimitBlock = false
    private var isWebsiteBlock = false
    private var blockedBrowser: String? = null
    private var dailyBlockedPackage: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val statusExecutor = Executors.newSingleThreadExecutor()
    private val statusCheckInProgress = AtomicBoolean(false)
    private var listeningToPrefs = false
    private var audioFocusRequest: AudioFocusRequest? = null

    private val cacheChangeListener =
        SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == LIMITS_CACHE_KEY || key == PROFILE_KEY || key == RESTRICTED_KEY) {
                checkForGrantedTime()
            }
        }

    // Also retry on a timer. Changes written by another process or a background
    // Flutter engine are not guaranteed to notify every SharedPreferences listener.
    private val recheckRunnable = object : Runnable {
        override fun run() {
            if (!isShowing || !isDailyTimeLimitBlock) return
            checkForGrantedTime()
            mainHandler.postDelayed(this, RECHECK_INTERVAL_MS)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val mode = intent.getStringExtra(EXTRA_MODE)
        val isProtectedSettings = mode == MODE_PROTECTED_SETTINGS
        val isSignInRequired = mode == MODE_SIGN_IN_REQUIRED
        val blockedDomain = if (mode == null) intent.getStringExtra("blocked_domain") else null
        blockedBrowser = intent.getStringExtra("blocked_browser")
        isWebsiteBlock = blockedDomain != null
        val blockedPackage = intent.getStringExtra("blocked_package") ?: "Restricted app"
        isDailyTimeLimitBlock = mode == null && blockedDomain == null &&
            intent.getBooleanExtra("time_limit_reached", false)
        if (isDailyTimeLimitBlock) dailyBlockedPackage = blockedPackage

        val appLabel = if (isDailyTimeLimitBlock) {
            try {
                val info = packageManager.getApplicationInfo(blockedPackage, 0)
                packageManager.getApplicationLabel(info).toString()
            } catch (_: Exception) {
                blockedPackage
            }
        } else {
            blockedPackage
        }

        // Resolve a readable name and icon for the blocked app. A blocked
        // website has neither, so it falls back to the WellScreen shield.
        var displayName = appLabel
        var appIcon: android.graphics.drawable.Drawable? = null
        if (blockedDomain == null && mode == null) {
            try {
                val info = packageManager.getApplicationInfo(blockedPackage, 0)
                displayName = packageManager.getApplicationLabel(info).toString()
                appIcon = packageManager.getApplicationIcon(info)
            } catch (_: Exception) {
                // Keep the package name as the label.
            }
        }

        val density = resources.displayMetrics.density
        fun dp(value: Int): Int = (value * density).toInt()

        val ink = Color.parseColor("#111827")
        val slate = Color.parseColor("#6B7280")
        val canvas = Color.parseColor("#FAF9F6")

        fun pill(fill: Int): GradientDrawable = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dp(999).toFloat()
            setColor(fill)
        }

        window.decorView.setBackgroundColor(canvas)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(canvas)
            setPadding(dp(24), dp(48), dp(24), dp(48))
        }

        val icon = ImageView(this).apply {
            if (appIcon != null) {
                setImageDrawable(appIcon)
            } else {
                setImageResource(android.R.drawable.ic_lock_lock)
                setColorFilter(Color.parseColor("#2563EB"))
            }
            layoutParams = LinearLayout.LayoutParams(dp(72), dp(72))
        }

        val badge = TextView(this).apply {
            text = when {
                isProtectedSettings -> "Protected"
                isSignInRequired -> "Sign in needed"
                blockedDomain != null -> "Blocked"
                isDailyTimeLimitBlock -> "Time limit reached"
                else -> "Restricted"
            }
            textSize = 12f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.parseColor("#DC2626"))
            background = pill(Color.parseColor("#FEE2E2"))
            setPadding(dp(12), dp(4), dp(12), dp(4))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(10) }
        }

        val title = TextView(this).apply {
            text = when {
                isProtectedSettings -> "Ask your guardian"
                isSignInRequired -> "Sign in to WellScreen"
                blockedDomain != null -> "Website blocked"
                else -> "$displayName is paused"
            }
            textSize = 26f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(ink)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(18) }
        }

        val message = TextView(this).apply {
            text = when {
                isSignInRequired ->
                    "This phone is protected by WellScreen. Sign in to keep " +
                        "using your apps."
                isProtectedSettings ->
                    "WellScreen's settings and the phone's date and time are " +
                        "protected while this phone is paired. To change them, " +
                        "ask your guardian for Emergency Access."
                blockedDomain != null ->
                    "$blockedDomain is blocked by WellScreen."
                isDailyTimeLimitBlock ->
                    "You've reached today's limit for this app. It will be " +
                        "available again after the next daily reset, or when " +
                        "your guardian adds time."
                else -> "Restricted by your guardian"
            }
            textSize = 15f
            setTextColor(slate)
            gravity = Gravity.CENTER
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(6) }
        }

        // White "Emergency Access" card with the request button.
        val card = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(16), dp(16), dp(16))
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(20).toFloat()
                setColor(Color.WHITE)
                setStroke(dp(1), Color.parseColor("#E5E7EB"))
            }
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ).apply { topMargin = dp(32) }
        }

        val cardTitle = TextView(this).apply {
            text = "Emergency Access"
            textSize = 16f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(ink)
        }

        val cardBody = TextView(this).apply {
            text = "Need this for something urgent? Ask your guardian to " +
                "temporarily lift the restriction."
            textSize = 13f
            setTextColor(slate)
            setPadding(0, dp(6), 0, dp(14))
        }

        val requestButton = TextView(this).apply {
            text = "Request Temporary Access"
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = pill(ink)
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(48),
            )
            // Requests are sent from the WellScreen chat, so open the app.
            setOnClickListener {
                val launch = packageManager.getLaunchIntentForPackage(packageName)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                }
                finish()
            }
        }

        card.addView(cardTitle)
        card.addView(cardBody)
        card.addView(requestButton)

        val backButton = TextView(this).apply {
            text = when {
                blockedDomain != null -> "Go to Google"
                else -> "Go Home"
            }
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(ink)
            gravity = Gravity.CENTER
            background = pill(Color.parseColor("#F1F5F9"))
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(48),
            ).apply { topMargin = dp(12) }
            setOnClickListener {
                when {
                    blockedDomain != null -> leaveToSafePage()
                    // Every app block goes home. finish() used to reveal the
                    // still-running restricted app for up to 5 seconds.
                    else -> returnToHome()
                }
            }
        }

        val openAppButton = TextView(this).apply {
            text = "Open WellScreen"
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
            background = pill(ink)
            isClickable = true
            isFocusable = true
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                dp(48),
            ).apply { topMargin = dp(32) }
            setOnClickListener {
                val launch = packageManager.getLaunchIntentForPackage(packageName)
                if (launch != null) {
                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launch)
                }
                finish()
            }
        }

        root.addView(icon)
        root.addView(badge)
        root.addView(title)
        root.addView(message)
        // No "request access" for blocked websites: they are harmful-category
        // or guardian-blocked sites, and time requests are for apps only.
        // Signing in needs WellScreen itself, not a request to the guardian.
        if (isSignInRequired) {
            root.addView(openAppButton)
        } else if (blockedDomain == null) {
            root.addView(card)
        }
        root.addView(backButton)
        setContentView(root)
    }

    override fun onStart() {
        super.onStart()
        isShowing = true
        pauseOtherAudio()
        if (isDailyTimeLimitBlock) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .registerOnSharedPreferenceChangeListener(cacheChangeListener)
            listeningToPrefs = true
            mainHandler.removeCallbacks(recheckRunnable)
            mainHandler.post(recheckRunnable)
        }
    }

    override fun onStop() {
        isShowing = false
        mainHandler.removeCallbacks(recheckRunnable)
        if (listeningToPrefs) {
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .unregisterOnSharedPreferenceChangeListener(cacheChangeListener)
            listeningToPrefs = false
        }
        super.onStop()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(recheckRunnable)
        statusExecutor.shutdownNow()
        releaseAudioFocus()
        super.onDestroy()
    }

    /**
     * Take audio focus so music or video from the blocked app (or one playing
     * behind it) stops instead of continuing under the block screen.
     */
    private fun pauseOtherAudio() {
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = audioFocusRequest ?: AudioFocusRequest.Builder(
                    AudioManager.AUDIOFOCUS_GAIN
                ).setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                ).setOnAudioFocusChangeListener { }.build()
                audioFocusRequest = request
                audio.requestAudioFocus(request)
            } else {
                @Suppress("DEPRECATION")
                audio.requestAudioFocus(
                    null,
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN,
                )
            }
        } catch (error: Exception) {
            Log.w(TAG, "Could not pause other audio", error)
        }
    }

    private fun releaseAudioFocus() {
        try {
            val audio = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { audio.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                audio.abandonAudioFocus(null)
            }
        } catch (_: Exception) {
            // Nothing else to release.
        }
    }

    private fun checkForGrantedTime() {
        val target = dailyBlockedPackage ?: return
        if (!isDailyTimeLimitBlock || !isShowing || isFinishing || isDestroyed) return
        if (!statusCheckInProgress.compareAndSet(false, true)) return

        // UsageStatsManager queries may scan today's events. Never run these
        // queries repeatedly on the main/UI thread.
        try {
            statusExecutor.execute {
                val allowanceIsAvailable = try {
                    !isManuallyRestricted(target) &&
                        (AppTimeLimitEnforcer.getStatus(applicationContext, target)
                            ?.remainingMilliseconds ?: 0L) > 0L
                } catch (error: Exception) {
                    Log.w(TAG, "Failed to recheck added allowance", error)
                    false
                }

                mainHandler.post {
                    statusCheckInProgress.set(false)
                    if (allowanceIsAvailable && isShowing && !isFinishing && !isDestroyed &&
                        dailyBlockedPackage == target
                    ) {
                        // The original target app may still be underneath this
                        // Activity. Finishing reveals it, now with a valid limit.
                        Log.d(TAG, "New allowance available; closing daily limit screen")
                        finish()
                    }
                }
            }
        } catch (error: RuntimeException) {
            statusCheckInProgress.set(false)
            Log.w(TAG, "Could not schedule allowance check", error)
        }
    }

    private fun isManuallyRestricted(targetPackage: String): Boolean {
        return try {
            val raw = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(RESTRICTED_KEY, "[]") ?: "[]"
            val array = JSONArray(raw)
            (0 until array.length()).any { array.optString(it) == targetPackage }
        } catch (_: Exception) {
            // An unreadable restriction cache is not proof that an app is safe.
            true
        }
    }

    /**
     * Website blocks: open a safe page in the same browser, so the blocked
     * page is no longer what the browser shows. Going home or back instead
     * left the blocked page open, and the child was blocked again every time
     * the browser came back (an endless loop). Started from this visible
     * screen, so Android always allows it.
     */
    private fun leaveToSafePage() {
        val browser = blockedBrowser
        if (browser.isNullOrBlank()) {
            returnToHome()
            return
        }
        try {
            startActivity(SafePageRedirect.intentFor(this, browser))
            finish()
        } catch (_: Exception) {
            returnToHome()
        }
    }

    private fun returnToHome() {
        val homeIntent = Intent(Intent.ACTION_MAIN)
            .addCategory(Intent.CATEGORY_HOME)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(homeIntent)
        finish()
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (isWebsiteBlock) {
            leaveToSafePage()
        } else {
            // Back must never return to the blocked app underneath.
            returnToHome()
        }
    }
}
