package com.wellscreen.app

import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "wellscreen/apps"
    private val limitNotificationsChannel = "wellscreen/app_limit_notifications"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ScreenTimeReportScheduler.schedule(this)
        AppTimeLimitNotifier.ensureChannel(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            limitNotificationsChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "ensureChannel" -> {
                    AppTimeLimitNotifier.ensureChannel(this)
                    result.success(true)
                }
                "showAssignedLimit" -> {
                    val appPackage = call.argument<String>("packageName")
                    val title = call.argument<String>("title")
                    val body = call.argument<String>("body")
                    if (appPackage.isNullOrBlank() || title.isNullOrBlank() || body.isNullOrBlank()) {
                        result.error("INVALID_ARGUMENT", "Missing app notification details", null)
                    } else {
                        result.success(
                            AppTimeLimitNotifier.showAssignedLimit(this, appPackage, title, body)
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> result.success(getInstalledApps())
                "getUsageAppMetadata" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    val metadata = linkedMapOf<String, Map<String, String>>()
                    // Limit the per-call MethodChannel message size. Current usage
                    // tracking can query additional batches if needed.
                    for (pkg in packages.distinct().take(300)) {
                        if (pkg.isNotBlank()) {
                            metadata[pkg] = InstalledAppMetadata.resolve(this, pkg)
                        }
                    }
                    result.success(metadata)
                }
                "openAccessibilitySettings" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "openUsageAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun getInstalledApps(): List<Map<String, String>> {
        val pm = packageManager
        val installedApps = pm.getInstalledApplications(PackageManager.GET_META_DATA)
        return installedApps
            .filter { app ->
                val hasLauncher = pm.getLaunchIntentForPackage(app.packageName) != null
                val isNotWellScreen = app.packageName != packageName
                hasLauncher && isNotWellScreen
            }
            .map { app ->
                val appName = pm.getApplicationLabel(app).toString()
                mapOf("appName" to appName, "packageName" to app.packageName)
            }
            .distinctBy { it["packageName"] }
            .sortedBy { it["appName"]?.lowercase() }
    }
}
