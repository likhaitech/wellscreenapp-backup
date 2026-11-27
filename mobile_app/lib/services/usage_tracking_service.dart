import 'package:usage_stats/usage_stats.dart';

import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import 'local_usage_report_cache_service.dart';
import 'usage_report_service.dart';

typedef UsageEventRecord = ({
  String packageName,
  int eventType,
  int timestampMs,
});

class UsageTrackingService {
  /// WellScreen's own package (android applicationId).
  static const String ownPackage = 'com.wellscreen.app';

  UsageTrackingService({
    UsageReportService? usageReportService,
    LocalUsageReportCacheService? localUsageReportCacheService,
  }) : _usageReportService = usageReportService ?? UsageReportService(),
       _localUsageReportCacheService =
           localUsageReportCacheService ?? LocalUsageReportCacheService();

  final UsageReportService _usageReportService;
  final LocalUsageReportCacheService _localUsageReportCacheService;
  static const int _activityResumedEventType = 1;

  Future<bool> hasUsagePermission() async =>
      await UsageStats.checkUsagePermission() == true;

  Future<void> openUsageAccessSettings() async {
    await UsageStats.grantUsagePermission();
  }

  /// Today's foreground time per package, plus the time each package was
  /// last used. The last-used time is needed by late-night detection
  /// (10 PM to 5 AM); without it AppUsageSummary.lastTimeUsed stays null
  /// and late-night use can never be detected.
  Future<({Map<String, int> ms, Map<String, DateTime> lastUsed})>
      _queryToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final usageMap = await UsageStats.queryAndAggregateUsageStats(
      startOfDay,
      now,
    );
    final ms = <String, int>{};
    final lastUsed = <String, DateTime>{};
    for (final entry in usageMap.entries) {
      ms[entry.key] =
          int.tryParse(entry.value.totalTimeInForeground ?? '0') ?? 0;
      final lastMs = int.tryParse(entry.value.lastTimeUsed ?? '');
      // Keep only real timestamps from today; Android reports 0 or an older
      // time for packages that were not used in this range.
      if (lastMs != null && lastMs > 0) {
        final last = DateTime.fromMillisecondsSinceEpoch(lastMs);
        if (!last.isBefore(startOfDay) && !last.isAfter(now)) {
          lastUsed[entry.key] = last;
        }
      }
    }
    return (ms: ms, lastUsed: lastUsed);
  }

  Future<Map<String, int>> _queryTodayMilliseconds() async =>
      (await _queryToday()).ms;

  /// Preserves the existing capped summary used by dashboards/ML.
  Future<List<AppUsageSummary>> getTodayUsage() async {
    final today = await _queryToday();
    return summarizeUsage(today.ms, lastUsed: today.lastUsed);
  }

  /// No top-10 cap: use this for the guardian's All Apps page and future
  /// per-app enforcement calculations, not getTodayUsage().
  Future<List<AppUsageSummary>> getAllTodayUsage() async {
    final today = await _queryToday();
    return summarizeAllUsage(today.ms, lastUsed: today.lastUsed);
  }

  /// Pure helper to allow tests without the Android usage_stats plugin.
  List<AppUsageSummary> summarizeUsage(
    Map<String, int> usage, {
    Map<String, DateTime> lastUsed = const {},
  }) =>
      summarizeAllUsage(usage, lastUsed: lastUsed).take(10).toList();

  List<AppUsageSummary> summarizeAllUsage(
    Map<String, int> usage, {
    Map<String, DateTime> lastUsed = const {},
  }) {
    final summaries = <AppUsageSummary>[];
    for (final entry in usage.entries) {
      if (entry.value <= 0) continue;
      // WellScreen's own screens are not counted as screen time, the same
      // as the background report (ScreenTimeReportJobService.kt), so the
      // child and the guardian see the same total.
      if (entry.key == ownPackage) continue;
      summaries.add(
        AppUsageSummary(
          packageName: entry.key,
          displayName: _makeReadableAppName(entry.key),
          usageDuration: Duration(milliseconds: entry.value),
          lastTimeUsed: lastUsed[entry.key],
        ),
      );
    }
    summaries.sort((a, b) => b.usageDuration.compareTo(a.usageDuration));
    return summaries;
  }

  Future<int> getTodayUsageMillisecondsForPackage(String packageName) async {
    final usage = await _queryTodayMilliseconds();
    final ms = usage[packageName] ?? 0;
    return ms < 0 ? 0 : ms;
  }

  Future<int> getTodayMaxAppOpenCount() async =>
      countMaxAppOpens(await _queryTodayEvents());

  Future<List<UsageEventRecord>> _queryTodayEvents() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final events = await UsageStats.queryEvents(startOfDay, now);
    return <UsageEventRecord>[
      for (final event in events)
        (
          packageName: event.packageName ?? '',
          eventType: event.eventTypeValue ?? -1,
          timestampMs: int.tryParse(event.timeStamp ?? '') ?? 0,
        ),
    ];
  }

  /// How many times each app was opened today (for the guardian's All Apps).
  Future<Map<String, int>> getTodayOpenCounts() async =>
      countOpensByPackage(await _queryTodayEvents());

  /// Opens per app: each switch into an app counts once; staying in the
  /// same app (screen changes inside it) does not.
  Map<String, int> countOpensByPackage(List<UsageEventRecord> events) {
    final sorted = [...events]
      ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    final opensByPackage = <String, int>{};
    String? lastResumedPackage;
    for (final event in sorted) {
      if (event.eventType != _activityResumedEventType) continue;
      if (event.packageName.isEmpty) continue;
      if (event.packageName != lastResumedPackage) {
        opensByPackage[event.packageName] =
            (opensByPackage[event.packageName] ?? 0) + 1;
      }
      lastResumedPackage = event.packageName;
    }
    return opensByPackage;
  }

  int countMaxAppOpens(List<UsageEventRecord> events) {
    final opensByPackage = countOpensByPackage(events);
    if (opensByPackage.isEmpty) return 0;
    return opensByPackage.values.reduce((a, b) => a > b ? a : b);
  }

  Future<UsageReport> getTodayUsageReport() async {
    // All apps, not only the top ten, so the total matches the background
    // report the guardian sees.
    final summaries = await getAllTodayUsage();
    final report = _usageReportService.generateFromSummaries(summaries);
    await _localUsageReportCacheService.saveTodayReport(report);
    return report;
  }

  Future<UsageReport?> getCachedTodayUsageReport() =>
      _localUsageReportCacheService.getCachedTodayReport();

  Future<Map<String, dynamic>?> getCachedTodayUsageReportData() =>
      _localUsageReportCacheService.getCachedTodayReportData();

  String _makeReadableAppName(String packageName) {
    final parts = packageName.split('.');
    if (parts.isEmpty) return packageName;
    final appName = parts.last;
    if (appName.isEmpty) return packageName;
    return appName[0].toUpperCase() + appName.substring(1);
  }
}
