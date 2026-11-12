import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

/// On the child device, mirrors server-approved grants into the existing
/// native SharedPreferences store. The native AccessibilityService verifies
/// exact package and expiration even when Flutter is not running.
/// Parent's permanent restrictions are NEVER changed by this service.
class TemporaryAppGrantService {
  static const String cacheKey = 'temporary_access_grants_json';
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _profileId;
  final Set<String> _activating = <String>{};

  Future<void> startForChild(String childProfileId) async {
    if (childProfileId.trim().isEmpty ||
        FirebaseAuth.instance.currentUser == null) {
      return;
    }
    if (_profileId == childProfileId && _subscription != null) return;
    await stop();
    _profileId = childProfileId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_child_profile_id', childProfileId);
    // Firestore's Android persistence delivers the latest approved grant and
    // reconnects automatically; no manual Sync Usage button is involved.
    _subscription = FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .collection('temporary_access_grants')
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          unawaited(_handleSnapshot(childProfileId, snapshot));
        }, onError: (Object error) {
          debugPrint('Temporary grant listener failed: $error');
        });
  }

  Future<void> _handleSnapshot(
    String profileId,
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (_profileId != profileId) return;
    final prefs = await SharedPreferences.getInstance();
    // An empty offline cache is not proof that the server revoked a grant.
    // Preserve the last local snapshot; Android still enforces its expiry.
    if (snapshot.metadata.isFromCache && snapshot.docs.isEmpty) return;
    if (prefs.getString('active_child_profile_id') != profileId) {
      // Never mirror a grant under the wrong child's enforcement identity.
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final grants = <Map<String, Object>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final pkg = data['packageName'];
      final state = data['state'];
      final until = data['expiresAt'];
      if (pkg is! String || pkg.isEmpty) continue;
      if (state == 'active' && until is Timestamp &&
          until.millisecondsSinceEpoch > now &&
          until.millisecondsSinceEpoch - now <= 180 * 60000) {
        grants.add({
          'packageName': pkg,
          'state': 'active',
          'expiresAtMs': until.millisecondsSinceEpoch,
        });
      } else if (state == 'pending_activation' && !snapshot.metadata.isFromCache) {
        // Activate only from a server-confirmed approval, never from local
        // pending writes or an unverified client-side status.
        unawaited(_activate(profileId, pkg));
      }
    }
    if (_profileId != profileId) return;
    await prefs.setString(cacheKey, jsonEncode({
      'childProfileId': profileId,
      'grants': grants,
    }));
  }

  Future<void> _activate(String profileId, String packageName) async {
    if (!_activating.add(packageName)) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _profileId != profileId) return;
      final token = await user.getIdToken();
      await Dio().post<Object?>(
        '${AppConfig.backendBaseUrl}/chat/grants/$profileId/$packageName/activate',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      // The authoritative Firestore stream will deliver the expiry, which is
      // then cached to Android. Never locally invent an expiry on HTTP success.
    } catch (error) {
      // Reconnection / subsequent snapshot / screen reopen retries activation.
      debugPrint('Temporary grant activation deferred: $error');
    } finally {
      _activating.remove(packageName);
    }
  }

  Future<void> detach() async {
    _profileId = null;
    await _subscription?.cancel();
    _subscription = null;
    // Keep last approved grant when Flutter goes away; Android independently
    // expires it. Logout uses stop(), which clears the cache.
  }

  Future<void> stop() async {
    await detach();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(cacheKey);
  }
}
