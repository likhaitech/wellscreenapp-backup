package com.wellscreen.app

/**
 * What the restriction screen (BlockedAppActivity) shows: the badge, the
 * title and which button is offered. Pure so it can be unit tested.
 */
internal object BlockScreenText {
    enum class Action { SIGN_IN, REQUEST_TEMPORARY_ACCESS, ASK_PARENT, NONE }

    /** No "Ask my parent" option for adult sites. */
    fun canAskToAllow(category: String?): Boolean = category != "adult"

    fun badge(
        isProtectedSettings: Boolean,
        isSignInRequired: Boolean,
        scheduleReason: String?,
        blockedDomain: String?,
        isDailyTimeLimitBlock: Boolean,
    ): String = when {
        isProtectedSettings -> "Protected"
        isSignInRequired -> "Sign in needed"
        scheduleReason == "bedtime" -> "Bedtime"
        scheduleReason == "break" -> "Break time"
        scheduleReason != null -> "Focus time"
        blockedDomain != null -> "Blocked"
        isDailyTimeLimitBlock -> "Time limit reached"
        else -> "Restricted"
    }

    fun title(
        isProtectedSettings: Boolean,
        isSignInRequired: Boolean,
        scheduleReason: String?,
        blockedDomain: String?,
        displayName: String,
    ): String = when {
        isProtectedSettings -> "Ask your guardian"
        isSignInRequired -> "Sign in to WellScreen"
        scheduleReason == "bedtime" -> "Time to rest"
        scheduleReason == "break" -> "Take a break"
        scheduleReason != null -> "Focus time"
        blockedDomain != null -> "Website blocked"
        else -> "$displayName is paused"
    }

    /** Which button the screen offers. */
    fun action(isSignInRequired: Boolean, blockedDomain: String?, category: String?): Action = when {
        isSignInRequired -> Action.SIGN_IN
        blockedDomain == null -> Action.REQUEST_TEMPORARY_ACCESS
        canAskToAllow(category) -> Action.ASK_PARENT
        else -> Action.NONE
    }

    const val REQUEST_BUTTON = "Request Temporary Access"
}
