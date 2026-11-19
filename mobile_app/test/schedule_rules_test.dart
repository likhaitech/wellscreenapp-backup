import 'package:app/models/schedule_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing or invalid data means everything is off', () {
    for (final raw in [null, 'x', <String, dynamic>{}]) {
      final rules = ScheduleRules.fromMap(raw);
      expect(rules.bedtimeEnabled, isFalse);
      expect(rules.breaksEnabled, isFalse);
      expect(rules.focusEndsAt, isNull);
    }
    final bad = ScheduleRules.fromMap({
      'bedtime': {'enabled': 'yes', 'startMinutes': 99999, 'endMinutes': -5},
      'breaks': {'enabled': true, 'afterMinutes': 7, 'breakMinutes': 999},
      'focus': {'durationMinutes': 100000, 'startedAt': 'now'},
    });
    expect(bad.bedtimeEnabled, isFalse);
    expect(bad.bedtimeStartMinutes, ScheduleRules.defaultBedtimeStart);
    expect(bad.breakAfterMinutes, ScheduleRules.defaultBreakAfter);
    expect(bad.breakLengthMinutes, ScheduleRules.defaultBreakLength);
    expect(bad.focusEndsAt, isNull);
  });

  test('focus ends after its length, counted from the server start time', () {
    final start = DateTime(2026, 11, 19, 16);
    final rules = ScheduleRules.fromMap({
      'focus': {'durationMinutes': 60, 'startedAt': Timestamp.fromDate(start)},
    });
    expect(rules.focusEndsAt, DateTime(2026, 11, 19, 17));
    expect(rules.isFocusActive(DateTime(2026, 11, 19, 16, 30)), isTrue);
    expect(rules.isFocusActive(DateTime(2026, 11, 19, 17, 1)), isFalse);
    final native = rules.toNativeJson();
    expect((native['focus'] as Map)['durationMs'], 3600000);
  });

  test('bedtime with the same start and end is never sent as enabled', () {
    final rules = ScheduleRules.fromMap({
      'bedtime': {'enabled': true, 'startMinutes': 600, 'endMinutes': 600},
    });
    expect((rules.toNativeJson()['bedtime'] as Map)['enabled'], isFalse);
  });

  test('time labels', () {
    expect(ScheduleRules.timeLabel(21 * 60), '9:00 PM');
    expect(ScheduleRules.timeLabel(6 * 60 + 5), '6:05 AM');
    expect(ScheduleRules.timeLabel(0), '12:00 AM');
    expect(ScheduleRules.timeLabel(12 * 60), '12:00 PM');
  });
}
