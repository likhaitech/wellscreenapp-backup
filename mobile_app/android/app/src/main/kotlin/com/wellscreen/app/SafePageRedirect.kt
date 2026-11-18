package com.wellscreen.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Browser

/**
 * Moves the browser off a blocked website before the block screen appears.
 *
 * Without this, the blocked page stayed open in the browser tab: every time
 * the child reopened the browser it landed on the same page and was blocked
 * again, so they could never get back to normal browsing.
 *
 * The safe page opens in one reused tab (EXTRA_APPLICATION_ID = WellScreen),
 * so repeated blocks do not pile up new tabs. The blocked site is still
 * blocked if it is opened again.
 */
object SafePageRedirect {
    const val SAFE_PAGE_URL = "https://www.google.com/"

    fun intentFor(context: Context, browserPackage: String): Intent =
        Intent(Intent.ACTION_VIEW, Uri.parse(SAFE_PAGE_URL)).apply {
            setPackage(browserPackage)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra(Browser.EXTRA_APPLICATION_ID, context.packageName)
        }

    /** Best effort: blocking must still happen even if this fails. */
    fun leaveBlockedPage(context: Context, browserPackage: String) {
        try {
            context.startActivity(intentFor(context, browserPackage))
        } catch (_: Exception) {
            // Browser could not open the safe page; the block screen still shows.
        }
    }
}
