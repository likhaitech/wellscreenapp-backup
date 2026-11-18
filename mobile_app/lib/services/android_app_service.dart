import 'package:flutter/services.dart';

import '../models/installed_app_info.dart';

class AndroidAppService {
  static const MethodChannel _channel = MethodChannel('wellscreen/apps');

  Future<List<InstalledAppInfo>> getInstalledApps() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );

      if (result == null) {
        return [];
      }

      final apps = result
          .map(
            (item) => InstalledAppInfo.fromMap(
          item as Map<dynamic, dynamic>,
        ),
      )
          .where(
            (app) =>
        app.appName.trim().isNotEmpty &&
            app.packageName.trim().isNotEmpty,
      )
          .toList();

      apps.sort(
            (a, b) => a.appName.toLowerCase().compareTo(
          b.appName.toLowerCase(),
        ),
      );

      return apps;
    } catch (_) {
      return [];
    }
  }

  /// Whether WellScreen's Accessibility service is switched on. Returns
  /// null when it cannot be read (e.g. not on Android), so callers can
  /// show "unknown" instead of guessing.
  Future<bool?> isAccessibilityServiceEnabled() async {
    try {
      return await _channel.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }

  Future<void> openUsageAccessSettings() async {
    await _channel.invokeMethod('openUsageAccessSettings');
  }
}