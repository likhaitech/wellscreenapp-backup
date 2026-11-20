import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/utils/primary_child.dart';

void main() {
  bool looksConnected(Map<String, dynamic> d) =>
      d['pairingStatus'] == 'connected' || (d['childEmail'] ?? '') != '';

  Timestamp at(int minutes) =>
      Timestamp.fromMillisecondsSinceEpoch(minutes * 60000);

  test('opens the connected child that was active most recently', () {
    final records = [
      {'pairingStatus': 'connected', 'lastSeenAt': at(10)}, // old phone
      {'pairingStatus': 'connected', 'lastSeenAt': at(500)}, // phone in use
      {'pairingStatus': 'connected', 'usageReportUpdatedAt': at(200)},
    ];
    expect(pickPrimaryChildIndex(records, looksConnected), 1);
  });

  test('a connected record beats an unpaired one with newer activity', () {
    final records = [
      {'pairingStatus': 'unpaired', 'childEmail': 'a@x.com', 'lastSeenAt': at(900)},
      {'pairingStatus': 'connected', 'lastSeenAt': at(5)},
    ];
    expect(pickPrimaryChildIndex(records, looksConnected), 1);
  });

  test('no records gives -1; one record gives 0', () {
    expect(pickPrimaryChildIndex(const [], looksConnected), -1);
    expect(pickPrimaryChildIndex([{'pairingStatus': 'pending'}], looksConnected), 0);
  });
}
