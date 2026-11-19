import 'package:flutter_test/flutter_test.dart';
import 'package:app/services/daily_usage_history.dart';

void main() {
  final now = DateTime(2026, 11, 19, 15, 30);

  test('dayKey pads month and day', () {
    expect(DailyUsageHistory.dayKey(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('parse drops bad keys and values, accepts JSON or a map', () {
    final fromMap = DailyUsageHistory.parse({
      '2026-11-18': 3600000,
      'nonsense': 5,
      '2026-13-01': 5,
      '2026-11-17': -1,
      '2026-11-16': 'x',
    });
    expect(fromMap, {'2026-11-18': 3600000});
    expect(DailyUsageHistory.parse('{"2026-11-18": 60000}'), {
      '2026-11-18': 60000,
    });
    expect(DailyUsageHistory.parse('not json'), isEmpty);
    expect(DailyUsageHistory.parse(null), isEmpty);
  });

  test('merge keeps fresh values, drops old and future days', () {
    final merged = DailyUsageHistory.merge(
      {'2026-11-18': 1, '2026-10-01': 9, '2026-11-17': 5},
      {'2026-11-18': 2, '2026-11-20': 7, '2026-11-19': 3},
      now,
    );
    expect(merged, {'2026-11-18': 2, '2026-11-17': 5, '2026-11-19': 3});
  });

  test('lastSevenDays ends today, oldest first, missing days are null', () {
    final days = DailyUsageHistory.lastSevenDays({
      '2026-11-19': 60000,
      '2026-11-13': 120000,
    }, now);
    expect(days.length, 7);
    expect(days.first.key, DateTime(2026, 11, 13));
    expect(days.first.value, const Duration(minutes: 2));
    expect(days.last.key, DateTime(2026, 11, 19));
    expect(days.last.value, const Duration(minutes: 1));
    expect(days[3].value, isNull);
  });

  test('30-day average skips today and days without readings', () {
    final result = DailyUsageHistory.averageOfCompletedDays({
      '2026-11-19': 999999999,
      '2026-11-18': 2 * 3600000,
      '2026-11-10': 4 * 3600000,
      '2026-10-01': 100 * 3600000,
    }, now);
    expect(result, isNotNull);
    expect(result!.daysCounted, 2);
    expect(result.average, const Duration(hours: 3));
    expect(
      DailyUsageHistory.averageOfCompletedDays({'2026-11-19': 5}, now),
      isNull,
    );
  });
}
