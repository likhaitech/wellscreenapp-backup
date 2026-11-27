// CASE-079 - Rule-Based Pattern Detection and Risk Level
// Random Forest model evaluated on 18,000 held-out simulated usage records.
// Code being tested: lib/services/ml_risk_classifier_service.dart
// Measured result file: ml/output/evaluation_report.txt (held-out 30%
// test split). The test also runs the app's real model on one profile of
// each level.
//
// Run: flutter test test/cases/ml_risk_classifier_service_case_079_test.dart -r expanded

import 'package:app/services/ml_risk_classifier_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'measured_results.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testCase(
    'CASE-079',
    file: 'test/cases/ml_risk_classifier_service_case_079_test.dart',
    codeTested: 'lib/services/ml_risk_classifier_service.dart',
    description:
        'Random Forest model is evaluated on 18,000 held-out simulated usage '
        'records.',
    expected:
        'Records are classified into Low, Moderate, and High Risk, with High '
        'Risk recall prioritized.',
    body: (tester) async {
      final report = measuredFile('ml/output/evaluation_report.txt');
      expect(report, contains('30% test (18000)'));
      final acc =
          RegExp(r'held-out test set: ([\d.]+)').firstMatch(report)!.group(1);
      final high = RegExp(r'High Risk\s+([\d.]+)\s+([\d.]+)')
          .firstMatch(report)!;
      final highRecall = double.parse(high.group(2)!);
      expect(highRecall, greaterThanOrEqualTo(0.9));

      // The app's real model gives all three levels.
      final service = MlRiskClassifierService();
      final labels = <String>{};
      await tester.runAsync(() async {
        for (final v in [
          [45, 120, 0, 20, 0, 0, 0],
          [180, 150, 20, 60, 1, 2, 5],
          [480, 120, 150, 240, 10, 12, 30],
        ]) {
          final r = await service.classify({
            'total_screen_time_minutes': v[0],
            'daily_limit_minutes': v[1],
            'late_night_minutes': v[2],
            'longest_session_minutes': v[3],
            'restricted_app_attempts_today': v[4],
            'rule_violations_7d': v[5],
            'frequent_app_opens_today': v[6],
          });
          labels.add(r.label);
        }
      });
      expect(labels, {'Low Risk', 'Moderate Risk', 'High Risk'});
      return 'On 18,000 held-out records: accuracy $acc, High Risk recall '
          '${high.group(2)} (the highest-priority metric); the app\'s model '
          'classified test profiles as Low, Moderate and High Risk';
    },
  );
}
