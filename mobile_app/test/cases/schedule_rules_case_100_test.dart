// CASE-100 - Rule Management and Restriction
// Run: flutter test test/cases/schedule_rules_case_100_test.dart -r expanded

import 'package:app/models/schedule_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-100',
    file: 'test/cases/schedule_rules_case_100_test.dart',
    codeTested: 'lib/models/schedule_rules.dart',
    description: 'Guardian sets the same start and end time.',
    expected: 'Bedtime is not saved; “Start and end time must be different.” is displayed.',
    body: (tester) async {
      final next = const ScheduleRules(bedtimeEnabled: true).copyWith(
        bedtimeStartMinutes: 21 * 60,
        bedtimeEndMinutes: 21 * 60,
      );
      expect(next.bedtimeError, 'Start and end time must be different.');
      expect((next.toNativeJson()['bedtime'] as Map)['enabled'], isFalse);
      expect(const ScheduleRules().bedtimeError, isNull);
      return 'Start 9:00 PM and end 9:00 PM: not saved, '
          '"${next.bedtimeError}" is shown';
    },
  );
}
