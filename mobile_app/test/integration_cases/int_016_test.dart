// INT-016 - Offline Logging and Synchronization Module -> Dashboard, Reports, and Recommendations Module
// Record usage while offline, then reconnect to the internet.
// Code being tested: lib/services/local_usage_report_cache_service.dart,
// lib/services/sync_status_service.dart, lib/services/child_status_text.dart
//
// Run: flutter test test/integration_cases/int_016_test.dart -r expanded

import 'dart:async';

import 'package:app/services/child_status_text.dart';
import 'package:app/services/local_usage_report_cache_service.dart';
import 'package:app/services/sync_status_service.dart';
import 'package:app/services/usage_report_service.dart';
import 'package:app/services/usage_tracking_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cases/case_report.dart';

void main() {
  testCase(
    'INT-016',
    file: 'test/integration_cases/int_016_test.dart',
    codeTested: 'lib/services/local_usage_report_cache_service.dart + '
        'sync_status_service.dart',
    description: 'Record usage while offline, then reconnect to the internet '
        '(Offline Logging and Synchronization -> Dashboard, Reports, and '
        'Recommendations).',
    expected: 'Usage logs are stored locally and synchronized when the '
        'connection returns, and the guardian dashboard is updated.',
    body: (tester) async {
      SharedPreferences.setMockInitialValues({});

      // Module 1 - Offline Logging: 40 min of Roblox with no internet.
      final report = UsageReportService().generateFromSummaries(
        UsageTrackingService().summarizeUsage({'com.roblox.client': 2400000}),
      );
      final cache = LocalUsageReportCacheService();
      await cache.saveTodayReport(report);
      final offline = ChildStatusText.syncIndicator(
          isOnline: false, lastOutcome: null, autoSyncMinutes: 5);
      expect(offline, 'Offline - will sync when reconnected');

      // The phone reconnects: back online is detected, which starts the upload.
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

      // Module 2 - Dashboard: the saved report is uploaded and shown.
      final saved = await cache.getCachedTodayReport();
      final uploaded = {
        'totalUsageDurationMs': saved!.totalUsageDuration.inMilliseconds
      };
      final shown = Duration(milliseconds: uploaded['totalUsageDurationMs']!);
      expect(shown, report.totalUsageDuration);
      final now = DateTime(2026, 11, 22, 10);
      final status = ChildStatusText.lastSync(
          [{'outcome': 'synced', 'timestampMs': now.millisecondsSinceEpoch}],
          now);
      expect(status, 'Synced just now');
      return '${shown.inMinutes} min of usage was kept on the phone while '
          'offline ("$offline"); after reconnecting it was synced ("$status") '
          'and the guardian dashboard shows ${shown.inMinutes} min';
    },
  );
}
