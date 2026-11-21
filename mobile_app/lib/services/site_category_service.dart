import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'adult_keyword_detector.dart';
import 'education_sites.dart';
import 'site_category_ml_classifier.dart';

/// A category match for a captured domain, tagging which existing mechanism
/// found it. A guardian allow rule suppresses category alerts for that domain.
class SiteCategoryMatch {
  const SiteCategoryMatch({
    required this.category,
    required this.source,
    this.confidence,
  });

  final String category;
  final String source; // 'lookup', 'keyword', or 'ml'
  final double? confidence;
}

enum WebsiteRuleAction { block, allow }

/// Domain-level guardian overrides. An allowed domain takes precedence over
/// a blocked domain and over the automatic detection mechanisms.
class WebsiteRules {
  const WebsiteRules({
    this.blockedDomains = const [],
    this.allowedDomains = const [],
  });

  final List<String> blockedDomains;
  final List<String> allowedDomains;

  static const int maxDomainsPerList = 200;
  static final RegExp _labelPattern = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
  );

  /// Accept a domain or HTTP(S) URL; keep only the normalized host.
  /// Paths, queries and fragments do not become separate rules. The usual
  /// www prefix is treated as the same site so a pasted URL is not missed.
  static String? normalizeDomain(String input) {
    final value = input.trim();
    if (value.isEmpty || RegExp(r'\s').hasMatch(value)) return null;

    final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        !uri.hasAuthority ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    var host = uri.host.toLowerCase();
    if (host.endsWith('.')) host = host.substring(0, host.length - 1);
    if (host.startsWith('www.')) host = host.substring(4);
    if (host.isEmpty || host.length > 253) return null;
    final labels = host.split('.');
    if (labels.length < 2 ||
        labels.any((label) => !_labelPattern.hasMatch(label)) ||
        !RegExp(r'[a-z]').hasMatch(labels.last)) {
      return null;
    }
    return host;
  }

  static List<String> _parseDomains(Object? raw) {
    if (raw is! List || raw.length > maxDomainsPerList) {
      throw const FormatException('Invalid website rule list.');
    }
    final domains = <String>{};
    for (final item in raw) {
      if (item is! String) {
        throw const FormatException('Invalid website domain.');
      }
      final normalized = normalizeDomain(item);
      if (normalized == null || normalized != item) {
        throw const FormatException('Invalid website domain.');
      }
      domains.add(normalized);
    }
    return domains.toList()..sort();
  }

  factory WebsiteRules.fromMap(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('Invalid website rules.');
    }
    return WebsiteRules(
      blockedDomains: _parseDomains(raw['blockedDomains']),
      allowedDomains: _parseDomains(raw['allowedDomains']),
    );
  }

  factory WebsiteRules.fromDocument(Map<String, dynamic>? data) {
    if (data == null || !data.containsKey('websiteRules')) {
      return const WebsiteRules();
    }
    return WebsiteRules.fromMap(data['websiteRules']);
  }

  Map<String, dynamic> toMap() => {
    'blockedDomains': blockedDomains,
    'allowedDomains': allowedDomains,
  };

  /// The guardian's own rule for exactly this site (www. ignored), or null.
  /// The rules after the guardian taps Block or Allow on [domain] (null
  /// removes the guardian's rule). Throws when a list would pass 200 sites.
  WebsiteRules withRule(String domain, WebsiteRuleAction? action) {
    final blocked = blockedDomains.toSet()..remove(domain);
    final allowed = allowedDomains.toSet()..remove(domain);
    if (action == WebsiteRuleAction.block) blocked.add(domain);
    if (action == WebsiteRuleAction.allow) allowed.add(domain);
    if (blocked.length > maxDomainsPerList ||
        allowed.length > maxDomainsPerList) {
      throw const FormatException('Maximum 200 websites per list.');
    }
    return WebsiteRules(
      blockedDomains: blocked.toList()..sort(),
      allowedDomains: allowed.toList()..sort(),
    );
  }

  WebsiteRuleAction? ruleFor(String domain) {
    final normalized = normalizeDomain(domain);
    if (normalized == null) return null;
    if (allowedDomains.contains(normalized)) return WebsiteRuleAction.allow;
    if (blockedDomains.contains(normalized)) return WebsiteRuleAction.block;
    return null;
  }

  bool isAllowed(String domain) {
    final normalized = normalizeDomain(domain);
    return normalized != null &&
        allowedDomains.any(
          (rule) => normalized == rule || normalized.endsWith('.$rule'),
        );
  }
}

