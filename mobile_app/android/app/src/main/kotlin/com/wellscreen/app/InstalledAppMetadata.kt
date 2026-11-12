package com.wellscreen.app

import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Base64
import java.io.ByteArrayOutputStream

/** Never guess app names from package fragments: query the installed Android package. */
internal object InstalledAppMetadata {
    private const val ICON_SIZE_PX = 40

    fun resolve(context: Context, pkg: String, includeIcon: Boolean = true): Map<String, String> {
        val pm = context.packageManager
        val appInfo = try {
            pm.getApplicationInfo(pkg, 0)
        } catch (_: PackageManager.NameNotFoundException) {
            // If the app was uninstalled, retain its package identity instead
            // of fabricating a familiar brand name from its package suffix.
            return mapOf("displayName" to pkg)
        }

        val launcherLabel = try {
            val launchIntent = pm.getLaunchIntentForPackage(pkg)
            val component = launchIntent?.resolveActivity(pm)
            component?.let { pm.getActivityInfo(it, 0).loadLabel(pm).toString() }
        } catch (_: Exception) {
            null
        }
        val applicationLabel = try {
            appInfo.loadLabel(pm)?.toString()
        } catch (_: Exception) {
            null
        }
        val label = listOf(launcherLabel, applicationLabel)
            .firstOrNull { !it.isNullOrBlank() }?.trim() ?: pkg

        if (!includeIcon) return mapOf("displayName" to label)

        val icon = try {
            val drawable = appInfo.loadIcon(pm)
            val bitmap = Bitmap.createBitmap(ICON_SIZE_PX, ICON_SIZE_PX, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, ICON_SIZE_PX, ICON_SIZE_PX)
            drawable.draw(Canvas(bitmap))
            val bytes = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes)
            bitmap.recycle()
            Base64.encodeToString(bytes.toByteArray(), Base64.NO_WRAP)
        } catch (_: Exception) {
            null
        }
        return if (icon.isNullOrEmpty()) {
            mapOf("displayName" to label)
        } else {
            mapOf("displayName" to label, "iconBase64" to icon)
        }
    }
}
