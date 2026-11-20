import 'package:app/models/daily_goal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AgeGroupRules.apply(null));

  test('manuscript values until the admin rules load', () {
    AgeGroupRules.apply(null);
    expect(ChildAgeGroup.upTo6.defaultMinutes, 60);
    expect(ChildAgeGroup.age7to12.defaultMinutes, 120);
    expect(ChildAgeGroup.age13to15.defaultMinutes, 180);
    expect(ChildAgeGroup.upTo6.blocksRiskySites, isTrue);
    expect(ChildAgeGroup.age7to12.blocksRiskySites, isFalse);
  });

  test('admin rules from a system patch are used', () {
    AgeGroupRules.apply({
      'goal_minutes_7_12': 90,
      'risky_sites_13_15': 'block',
    });
    expect(ChildAgeGroup.age7to12.defaultMinutes, 90);
    expect(ChildAgeGroup.age13to15.blocksRiskySites, isTrue);
    // Groups the patch didn't touch keep the manuscript value.
    expect(ChildAgeGroup.upTo6.defaultMinutes, 60);
  });

  test('malformed values are ignored', () {
    AgeGroupRules.apply({
      'goal_minutes_7_12': '90',
      'goal_minutes_13_15': 5,
      'risky_sites_7_12': 'maybe',
    });
    expect(ChildAgeGroup.age7to12.defaultMinutes, 120);
    expect(ChildAgeGroup.age13to15.defaultMinutes, 180);
    expect(ChildAgeGroup.age7to12.blocksRiskySites, isFalse);
  });

  test('a new age group gets the admin default as its goal', () {
    AgeGroupRules.apply({'goal_minutes_7_12': 90});
    expect(
      DailyGoal.ageGroupUpdate(ChildAgeGroup.age7to12)[DailyGoal.minutesField],
      90,
    );
  });
}
