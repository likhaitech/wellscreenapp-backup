// CASE-076 - Rule-Based Pattern Detection and Risk Level
// Gambling website-name AI on 6,447 held-out real gambling domains at 0.90.
// Code being tested: lib/services/site_category_ml_classifier.dart
// Measured result file: ml/site_category/output/category_classifier_evaluation.txt
// (from train_category_classifier.py on the held-out test split).
//
// Run: flutter test test/cases/site_category_ml_classifier_case_076_test.dart -r expanded

import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'measured_results.dart';

void main() {
  testCase(
    'CASE-076',
    file: 'test/cases/site_category_ml_classifier_case_076_test.dart',
    codeTested: 'lib/services/site_category_ml_classifier.dart',
    description:
        'Gambling website-name AI is run on 6,447 held-out real gambling '
        'domains at 0.90 confidence.',
    expected: 'Most real gambling domains are flagged.',
    body: (tester) async {
      final txt = measuredFile(
          'ml/site_category/output/category_classifier_evaluation.txt');
      final m = RegExp(r'gambling: (\d+)/(\d+) caught at confidence >= 0\.9 '
              r'\(([\d.]+)% recall')
          .firstMatch(txt)!;
      final caught = int.parse(m.group(1)!);
      final total = int.parse(m.group(2)!);
      expect(total, 6447);
      expect(caught, greaterThan(total ~/ 2));
      return 'Measured: $caught of $total held-out gambling domains were '
          'flagged at confidence 0.90 or higher (${m.group(3)}% recall)';
    },
  );
}
