package com.wellscreen.app

/**
 * The SMS backup alert's rules, kept pure for unit tests. The text goes to
 * the guardian's verified number, which Flutter stores on the child phone,
 * and needs no internet (it is sent over the mobile network).
 */
internal object SmsBackupAlert {
    fun restrictedAppMessage(appLabel: String): String =
        "WellScreen alert: \"$appLabel\" was opened and blocked on your child's device."

    /** Send only with a number, the SMS permission, and once per app per day. */
    fun shouldSend(phoneNumber: String?, hasPermission: Boolean, onCooldown: Boolean): Boolean =
        !phoneNumber.isNullOrBlank() && hasPermission && !onCooldown
}

/** Alerts the child phone sends when protection is switched off. */
internal object ProtectionAlertText {
    const val DEVICE_ADMIN_TITLE = "WellScreen uninstall protection disabled"
    const val DEVICE_ADMIN_BODY = "Device Admin protection has been disabled on your child's device."
}
