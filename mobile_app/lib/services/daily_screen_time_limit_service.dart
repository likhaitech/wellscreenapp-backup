import 'package:shared_preferences/shared_preferences.dart';

import '../models/daily_goal.dart';

/// The child's daily screen-time goal, cached on the phone. The value comes
/// from the guardian (age group or their own goal, see DailyGoal) and is
/// written here by ChildHomeScreen; reading it also updates
/// DailyGoal.activeGoal, which the usage alerts use.
class DailyScreenTimeLimitService {
  static const String _dailyScreenTimeLimitMinutesKey =
      'daily_screen_time_limit_minutes';

  static const Duration defaultDailyLimit = Duration(
    minutes: DailyGoal.fallbackMinutes,
  );

  Future<void> saveDailyLimit(Duration dailyLimit) async {
    final preferences = await SharedPreferences.getInstance();

    if (dailyLimit <= Duration.zero) {
      await preferences.remove(_dailyScreenTimeLimitMinutesKey);
      DailyGoal.activeGoal = defaultDailyLimit;
      return;
    }

    DailyGoal.activeGoal = dailyLimit;

    await preferences.setInt(
      _dailyScreenTimeLimitMinutesKey,
      dailyLimit.inMinutes,
    );
  }

  Future<Duration> getDailyLimit() async {
    final preferences = await SharedPreferences.getInstance();
    final savedMinutes = preferences.getInt(_dailyScreenTimeLimitMinutesKey);

    final limit = savedMinutes == null || savedMinutes <= 0
        ? defaultDailyLimit
        : Duration(minutes: savedMinutes);
    DailyGoal.activeGoal = limit;
    return limit;
  }

  Future<void> clearDailyLimit() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_dailyScreenTimeLimitMinutesKey);
    DailyGoal.activeGoal = defaultDailyLimit;
  }
}
