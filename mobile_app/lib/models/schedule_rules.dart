import 'package:cloud_firestore/cloud_firestore.dart';

/// Guardian schedules: bedtime lock (Objective 2.5 "scheduled lock
/// sessions"), focus mode and break timers ("cooldown timers").
///
/// Stored in app_rules/{guardianUid}.schedules, mirrored by the child phone
/// into SharedPreferences ('wellscreen_schedules_json') for the native
/// blocker (ScheduleEnforcer.kt).
class ScheduleRules {
  const ScheduleRules({
    this.bedtimeEnabled = false,
    this.bedtimeStartMinutes = defaultBedtimeStart,
    this.bedtimeEndMinutes = defaultBedtimeEnd,
    this.focusDurationMinutes = 0,
    this.focusStartedAt,
    this.breaksEnabled = false,
    this.breakAfterMinutes = defaultBreakAfter,
    this.breakLengthMinutes = defaultBreakLength,
  });

  static const int defaultBedtimeStart = 21 * 60; // 9:00 PM
  static const int defaultBedtimeEnd = 6 * 60; // 6:00 AM
  static const int defaultBreakAfter = 60;
  static const int defaultBreakLength = 10;

  static const List<int> focusChoices = [30, 60, 120];
  static const List<int> breakAfterChoices = [30, 45, 60, 90];
  static const List<int> breakLengthChoices = [5, 10, 15, 30];

  final bool bedtimeEnabled;
  final int bedtimeStartMinutes;
  final int bedtimeEndMinutes;
  final int focusDurationMinutes;
  final DateTime? focusStartedAt;
  final bool breaksEnabled;
  final int breakAfterMinutes;
  final int breakLengthMinutes;

  DateTime? get focusEndsAt {
    final start = focusStartedAt;
    if (start == null || focusDurationMinutes <= 0) return null;
    return start.add(Duration(minutes: focusDurationMinutes));
  }

  bool isFocusActive(DateTime now) {
    final end = focusEndsAt;
    return end != null && end.isAfter(now);
  }

  static int _minutes(Object? value, int fallback) =>
      value is int && value >= 0 && value < 24 * 60 ? value : fallback;

  static int _choice(Object? value, List<int> allowed, int fallback) =>
      value is int && allowed.contains(value) ? value : fallback;

  /// Reads the Firestore map. Anything missing or invalid falls back to
  /// "off" / defaults, so a bad value can never lock a phone by accident.
  factory ScheduleRules.fromMap(Object? raw) {
    if (raw is! Map) return const ScheduleRules();
    final bedtime = raw['bedtime'] is Map ? raw['bedtime'] as Map : const {};
    final focus = raw['focus'] is Map ? raw['focus'] as Map : const {};
    final breaks = raw['breaks'] is Map ? raw['breaks'] as Map : const {};
    final startedAt = focus['startedAt'];
    final duration = focus['durationMinutes'];
    return ScheduleRules(
      bedtimeEnabled: bedtime['enabled'] == true,
      bedtimeStartMinutes: _minutes(bedtime['startMinutes'], defaultBedtimeStart),
      bedtimeEndMinutes: _minutes(bedtime['endMinutes'], defaultBedtimeEnd),
      focusDurationMinutes:
          duration is int && duration > 0 && duration <= 240 ? duration : 0,
      focusStartedAt: startedAt is Timestamp ? startedAt.toDate() : null,
      breaksEnabled: breaks['enabled'] == true,
      breakAfterMinutes:
          _choice(breaks['afterMinutes'], breakAfterChoices, defaultBreakAfter),
      breakLengthMinutes: _choice(
        breaks['breakMinutes'],
        breakLengthChoices,
        defaultBreakLength,
      ),
    );
  }

  Map<String, Object> bedtimeMap() => {
    'enabled': bedtimeEnabled,
    'startMinutes': bedtimeStartMinutes,
    'endMinutes': bedtimeEndMinutes,
  };

  Map<String, Object> breaksMap() => {
    'enabled': breaksEnabled,
    'afterMinutes': breakAfterMinutes,
    'breakMinutes': breakLengthMinutes,
  };

  /// What the native blocker reads. Focus is sent as an end time based on
  /// the server's start time, plus its length (used against clock changes).
  Map<String, Object> toNativeJson() => {
    'bedtime': {
      'enabled': bedtimeEnabled && bedtimeStartMinutes != bedtimeEndMinutes,
      'start': bedtimeStartMinutes,
      'end': bedtimeEndMinutes,
    },
    'focus': {
      'untilMs': focusEndsAt?.millisecondsSinceEpoch ?? 0,
      'durationMs': focusDurationMinutes * 60000,
    },
    'breaks': {
      'enabled': breaksEnabled,
      'afterMinutes': breakAfterMinutes,
      'breakMinutes': breakLengthMinutes,
    },
  };

  ScheduleRules copyWith({
    bool? bedtimeEnabled,
    int? bedtimeStartMinutes,
    int? bedtimeEndMinutes,
    bool? breaksEnabled,
    int? breakAfterMinutes,
    int? breakLengthMinutes,
  }) => ScheduleRules(
    bedtimeEnabled: bedtimeEnabled ?? this.bedtimeEnabled,
    bedtimeStartMinutes: bedtimeStartMinutes ?? this.bedtimeStartMinutes,
    bedtimeEndMinutes: bedtimeEndMinutes ?? this.bedtimeEndMinutes,
    focusDurationMinutes: focusDurationMinutes,
    focusStartedAt: focusStartedAt,
    breaksEnabled: breaksEnabled ?? this.breaksEnabled,
    breakAfterMinutes: breakAfterMinutes ?? this.breakAfterMinutes,
    breakLengthMinutes: breakLengthMinutes ?? this.breakLengthMinutes,
  );

  /// Why a bedtime cannot be saved, or null when it can.
  String? get bedtimeError => bedtimeStartMinutes == bedtimeEndMinutes
      ? 'Start and end time must be different.'
      : null;

  /// "9:00 PM" style label for minutes after midnight.
  static String timeLabel(int minutes) {
    final hour24 = minutes ~/ 60;
    final minute = minutes % 60;
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    final suffix = hour24 < 12 ? 'AM' : 'PM';
    return '$hour12:${minute.toString().padLeft(2, '0')} $suffix';
  }
}
