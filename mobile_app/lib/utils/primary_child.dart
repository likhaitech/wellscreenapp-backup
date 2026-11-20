import 'package:cloud_firestore/cloud_firestore.dart';

/// Which of a guardian's child records the dashboard, Reports and Chat open.
///
/// A guardian can end up with several child records (re-pairing a phone,
/// test devices). The old rule took the FIRST one that looked connected,
/// so Reports could show an old record that no phone uploads to any more.
/// Now: records with pairingStatus "connected" first, and among those the
/// one with the most recent activity (lastSeenAt or usageReportUpdatedAt).
int lastActivityMs(Map<String, dynamic> data) {
  int ms(Object? value) => value is Timestamp ? value.millisecondsSinceEpoch : 0;
  final seen = ms(data['lastSeenAt']);
  final usage = ms(data['usageReportUpdatedAt']);
  return seen > usage ? seen : usage;
}

/// Index of the record to open in [records], or -1 when there are none.
/// [looksConnected] is the dashboard's existing "is this child set up" test.
int pickPrimaryChildIndex(
  List<Map<String, dynamic>> records,
  bool Function(Map<String, dynamic>) looksConnected,
) {
  if (records.isEmpty) return -1;
  int best = -1;
  int rank(Map<String, dynamic> data) {
    if (data['pairingStatus'] == 'connected') return 2;
    return looksConnected(data) ? 1 : 0;
  }

  for (var i = 0; i < records.length; i++) {
    if (best == -1) {
      best = i;
      continue;
    }
    final a = records[i];
    final b = records[best];
    final ra = rank(a);
    final rb = rank(b);
    if (ra > rb || (ra == rb && lastActivityMs(a) > lastActivityMs(b))) {
      best = i;
    }
  }
  return best;
}
