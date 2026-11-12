import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_rule.dart';

class AppRulesService {
  static const String _rulesKey = 'app_rules_json';
  static const String _restrictedPackagesKey = 'restricted_packages_json';

  Future<List<AppRule>> getRules() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rulesKey);

    if (raw == null || raw.trim().isEmpty) {
      return [];
    }

    try {
      final List decoded = jsonDecode(raw);
      return decoded
          .map((item) => AppRule.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Parent side: Firestore is authoritative for editing the complete rules
  /// array. The local cache is a fallback only when the cloud read fails.
  Future<List<AppRule>> fetchCurrentRules() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return getRules();
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('app_rules')
          .doc(user.uid)
          .get();

      final rawRules = snapshot.data()?['rules'];

      if (rawRules is! List) {
        return await getRules();
      }

      final rules = rawRules
          .map((item) => AppRule.fromMap(Map<String, dynamic>.from(item)))
          .toList();

      await saveRulesLocally(rules);
      return rules;
    } catch (_) {
      return getRules();
    }
  }

  Future<void> saveRules(List<AppRule> rules) async {
    await saveRulesLocally(rules);
    await syncRulesToFirestore(rules);
  }

  Future<void> saveRulesLocally(List<AppRule> rules) async {
    final prefs = await SharedPreferences.getInstance();

    final encodedRules = jsonEncode(rules.map((rule) => rule.toMap()).toList());

    final restrictedPackages = rules
        .where((rule) => rule.restrictEnabled)
        .map((rule) => rule.packageName)
        .where((packageName) => packageName.trim().isNotEmpty)
        .toSet()
        .toList();

    // Write the native enforcement cache first. Android's AccessibilityService
    // reads flutter.restricted_packages_json even while Firestore is offline.
    // An intentionally empty, authoritative rules list still writes "[]".
    final restrictionsSaved = await prefs.setString(
      _restrictedPackagesKey,
      jsonEncode(restrictedPackages),
    );
    if (!restrictionsSaved) {
      throw StateError('Failed to persist restricted packages on this device');
    }

    final rulesSaved = await prefs.setString(_rulesKey, encodedRules);
    if (!rulesSaved) {
      throw StateError('Failed to persist app rules on this device');
    }
  }

  Future<void> syncRulesToFirestore(List<AppRule> rules) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    final monitoredRules = rules.where((rule) => rule.monitorEnabled).toList();
    final restrictedRules = rules
        .where((rule) => rule.restrictEnabled)
        .toList();

    await FirebaseFirestore.instance.collection('app_rules').doc(user.uid).set({
      'parentId': user.uid,
      'rules': rules.map((rule) => rule.toMap()).toList(),
      'monitoredCount': monitoredRules.length,
      'restrictedCount': restrictedRules.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Child side: mirror *validated* parent rules into the native offline
  /// cache. Do not erase restrictions merely because a Firestore snapshot is
  /// temporarily missing from the local cache while the phone is offline.
  ///
  /// A confirmed missing server document or an explicit, valid [] does
  /// clear restrictions. Those are the parent's authoritative removals.
  Stream<List<AppRule>> watchRulesForParent(String parentId) {
    if (parentId.trim().isEmpty) {
      return Stream.value([]);
    }

    return FirebaseFirestore.instance
        .collection('app_rules')
        .doc(parentId)
        // A metadata-only change from local cache -> confirmed server result
        // must be observed so actual server-side deletions can take effect.
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snapshot) async {
          if (!snapshot.exists) {
            if (snapshot.metadata.isFromCache) {
              // Unknown while offline: keep the last successfully synced
              // restrictions rather than accidentally unlocking apps.
              return await getRules();
            }
            // Confirmed absent from the server: parent has no saved rules.
            await saveRulesLocally([]);
            return <AppRule>[];
          }

          final rawRules = snapshot.data()?['rules'];
          if (rawRules is! List) {
            // Absent or malformed rules field is NOT the same as an explicit
            // empty list. Keep the last valid copy until it is corrected.
            return await getRules();
          }

          final List<AppRule> rules;
          try {
            rules = rawRules
                .map((item) => AppRule.fromMap(Map<String, dynamic>.from(item)))
                .toList();
          } catch (_) {
            // Never clear native restrictions because a transient or
            // malformed snapshot could not be decoded.
            return await getRules();
          }

          await saveRulesLocally(rules);
          return rules;
        });
  }

  Future<void> upsertRule(AppRule rule) async {
    final rules = await getRules();

    final index = rules.indexWhere(
      (item) => item.packageName == rule.packageName,
    );

    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }

    await saveRules(rules);
  }

  Future<void> removeRule(String packageName) async {
    final rules = await getRules();

    rules.removeWhere((rule) => rule.packageName == packageName);

    await saveRules(rules);
  }

  Future<void> clearRules() async {
    await saveRulesLocally([]);

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return;
    }

    await FirebaseFirestore.instance.collection('app_rules').doc(user.uid).set({
      'parentId': user.uid,
      'rules': [],
      'monitoredCount': 0,
      'restrictedCount': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
