// CASE-085 - Rule Management and Restriction
// Run: flutter test test/cases/daily_goal_case_085_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-085',
    file: 'test/cases/daily_goal_case_085_test.dart',
    codeTested: 'lib/models/daily_goal.dart',
    description: 'Guardian taps Use recommended.',
    expected: 'The goal returns to the age-group default (1 h, 2 h, or 3 h).',
    body: (tester) async {
      final results = <String>[];
      for (final group in ChildAgeGroup.values) {
        final adjusted = {
          DailyGoal.ageGroupField: group.id,
          DailyGoal.minutesField: 300,
        };
        // Use recommended writes the age-group default back.
        final reset = {...adjusted, ...DailyGoal.ageGroupUpdate(group)};
        expect(DailyGoal.minutesFor(reset), group.defaultMinutes);
        expect(DailyGoal.isCustom(reset), isFalse);
        results.add('Ages ${group.label} -> '
            '${DailyGoal.label(DailyGoal.minutesFor(reset))}');
      }
      expect(results, ['Ages 6 and below -> 1h', 'Ages 7–12 -> 2h',
          'Ages 13–15 -> 3h']);
      return 'From an adjusted 5h goal, Use recommended gives: '
          '${results.join(', ')}';
    },
  );
}
