// CASE-059 - Rule-Based Pattern Detection and Risk Level
// Child's screen time reaches two hours past the daily goal.
// Code being tested: lib/services/monitoring_usage_alert_service.dart
//
// Run: flutter test test/cases/monitoring_usage_alert_service_case_059_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/services/monitoring_usage_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'usage_fixtures.dart';

void main() {
  testCase(
    'CASE-059',
    file: 'test/cases/monitoring_usage_alert_service_case_059_test.dart',
    codeTested: 'lib/services/monitoring_usage_alert_service.dart',
    description:
        'Child’s screen time reaches two hours past the daily goal.',
    expected: 'Guardian receives a second usage alert.',
    body: (tester) async {
      DailyGoal.activeGoal = const Duration(hours: 2);
      final events = MonitoringUsageAlertService.buildEvents(
        report: quietReport(),
        appSummaries: [
          app('YouTube', const Duration(hours: 1, minutes: 20)),
          app('Roblox', const Duration(hours: 1, minutes: 20)),
          app('TikTok', const Duration(hours: 1, minutes: 20)),
        ],
        now: DateTime(2026, 11, 22, 20, 0),
      );
      final types = typesOf(events);
      expect(types, contains('usage_warning_threshold'));
      expect(types, contains('usage_high_threshold'));
      final second =
          events.firstWhere((e) => e['type'] == 'usage_high_threshold');
      return '4 hours of use (goal 2 h + 2 h): a second usage alert '
          '"${second['label']}" (${second['eventId']}) was created for the '
          'guardian';
    },
  );
}
