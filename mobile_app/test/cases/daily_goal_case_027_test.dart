// CASE-027 - Profile Management
// Run: flutter test test/cases/daily_goal_case_027_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-027',
    file: 'test/cases/daily_goal_case_027_test.dart',
    codeTested: 'lib/models/daily_goal.dart',
    description: 'Guardian selects age group 6 and below and generates a code.',
    expected: 'The child profile is created with a recommended daily goal of 1 hour.',
    body: (tester) async {
      final profile = DailyGoal.ageGroupUpdate(ChildAgeGroup.upTo6);
      expect(profile[DailyGoal.ageGroupField], '6_and_below');
      expect(DailyGoal.minutesFor(profile), 60);
      return 'Age group 6 and below saves a daily goal of '
          '${DailyGoal.longLabel(DailyGoal.minutesFor(profile))}';
    },
  );
}
