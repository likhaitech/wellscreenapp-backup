// CASE-058 - Rule-Based Pattern Detection and Risk Level
// Child's screen time reaches the daily goal.
// Code being tested: lib/services/monitoring_usage_alert_service.dart
// (buildEvents: the usage alerts sent to the guardian).
//
// Run: flutter test test/cases/monitoring_usage_alert_service_case_058_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/services/monitoring_usage_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'usage_fixtures.dart';

void main() {
  testCase(
    'CASE-058',
    file: 'test/cases/monitoring_usage_alert_service_case_058_test.dart',
    codeTested: 'lib/services/monitoring_usage_alert_service.dart',
    description: 'Child’s screen time reaches the daily goal.',
    expected:
        'Child sees “You reached your daily goal”; guardian receives '
        'a usage alert; the phone is not locked.',
    body: (tester) async {
      DailyGoal.activeGoal = const Duration(hours: 2); // age 7-12 goal
      final now = DateTime(2026, 11, 22, 16, 0);
      final events = MonitoringUsageAlertService.buildEvents(
        report: quietReport(),
        appSummaries: [
          app('YouTube', const Duration(hours: 1, minutes: 10)),
          app('Roblox', const Duration(minutes: 50)),
        ],
        now: now,
      );
      final types = typesOf(events);
      expect(types, contains('usage_warning_threshold'));
      expect(types, isNot(contains('usage_high_threshold')));
      final alert =
          events.firstWhere((e) => e['type'] == 'usage_warning_threshold');
      // The daily goal only alerts - no event locks or blocks the phone.
      expect(types.where((t) => t.contains('lock') || t.contains('block')),
          isEmpty);
      return '2 hours of use reached the 2-hour daily goal: the guardian\'s '
          'usage alert "${alert['label']}" (${alert['eventId']}) was created '
          'and nothing locks the phone';
    },
  );
}
