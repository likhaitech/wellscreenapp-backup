// CASE-080 - Rule-Based Pattern Detection and Risk Level
// Guardian opens Reports on a paired child with synced usage.
// Code being tested: lib/services/ml_risk_classifier_service.dart - the
// AI Risk Assessment card in Reports shows this model's level next to the
// rule-based result from PatternDetectionService.
//
// Run: flutter test test/cases/ml_risk_classifier_service_case_080_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/ml_risk_classifier_service.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'usage_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testCase(
    'CASE-080',
    file: 'test/cases/ml_risk_classifier_service_case_080_test.dart',
    codeTested: 'lib/services/ml_risk_classifier_service.dart',
    description: 'Guardian opens Reports on a paired child with synced usage.',
    expected:
        'AI Risk Assessment shows the model’s risk level beside the '
        'rule-based result.',
    body: (tester) async {
      // A heavy day: 8 hours, late-night use, many blocked attempts.
      DailyGoal.activeGoal = const Duration(hours: 2);
      final rule = PatternDetectionService().generateReport([
        app('TikTok', const Duration(hours: 8),
            lastUsed: DateTime(2026, 11, 22, 23, 30)),
      ]);
      expect(rule.patternStatus, UsagePatternStatus.unhealthy);

      late MlRiskAssessment ai;
      await tester.runAsync(() async {
        ai = await MlRiskClassifierService().classify({
          'total_screen_time_minutes': 480,
          'daily_limit_minutes': 120,
          'late_night_minutes': 150,
          'longest_session_minutes': 240,
          'restricted_app_attempts_today': 10,
          'rule_violations_7d': 12,
          'frequent_app_opens_today': 30,
        });
      });
      expect(ai.label, 'High Risk');
      return 'The AI model gave "${ai.label}" '
          '(${(ai.confidence * 100).round()}% confidence), shown beside the '
          'rule-based result "${rule.patternStatus.name}"';
    },
  );
}
