import 'package:app/widgets/admin_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('log actions read as words', () {
    expect(adminActionTitle('system_patch_applied'), 'System patch applied');
    expect(adminActionTitle(null), 'Unknown action');
  });

  test('logs are grouped by day', () {
    final now = DateTime(2026, 11, 21, 6, 0);
    Timestamp at(DateTime d) => Timestamp.fromDate(d);
    expect(adminLogDay(at(DateTime(2026, 11, 21, 5, 12)), now: now), 'Today');
    expect(adminLogDay(at(DateTime(2026, 11, 20, 21, 40)), now: now), 'Yesterday');
    expect(adminLogDay(at(DateTime(2026, 11, 18, 9, 0)), now: now), '18 Nov 2026');
    expect(adminLogDay(null, now: now), 'Earlier');
  });

  test('log level colours', () {
    expect(adminLogKind({'level': 'error'}).$1, 'Error');
    expect(adminLogKind({'level': 'warning'}).$1, 'Warning');
    expect(adminLogKind({'level': 'info', 'action': 'usage_sync'}).$1, 'Sync');
    expect(adminLogKind({'level': 'info', 'action': 'user_updated'}).$1, 'Activity');
  });
}
