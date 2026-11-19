import 'dart:convert';

/// Per-day screen-time totals kept on the child's phone and synced to the
/// child profile as `dailyUsageTotals` ({'yyyy-mm-dd': milliseconds}), so
/// the guardian's dashboard can draw a real 7-day chart and a 30-day
/// average instead of only today's report.
///
/// The app's 5-minute sync sends the whole map; the native background job
/// (ScreenTimeReportJobService) also updates today's entry while the app
/// is closed. Values come from the same Android UsageStats totals the child's own
/// Weekly Summary uses. Nothing is estimated: a day with no reading is
/// simply missing, and the chart shows it as empty.
class DailyUsageHistory {
  DailyUsageHistory._();

  static const String prefsKey = 'wellscreen_daily_usage_totals_json';
  static const String refreshedDayKey = 'wellscreen_daily_usage_refreshed_day';

  /// How many days are kept (a little over 30 so the 30-day average
  /// always has a full window).
  static const int keepDays = 35;

  static String dayKey(DateTime day) {
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '${day.year}-$m-$d';
  }

  static DateTime? parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(y, m, d);
  }

  /// Reads a totals map from prefs JSON or a Firestore field. Bad keys and
  /// non-numeric or negative values are dropped.
  static Map<String, int> parse(Object? raw) {
    Object? source = raw;
    if (raw is String) {
      try {
        source = jsonDecode(raw);
      } catch (_) {
        return {};
      }
    }
    if (source is! Map) return {};
    final result = <String, int>{};
    source.forEach((key, value) {
      final k = key.toString();
      if (parseDayKey(k) == null) return;
      if (value is num && value >= 0) result[k] = value.toInt();
    });
    return result;
  }

  /// Fresh readings replace stored ones for the same day; days older than
  /// [keepDays] and days in the future (clock changes) are dropped.
  static Map<String, int> merge(
    Map<String, int> stored,
    Map<String, int> fresh,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final oldest = DateTime(today.year, today.month, today.day - keepDays + 1);
    final merged = <String, int>{...stored, ...fresh};
    merged.removeWhere((key, _) {
      final day = parseDayKey(key);
      return day == null || day.isBefore(oldest) || day.isAfter(today);
    });
    return merged;
  }

  /// The last 7 days, oldest first, ending today. A day with no reading
  /// is null.
  static List<MapEntry<DateTime, Duration?>> lastSevenDays(
    Map<String, int> totals,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(7, (index) {
      final day = DateTime(today.year, today.month, today.day - 6 + index);
      final ms = totals[dayKey(day)];
      return MapEntry<DateTime, Duration?>(
        day,
        ms == null ? null : Duration(milliseconds: ms),
      );
    });
  }

  /// Average per day over the completed days (today excluded, because it
  /// isn't over yet) in the last [days] days that have a reading. Null if
  /// there are none. Also returns how many days were averaged.
  static ({Duration average, int daysCounted})? averageOfCompletedDays(
    Map<String, int> totals,
    DateTime now, {
    int days = 30,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    var sum = 0;
    var count = 0;
    for (var i = 1; i <= days; i++) {
      final day = DateTime(today.year, today.month, today.day - i);
      final ms = totals[dayKey(day)];
      if (ms == null) continue;
      sum += ms;
      count++;
    }
    if (count == 0) return null;
    return (
      average: Duration(milliseconds: sum ~/ count),
      daysCounted: count,
    );
  }
}
