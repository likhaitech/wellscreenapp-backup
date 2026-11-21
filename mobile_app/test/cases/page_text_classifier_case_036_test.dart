// CASE-036 - Rule-Based Pattern Detection and Risk Level
// Page-word check on 76 real gambling pages and 93 real adult pages.
// Code being tested: android/.../PageTextClassifier.kt
// Measured result file: ml/site_category/PAGE_TEXT_RESULTS.md
//
// Run: flutter test test/cases/page_text_classifier_case_036_test.dart -r expanded

import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';
import 'measured_results.dart';

void main() {
  testCase(
    'CASE-036',
    file: 'test/cases/page_text_classifier_case_036_test.dart',
    codeTested: 'android/app/src/main/kotlin/com/wellscreen/app/PageTextClassifier.kt',
    description:
        'Page-word check is run on 76 real gambling pages and 93 real adult '
        'pages.',
    expected: 'Most real gambling and adult pages are blocked.',
    body: (tester) async {
      final md = measuredFile('ml/site_category/PAGE_TEXT_RESULTS.md');
      // The latest result table (after the 21 Nov updates).
      final gambling = int.parse(
          RegExp(r'\| Gambling, real pages \(76\) \| (\d+)')
              .allMatches(md)
              .last
              .group(1)!);
      final adult = int.parse(RegExp(r'\| Adult, real pages \(93\) \| (\d+)')
          .allMatches(md)
          .last
          .group(1)!);
      expect(gambling, greaterThan(76 ~/ 2));
      expect(adult, greaterThan(93 ~/ 2));
      String pct(int n, int of) => '${(n * 100 / of).round()}%';
      return 'Measured: $gambling of 76 gambling pages (${pct(gambling, 76)}) '
          'and $adult of 93 adult pages (${pct(adult, 93)}) were blocked';
    },
  );
}
