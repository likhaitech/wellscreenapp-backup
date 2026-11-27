/// Status text on the child's home screen (sync and Emergency Access).
/// Pure so it can be unit tested; ChildHomeScreen shows it.
class ChildStatusText {
  ChildStatusText._();

  static const String offline = 'Offline - will sync when reconnected';
  static const String requestSent =
      'Request sent - your parent has been notified.';
  static const String urgentApproved = 'Urgent Access Approved';

  /// The line under the Sync Usage button.
  static String syncIndicator({
    required bool isOnline,
    required String? lastOutcome,
    required int autoSyncMinutes,
  }) {
    if (!isOnline) return offline;
    if (lastOutcome == 'synced') {
      return 'Synced - auto-syncs every $autoSyncMinutes min';
    }
    if (lastOutcome == 'queued_offline' || lastOutcome == 'failed_timeout') {
      return 'Online - usage recovery will run automatically when scheduled.';
    }
    if (lastOutcome != null) {
      return 'Online - last sync failed. Tap Sync Usage to retry.';
    }
    return 'Auto-syncs every $autoSyncMinutes min';
  }

  /// "Synced just now" / "Synced 5m ago" from the newest successful sync.
  static String lastSync(List<Map<String, dynamic>> syncLog, DateTime now) {
    int? lastSyncedMs;
    for (final entry in syncLog.reversed) {
      final timestamp = entry['timestampMs'];
      if (entry['outcome'] == 'synced' && timestamp is int) {
        lastSyncedMs = timestamp;
        break;
      }
    }
    if (lastSyncedMs == null) return 'Not synced yet';
    final elapsed = now.difference(
      DateTime.fromMillisecondsSinceEpoch(lastSyncedMs),
    );
    if (elapsed.inMinutes < 1) return 'Synced just now';
    if (elapsed.inMinutes < 60) return 'Synced ${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return 'Synced ${elapsed.inHours}h ago';
    return 'Synced ${elapsed.inDays}d ago';
  }

  /// Reopening WellScreen syncs usage by itself unless a sync was tried
  /// within [minGap] (no tap on Sync usage needed).
  static bool shouldSyncOnReopen(
    DateTime? lastAttempt,
    DateTime now,
    Duration minGap,
  ) => lastAttempt == null || now.difference(lastAttempt) >= minGap;

  /// Title and line on the Emergency Access card for a request [status].
  static ({String title, String subtitle}) emergencyCard(String? status) =>
      switch (status) {
        'requested' => (
          title: 'Request Sent',
          subtitle: 'Waiting for your parent to respond',
        ),
        'denied' => (
          title: 'Need Urgent Access?',
          subtitle: 'Your last request was denied. You can ask again.',
        ),
        _ => (
          title: 'Need Urgent Access?',
          subtitle: 'Request temporary time from parent',
        ),
      };
}
