import 'package:app/services/daily_usage_history.dart';
import 'package:app/services/weekly_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const min = 60000;
  final now = DateTime(2026, 11, 28, 15);
  String key(int daysAgo) =>
      DailyUsageHistory.dayKey(DateTime(2026, 11, 28 - daysAgo));

  test('week total, average, days over goal, busiest and lightest day', () {
    final totals = {
      key(0): 60 * min,
      key(1): 200 * min,
      key(2): 30 * min,
      key(3): 150 * min,
    };
    final week = WeeklySummary.from(
      totals: totals,
      goal: const Duration(minutes: 135),
      now: now,
    );
    expect(week.total, const Duration(minutes: 440));
    expect(week.daysWithData, 4);
    expect(week.dailyAverage, const Duration(minutes: 110));
    expect(week.daysOverGoal, 2);
    expect(week.busiest!.value, const Duration(minutes: 200));
    expect(week.lightest!.value, const Duration(minutes: 30));
  });

  test('compares the week with the 30-day average', () {
    final totals = {
      for (var i = 1; i <= 20; i++) key(i): 100 * min,
      key(0): 100 * min,
    };
    final week = WeeklySummary.from(
      totals: totals,
      goal: const Duration(minutes: 135),
      now: now,
    );
    expect(week.usualAverage, const Duration(minutes: 100));
    expect(week.percentVsUsual, 0);
  });

  test('no readings means no averages', () {
    final week = WeeklySummary.from(
      totals: const {},
      goal: const Duration(minutes: 135),
      now: now,
    );
    expect(week.daysWithData, 0);
    expect(week.dailyAverage, isNull);
    expect(week.busiest, isNull);
    expect(week.topApps, isEmpty);
  });

  test('top apps: sorted, at most five, share of the week', () {
    final apps = WeeklySummary.parseTopApps([
      {'packageName': 'a', 'displayName': 'A', 'usageDurationMs': 10 * min},
      {'packageName': 'b', 'displayName': 'B', 'usageDurationMs': 30 * min},
      {'packageName': 'bad', 'usageDurationMs': -1},
      {'packageName': 'c', 'usageDurationMs': 20 * min},
      {'packageName': 'd', 'displayName': 'D', 'usageDurationMs': 5 * min},
      {'packageName': 'e', 'displayName': 'E', 'usageDurationMs': 4 * min},
      {'packageName': 'f', 'displayName': 'F', 'usageDurationMs': 1 * min},
    ], 100 * min);
    expect(apps.map((a) => a.packageName), ['b', 'c', 'a', 'd', 'e']);
    expect(apps.first.share, closeTo(0.30, 0.001));
    expect(apps[1].name, 'c');
  });
}
