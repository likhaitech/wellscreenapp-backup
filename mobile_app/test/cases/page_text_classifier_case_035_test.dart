// CASE-035 - Rule-Based Pattern Detection and Risk Level
// Page-word check on 197 normal and 39 education, health and news pages.
// Code being tested: android/.../PageTextClassifier.kt
// Measured result file: ml/site_category/PAGE_TEXT_RESULTS.md (the same
// Kotlin code was run on the real pages on 21 Nov 2026; the page text
// stays on the laptop for privacy, so this case reads the measured table).
//
// Run: flutter test test/cases/page_text_classifier_case_035_test.dart -r expanded

import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'measured_results.dart';

void main() {
  testCase(
    'CASE-035',
    file: 'test/cases/page_text_classifier_case_035_test.dart',
    codeTested: 'android/app/src/main/kotlin/com/wellscreen/app/PageTextClassifier.kt',
    description:
        'Page-word check is run on 197 normal pages and 39 education, '
        'health, and news pages.',
    expected: 'No normal or education, health, and news page is blocked.',
    body: (tester) async {
      final md = measuredFile('ml/site_category/PAGE_TEXT_RESULTS.md');
      final normal = RegExp(r'\| Normal \(197\) \| \*\*(\d+)\*\*')
          .allMatches(md)
          .last;
      final edu = RegExp(
              r'\| Education / health / news \(39\) \| \*\*(\d+)\*\*')
          .allMatches(md)
          .last;
      expect(normal.group(1), '0');
      expect(edu.group(1), '0');
      return 'Measured with the app\'s page-word check: 0 of 197 normal pages '
          'and 0 of 39 education, health and news pages were blocked';
    },
  );
}
