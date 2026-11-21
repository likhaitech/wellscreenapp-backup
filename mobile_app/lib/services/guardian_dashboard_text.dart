/// Text and rules on the guardian's dashboard. Pure so they can be unit
/// tested; ParentDashboardScreen shows them.
library;

const String pairChildFirst = 'Pair a child account first';

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
