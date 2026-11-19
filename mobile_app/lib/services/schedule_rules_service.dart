import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/schedule_rules.dart';

/// Guardian side: reads and saves schedules in app_rules/{guardianUid}.
/// Only the guardian may write that document (firestore.rules).
class ScheduleRulesService {
  DocumentReference<Map<String, dynamic>> _ref() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please log in again.');
    return FirebaseFirestore.instance.collection('app_rules').doc(user.uid);
  }

  Future<ScheduleRules> fetch() async {
    final snapshot = await _ref().get(const GetOptions(source: Source.server));
    return ScheduleRules.fromMap(snapshot.data()?['schedules']);
  }

  Future<void> _merge(Map<String, Object?> schedules) async {
    final ref = _ref();
    await FirebaseFirestore.instance.runTransaction<void>((transaction) async {
      final snapshot = await transaction.get(ref);
      transaction.set(ref, {
        'parentId': ref.id,
        // Keep the existing app-rule schema valid on first creation.
        if (!snapshot.exists) ...{
          'rules': <Map<String, dynamic>>[],
          'monitoredCount': 0,
          'restrictedCount': 0,
        },
        'schedules': schedules,
        'schedulesUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> saveBedtime(ScheduleRules rules) =>
      _merge({'bedtime': rules.bedtimeMap()});

  Future<void> saveBreaks(ScheduleRules rules) =>
      _merge({'breaks': rules.breaksMap()});

  /// Starts focus now, using the server's clock for the start time.
  Future<void> startFocus(int minutes) => _merge({
    'focus': {
      'durationMinutes': minutes,
      'startedAt': FieldValue.serverTimestamp(),
    },
  });

  Future<void> endFocus() => _merge({
    'focus': {'durationMinutes': 0, 'startedAt': null},
  });
}
