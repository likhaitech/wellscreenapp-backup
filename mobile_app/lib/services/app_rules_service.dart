import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_rule.dart';
import 'site_category_service.dart';

class AppRulesService {
  // The child dashboard already creates this service when it opens.
  // Initialize the independent account/pairing-aware website-rule mirror
  // without requiring edits to the protected dashboard screens.
  AppRulesService() {
    SiteCategoryService.ensureWebsiteRulesSync();
    // Keep manual restrictions synchronized even when the child navigates
    // away from the dashboard's Active App Rules widget.
    _ensureChildRulesSync();
  }

  static const String _rulesKey = 'app_rules_json';
  static const String _restrictedPackagesKey = 'restricted_packages_json';
  static const String _childRuleScopeKey = 'app_rules_child_scope_json';
  static _ChildAppRulesSync? _childRulesSync;

  static void _ensureChildRulesSync() {
    if (_childRulesSync != null) return;
    try {
      _childRulesSync = _ChildAppRulesSync(
        FirebaseAuth.instance,
        FirebaseFirestore.instance,
      );
    } catch (error) {
      // Firebase is deliberately absent in the local cache unit tests.
      debugPrint('App rules sync not started: $error');
    }
  }

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
    await _writeRulesLocally(prefs, rules);
  }

  static Future<void> _writeRulesLocally(
    SharedPreferences prefs,
    List<AppRule> rules,
  ) async {
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

  /// UI-only stream. The independent child sync owns native cache writes,
  /// preventing a rebuilt widget's stale offline snapshot from undoing a
  /// more recent guardian restriction.
  Stream<List<AppRule>> watchRulesForParent(String parentId) {
    if (parentId.trim().isEmpty) {
      return Stream.value([]);
    }

    return FirebaseFirestore.instance
        .collection('app_rules')
        .doc(parentId)
        .snapshots(includeMetadataChanges: true)
        .asyncMap((snapshot) async {
          if (snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites) {
            return await getRules();
          }
          return _decodeConfirmedRules(snapshot) ?? await getRules();
        });
  }

  /// Null means unknown/malformed, not an authoritative empty rule list.
  static List<AppRule>? _decodeConfirmedRules(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return <AppRule>[];
    final raw = snapshot.data()?['rules'];
    if (raw is! List) return null;
    try {
      return raw.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        if (map['packageName'] is! String ||
            (map['packageName'] as String).trim().isEmpty ||
            map['restrictEnabled'] is! bool) {
          throw const FormatException('Invalid app rule');
        }
        return AppRule.fromMap(map);
      }).toList();
    } catch (_) {
      return null;
    }
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

/// One independent account/pairing-aware listener per Flutter process.
/// Android keeps enforcing the last confirmed cache when the child is offline.
class _ChildAppRulesSync {
  _ChildAppRulesSync(this._auth, this._firestore) {
    _auth.authStateChanges().listen(_onAuthChanged, onError: _logError);
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _accountSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _rulesSub;
  String? _uid;
  String? _parentId;
  bool _seenAuth = false;
  bool _seenPairing = false;
  int _authVersion = 0;
  int _rulesVersion = 0;
  Future<void> _pendingWrites = Future<void>.value();

  void _logError(Object error) => debugPrint('App rules sync: $error');

  void _enqueue(Future<void> Function() write) {
    _pendingWrites = _pendingWrites
        .then((_) => write())
        .catchError((Object error) => _logError(error));
  }

  Map<String, dynamic> _scope(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(
        prefs.getString(AppRulesService._childRuleScopeKey) ?? '{}',
      );
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Replaced by a confirmed pairing.
    }
    return {};
  }

  Future<void> _clearChildCache(SharedPreferences prefs) async {
    await AppRulesService._writeRulesLocally(prefs, <AppRule>[]);
    await prefs.remove(AppRulesService._childRuleScopeKey);
  }

  void _onAuthChanged(User? user) {
    final uid = user?.uid;
    if (_seenAuth && uid == _uid) return;
    final previousUid = _uid;
    _seenAuth = true;
    _uid = uid;
    _parentId = null;
    _seenPairing = false;
    final version = ++_authVersion;
    ++_rulesVersion;
    unawaited(_accountSub?.cancel());
    unawaited(_rulesSub?.cancel());
    _accountSub = null;
    _rulesSub = null;

    _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      if (version != _authVersion) return;
      final scope = _scope(prefs);
      if (uid == null ||
          (previousUid != null && previousUid != uid) ||
          (scope.isNotEmpty && scope['childUid'] != uid)) {
        await _clearChildCache(prefs);
      }
    });

    if (uid == null) return;
    _accountSub = _firestore
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          if (version != _authVersion ||
              snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites) {
            return;
          }
          final data = snapshot.data();
          final parent = data?['pairedParentId'];
          final profile = data?['pairedChildProfileId'];
          final isChild = data?['role'] == 'child';
          if (isChild &&
              data?['pairingStatus'] == 'connected' &&
              parent is String &&
              parent.isNotEmpty &&
              profile is String &&
              profile.isNotEmpty) {
            _onPairingChanged(uid, parent, true);
          } else {
            _onPairingChanged(uid, null, isChild);
          }
        }, onError: _logError);
  }

  void _onPairingChanged(String uid, String? parentId, bool isChild) {
    if (_seenPairing && parentId == _parentId) return;
    _seenPairing = true;
    _parentId = parentId;
    final version = ++_rulesVersion;
    unawaited(_rulesSub?.cancel());
    _rulesSub = null;

    _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      if (version != _rulesVersion) return;
      final scope = _scope(prefs);
      if (parentId == null) {
        // Never wipe the guardian's own editor cache on an ordinary login.
        if (isChild || scope.isNotEmpty) await _clearChildCache(prefs);
      } else if (scope.isNotEmpty &&
          (scope['childUid'] != uid || scope['parentId'] != parentId)) {
        await _clearChildCache(prefs);
      }
    });

    if (parentId == null) return;
    _rulesSub = _firestore
        .collection('app_rules')
        .doc(parentId)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          if (version != _rulesVersion ||
              snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites) {
            return;
          }
          final rules = AppRulesService._decodeConfirmedRules(snapshot);
          if (rules == null) {
            debugPrint('App rules sync: malformed rules; retaining cache');
            return;
          }
          _enqueue(() async {
            final prefs = await SharedPreferences.getInstance();
            if (version != _rulesVersion) return;
            await AppRulesService._writeRulesLocally(prefs, rules);
            final saved = await prefs.setString(
              AppRulesService._childRuleScopeKey,
              jsonEncode({'childUid': uid, 'parentId': parentId}),
            );
            if (!saved) throw StateError('Could not persist app rule scope');
            debugPrint(
              'App rules synced: '
              '${rules.where((rule) => rule.restrictEnabled).length} restricted apps',
            );
          });
        }, onError: _logError);
  }
}
