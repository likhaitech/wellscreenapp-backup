import '../models/app_usage_summary.dart';
import '../models/daily_goal.dart';
import '../models/usage_report.dart';

class PatternDetectionService {
  /// Total-use thresholds follow the child's daily goal (age group or the
  /// guardian's own value, see DailyGoal): warning at the goal, unhealthy
  /// two hours past it. 3h / 5h until the goal is known.
  static Duration get warningTotalUsageLimit => DailyGoal.activeGoal;
  static Duration get unhealthyTotalUsageLimit =>
      DailyGoal.activeGoal + DailyGoal.highAlertExtra;

  static const Duration warningSingleAppLimit = Duration(hours: 1, minutes: 30);
  static const Duration unhealthySingleAppLimit = Duration(hours: 3);

  static const Duration riskyAppUsageLimit = Duration(hours: 1);

  static const List<String> riskyKeywords = [
    'facebook',
    'messenger',
    'instagram',
    'tiktok',
    'youtube',
    'twitter',
    'x',
    'snapchat',
    'discord',
    'netflix',
    'game',
    'games',
    'gaming',
    'roblox',
    'minecraft',
    'mlbb',
    'mobilelegends',
    'pubg',
    'cod',
    'freefire',
  ];

  UsageReport generateReport(List<AppUsageSummary> summaries) {
    final totalUsageDuration = _getTotalUsageDuration(summaries);
    final topUsedApp = _getTopUsedApp(summaries);
    final unhealthyAppCount = _getUnhealthyAppCount(summaries);
    final hasLongSingleAppUsage = _hasLongSingleAppUsage(summaries);
    final hasVeryLongSingleAppUsage = _hasVeryLongSingleAppUsage(summaries);
    final hasLateNightUsage = _hasLateNightUsage(summaries);

    final status = _detectStatus(
      totalUsageDuration: totalUsageDuration,
      unhealthyAppCount: unhealthyAppCount,
      hasLongSingleAppUsage: hasLongSingleAppUsage,
      hasVeryLongSingleAppUsage: hasVeryLongSingleAppUsage,
      hasLateNightUsage: hasLateNightUsage,
    );

    return UsageReport(
      totalUsageDuration: totalUsageDuration,
      topUsedApp: topUsedApp,
      unhealthyAppCount: unhealthyAppCount,
      generatedAt: DateTime.now(),
      patternStatus: status,
      recommendationMessage: _getRecommendationMessage(
        status: status,
        totalUsageDuration: totalUsageDuration,
        topUsedApp: topUsedApp,
        unhealthyAppCount: unhealthyAppCount,
        hasLongSingleAppUsage: hasLongSingleAppUsage,
        hasLateNightUsage: hasLateNightUsage,
      ),
    );
  }

  Duration _getTotalUsageDuration(List<AppUsageSummary> summaries) {
    return summaries.fold(
      Duration.zero,
      (total, app) => total + app.usageDuration,
    );
  }

  AppUsageSummary? _getTopUsedApp(List<AppUsageSummary> summaries) {
    if (summaries.isEmpty) {
      return null;
    }

    final sortedApps = [...summaries]
      ..sort((a, b) => b.usageDuration.compareTo(a.usageDuration));

    return sortedApps.first;
  }

  int _getUnhealthyAppCount(List<AppUsageSummary> summaries) {
    return summaries.where((app) {
      return _isRiskyApp(app) && app.usageDuration >= riskyAppUsageLimit;
    }).length;
  }

  bool _hasLongSingleAppUsage(List<AppUsageSummary> summaries) {
    return summaries.any(
      (app) => app.usageDuration >= warningSingleAppLimit,
    );
  }

  /// True when a single app was used continuously for [unhealthySingleAppLimit]
  /// (3h) or more. Previously this constant was declared but never checked
  /// anywhere, so an extreme single-app session (e.g. 6 straight hours)
  /// produced the exact same "warning-tier" signal as a 1h31m session via
  /// [_hasLongSingleAppUsage]. This escalates it to the unhealthy tier.
  bool _hasVeryLongSingleAppUsage(List<AppUsageSummary> summaries) {
    return summaries.any(
      (app) => app.usageDuration >= unhealthySingleAppLimit,
    );
  }

  bool _hasLateNightUsage(List<AppUsageSummary> summaries) {
    return summaries.any((app) {
      final lastTimeUsed = app.lastTimeUsed;

      if (lastTimeUsed == null) {
        return false;
      }

      return lastTimeUsed.hour >= 22 || lastTimeUsed.hour < 5;
    });
  }

  bool _isRiskyApp(AppUsageSummary app) {
    final packageName = app.packageName.toLowerCase();
    final displayName = app.displayName.toLowerCase();

    return riskyKeywords.any(
      (keyword) =>
          _matchesKeyword(packageName, keyword) ||
          _matchesKeyword(displayName, keyword),
    );
  }

  /// Matches [keyword] as a whole token within [text] rather than as a bare
  /// substring, so short/common keywords like 'x' or 'cod' don't false-match
  /// unrelated names such as "Firefox" or "VSCode". A token boundary is any
  /// character that isn't a letter or digit (covers package-name separators
  /// like '.', '_', '-', and spaces in display names).
  bool _matchesKeyword(String text, String keyword) {
    final pattern = RegExp(
      r'(?<![a-z0-9])' + RegExp.escape(keyword) + r'(?![a-z0-9])',
    );
    return pattern.hasMatch(text);
  }

  UsagePatternStatus _detectStatus({
    required Duration totalUsageDuration,
    required int unhealthyAppCount,
    required bool hasLongSingleAppUsage,
    required bool hasVeryLongSingleAppUsage,
    required bool hasLateNightUsage,
  }) {
    if (totalUsageDuration >= unhealthyTotalUsageLimit ||
        unhealthyAppCount >= 3 ||
        hasLateNightUsage ||
        hasVeryLongSingleAppUsage) {
      return UsagePatternStatus.unhealthy;
    }

    if (totalUsageDuration >= warningTotalUsageLimit ||
        unhealthyAppCount >= 1 ||
        hasLongSingleAppUsage) {
      return UsagePatternStatus.warning;
    }

    return UsagePatternStatus.healthy;
  }

  String _getRecommendationMessage({
    required UsagePatternStatus status,
    required Duration totalUsageDuration,
    required AppUsageSummary? topUsedApp,
    required int unhealthyAppCount,
    required bool hasLongSingleAppUsage,
    required bool hasLateNightUsage,
  }) {
    final topAppName = topUsedApp?.displayName ?? 'No app';

    switch (status) {
      case UsagePatternStatus.healthy:
        return 'Usage looks healthy. Keep maintaining balanced screen time.';

      case UsagePatternStatus.warning:
        if (hasLongSingleAppUsage) {
          return '$topAppName was used for a long session. A short break is recommended.';
        }

        if (unhealthyAppCount > 0) {
          return 'Some social media or gaming apps have high usage. Consider setting app limits.';
        }

        return 'Screen time is getting high. Consider taking a break.';

      case UsagePatternStatus.unhealthy:
        if (hasLateNightUsage) {
          return 'Late-night phone usage was detected. Consider enabling bedtime restrictions.';
        }

        if (unhealthyAppCount >= 3) {
          return 'Multiple social media or gaming apps show high usage. Guardian guidance is recommended.';
        }

        return 'Total screen time is too high. Consider using focus mode or temporary app blocking.';
    }
  }
}