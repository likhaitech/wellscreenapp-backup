// INT-005 - Usage Monitoring Module -> Rule-Based Pattern Detection and Risk Level Module
// Send recorded screen time and app usage.
// Code being tested: lib/services/usage_tracking_service.dart,
// lib/services/pattern_detection_service.dart,
// lib/services/ml_risk_classifier_service.dart
//
// Run: flutter test test/integration_cases/int_005_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/ml_risk_classifier_service.dart';
import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cases/case_report.dart';

/// The same seven inputs the child home screen gives the AI assistant
/// (child_home_screen.dart), with screen time taken from the usage report.
Map<String, num> features(UsageReport report, List<int> rest) => {
      'total_screen_time_minutes': report.totalUsageDuration.inMinutes,
      'daily_limit_minutes': rest[0],
      'late_night_minutes': rest[1],
      'longest_session_minutes': rest[2],
      'restricted_app_attempts_today': rest[3],
      'rule_violations_7d': rest[4],
      'frequent_app_opens_today': rest[5],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testCase(
    'INT-005',
    file: 'test/integration_cases/int_005_test.dart',
    codeTested: 'lib/services/usage_tracking_service.dart -> '
        'pattern_detection_service.dart + ml_risk_classifier_service.dart',
    description: 'Send recorded screen time and app usage '
        '(Usage Monitoring -> Rule-Based Pattern Detection and Risk Level).',
    expected: 'Usage indicators are evaluated and the child’s risk level is '
        'classified as Low, Moderate, or High Risk.',
    body: (tester) async {
      DailyGoal.activeGoal = const Duration(hours: 2);
      const minute = 60000;

      // Module 1 - Usage Monitoring: two days of recorded usage.
      final light = UsageReportService().generateFromSummaries(
        UsageTrackingService()
            .summarizeUsage({'com.google.android.youtube': 45 * minute}),
      );
      final heavy = UsageReportService().generateFromSummaries(
        UsageTrackingService().summarizeUsage({
          'com.google.android.youtube': 240 * minute,
          'com.roblox.client': 240 * minute,
        }),
      );
      expect(light.totalUsageDuration.inMinutes, 45);
      expect(heavy.totalUsageDuration.inMinutes, 480);

      // Module 2 - Pattern detection (rules) and the AI assistant.
      expect(light.patternStatus, UsagePatternStatus.healthy);
      expect(heavy.patternStatus, UsagePatternStatus.unhealthy);
      final service = MlRiskClassifierService();
      late MlRiskAssessment low;
      late MlRiskAssessment high;
      await tester.runAsync(() async {
        low = await service.classify(features(light, [120, 0, 20, 0, 0, 0]));
        high = await service
            .classify(features(heavy, [120, 150, 240, 10, 12, 30]));
      });
      expect(low.label, 'Low Risk');
      expect(high.label, 'High Risk');
      return 'A 45-minute day was evaluated as healthy and Low Risk; an '
          '8-hour day with late-night use and blocked attempts as unhealthy '
          'and High Risk';
    },
  );
}
