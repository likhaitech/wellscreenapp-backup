// CASE-135 - Dashboard, Reports, and Recommendations
// Run: flutter test test/cases/intervention_recommendation_service_case_135_test.dart -r expanded

import 'package:app/models/usage_report.dart';
import 'package:app/services/intervention_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-135',
    file: 'test/cases/intervention_recommendation_service_case_135_test.dart',
    codeTested: 'lib/services/intervention_recommendation_service.dart',
    description: 'Guardian opens Reports after an unhealthy pattern is detected.',
    expected: 'A recommendation that matches the detected pattern is displayed.',
    body: (tester) async {
      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 6),
        topUsedApp: null,
        unhealthyAppCount: 1,
        generatedAt: DateTime(2026, 11, 22, 23),
        patternStatus: UsagePatternStatus.unhealthy,
        recommendationMessage: 'Late-night usage was detected.',
      );
      final tip = InterventionRecommendationService().getRecommendation(report);
      expect(tip.title, 'Bedtime Restriction Recommended');
      return 'Late-night unhealthy pattern -> "${tip.title}": ${tip.message}';
    },
  );
}
