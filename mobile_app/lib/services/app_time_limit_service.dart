import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_time_limit.dart';
import 'app_time_limit_cloudflare_notifier.dart';

/// Parent-side editing and child-side local mirroring of per-app allowances.
///
/// The native WellScreenAccessibilityService enforces this service's local
/// cache while Accessibility and Usage Access permissions remain enabled.
///
/// Do NOT add time-limited packages to restricted_packages_json:
/// that key represents permanent restrictions, not daily time allowances.
class AppTimeLimitService {
  static const String nativeCacheKey = 'app_time_limits_json';

  CollectionReference<Map<String, dynamic>> _limitsCollection(String childId) {
    if (childId.trim().isEmpty) {
      throw ArgumentError.value(childId, 'childId', 'Child profile required');
    }

    return FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childId)
        .collection('app_time_limits');
  }

  Future<int?> readLimitMinutes({
    required String childProfileId,
    required String packageName,
  }) async {
    final doc = await _limitsCollection(childProfileId).doc(packageName).get();

    final data = doc.data();
    if (data == null) return null;

    final value = data['limitMinutes'];
    if (value is! num) return null;

    final minutes = value.toInt();
    return minutes >= 1 && minutes <= 1440 ? minutes : null;
  }

  Future<void> saveLimit({
    required String childProfileId,
    required String packageName,
    required String appName,
    required int minutes,
  }) async {
    if (minutes < 1 || minutes > 1440) {
      throw ArgumentError.value(minutes, 'minutes', 'Must be 1–1440');
    }

    if (packageName.trim().isEmpty || packageName.contains('/')) {
      throw ArgumentError.value(packageName, 'packageName', 'Invalid package');
    }

    final guardian = FirebaseAuth.instance.currentUser;
    if (guardian == null) {
      throw StateError('Please sign in again.');
    }

    // Client-side check for user-friendly errors.
    // Firestore Security Rules must still enforce authorization.
    final child = await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .get();

    if (!child.exists || child.data()?['parentId'] != guardian.uid) {
      throw StateError('Only the paired guardian can edit these limits.');
    }

    // STEP 1: Save the app time limit to Firebase Firestore.
    await _limitsCollection(childProfileId).doc(packageName).set({
      'packageName': packageName,
      'appName': appName,
      'limitMinutes': minutes,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // STEP 2: Request a notification through Cloudflare Workers.
    // This runs only after the Firestore save succeeds.
    //
    // Do not assign the result to a variable because the current notifier
    // method returns Future<void>, not Future<bool>.
    try {
      await AppTimeLimitCloudflareNotifier.notifyLimitSaved(
        childProfileId: childProfileId,
        packageName: packageName,
      );

      debugPrint(
        'App-limit Cloudflare notification request finished for $appName. '
        'Check notifier logs for FCM acceptance status.',
      );
    } catch (error) {
      // A notification failure must not undo or misreport a saved time limit.
      debugPrint('App limit saved, but notification request failed: $error');
    }
  }

  Future<void> removeLimit({
    required String childProfileId,
    required String packageName,
  }) async {
    final guardian = FirebaseAuth.instance.currentUser;
    if (guardian == null) {
      throw StateError('Please sign in again.');
    }

    final child = await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .get();

    if (!child.exists || child.data()?['parentId'] != guardian.uid) {
      throw StateError('Only the paired guardian can edit these limits.');
    }

    await _limitsCollection(childProfileId).doc(packageName).delete();
  }

  Stream<List<AppTimeLimit>> watchLimits(String childProfileId) {
    if (childProfileId.trim().isEmpty) {
      return Stream<List<AppTimeLimit>>.value(<AppTimeLimit>[]);
    }

    return _limitsCollection(childProfileId).snapshots().map(_decodeSnapshot);
  }

  /// Child-only stream: caches limits for native Android enforcement.
  ///
  /// The cache is tagged with the child profile ID to prevent applying
  /// one child's limits to a different account.
  Stream<List<AppTimeLimit>> watchForChildAndCache(String childProfileId) {
    return watchLimits(childProfileId).asyncMap((limits) async {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString(
        nativeCacheKey,
        jsonEncode({
          'childProfileId': childProfileId,
          'limits': limits.map((limit) => limit.toMap()).toList(),
        }),
      );

      await prefs.setString('active_child_profile_id', childProfileId);

      return limits;
    });
  }

  /// Keep the offline cache for the same child.
  /// Clear it when the active child profile changes.
  Future<void> prepareCacheForChild(String childProfileId) async {
    if (childProfileId.trim().isEmpty) {
      await clearCachedLimits();
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (prefs.getString('active_child_profile_id') != childProfileId) {
      await clearCachedLimits();
    }
  }

  /// Remove child-specific native rules when switching accounts.
  Future<void> clearCachedLimits() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('active_child_profile_id');
    await prefs.remove(nativeCacheKey);
  }

  static List<AppTimeLimit> _decodeSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final limits = <AppTimeLimit>[];

    for (final document in snapshot.docs) {
      try {
        limits.add(AppTimeLimit.fromMap(document.data()));
      } on FormatException {
        // Invalid records aren't enforced.
        // Never interpret invalid data as zero minutes.
      }
    }

    return limits;
  }
}
