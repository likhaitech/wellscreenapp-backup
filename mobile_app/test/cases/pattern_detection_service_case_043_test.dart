// CASE-043 - Rule-Based Pattern Detection and Risk Level
// Guardian opens Reports after usage is synced.
// Code being tested: lib/services/pattern_detection_service.dart (the
// report the Reports screen displays: risk level + detected pattern).
//
// Run: flutter test test/cases/pattern_detection_service_case_043_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'usage_fixtures.dart';

void main() {
  testCase(
    'CASE-043',
    file: 'test/cases/pattern_detection_service_case_043_test.dart',
    codeTested: 'lib/services/pattern_detection_service.dart',
    description: 'Guardian opens Reports after usage is synced.',
    expected: 'The risk level and detected patterns are displayed.',
    body: (tester) async {
      DailyGoal.activeGoal = const Duration(hours: 2);
      final service = PatternDetectionService();
      final healthy = service.generateReport([
        app('Khan Academy', const Duration(minutes: 40)),
      ]);
      final warning = service.generateReport([
        app('YouTube', const Duration(hours: 1, minutes: 30)),
        app('Roblox', const Duration(minutes: 40)),
      ]);
      final unhealthy = service.generateReport([
        app('TikTok', const Duration(hours: 4)),
      ]);
      expect(healthy.patternStatus, UsagePatternStatus.healthy);
      expect(warning.patternStatus, UsagePatternStatus.warning);
      expect(unhealthy.patternStatus, UsagePatternStatus.unhealthy);
      for (final r in [healthy, warning, unhealthy]) {
        expect(r.recommendationMessage, isNotEmpty);
        expect(r.totalUsageLabel, isNotEmpty);
      }
      return 'Synced usage produced the level and pattern shown in Reports: '
          'healthy ("${healthy.recommendationMessage}"), warning '
          '("${warning.recommendationMessage}") and unhealthy '
          '("${unhealthy.recommendationMessage}")';
    },
  );
}
