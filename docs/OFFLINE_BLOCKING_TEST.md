# Verify offline restrictions before changing native code

## What the supplied Kotlin source currently does

- `WellScreenAccessibilityService.checkRestrictedApp()` uses local
  `flutter.restricted_packages_json` in `FlutterSharedPreferences`, not an
  online Firebase request, to decide permanent restrictions.
- `AppTimeLimitEnforcer.isLimitReached()` reads locally persisted
  `flutter.app_time_limits_json` and Android UsageStats.
- The Accessibility Service must stay enabled for blocking to work.
- The rules and limits **must first have reached the child while online**.
  New parent changes cannot arrive while the child has no internet.

## Two-phone offline test

1. On parent phone, restrict a harmless test app and set a short limit on
   another app. Keep both devices online until the child confirms that the
   rule and limit have synced.
2. On child phone, open both apps while online. Confirm permanent restriction
   blocks immediately and the time-limited app blocks at its threshold.
3. Turn off **Wi-Fi and mobile data**, but leave WellScreen's Accessibility
   and Usage Access permissions enabled. Do not force-stop or uninstall it.
4. Try opening the permanently restricted app again. It should still show
   BlockedAppActivity while offline.
5. For the app with a daily time limit, verify that it remains blocked once
   its cached limit is exceeded. The daily limit resets at local midnight.
6. Reconnect and confirm parent changes sync again without losing blocking.

## Android logs and permissions

From `mobile_app` in Windows PowerShell:

```powershell
adb devices
adb shell appops get com.wellscreen.app GET_USAGE_STATS
adb logcat -s WellScreenLimits:V WellScreenBackground:V WellScreenSecurity:V
```

To check whether the *existing* restricted-package cache is present on a
**debuggable** build, inspect the relevant shared_preferences entry locally.
Do **not** upload the whole SharedPreferences XML: it may contain phone
numbers, credentials, and other private data.

If the offline block fails, request the child's current complete files:

- `android/app/src/main/kotlin/com/wellscreen/app/WellScreenAccessibilityService.kt`
- `android/app/src/main/kotlin/com/wellscreen/app/AppTimeLimitEnforcer.kt`
- `android/app/src/main/kotlin/com/wellscreen/app/BlockedAppActivity.kt`
- `lib/services/app_rules_service.dart`
- `lib/services/app_time_limit_service.dart`

Do **not** overwrite your current AccessibilityService with an older patch
before inspecting it. Failure could be a missing cache, disabled Accessibility
Service, an emergency-access bypass, or an absent Usage Access permission.
