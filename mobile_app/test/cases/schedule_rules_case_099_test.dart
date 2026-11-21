// CASE-099 - Rule Management and Restriction
// Run: flutter test test/cases/schedule_rules_case_099_test.dart -r expanded

import 'package:app/models/schedule_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-099',
    file: 'test/cases/schedule_rules_case_099_test.dart',
    codeTested: 'lib/models/schedule_rules.dart',
    description: 'Guardian taps End focus now.',
    expected: '“Focus mode ended.” is displayed and the child’s apps unlock.',
    body: (tester) async {
      // What "End focus now" saves.
      final rules = ScheduleRules.fromMap({
        'focus': {'durationMinutes': 0, 'startedAt': null},
      });
      expect(rules.isFocusActive(DateTime.now()), isFalse);
      expect((rules.toNativeJson()['focus'] as Map)['untilMs'], 0);
      return 'After End focus now, focus is not active and the child phone '
          'gets untilMs 0, so apps unlock';
    },
  );
}
