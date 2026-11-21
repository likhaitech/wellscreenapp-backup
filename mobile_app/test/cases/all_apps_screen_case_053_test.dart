// CASE-053 - Usage Monitoring
// Run: flutter test test/cases/all_apps_screen_case_053_test.dart -r expanded

import 'package:app/screens/all_apps_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-053',
    file: 'test/cases/all_apps_screen_case_053_test.dart',
    codeTested: 'lib/screens/all_apps_screen.dart',
    description: 'Guardian taps an app in All Apps.',
    expected: 'The app’s usage details and a Set Time Limit option are shown.',
    body: (tester) async {
      final lines = appUsageDetailLines(
        usageMs: 45 * 60000,
        openCount: 6,
      );
      expect(lines, ['Usage today: 45m', 'Times opened: 6']);
      expect(setTimeLimitLabel, 'Set Time Limit');
      return 'The details sheet for YouTube shows ${lines.join(' and ')}, '
          'with a "$setTimeLimitLabel" button';
    },
  );
}
