import 'package:flutter_test/flutter_test.dart';

import 'package:app/models/usage_report.dart';
import 'package:app/services/screen_time_goal_service.dart';

void main() {
  group('ScreenTimeGoalService', () {
    test('returns withinLimit when usage is below threshold', () {
      final service = ScreenTimeGoalService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 1),
        topUsedApp: null,
        unhealthyAppCount: 0,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.healthy,
        recommendationMessage: 'Usage looks healthy.',
      );

      final result = service.evaluate(
        report: report,
        dailyLimit: const Duration(hours: 3),
      );

      expect(result.status, ScreenTimeGoalStatus.withinLimit);
      expect(result.remainingDuration, const Duration(hours: 2));
      expect(result.isExceeded, false);
    });

    test('returns nearLimit when usage reaches 80 percent of daily limit', () {
      final service = ScreenTimeGoalService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 2, minutes: 30),
        topUsedApp: null,
        unhealthyAppCount: 0,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.warning,
        recommendationMessage: 'Screen time is getting high.',
      );

      final result = service.evaluate(
        report: report,
        dailyLimit: const Duration(hours: 3),
      );

      expect(result.status, ScreenTimeGoalStatus.nearLimit);
      expect(result.isExceeded, false);
      expect(result.message.contains('close to the daily goal'), true);
    });

    test('returns exceeded when usage reaches daily limit', () {
      final service = ScreenTimeGoalService();

      final report = UsageReport(
        totalUsageDuration: const Duration(hours: 3),
        topUsedApp: null,
        unhealthyAppCount: 1,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.unhealthy,
        recommendationMessage: 'Total screen time is too high.',
      );

      final result = service.evaluate(
        report: report,
        dailyLimit: const Duration(hours: 3),
      );

      expect(result.status, ScreenTimeGoalStatus.exceeded);
      expect(result.remainingDuration, Duration.zero);
      expect(result.isExceeded, true);
    });

    test('returns exceeded when daily limit is invalid', () {
      final service = ScreenTimeGoalService();

      final report = UsageReport(
        totalUsageDuration: const Duration(minutes: 30),
        topUsedApp: null,
        unhealthyAppCount: 0,
        generatedAt: DateTime(2026, 6, 30),
        patternStatus: UsagePatternStatus.healthy,
        recommendationMessage: 'Usage looks healthy.',
      );

      final result = service.evaluate(
        report: report,
        dailyLimit: Duration.zero,
      );

      expect(result.status, ScreenTimeGoalStatus.exceeded);
      expect(result.remainingDuration, Duration.zero);
      expect(result.message, 'No valid daily screen-time goal is set.');
    });
  });
}
