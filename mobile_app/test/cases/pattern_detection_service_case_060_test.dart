// CASE-060 - Rule-Based Pattern Detection and Risk Level
// Child uses the phone between 10:00 PM and 5:00 AM.
// Code being tested: lib/services/pattern_detection_service.dart
//
// Run: flutter test test/cases/pattern_detection_service_case_060_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/monitoring_usage_alert_service.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'usage_fixtures.dart';

void main() {
  testCase(
    'CASE-060',
    file: 'test/cases/pattern_detection_service_case_060_test.dart',
    codeTested: 'lib/services/pattern_detection_service.dart',
    description: 'Child uses the phone between 10:00 PM and 5:00 AM.',
    expected:
        'Late-night use is detected and shown as a detected pattern in '
        'Reports.',
    body: (tester) async {
      DailyGoal.activeGoal = const Duration(hours: 2);
      final lateUse = DateTime(2026, 11, 22, 23, 15);
      final apps = [
        app('YouTube', const Duration(minutes: 30), lastUsed: lateUse),
      ];
      final report = PatternDetectionService().generateReport(apps);
      expect(report.patternStatus, UsagePatternStatus.unhealthy);
      expect(report.recommendationMessage,
          startsWith('Late-night phone usage was detected'));
      final events = MonitoringUsageAlertService.buildEvents(
        report: report,
        appSummaries: apps,
        now: DateTime(2026, 11, 22, 23, 30),
      );
      expect(typesOf(events), contains('late_night_usage'));
      return 'Use at 11:15 PM was detected as a late-night pattern '
          '(status unhealthy: "${report.recommendationMessage}") and a '
          'late-night alert was created';
    },
  );
}
