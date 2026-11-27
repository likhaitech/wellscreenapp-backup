import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/services/guardian_dashboard_text.dart';

void main() {
  Timestamp at(int minutes) =>
      Timestamp.fromMillisecondsSinceEpoch(minutes * 60000);

  test('lists only paired child devices, most recently active first', () {
    final records = [
      {'pairingStatus': 'connected', 'childEmail': 'a@x.com', 'lastSeenAt': at(10)},
      {'pairingStatus': 'waiting'}, // code made, no phone yet
      {'pairingStatus': 'connected', 'childEmail': 'b@x.com', 'lastSeenAt': at(500)},
      {'pairingStatus': 'unpaired'}, // phone removed
      {'pairingStatus': 'connected', 'usageReportUpdatedAt': at(200)},
    ];
    expect(connectedDeviceIndexes(records), [2, 4, 0]);
  });

  test('no paired devices gives an empty list', () {
    expect(connectedDeviceIndexes(const []), isEmpty);
    expect(
      connectedDeviceIndexes([
        {'pairingStatus': 'waiting'},
      ]),
      isEmpty,
    );
  });

  test('the dashboard follows the child the guardian picked', () {
    final ids = ['p1', 'p2', 'p3'];
    final records = [
      {'pairingStatus': 'connected', 'childEmail': 'a@x.com'},
      {'pairingStatus': 'connected', 'childEmail': 'b@x.com'},
      {'pairingStatus': 'unpaired'},
    ];
    expect(selectedChildIndex(ids, records, 'p2'), 1);
    // No pick yet: the dashboard uses its automatic choice.
    expect(selectedChildIndex(ids, records, null), -1);
    // Picked child was unpaired or removed: fall back to automatic choice.
    expect(selectedChildIndex(ids, records, 'p3'), -1);
    expect(selectedChildIndex(ids, records, 'gone'), -1);
  });

  test('popup text uses the dashboard wording', () {
    expect(connectedDevicesTitle, 'Connected Devices');
    expect(noConnectedDevices, 'No child device is connected yet.');
  });
}
