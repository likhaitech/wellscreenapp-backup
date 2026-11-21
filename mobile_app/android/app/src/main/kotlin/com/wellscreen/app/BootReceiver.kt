package com.wellscreen.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (!BootRestore.shouldRestoreReporting(intent.action)) return

        Log.i(TAG, "Device boot completed; restoring screen-time reporting job")

        ScreenTimeReportScheduler.schedule(context.applicationContext)
    }

    companion object {
        private const val TAG = "WellScreenBoot"
    }
}