/// On-device website classification and guardian override management.
///
/// The dataset, keyword detector and ML classifier retain their original
/// order and measured confidence thresholds. Native SiteBlocker uses the
/// same guardian overrides for real-time blocking; the Dart allow override
/// also prevents false harmful-site category alerts.
class SiteCategoryService {
  static const String _assetPath =
      'assets/site_categories/cleaned_site_categories.csv';
  static const String websiteRulesCacheKey = 'website_rules_json';

  static _WebsiteRulesSync? _websiteRulesSync;

  final SiteCategoryMlClassifier _mlClassifier = SiteCategoryMlClassifier();
  final AdultKeywordDetector _keywordDetector = AdultKeywordDetector();
  Map<String, String>? _domainToCategory;

  /// Start once per application process. AppRulesService already exists on
  /// both dashboards; this dedicated listener continues to follow the
  /// child's account even when the pairing/rules widgets are not visible.
  static void ensureWebsiteRulesSync() {
    if (_websiteRulesSync != null) return;
    try {
      _websiteRulesSync = _WebsiteRulesSync(
        FirebaseAuth.instance,
        FirebaseFirestore.instance,
      );
    } catch (error) {
      // Firebase may not be initialized in tests or at early startup.
      debugPrint('Website rules sync not started: $error');
    }
  }

  DocumentReference<Map<String, dynamic>> _guardianRef() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please log in again.');
    return FirebaseFirestore.instance.collection('app_rules').doc(user.uid);
  }

  /// Guardian edits use the server's current rules, never a stale UI cache.
  Future<WebsiteRules> fetchGuardianWebsiteRules() async {
    final snapshot = await _guardianRef().get(
      const GetOptions(source: Source.server),
    );
    return WebsiteRules.fromDocument(snapshot.data());
  }

  /// A transaction merges only the website-rule fields into app_rules.
  /// Passing null removes the exact domain from both lists.
  Future<WebsiteRules> updateGuardianWebsiteRule(
    String input,
    WebsiteRuleAction? action,
  ) async {
    final domain = WebsiteRules.normalizeDomain(input);
    if (domain == null) {
      throw const FormatException('Enter a valid website such as example.com.');
    }

    final ref = _guardianRef();
    return FirebaseFirestore.instance.runTransaction<WebsiteRules>((
      transaction,
    ) async {
      final snapshot = await transaction.get(ref);
      final previous = WebsiteRules.fromDocument(snapshot.data());
      final next = previous.withRule(domain, action);

      transaction.set(ref, {
        'parentId': ref.id,
        // Keep the existing app-rule schema valid on first creation.
        if (!snapshot.exists) ...{
          'rules': <Map<String, dynamic>>[],
          'monitoredCount': 0,
          'restrictedCount': 0,
        },
        'websiteRules': next.toMap(),
        'websiteRulesUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return next;
    });
  }

  static Future<WebsiteRules> _cachedChildRules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(websiteRulesCacheKey);
      if (raw == null) return const WebsiteRules();
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['parentId'] is! String ||
          (decoded['parentId'] as String).isEmpty ||
          decoded['childUid'] is! String ||
          (decoded['childUid'] as String).isEmpty) {
        return const WebsiteRules();
      }
      return WebsiteRules.fromMap(decoded);
    } catch (_) {
      // Do not bypass automatic detection when the cache cannot be read.
      return const WebsiteRules();
    }
  }

  Future<void> _ensureLoaded() async {
    if (_domainToCategory != null) return;

    final raw = await rootBundle.loadString(_assetPath);
    final lines = raw.split('\n');
    final map = <String, String>{};

    for (final line in lines.skip(1)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex == -1) continue;
      final domain = trimmed.substring(0, commaIndex);
      final category = trimmed.substring(commaIndex + 1);
      map[domain] = category;
    }
    _domainToCategory = map;
  }

  String? _lookupExact(String normalizedDomain) {
    final map = _domainToCategory!;
    final labels = normalizedDomain.split('.');
    for (var start = 0; start <= labels.length - 2; start++) {
      final candidate = labels.sublist(start).join('.');
      final category = map[candidate];
      if (category != null) return category;
    }
    return null;
  }

  Future<SiteCategoryMatch?> classify(String domain) async {
    final normalized = domain.trim().toLowerCase();

    // Explicit allow overrides lookup, keywords and ML. Custom block rules
    // are enforced natively without inventing a harmful-site category.
    final guardianRules = await _cachedChildRules();
    if (guardianRules.isAllowed(normalized)) return null;
    // Education and health sites are never flagged automatically, so a
    // child's school research on sex education or LGBT topics is not blocked.
    if (EducationSites.isProtected(normalized)) return null;

    await _ensureLoaded();
    final exactCategory = _lookupExact(normalized);
    if (exactCategory != null) {
      return SiteCategoryMatch(category: exactCategory, source: 'lookup');
    }

    if (_keywordDetector.matches(normalized)) {
      return const SiteCategoryMatch(category: 'adult', source: 'keyword');
    }

    final mlPrediction = await _mlClassifier.predict(normalized);
    if (mlPrediction != null && mlPrediction.meetsDeploymentBar) {
      return SiteCategoryMatch(
        category: mlPrediction.category,
        source: 'ml',
        confidence: mlPrediction.confidence,
      );
    }
    return null;
  }
}

