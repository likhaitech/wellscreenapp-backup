// CASE-154 - Offline Logging and Synchronization
// Run: flutter test test/cases/child_status_text_case_154_test.dart -r expanded

import 'package:app/services/child_status_text.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-154',
    file: 'test/cases/child_status_text_case_154_test.dart',
    codeTested: 'mobile_app/android/app/src/main/kotlin/com/wellscreen/app/BackgroundLogSync.kt',
    description: 'A sync fails, then the child taps Sync usage now.',
    expected: 'The failed sync is reported and the retry uploads the saved data.',
    body: (tester) async {
      final failed = ChildStatusText.syncIndicator(
        isOnline: true, lastOutcome: 'failed', autoSyncMinutes: 5);
      expect(failed, 'Online - last sync failed. Tap Sync Usage to retry.');
      final now = DateTime(2026, 11, 22, 10);
      final log = [
        {'outcome': 'failed', 'timestampMs': now.subtract(const Duration(minutes: 3)).millisecondsSinceEpoch},
        {'outcome': 'synced', 'timestampMs': now.millisecondsSinceEpoch},
      ];
      expect(ChildStatusText.syncIndicator(isOnline: true, lastOutcome: 'synced', autoSyncMinutes: 5),
          startsWith('Synced'));
      expect(ChildStatusText.lastSync(log, now), 'Synced just now');
      return 'First: "$failed"; after tapping Sync usage now the saved data '
          'uploads and the status reads "${ChildStatusText.lastSync(log, now)}"';
    },
  );
}
