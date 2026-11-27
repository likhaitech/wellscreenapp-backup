// CASE-055 - Usage Monitoring
// Run: flutter test test/cases/daily_usage_history_case_055_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/services/daily_usage_history.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-055',
    file: 'test/cases/daily_usage_history_case_055_test.dart',
    codeTested: 'lib/services/daily_usage_history.dart',
    description: 'Guardian opens the weekly chart.',
    expected: 'The last seven days are shown with the daily goal line and the 30-day average.',
    body: (tester) async {
      final now = DateTime(2026, 11, 22, 18);
      const h = 3600000;
      final totals = <String, int>{
        for (var i = 0; i < 10; i++)
          DailyUsageHistory.dayKey(now.subtract(Duration(days: i))): (i % 3 + 1) * h,
      };
      final week = DailyUsageHistory.lastSevenDays(totals, now);
      expect(week.length, 7);
      expect(week.last.key, DateTime(2026, 11, 22));
      final avg = DailyUsageHistory.averageOfCompletedDays(totals, now)!;
      expect(avg.daysCounted, 9);
      final goal = DailyGoal.minutesFor({DailyGoal.ageGroupField: '7_12'});
      return '7 bars from Nov 16 to Nov 22, goal line at ${goal ~/ 60}h, '
          '30-day average ${avg.average.inMinutes} min over ${avg.daysCounted} '
          'completed days';
    },
  );
}
