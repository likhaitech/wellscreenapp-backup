import 'package:app/models/daily_goal.dart';
import 'package:app/services/monitoring_usage_alert_service.dart';
import 'package:app/services/pattern_detection_service.dart';
import 'package:app/widgets/daily_goal_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Map<String, Object>?> _openSheet(
  WidgetTester tester,
  Map<String, dynamic>? profile,
  Future<void> Function() interact,
) async {
  Map<String, Object>? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDailyGoalSheet(
                context,
                childName: 'Mika',
                profile: profile,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await interact();
  await tester.tap(find.text('Save goal'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('picking an age group saves its recommended goal', (
    tester,
  ) async {
    final result = await _openSheet(tester, {}, () async {
      await tester.tap(find.text('7–12'));
      await tester.pump();
    });

    expect(result, {'ageGroup': '7_12', 'dailyGoalMinutes': 120});
  });

  testWidgets('guardian can adjust the goal away from the default', (
    tester,
  ) async {
    final result = await _openSheet(tester, {'ageGroup': '6_and_below'}, () async {
      expect(find.text('1h'), findsOneWidget);
      await tester.tap(find.byTooltip('More time'));
      await tester.tap(find.byTooltip('More time'));
      await tester.pump();
      expect(find.text('1h 30m'), findsOneWidget);
      expect(find.text('Use recommended'), findsOneWidget);
    });

    expect(result, {'ageGroup': '6_and_below', 'dailyGoalMinutes': 90});
  });

  group('usage alerts follow the goal', () {
    tearDown(() => DailyGoal.activeGoal = const Duration(hours: 3));

    test('warning at the goal, high two hours later', () {
      DailyGoal.activeGoal = const Duration(hours: 1);
      expect(PatternDetectionService.warningTotalUsageLimit,
          const Duration(hours: 1));
      expect(PatternDetectionService.unhealthyTotalUsageLimit,
          const Duration(hours: 3));
    });

    test('3-hour goal keeps the original 3h / 5h alert IDs', () {
      expect(
        MonitoringUsageAlertService.usageEventId(
            const Duration(hours: 3), '20261120'),
        'usage3h_20261120',
      );
      expect(
        MonitoringUsageAlertService.usageEventId(
            const Duration(hours: 5), '20261120'),
        'usage5h_20261120',
      );
      expect(
        MonitoringUsageAlertService.usageEventId(
            const Duration(minutes: 90), '20261120'),
        'usage90m_20261120',
      );
    });
  });
}
