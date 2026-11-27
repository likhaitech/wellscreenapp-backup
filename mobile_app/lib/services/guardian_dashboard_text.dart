/// Text and rules on the guardian's dashboard. Pure so they can be unit
/// tested; ParentDashboardScreen shows them.
library;

import '../utils/primary_child.dart';

const String pairChildFirst = 'Pair a child account first';

/// Title of the popup that opens when the guardian taps the child card.
const String connectedDevicesTitle = 'Connected Devices';
const String noConnectedDevices = 'No child device is connected yet.';
const String switchChildHint = 'Tap a child to view their dashboard.';

/// Index of the child the guardian picked in the popup, or -1 when there is
/// no pick or the picked child is gone or no longer paired (then the
/// dashboard falls back to the most recently active child).
int selectedChildIndex(
  List<String> ids,
  List<Map<String, dynamic>> records,
  String? selectedId,
) {
  if (selectedId == null || selectedId.isEmpty) return -1;
  final index = ids.indexOf(selectedId);
  if (index < 0 || !childLooksConnected(records[index])) return -1;
  return index;
}

/// Indexes of the paired child devices in [records], most recently active
/// first. Each child_profiles record is one paired child phone; records that
/// are waiting for pairing or were unpaired are left out.
List<int> connectedDeviceIndexes(List<Map<String, dynamic>> records) {
  final indexes = [
    for (var i = 0; i < records.length; i++)
      if (childLooksConnected(records[i])) i,
  ];
  indexes.sort(
    (a, b) => lastActivityMs(records[b]).compareTo(lastActivityMs(records[a])),
  );
  return indexes;
}

/// True when a child record is set up (paired, or has a child account).
bool childLooksConnected(Map<String, dynamic> data) {
  final pairingStatus = (data['pairingStatus'] ?? '').toString();
  final childEmail = (data['childEmail'] ?? '').toString();
  final childAccountId = (data['childAccountId'] ?? '').toString();
  return pairingStatus == 'connected' ||
      childEmail.isNotEmpty ||
      childAccountId.isNotEmpty;
}

/// The protection pills under the child card, in order.
List<String> protectionStatusLabels(Map<String, dynamic> child) => [
  child['accessibilityEnabled'] == false ? 'Blocking off' : 'Protection on',
  if (child['usageAccessEnabled'] == false) 'Usage Access off',
  if (child['smsPermissionGranted'] == false) 'SMS backup off',
];

/// Emergency Access: the guardian may approve any time from 1 to 120 min.
const int maxEmergencyMinutes = 120;

bool isValidEmergencyMinutes(int minutes) =>
    minutes >= 1 && minutes <= maxEmergencyMinutes;

/// The quick choices on the approve sheet, including what the child asked.
List<int> emergencyMinuteChoices(int? askedMinutes) =>
    <int>{5, 10, 15, 30, 45, 60, 90, 120, ?askedMinutes}
        .where((m) => m > 0 && m <= maxEmergencyMinutes)
        .toList()
      ..sort();

String askedForLabel(int minutes) => 'Asked for $minutes min';
