// INT-010 - Rule Management and Restriction Module -> Usage Monitoring Module
// Guardian changes the child's daily screen-time goal.
// Code being tested: lib/models/daily_goal.dart,
// lib/services/daily_screen_time_limit_service.dart,
// lib/services/screen_time_goal_service.dart,
// lib/services/monitoring_usage_alert_service.dart
//
// Run: flutter test test/integration_cases/int_010_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/services/daily_screen_time_limit_service.dart';
import 'package:app/services/monitoring_usage_alert_service.dart';
import 'package:app/services/screen_time_goal_service.dart';
import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cases/case_report.dart';
import '../cases/usage_fixtures.dart';

void main() {
  testCase(
    'INT-010',
    file: 'test/integration_cases/int_010_test.dart',
    codeTested: 'lib/models/daily_goal.dart -> '
        'daily_screen_time_limit_service.dart + '
        'monitoring_usage_alert_service.dart',
    description: 'Guardian changes the child’s daily screen-time goal '
        '(Rule Management -> Usage Monitoring).',
    expected: 'The child device shows the new goal and usage alerts follow '
        'the new goal.',
    body: (tester) async {
      SharedPreferences.setMockInitialValues({});

      final profile = <String, dynamic>{DailyGoal.ageGroupField: '7_12'};
      expect(DailyGoal.minutesFor(profile), 120);
      profile[DailyGoal.minutesField] = DailyGoal.clampMinutes(150);
      final goal = DailyGoal.durationFor(profile);
      expect(goal, const Duration(minutes: 150));

      await DailyScreenTimeLimitService().saveDailyLimit(goal);
      expect(DailyGoal.activeGoal, const Duration(minutes: 150));
      final home = ScreenTimeGoalService().evaluate(
        report: UsageReportService().generateFromSummaries(UsageTrackingService()
            .summarizeUsage({'com.google.android.youtube': 130 * 60000})),
        dailyLimit: goal,
      );
      expect(home.remainingDuration.inMinutes, 20);

      bool goalAlert(int usedMinutes) =>
          MonitoringUsageAlertService.buildEvents(
            report: quietReport(),
            appSummaries: [app('YouTube', Duration(minutes: usedMinutes))],
            now: DateTime(2026, 11, 22, 15),
          ).any((e) => e['eventId'] == 'usage150m_20261122');

      expect(goalAlert(130), isFalse); // past the old 2h goal, no alert
      expect(goalAlert(155), isTrue); // past the new 2h 30m goal
      return 'The goal changed from 2h to 2h 30m: the child phone saved it '
          '(20 min left at 2h 10m of use) and the goal alert came at 2h 30m, '
          'not at the old 2h';
    },
  );
}
