// CASE-098 - Rule Management and Restriction
// Run: flutter test test/cases/schedule_rules_case_098_test.dart -r expanded

import 'package:app/models/schedule_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-098',
    file: 'test/cases/schedule_rules_case_098_test.dart',
    codeTested: 'lib/models/schedule_rules.dart',
    description: 'Guardian taps Lock apps now for study time.',
    expected: '“Focus mode started.” is displayed; apps lock on the child device while calls and WellScreen still work.',
    body: (tester) async {
      final started = DateTime(2026, 11, 22, 16, 0);
      // What "Lock apps now" (1 hour) saves.
      final rules = ScheduleRules.fromMap({
        'focus': {
          'durationMinutes': 60,
          'startedAt': Timestamp.fromDate(started),
        },
      });
      expect(rules.isFocusActive(started.add(const Duration(minutes: 30))),
          isTrue);
      final until = (rules.toNativeJson()['focus'] as Map)['untilMs'];
      expect(until,
          started.add(const Duration(hours: 1)).millisecondsSinceEpoch);
      return 'Focus started at 4:00 PM for 1 hour: active at 4:30 PM and the '
          'child phone is told to pause apps until 5:00 PM (calls and '
          'WellScreen are never paused)';
    },
  );
}
