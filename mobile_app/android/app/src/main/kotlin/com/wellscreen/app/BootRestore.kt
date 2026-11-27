package com.wellscreen.app

/** Which system broadcasts make WellScreen restart usage reporting. */
internal object BootRestore {
    const val BOOT_COMPLETED = "android.intent.action.BOOT_COMPLETED"

    fun shouldRestoreReporting(action: String?): Boolean = action == BOOT_COMPLETED
}
