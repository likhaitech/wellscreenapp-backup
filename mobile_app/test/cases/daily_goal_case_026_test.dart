// CASE-026 - Profile Management
// Run: flutter test test/cases/daily_goal_case_026_test.dart -r expanded

import 'package:app/models/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-026',
    file: 'test/cases/daily_goal_case_026_test.dart',
    codeTested: 'lib/models/daily_goal.dart',
    description: 'Guardian selects age group 7–12 and generates a code.',
    expected: 'The child profile is created with a recommended daily goal of 2 hours.',
    body: (tester) async {
      final profile = DailyGoal.ageGroupUpdate(ChildAgeGroup.age7to12);
      expect(profile[DailyGoal.ageGroupField], '7_12');
      expect(DailyGoal.minutesFor(profile), 120);
      return 'Age group 7–12 saves ageGroup "7_12" and a daily goal of '
          '${DailyGoal.longLabel(DailyGoal.minutesFor(profile))}';
    },
  );
}
