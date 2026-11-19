import 'package:app/models/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('age group defaults (manuscript Ch. III)', () {
    test('6 and below is 1 hour, 7-12 is 2 hours, 13-15 is 3 hours', () {
      expect(DailyGoal.minutesFor({'ageGroup': '6_and_below'}), 60);
      expect(DailyGoal.minutesFor({'ageGroup': '7_12'}), 120);
      expect(DailyGoal.minutesFor({'ageGroup': '13_15'}), 180);
    });

    test('no age group or an unknown value falls back to 3 hours', () {
      expect(DailyGoal.minutesFor(null), 180);
      expect(DailyGoal.minutesFor({}), 180);
      expect(DailyGoal.minutesFor({'ageGroup': 'adult'}), 180);
    });
  });

  group('guardian adjustment', () {
    test('a valid dailyGoalMinutes overrides the age default', () {
      final profile = {'ageGroup': '7_12', 'dailyGoalMinutes': 150};
      expect(DailyGoal.minutesFor(profile), 150);
      expect(DailyGoal.isCustom(profile), isTrue);
      expect(DailyGoal.summary(profile), '2h 30m a day · Ages 7–12 (adjusted)');
    });

    test('override equal to the default is not marked adjusted', () {
      final profile = {'ageGroup': '6_and_below', 'dailyGoalMinutes': 60};
      expect(DailyGoal.isCustom(profile), isFalse);
      expect(DailyGoal.summary(profile), '1h a day · Ages 6 and below');
    });

    test('out-of-range or wrong-type overrides are ignored', () {
      expect(DailyGoal.minutesFor({'ageGroup': '7_12', 'dailyGoalMinutes': 5}), 120);
      expect(DailyGoal.minutesFor({'ageGroup': '7_12', 'dailyGoalMinutes': 2000}), 120);
      expect(DailyGoal.minutesFor({'ageGroup': '7_12', 'dailyGoalMinutes': '90'}), 120);
    });

    test('choosing an age group resets the goal to its default', () {
      expect(DailyGoal.ageGroupUpdate(ChildAgeGroup.upTo6),
          {'ageGroup': '6_and_below', 'dailyGoalMinutes': 60});
    });

    test('clampMinutes keeps 15-minute steps inside 15 min - 12 h', () {
      expect(DailyGoal.clampMinutes(0), 15);
      expect(DailyGoal.clampMinutes(97), 90);
      expect(DailyGoal.clampMinutes(5000), 720);
    });
  });

  test('labels', () {
    expect(DailyGoal.label(45), '45m');
    expect(DailyGoal.label(120), '2h');
    expect(DailyGoal.longLabel(60), '1 hour');
    expect(DailyGoal.longLabel(150), '2 hours 30 minutes');
    expect(DailyGoal.summary({}), '3h a day · Age group not set');
  });
}
