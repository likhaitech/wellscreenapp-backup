import '../models/usage_report.dart';

enum ScreenTimeGoalStatus { withinLimit, nearLimit, exceeded }

class ScreenTimeGoalResult {
  const ScreenTimeGoalResult({
    required this.status,
    required this.dailyLimit,
    required this.usedDuration,
    required this.remainingDuration,
    required this.progressPercent,
    required this.message,
  });

  final ScreenTimeGoalStatus status;
  final Duration dailyLimit;
  final Duration usedDuration;
  final Duration remainingDuration;
  final double progressPercent;
  final String message;

  bool get isExceeded => status == ScreenTimeGoalStatus.exceeded;
}

class ScreenTimeGoalService {
  static const double nearLimitThreshold = 0.8;

  ScreenTimeGoalResult evaluate({
    required UsageReport report,
    required Duration dailyLimit,
  }) {
    final usedDuration = report.totalUsageDuration;

    if (dailyLimit <= Duration.zero) {
      return ScreenTimeGoalResult(
        status: ScreenTimeGoalStatus.exceeded,
        dailyLimit: dailyLimit,
        usedDuration: usedDuration,
        remainingDuration: Duration.zero,
        progressPercent: 1,
        message: 'No valid daily screen-time goal is set.',
      );
    }

    final progressPercent =
        usedDuration.inMilliseconds / dailyLimit.inMilliseconds;

    final remainingDuration = usedDuration >= dailyLimit
        ? Duration.zero
        : dailyLimit - usedDuration;

    if (usedDuration >= dailyLimit) {
      return ScreenTimeGoalResult(
        status: ScreenTimeGoalStatus.exceeded,
        dailyLimit: dailyLimit,
        usedDuration: usedDuration,
        remainingDuration: remainingDuration,
        progressPercent: progressPercent,
        message:
            'Recommended daily screen-time goal reached. Consider a break, focus mode or app limits.',
      );
    }

    if (progressPercent >= nearLimitThreshold) {
      return ScreenTimeGoalResult(
        status: ScreenTimeGoalStatus.nearLimit,
        dailyLimit: dailyLimit,
        usedDuration: usedDuration,
        remainingDuration: remainingDuration,
        progressPercent: progressPercent,
        message:
            'Screen time is close to the daily goal. A break or cooldown timer is recommended.',
      );
    }

    return ScreenTimeGoalResult(
      status: ScreenTimeGoalStatus.withinLimit,
      dailyLimit: dailyLimit,
      usedDuration: usedDuration,
      remainingDuration: remainingDuration,
      progressPercent: progressPercent,
      message: 'Screen time is still within the daily goal.',
    );
  }
}
