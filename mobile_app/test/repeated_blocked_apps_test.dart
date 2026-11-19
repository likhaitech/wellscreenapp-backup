import 'package:app/services/monitoring_usage_alert_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 19, 15);
  Map<String, dynamic> entry(String pkg, DateTime at,
          {String outcome = 'blocked', String? source}) =>
      {
        'packageName': pkg,
        'outcome': outcome,
        'timestampMs': at.millisecondsSinceEpoch,
        'blockSource': ?source,
      };

  test('counts only today\'s app blocks with 3 or more attempts', () {
    final log = [
      for (var i = 0; i < 3; i++) entry('com.zhiliaoapp.musically', now),
      entry('com.roblox.client', now),
      entry('com.roblox.client', now),
      // Yesterday does not count.
      entry('com.roblox.client', now.subtract(const Duration(days: 1))),
    ];
    expect(MonitoringUsageAlertService.repeatedBlockedApps(log, now), {
      'com.zhiliaoapp.musically': 3,
    });
  });

  test('counts blocked websites too', () {
    final log = [
      for (var i = 0; i < 3; i++)
        entry('youtube.com', now, source: 'parent_rule'),
      for (var i = 0; i < 4; i++) entry('okbet.com', now, source: 'ai'),
      entry('tiktok.com', now, source: 'parent_rule'),
    ];
    expect(MonitoringUsageAlertService.repeatedBlockedApps(log, now), {
      'youtube.com': 3,
      'okbet.com': 4,
    });
  });

  test('ignores WellScreen settings, schedule blocks and bypasses', () {
    final log = [
      for (var i = 0; i < 5; i++) entry('WellScreen settings', now),
      for (var i = 0; i < 5; i++)
        entry('com.google.android.youtube', now, source: 'schedule'),
      for (var i = 0; i < 5; i++)
        entry('com.zhiliaoapp.musically', now,
            outcome: 'emergency_access_bypass'),
    ];
    expect(MonitoringUsageAlertService.repeatedBlockedApps(log, now), isEmpty);
  });

  test('alerts at 3, 5 and 10 attempts', () {
    expect(MonitoringUsageAlertService.attemptMilestone(2), 0);
    expect(MonitoringUsageAlertService.attemptMilestone(3), 3);
    expect(MonitoringUsageAlertService.attemptMilestone(4), 3);
    expect(MonitoringUsageAlertService.attemptMilestone(7), 5);
    expect(MonitoringUsageAlertService.attemptMilestone(25), 10);
  });

  test('event IDs match the native format', () {
    expect(
      MonitoringUsageAlertService.repeatedAttemptEventId(
          'youtube.com', '20261119', 3),
      'rra_youtube_com_20261119',
    );
    expect(
      MonitoringUsageAlertService.repeatedAttemptEventId(
          'youtube.com', '20261119', 10),
      'rra_youtube_com_20261119_10',
    );
  });
}
