// CASE-023 - Rule-Based Pattern Detection and Risk Level
// Child uses one app for a long continuous session.
// Code being tested: lib/services/pattern_detection_service.dart
//
// Run: flutter test test/cases/pattern_detection_service_case_023_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/monitoring_usage_alert_service.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'usage_fixtures.dart';

void main() {
  testCase(
    'CASE-023',
    file: 'test/cases/pattern_detection_service_case_023_test.dart',
    codeTested: 'lib/services/pattern_detection_service.dart',
    description: 'Child uses one app for a long continuous session.',
    expected: 'The prolonged session is detected and shown as a usage warning.',
    body: (tester) async {
      DailyGoal.activeGoal = const Duration(hours: 3);
      final apps = [
        app('Roblox', const Duration(hours: 1, minutes: 45),
            lastUsed: DateTime(2026, 11, 22, 16, 0)),
      ];
      final report = PatternDetectionService().generateReport(apps);
      expect(report.patternStatus, UsagePatternStatus.warning);
      expect(report.recommendationMessage,
          'Roblox was used for a long session. A short break is recommended.');
      final events = MonitoringUsageAlertService.buildEvents(
        report: report,
        appSummaries: apps,
        now: DateTime(2026, 11, 22, 16, 5),
      );
      expect(typesOf(events), contains('app_usage_warning_threshold'));
      return 'A 1 h 45 min Roblox session was detected (status warning: '
          '"${report.recommendationMessage}") and an app usage warning was '
          'created';
    },
  );
}
