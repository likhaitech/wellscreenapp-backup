package com.wellscreen.app

import java.util.Locale

/**
 * Recognises the system screens a child could use to switch WellScreen off
 * or remove it: WellScreen's App info (Uninstall, Force stop, Clear storage),
 * the uninstall dialog, WellScreen's Accessibility page and the Device Admin
 * "Deactivate" page, plus the Date & time page. While the phone is paired, the Accessibility service
 * covers these screens with a "Ask your guardian" screen.
 *
 * Screens needed during setup stay open: the Accessibility list, Usage
 * access, battery optimisation and the Device Admin "Activate" page.
 * Pure (no Android types) for unit tests.
 */
internal object ProtectedSettingsGuard {

    /** Apps that show Settings pages or the uninstall dialog. */
    val SETTINGS_PACKAGES: Set<String> = setOf(
        "com.android.settings",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.samsung.android.packageinstaller",
        "com.miui.securitycenter",
        "com.coloros.safecenter",
        "com.oplus.safecenter",
    )

    private const val DEVICE_ADMIN_LABEL = "wellscreen uninstall protection"

    private val dangerWords = listOf(
        "uninstall",
        "force stop",
        "clear storage",
        "clear data",
        "deactivate",
        "use wellscreen",
        "wellscreen shortcut",
    )

    /**
     * @param texts every text and content description on the screen.
     * @param appLabel WellScreen's app name ("WellScreen").
     * @param accessibilityDescription WellScreen's accessibility description,
     *   shown only on WellScreen's own Accessibility page.
     */
    private val dateTimeTitles = listOf("date & time", "date and time")
    private val dateTimeControls = listOf(
        "set time automatically",
        "set date",
        "set time",
        "automatic date",
        "use network-provided time",
        "network-provided time",
        "time zone",
    )

    /**
     * Android's Date & time page. Changing the date or time zone would reset
     * "today" for daily app limits, so it is covered while paired. The
     * System list (which only shows a "Date & time" row and the zone name)
     * stays open.
     */
    fun isDateTimeScreen(texts: List<String>): Boolean {
        val lower = texts.map { it.lowercase(Locale.ROOT) }
        val hasTitle = lower.any { text -> dateTimeTitles.any { text.contains(it) } }
        val hasControl = lower.any { text -> dateTimeControls.any { text.contains(it) } }
        return hasTitle && hasControl
    }

    fun isProtectedScreen(
        texts: List<String>,
        appLabel: String,
        accessibilityDescription: String,
    ): Boolean {
        if (isDateTimeScreen(texts)) return true
        val lower = texts.map { it.lowercase(Locale.ROOT) }
        val description = accessibilityDescription.lowercase(Locale.ROOT).take(60)
        if (description.length >= 20 && lower.any { it.contains(description) }) return true

        val label = appLabel.lowercase(Locale.ROOT)
        if (label.isBlank() || lower.none { it.contains(label) }) return false

        // The Device Admin name contains "Uninstall"; it is not a danger word.
        val cleaned = lower.map { it.replace(DEVICE_ADMIN_LABEL, "") }

        // Turning Device Admin ON (setup checklist) must stay possible.
        val isActivationPage =
            cleaned.any { it.contains("activate this device admin") } &&
                cleaned.none { it.contains("deactivate") }
        if (isActivationPage) return false

        return cleaned.any { text -> dangerWords.any { text.contains(it) } }
    }
}
