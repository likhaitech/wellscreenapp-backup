package com.wellscreen.app

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** Set by the block screen so the app opens straight to a request. */
        const val EXTRA_ACTION = "wellscreen_action"
        const val ACTION_EMERGENCY_REQUEST = "emergency_request"

        @Volatile
        private var pendingAction: String? = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        rememberAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        rememberAction(intent)
    }

    private fun rememberAction(intent: Intent?) {
        val action = intent?.getStringExtra(EXTRA_ACTION) ?: return
        pendingAction = action
        intent.removeExtra(EXTRA_ACTION)
    }

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
                // Read once: the Dart side opens the matching screen.
                "takeLaunchAction" -> {
                    val action = pendingAction
                    pendingAction = null
                    result.success(action)
                }
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
                "isAccessibilityServiceEnabled" ->
                    result.success(isWellScreenAccessibilityEnabled())
                "openUsageAccessSettings" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val power = getSystemService(Context.POWER_SERVICE) as? PowerManager
                    result.success(power?.isIgnoringBatteryOptimizations(packageName))
                }
                "openBatteryOptimizationSettings" -> {
                    // One-tap "Let WellScreen always run in background?"
                    // dialog first. The general battery list is only a
                    // fallback: on newer Android, reaching "Allow background
                    // usage" from it goes through WellScreen's App info,
                    // which the protected-settings guard covers while paired.
                    val direct = Intent(
                        Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    var opened = false
                    for (intent in listOf(direct, list)) {
                        try {
                            startActivity(intent)
                            opened = true
                            break
                        } catch (_: Exception) {
                            // Try the next screen.
                        }
                    }
                    result.success(opened)
                }
                "isDeviceAdminActive" -> {
                    val policy = getSystemService(Context.DEVICE_POLICY_SERVICE)
                        as? DevicePolicyManager
                    val admin = ComponentName(this, WellScreenDeviceAdminReceiver::class.java)
                    result.success(policy?.isAdminActive(admin))
                }
                "requestDeviceAdmin" -> {
                    try {
                        val admin = ComponentName(this, WellScreenDeviceAdminReceiver::class.java)
                        val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                            .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                            .putExtra(
                                DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                "Lets WellScreen warn your guardian before it " +
                                    "can be removed from this phone.",
                            )
                        startActivity(intent)
                        result.success(true)
                    } catch (_: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * True when WellScreen's AccessibilityService is switched on in Android
     * settings. All app and website blocking runs inside that service, so
     * the guardian is told when it is off.
     */
    private fun isWellScreenAccessibilityEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val full = ComponentName(this, WellScreenAccessibilityService::class.java)
        val names = setOf(
            full.flattenToString().lowercase(),
            full.flattenToShortString().lowercase(),
        )
        return enabled.split(':').any { it.trim().lowercase() in names }
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
