/// Age-based daily screen-time goal (manuscript Ch. III defaults):
/// 6 and below -> 1 hour, 7-12 -> 2 hours, 13-15 -> 3 hours.
///
/// The guardian picks the child's age group when pairing or later in
/// Devices, and may still change the goal. Both live on
/// child_profiles/{id}: `ageGroup` and an optional `dailyGoalMinutes`
/// override. The goal only drives alerts and the progress bar; it never
/// locks the phone (per-app time limits do that).
enum ChildAgeGroup {
  upTo6('6_and_below', '6 and below', 60),
  age7to12('7_12', '7–12', 120),
  age13to15('13_15', '13–15', 180);

  const ChildAgeGroup(this.id, this.label, this.defaultMinutes);

  /// Value stored in Firestore.
  final String id;

  /// "Ages $label" in the UI.
  final String label;
  final int defaultMinutes;

  static ChildAgeGroup? parse(Object? value) {
    for (final group in values) {
      if (group.id == value) return group;
    }
    return null;
  }
}

class DailyGoal {
  DailyGoal._();

  static const String ageGroupField = 'ageGroup';
  static const String minutesField = 'dailyGoalMinutes';
  static const String updatedAtField = 'dailyGoalUpdatedAt';

  /// Used when no age group has been chosen yet (older pairings).
  static const int fallbackMinutes = 180;

  /// Guardian adjustment range and step.
  static const int minMinutes = 15;
  static const int maxMinutes = 720;
  static const int stepMinutes = 15;

  /// The "high" alert fires this long after the goal is reached
  /// (3h goal -> alerts at 3h and 5h, as before).
  static const Duration highAlertExtra = Duration(hours: 2);

  /// The goal this phone is currently using. Set on the child's phone from
  /// its profile (see ChildHomeScreen); 3 hours until then.
  static Duration activeGoal = const Duration(minutes: fallbackMinutes);

  static bool isValidMinutes(Object? value) =>
      value is int && value >= minMinutes && value <= maxMinutes;

  /// The goal for a child profile: the guardian's own value if set,
  /// otherwise the age-group default, otherwise 3 hours.
  static int minutesFor(Map<String, dynamic>? profile) {
    final custom = profile?[minutesField];
    if (isValidMinutes(custom)) return custom as int;
    final group = ChildAgeGroup.parse(profile?[ageGroupField]);
    return group?.defaultMinutes ?? fallbackMinutes;
  }

  static Duration durationFor(Map<String, dynamic>? profile) =>
      Duration(minutes: minutesFor(profile));

  /// True when the guardian changed the goal away from the age default.
  static bool isCustom(Map<String, dynamic>? profile) {
    final custom = profile?[minutesField];
    if (!isValidMinutes(custom)) return false;
    final group = ChildAgeGroup.parse(profile?[ageGroupField]);
    return custom != (group?.defaultMinutes ?? fallbackMinutes);
  }

  /// Firestore update for a new age group: resets the goal to its default.
  static Map<String, Object> ageGroupUpdate(ChildAgeGroup group) => {
    ageGroupField: group.id,
    minutesField: group.defaultMinutes,
  };

  /// Clamped to the allowed range and rounded to the step.
  static int clampMinutes(int minutes) {
    final stepped = (minutes / stepMinutes).round() * stepMinutes;
    return stepped.clamp(minMinutes, maxMinutes);
  }

  /// "1h", "2h 30m", "45m".
  static String label(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// "1 hour", "2 hours 30 minutes" for alert text.
  static String longLabel(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final parts = <String>[
      if (h > 0) '$h hour${h == 1 ? '' : 's'}',
      if (m > 0) '$m minute${m == 1 ? '' : 's'}',
    ];
    return parts.isEmpty ? '0 minutes' : parts.join(' ');
  }

  /// One line for the guardian, e.g. "2h a day · Ages 7–12" or
  /// "2h 30m a day · Ages 7–12 (adjusted)".
  static String summary(Map<String, dynamic>? profile) {
    final group = ChildAgeGroup.parse(profile?[ageGroupField]);
    final goal = '${label(minutesFor(profile))} a day';
    if (group == null) return '$goal · Age group not set';
    return '$goal · Ages ${group.label}${isCustom(profile) ? ' (adjusted)' : ''}';
  }
}
