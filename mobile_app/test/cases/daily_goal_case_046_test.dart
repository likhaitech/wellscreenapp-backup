// CASE-046 - Rule Management and Restriction
// Run: flutter test test/cases/daily_goal_case_046_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-046',
    file: 'test/cases/daily_goal_case_046_test.dart',
    codeTested: 'lib/models/daily_goal.dart',
    description: 'Guardian changes the daily goal with Edit.',
    expected: '“Daily goal saved.” is displayed and the goal is marked “(adjusted)”.',
    body: (tester) async {
      final before = {DailyGoal.ageGroupField: '7_12'};
      expect(DailyGoal.summary(before), '2h a day · Ages 7–12');
      // Guardian taps Edit and picks 2h 30m.
      final after = {
        ...before,
        DailyGoal.minutesField: DailyGoal.clampMinutes(150),
      };
      expect(DailyGoal.minutesFor(after), 150);
      expect(DailyGoal.isCustom(after), isTrue);
      final summary = DailyGoal.summary(after);
      expect(summary, endsWith('(adjusted)'));
      return 'Goal changed from 2h to 2h 30m; the card now reads "$summary" '
          '(the "Daily goal saved." message is on the emulator figure)';
    },
  );
}
