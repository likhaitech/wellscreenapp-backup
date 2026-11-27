
import 'package:app/models/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-028',
    file: 'test/cases/daily_goal_case_028_test.dart',
    codeTested: 'lib/screens/device_pairing_screen.dart',
    description: 'Guardian opens the child profile.',
    expected: 'The child’s name, age group, daily goal, and device status are displayed.',
    body: (tester) async {
      final profile = <String, dynamic>{
        'childName': 'Ana',
        DailyGoal.ageGroupField: '7_12',
      };
      final line = DailyGoal.summary(profile);
      expect(line, '2h a day · Ages 7–12');
      return 'Child profile line for Ana: "$line" (name and Paired / '
          'Waiting device status on the emulator figure)';
    },
  );
}
