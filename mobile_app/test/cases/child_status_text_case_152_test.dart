// CASE-152 - Offline Logging and Synchronization
// Run: flutter test test/cases/child_status_text_case_152_test.dart -r expanded

import 'package:app/services/child_status_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-152',
    file: 'test/cases/child_status_text_case_152_test.dart',
    codeTested: 'lib/screens/child_home_screen.dart',
    description: 'Child leaves WellScreen, uses apps, then reopens WellScreen.',
    expected: 'Usage syncs automatically when the app is reopened, without tapping Sync usage.',
    body: (tester) async {
      final now = DateTime(2026, 11, 22, 10, 30);
      const gap = Duration(minutes: 2);
      expect(ChildStatusText.shouldSyncOnReopen(DateTime(2026, 11, 22, 10, 10), now, gap), isTrue);
      expect(ChildStatusText.shouldSyncOnReopen(DateTime(2026, 11, 22, 10, 29, 30), now, gap), isFalse);
      return 'Reopened 20 min after the last sync: usage syncs by itself; '
          'reopened 30 s after a sync: no repeat';
    },
  );
}
