import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/usage_tracking_service.dart';

/// Covers UsageTrackingService.summarizeUsage and .countMaxAppOpens -
/// previously untestable because getTodayUsage()/getTodayMaxAppOpenCount()
/// call the native usage_stats plugin's static
/// UsageStats.queryAndAggregateUsageStats()/queryEvents() directly and
/// work with its UsageInfo/EventUsageInfo types, which have no in-memory
/// fake and talk to real Android APIs. Fixed the same way for both: the
/// actual transformation logic is extracted into a pure method that takes
/// plain Dart values instead of the plugin's own types (a
/// `Map<String, int>` for summarizeUsage, a `List<UsageEventRecord>` -
/// itself a plain record type, not the plugin's EventUsageInfo - for
/// countMaxAppOpens). getTodayUsage()/getTodayMaxAppOpenCount() (the
/// native-plugin-touching parts) are intentionally NOT covered here -
/// there's nothing to check without a real device/emulator. The
/// EventUsageInfo shape and its ACTIVITY_RESUMED=1 event-type mapping
/// used to build countMaxAppOpens() were confirmed directly from the
/// usage_stats plugin's real source (github.com/Parassharmaa/usage_stats),
/// not guessed.
void main() {
  group('UsageTrackingService.summarizeUsage', () {
    final service = UsageTrackingService();

    test('drops packages with zero or negative usage', () {
      final result = service.summarizeUsage({
        'com.example.zero': 0,
        'com.example.real': 60000,
      });

      expect(result, hasLength(1));
      expect(result.single.packageName, 'com.example.real');
    });

    test('sorts by usage duration descending', () {
      final result = service.summarizeUsage({
        'com.example.small': 1000,
        'com.example.big': 500000,
        'com.example.medium': 60000,
      });

      expect(
        result.map((s) => s.packageName).toList(),
        ['com.example.big', 'com.example.medium', 'com.example.small'],
      );
    });

    test('caps the result at 10 entries even with more real usage', () {
      final input = <String, int>{
        for (var i = 0; i < 15; i++) 'com.example.app$i': (15 - i) * 1000,
      };

      final result = service.summarizeUsage(input);

      expect(result, hasLength(10));
      // Confirms the cap keeps the TOP 10 by usage, not just the first 10
      // map entries encountered.
      expect(result.first.packageName, 'com.example.app0');
      expect(result.last.packageName, 'com.example.app9');
    });

    test(
      'derives a capitalized display name from the last package-name segment',
      () {
        final result = service.summarizeUsage({
          'com.google.android.youtube': 60000,
        });

        expect(result.single.displayName, 'Youtube');
      },
    );

    test(
      'falls back to the raw package name when it has no dot-separated '
      'segments to derive a name from',
      () {
        final result = service.summarizeUsage({'singleword': 60000});
        expect(result.single.displayName, 'Singleword');
      },
    );

    test('usageDuration reflects the exact input milliseconds', () {
      final result = service.summarizeUsage({'com.example.app': 123456});
      expect(
        result.single.usageDuration,
        const Duration(milliseconds: 123456),
      );
    });

    test('an empty map produces an empty summary list', () {
      expect(service.summarizeUsage({}), isEmpty);
    });

    test('passes the last-used time through (needed for late-night alerts)',
        () {
      final lateNight = DateTime(2026, 11, 25, 23, 20);
      final result = service.summarizeAllUsage(
        {'com.example.game': 60000, 'com.example.notes': 30000},
        lastUsed: {'com.example.game': lateNight},
      );

      expect(
        result.firstWhere((s) => s.packageName == 'com.example.game')
            .lastTimeUsed,
        lateNight,
      );
      expect(
        result.firstWhere((s) => s.packageName == 'com.example.notes')
            .lastTimeUsed,
        isNull,
      );
    });
  });

  group('UsageTrackingService.countMaxAppOpens', () {
    final service = UsageTrackingService();

    UsageEventRecord resumed(String packageName, int timestampMs) => (
          packageName: packageName,
          eventType: 1, // ACTIVITY_RESUMED
          timestampMs: timestampMs,
        );

    UsageEventRecord paused(String packageName, int timestampMs) => (
          packageName: packageName,
          eventType: 2, // ACTIVITY_PAUSED
          timestampMs: timestampMs,
        );

    test('an empty event list has no opens', () {
      expect(service.countMaxAppOpens([]), 0);
    });

    test('counts one open per distinct ACTIVITY_RESUMED event', () {
      final events = [
        resumed('com.example.a', 1000),
        resumed('com.example.b', 2000),
        resumed('com.example.a', 3000),
      ];

      // com.example.a resumed twice, separated by b - both are genuine
      // re-opens, so it should count 2.
      expect(service.countMaxAppOpens(events), 2);
    });

    test(
      'collapses consecutive resumes of the SAME app into a single open '
      '(internal navigation, not a re-open)',
      () {
        final events = [
          resumed('com.example.a', 1000),
          resumed('com.example.a', 1200), // same app's own next activity
          resumed('com.example.a', 1400),
        ];

        expect(service.countMaxAppOpens(events), 1);
      },
    );

    test('ignores non-ACTIVITY_RESUMED event types', () {
      final events = [
        resumed('com.example.a', 1000),
        paused('com.example.a', 1500),
        resumed('com.example.a', 2000), // still "same as last resumed"
      ];

      // The intervening PAUSED event must not reset the
      // same-package-collapse logic - this is still one continuous
      // session from ACTIVITY_RESUMED's point of view.
      expect(service.countMaxAppOpens(events), 1);
    });

    test('returns the single HIGHEST per-app count, not the cross-app sum', () {
      final events = [
        resumed('com.example.frequent', 1000),
        resumed('com.example.other', 2000),
        resumed('com.example.frequent', 3000),
        resumed('com.example.other', 4000),
        resumed('com.example.frequent', 5000),
      ];

      // com.example.frequent: 3 opens, com.example.other: 2 opens.
      // Table 6 scores per-app, so this must return 3, not 5.
      expect(service.countMaxAppOpens(events), 3);
    });

    test('ignores events with an empty package name', () {
      final events = [resumed('', 1000), resumed('com.example.a', 2000)];
      expect(service.countMaxAppOpens(events), 1);
    });

    test(
      'sorts defensively by timestamp before collapsing, even if the '
      'input list is out of order',
      () {
        final events = [
          resumed('com.example.a', 3000),
          resumed('com.example.b', 1000),
          resumed('com.example.a', 2000),
        ];

        // Chronologically: b, a, a - the two 'a' resumes are adjacent in
        // TIME even though they aren't adjacent in this out-of-order
        // input list, so they should still collapse to one open for 'a'.
        expect(service.countMaxAppOpens(events), 1);
      },
    );
  });
}
