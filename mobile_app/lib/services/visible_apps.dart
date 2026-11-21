import '../models/app_usage_summary.dart';

/// System parts of Android (home screen, settings, permission pop-ups) are
/// not "apps the child used" and are hidden from Top Apps Today.
bool isSystemPackage(String packageName) {
  final package = packageName.toLowerCase();
  return package.contains('launcher') ||
      package.contains('permissioncontroller') ||
      package.contains('systemui') ||
      package.contains('packageinstaller') ||
      package.endsWith('.settings');
}

/// Apps to show the child, most used first, with system parts removed.
List<AppUsageSummary> visibleUserApps(List<AppUsageSummary> apps) =>
    apps.where((app) => !isSystemPackage(app.packageName)).toList();

/// True when the newest usage report is from an earlier day than [now], so
/// the guardian is asked to have the child device sync usage today.
bool isUsageReportStale(DateTime? recordedAt, DateTime now) =>
    recordedAt != null &&
    (recordedAt.year != now.year ||
        recordedAt.month != now.month ||
        recordedAt.day != now.day);

const String syncUsageTodayMessage = 'Ask the child device to sync usage today.';
