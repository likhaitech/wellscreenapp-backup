import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/daily_goal.dart';

/// Keeps the admin's age-group rules (system_settings/global, written only
/// by the backend after a validated system patch) live on this phone, so a
/// patch shows up on guardian and child devices within seconds.
class SystemSettingsService {
  SystemSettingsService._();

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

  /// Safe to call more than once; needs a signed-in user (Firestore rules).
  static void start() {
    if (_sub != null || FirebaseAuth.instance.currentUser == null) return;
    _sub = FirebaseFirestore.instance
        .collection('system_settings')
        .doc('global')
        .snapshots()
        .listen(
          (snapshot) => AgeGroupRules.apply(snapshot.data()),
          onError: (Object error) {
            // Built-in manuscript values stay in use.
            debugPrint('Could not read system settings: $error');
            _sub = null;
          },
        );
  }

  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }
}
