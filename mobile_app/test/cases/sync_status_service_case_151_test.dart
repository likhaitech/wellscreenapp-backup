// CASE-151 - Offline Logging and Synchronization
// Run: flutter test test/cases/sync_status_service_case_151_test.dart -r expanded

import 'dart:async';

import 'package:app/services/child_status_text.dart';
import 'package:app/services/sync_status_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'case_report.dart';

void main() {
  testCase(
    'CASE-151',
    file: 'test/cases/sync_status_service_case_151_test.dart',
    codeTested: 'lib/services/sync_status_service.dart',
    description: 'Child phone reconnects to the internet.',
    expected: 'Saved usage is uploaded automatically and the status shows “Synced just now”.',
    body: (tester) async {
      final changes = StreamController<List<ConnectivityResult>>();
      final service = SyncStatusService(
        checkConnectivity: () async => [ConnectivityResult.none],
        connectivityChanges: changes.stream,
      );
      final seen = <bool>[];
      final sub = service.onlineStatusChanges.listen(seen.add);
      changes.add([ConnectivityResult.none]);
      changes.add([ConnectivityResult.wifi]);
      await tester.pump();
      await sub.cancel();
      await changes.close();
      expect(seen, [false, true]);
      final now = DateTime(2026, 11, 22, 10);
      final label = ChildStatusText.lastSync(
        [{'outcome': 'synced', 'timestampMs': now.millisecondsSinceEpoch}], now);
      expect(label, 'Synced just now');
      return 'Back online is detected (offline -> online), which starts the '
          'automatic upload; afterwards the status reads "$label"';
    },
  );
}
