package com.wellscreen.app

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class WellScreenDeviceAdminReceiver : DeviceAdminReceiver() {

    override fun onDisableRequested(
        context: Context,
        intent: Intent
    ): CharSequence {
        return "Disabling WellScreen removes its uninstall protection. Please discuss this with your parent or guardian before continuing."
    }
}