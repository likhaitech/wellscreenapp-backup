// CASE-050 - Usage Monitoring
// Run: flutter test test/cases/usage_tracking_service_case_050_test.dart -r expanded

import 'package:app/services/usage_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-050',
    file: 'test/cases/usage_tracking_service_case_050_test.dart',
    codeTested: 'lib/services/usage_tracking_service.dart',
    description: 'Guardian opens All Apps.',
    expected: 'Each app shows its time used and the number of times it was opened.',
    body: (tester) async {
      final tracking = UsageTrackingService();
      // Android events: 1 = app came to the front, 2 = went to the back.
      final events = [
        (packageName: 'com.google.android.youtube', eventType: 1, timestampMs: 1000),
        (packageName: 'com.google.android.youtube', eventType: 2, timestampMs: 2000),
        (packageName: 'com.zhiliaoapp.musically', eventType: 1, timestampMs: 3000),
        (packageName: 'com.zhiliaoapp.musically', eventType: 1, timestampMs: 3500),
        (packageName: 'com.zhiliaoapp.musically', eventType: 2, timestampMs: 4000),
        (packageName: 'com.google.android.youtube', eventType: 1, timestampMs: 5000),
      ];
      final opens = tracking.countOpensByPackage(events);
      expect(opens['com.google.android.youtube'], 2);
      expect(opens['com.zhiliaoapp.musically'], 1);
      final apps = tracking.summarizeAllUsage({
        'com.google.android.youtube': 45 * 60000,
        'com.zhiliaoapp.musically': 20 * 60000,
      });
      expect(apps.first.usageDuration.inMinutes, 45);
      return 'YouTube: ${apps.first.usageDuration.inMinutes} min, opened '
          '${opens['com.google.android.youtube']} times; TikTok: 20 min, opened '
          '${opens['com.zhiliaoapp.musically']} time (a screen change inside '
          'TikTok is not a new open)';
    },
  );
}
