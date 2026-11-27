// INT-013 - Dashboard, Reports, and Recommendations Module -> Rule-Based Pattern Detection and Risk Level Module
// Generate a usage report.
// Code being tested: lib/services/pattern_detection_service.dart,
// lib/services/ml_risk_classifier_service.dart,
// lib/services/intervention_recommendation_service.dart,
// lib/services/report_export_service.dart
//
// Run: flutter test test/integration_cases/int_013_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:app/models/usage_report.dart';
import 'package:app/services/intervention_recommendation_service.dart';
import 'package:app/services/ml_risk_classifier_service.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:app/services/report_export_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../cases/case_report.dart';
import '../cases/usage_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testCase(
    'INT-013',
    file: 'test/integration_cases/int_013_test.dart',
    codeTested: 'lib/services/report_export_service.dart <- '
        'pattern_detection_service.dart + ml_risk_classifier_service.dart',
    description: 'Generate a usage report '
        '(Dashboard, Reports, and Recommendations -> Rule-Based Pattern '
        'Detection and Risk Level).',
    expected: 'The report shows the usage summary, risk level, and digital '
        'wellness recommendations.',
    body: (tester) async {
      DailyGoal.activeGoal = const Duration(hours: 2);


      final apps = [
        app('YouTube', const Duration(minutes: 40),
            lastUsed: DateTime(2026, 11, 22, 23, 15)),
      ];
      final report = PatternDetectionService().generateReport(apps);
      expect(report.patternStatus, UsagePatternStatus.unhealthy);
      late MlRiskAssessment risk;
      await tester.runAsync(() async {
        risk = await MlRiskClassifierService().classify({
          'total_screen_time_minutes': report.totalUsageDuration.inMinutes,
          'daily_limit_minutes': 120,
          'late_night_minutes': 40,
          'longest_session_minutes': 40,
          'restricted_app_attempts_today': 0,
          'rule_violations_7d': 0,
          'frequent_app_opens_today': 0,
        });
      });
      expect(['Low Risk', 'Moderate Risk', 'High Risk'], contains(risk.label));

      // Module 1 - Reports: recommendation and the exported report.
      final tip = InterventionRecommendationService().getRecommendation(report);
      expect(tip.title, 'Bedtime Restriction Recommended');
      final data = <String, dynamic>{
        'name': 'Ana',
        'latestUsageReport': {
          'totalUsageDurationMs': report.totalUsageDuration.inMilliseconds,
          'patternStatus': report.patternStatus.name,
          'recommendationMessage': tip.message,
        },
        'mlRiskAssessment': {
          'label': risk.label,
          'confidence': risk.confidence,
        },
      };
      final pdf =
          ReportExportService.buildReport(data, DateTime(2026, 11, 22, 23, 30));
      final bytes = await tester.runAsync(() => pdf.save());
      expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
      return 'The report for Ana has the usage summary '
          '(${report.totalUsageDuration.inMinutes} min, status '
          '${report.patternStatus.name}), risk level "${risk.label}" from the '
          'AI assistant, and the recommendation "${tip.title}" '
          '(PDF ${(bytes.length / 1024).toStringAsFixed(1)} KB)';
    },
  );
}