/// Keeps custom website rules scoped to the authenticated child and its
/// current guardian. Server snapshots are authoritative; offline cache is
/// retained only for the same child/guardian. All writes are serialized.
class _WebsiteRulesSync {
  _WebsiteRulesSync(this._auth, this._firestore) {
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

  void _logError(Object error) {
    debugPrint('Website rules sync: $error');
  }

  void _enqueue(Future<void> Function() write) {
    _pendingWrites = _pendingWrites
        .then((_) => write())
        .catchError((Object error) => _logError(error));
  }

  Map<String, dynamic> _readCache(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(
        prefs.getString(SiteCategoryService.websiteRulesCacheKey) ?? '{}',
      );
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A malformed cache will be replaced by an authoritative snapshot.
    }
    return {};
  }

  Future<void> _writeCache(
    SharedPreferences prefs,
    String? uid,
    String? parentId,
    WebsiteRules rules,
  ) async {
    final saved = await prefs.setString(
      SiteCategoryService.websiteRulesCacheKey,
      jsonEncode({
        'childUid': uid ?? '',
        'parentId': parentId ?? '',
        ...rules.toMap(),
      }),
    );
    if (!saved) throw StateError('Could not persist website rules.');
  }

  void _onAuthChanged(User? user) {
    final uid = user?.uid;
    if (_seenAuth && uid == _uid) return;
    _seenAuth = true;
    _uid = uid;
    _parentId = null;
    _seenPairing = false;
    final authVersion = ++_authVersion;
    ++_rulesVersion;
    unawaited(_accountSub?.cancel());
    unawaited(_rulesSub?.cancel());
    _accountSub = null;
    _rulesSub = null;

    // Signing out or switching accounts keeps the phone's website rules;
    // only a confirmed unpair of the same child (or a new pairing) changes
    // them - see _onPairingChanged. Same policy as AppRulesService.
    if (uid == null) return;
    _accountSub = _firestore
        .collection('users')
        .doc(uid)
        .snapshots(includeMetadataChanges: true)
        .listen((snapshot) {
          if (authVersion != _authVersion ||
              snapshot.metadata.isFromCache ||
              snapshot.metadata.hasPendingWrites) {
            return;
          }
          final data = snapshot.data();
          final parent = data?['pairedParentId'];
          final profile = data?['pairedChildProfileId'];
          if (data?['role'] == 'child' &&
              data?['pairingStatus'] == 'connected' &&
              parent is String &&
              parent.isNotEmpty &&
              profile is String &&
              profile.isNotEmpty) {
            _onPairingChanged(uid, parent, true);
          } else {
            _onPairingChanged(uid, null, data?['role'] == 'child');
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
      final cached = _readCache(prefs);
      final cachedChild = cached['childUid'];
      if (parentId == null) {
        // Only the guardian removing THIS child's device releases the
        // phone; another unpaired account or a guardian keeps the rules.
        if (isChild && (cachedChild == null || cachedChild == uid)) {
          await _writeCache(prefs, uid, null, const WebsiteRules());
        }
      } else if (cachedChild != uid || cached['parentId'] != parentId) {
        await _writeCache(prefs, uid, parentId, const WebsiteRules());
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
          _enqueue(() async {
            final prefs = await SharedPreferences.getInstance();
            if (version != _rulesVersion) return;
            // Missing server document/field means no custom rules; malformed
            // data throws instead of erasing the last valid rule set.
            final rules = WebsiteRules.fromDocument(snapshot.data());
            await _writeCache(prefs, uid, parentId, rules);
          });
        }, onError: _logError);
  }
}
