import 'daily_usage_history.dart';

/// One app in the week's top list (from the child's sync,
/// latestUsageReport.weeklyTopApps).
class WeeklyApp {
  const WeeklyApp({
    required this.packageName,
    required this.name,
    required this.duration,
    required this.share,
  });

  final String packageName;
  final String name;
  final Duration duration;

  /// Part of the week's app time, 0 to 1.
  final double share;
}

/// The guardian's "This week" summary: the last 7 days ending today.
/// Pure, so it can be unit tested; ParentDashboardScreen shows it.
class WeeklySummary {
  const WeeklySummary({
    required this.days,
    required this.total,
    required this.daysWithData,
    required this.dailyAverage,
    required this.daysOverGoal,
    required this.busiest,
    required this.lightest,
    required this.usualAverage,
    required this.percentVsUsual,
    required this.topApps,
  });

  final List<MapEntry<DateTime, Duration?>> days;
  final Duration total;
  final int daysWithData;
  final Duration? dailyAverage;
  final int daysOverGoal;
  final MapEntry<DateTime, Duration>? busiest;
  final MapEntry<DateTime, Duration>? lightest;

  /// 30-day average of completed days, and this week's average compared
  /// with it in percent (+18 = 18% above). Null without enough data.
  final Duration? usualAverage;
  final int? percentVsUsual;
  final List<WeeklyApp> topApps;

  static WeeklySummary from({
    required Map<String, int> totals,
    required Duration goal,
    required DateTime now,
    Object? weeklyTopApps,
    Object? weeklyAppsTotalMs,
  }) {
    final days = DailyUsageHistory.lastSevenDays(totals, now);
    var totalMs = 0;
    var withData = 0;
    var overGoal = 0;
    MapEntry<DateTime, Duration>? busiest;
    MapEntry<DateTime, Duration>? lightest;
    for (final day in days) {
      final value = day.value;
      if (value == null) continue;
      withData++;
      totalMs += value.inMilliseconds;
      if (goal > Duration.zero && value > goal) overGoal++;
      if (busiest == null || value > busiest.value) {
        busiest = MapEntry(day.key, value);
      }
      if (lightest == null || value < lightest.value) {
        lightest = MapEntry(day.key, value);
      }
    }
    final average = withData == 0
        ? null
        : Duration(milliseconds: totalMs ~/ withData);
    final usual = DailyUsageHistory.averageOfCompletedDays(totals, now)?.average;
    int? percent;
    if (average != null && usual != null && usual > Duration.zero) {
      percent = ((average.inMilliseconds - usual.inMilliseconds) * 100 /
              usual.inMilliseconds)
          .round();
    }
    return WeeklySummary(
      days: days,
      total: Duration(milliseconds: totalMs),
      daysWithData: withData,
      dailyAverage: average,
      daysOverGoal: overGoal,
      busiest: busiest,
      lightest: withData > 1 ? lightest : null,
      usualAverage: usual,
      percentVsUsual: percent,
      topApps: parseTopApps(weeklyTopApps, weeklyAppsTotalMs),
    );
  }

  /// Reads the child's weekly top apps. Bad entries are skipped.
  static List<WeeklyApp> parseTopApps(Object? raw, Object? totalMs) {
    if (raw is! List) return const [];
    final entries = <({String pkg, String name, int ms})>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final pkg = (item['packageName'] ?? '').toString();
      final ms = item['usageDurationMs'];
      if (pkg.isEmpty || ms is! num || ms <= 0) continue;
      final name = (item['displayName'] ?? '').toString();
      entries.add((pkg: pkg, name: name.isEmpty ? pkg : name, ms: ms.toInt()));
    }
    entries.sort((a, b) => b.ms.compareTo(a.ms));
    final listed = entries.fold<int>(0, (sum, e) => sum + e.ms);
    final whole = totalMs is num && totalMs >= listed ? totalMs.toInt() : listed;
    return [
      for (final e in entries.take(5))
        WeeklyApp(
          packageName: e.pkg,
          name: e.name,
          duration: Duration(milliseconds: e.ms),
          share: whole == 0 ? 0 : e.ms / whole,
        ),
    ];
  }
}
