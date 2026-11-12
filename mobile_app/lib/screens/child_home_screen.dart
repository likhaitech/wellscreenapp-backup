import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_rule.dart';
import '../models/app_time_limit.dart';
import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import '../services/alert_notification_client.dart';
import '../services/monitoring_usage_alert_service.dart';
import '../services/installed_app_metadata_service.dart';
import '../services/app_rules_service.dart';
import '../services/app_time_limit_service.dart';
import '../services/app_time_limit_notification_service.dart';
import '../services/daily_screen_time_limit_service.dart';
import '../services/emergency_access_service.dart';
import '../services/ml_risk_classifier_service.dart';
import '../services/site_category_service.dart';
import '../services/sync_status_service.dart';
import '../services/usage_dashboard_controller_service.dart';
import '../services/usage_tracking_service.dart';
import '../services/temporary_app_grant_service.dart';
import '../services/chat_notifications_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_bottom_nav.dart';
import 'capture_debug_screen.dart';
import 'login_screen.dart';
import 'parent_child_chat_screen.dart';
import 'chat_notifications_screen.dart';
import 'profile_settings_screen.dart';
import 'qr_scan_screen.dart';

/// Thrown by [_ChildHomeScreenState._getCurrentPositionOrThrow] specifically
/// when Android's device-wide location services (GPS) are off - as opposed
/// to a permission problem, which is a separate, differently-handled case.
/// Its own type (rather than a generic Exception matched by string) lets
/// both the manual share flow and the periodic auto-share flow react to
/// this one case distinctly: the manual flow prompts to open Settings, the
/// silent auto flow only raises the passive banner in _gpsCard() instead of
/// interrupting whatever the user is doing.
class LocationServicesDisabledException implements Exception {
  @override
  String toString() => 'Location services are turned off on this device.';
}

class ChildHomeScreen extends StatefulWidget {
  const ChildHomeScreen({super.key});

  @override
  State<ChildHomeScreen> createState() => _ChildHomeScreenState();
}

class _ChildHomeScreenState extends State<ChildHomeScreen>
    with WidgetsBindingObserver {
  // Aliased onto the shared AppColors palette (theme/app_theme.dart) - see
  // the matching comment in parent_dashboard_screen.dart. softRed has no
  // AppColors equivalent for "red but softer than dangerBg", so it stays a
  // local literal for now (used in exactly one place - the SMS failure
  // banner below).
  static const Color purple = AppColors.primary;
  static const Color deepPurple = AppColors.primaryDark;
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;
  static const Color softGreen = AppColors.successBg;
  static const Color softBlue = AppColors.infoBg;
  static const Color softRed = Color(0xFFFFEFEF);

  // Used by handleBottomNavTap to scroll to the existing pairing section
  // when a child device has not yet been connected to a parent.
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _pairingSectionKey = GlobalKey();

  final AppRulesService _rulesService = AppRulesService();
  final AppTimeLimitService _appTimeLimitService = AppTimeLimitService();
  final AppTimeLimitNotificationService _limitNotifications =
      AppTimeLimitNotificationService.instance;
  StreamSubscription<List<AppTimeLimit>>? _appTimeLimitSubscription;
  String? _timeLimitProfileId;
  int _timeLimitWatchGeneration = 0;
  final UsageTrackingService _usageTrackingService = UsageTrackingService();
  final AlertNotificationClient _alertNotificationClient =
      AlertNotificationClient();
  final MonitoringUsageAlertService _monitoringUsageAlerts =
      const MonitoringUsageAlertService();
  final UsageDashboardControllerService _usageDashboardController =
      UsageDashboardControllerService();
  final SyncStatusService _syncStatusService = SyncStatusService();
  final MlRiskClassifierService _mlRiskClassifierService =
      MlRiskClassifierService();
  final SiteCategoryService _siteCategoryService = SiteCategoryService();
  final DailyScreenTimeLimitService _dailyScreenTimeLimitService =
      DailyScreenTimeLimitService();
  final EmergencyAccessService _emergencyAccessService =
      EmergencyAccessService();
  final TemporaryAppGrantService _temporaryGrants = TemporaryAppGrantService();
  final pairingCodeController = TextEditingController();
  final emergencyReasonController = TextEditingController();
  StreamSubscription<bool>? _connectivitySubscription;
  Timer? _presenceHeartbeatTimer;
  DateTime? _lastPresenceWriteAttempt;
  static const Duration _presenceHeartbeatInterval = Duration(minutes: 5);

  int currentIndex = 0;
  bool isPairing = false;
  bool isSharingLocation = false;
  bool isSyncingUsage = false;
  bool isRequestingEmergencyAccess = false;

  // Real local usage data loaded via UsageDashboardControllerService, which
  // wraps UsageTrackingService (Android UsageStats), PatternDetectionService
  // and ScreenTimeGoalService. This layer already existed in the codebase
  // (usage_dashboard_controller_service.dart etc.) but nothing imported it
  // from any screen, so this card was showing hardcoded "4h 25m" / "Low
  // Risk" / "32/100" placeholders instead. See BRANCH_REAUDIT for details.
  UsageDashboardControllerState? _usageDashboardState;
  bool _loadingUsageDashboard = true;

  // SMS backup-alert status (see SmsAlertSender.kt). The actual sending
  // happens natively in WellScreenAccessibilityService when a restricted
  // app is blocked - this state is just what the Flutter UI needs to show
  // whether that's actually wired up (permission granted + a parent phone
  // number cached) and a log of what's happened so far.
  bool _smsPermissionGranted = false;
  String? _cachedParentPhoneNumber;
  List<Map<String, dynamic>> _smsAlertLog = [];
  String? _syncedParentIdForPhoneNumber;

  // Synchronization status (see SyncStatusService / _attemptFirestoreSync
  // below). cloud_firestore's set()/update() Futures hang indefinitely when
  // offline instead of throwing (firebase/flutterfire#17643) - this state
  // tracks real online/offline status and a log of what actually happened
  // on each sync attempt (synced / queued_offline / failed_timeout), not
  // just whether the sync button was tapped.
  bool _isOnline = true;
  List<Map<String, dynamic>> _syncLog = [];

  // Automatic periodic GPS sharing (as opposed to the manual "Share GPS"
  // button, which still exists and still works the same way). This is a
  // plain Dart Timer.periodic, NOT a native Android background service /
  // WorkManager job - it only runs while this app's process is alive
  // (foreground, or backgrounded-but-not-killed by the OS). If Android
  // kills the process (common on stricter OEM battery managers), periodic
  // sharing stops until the app is reopened, same as every other in-app
  // timer this codebase uses. A true kill-proof background tracker would
  // need a native foreground service with its own persistent notification
  // - bigger scope, not built here, flagged as real follow-up work rather
  // than silently pretending this covers the "even when closed" case.
  static const Duration _locationAutoShareInterval = Duration(minutes: 15);
  Timer? _locationAutoShareTimer;

  // Latest snapshot of the child's own users/{uid} doc, cached from the
  // StreamBuilder in build() below so _autoShareLocation() has
  // pairedParentId/pairedChildProfileId to work with even though a
  // Timer callback has no BuildContext of its own.
  Map<String, dynamic>? _cachedUserData;

  // True once an automatic (or manual) GPS attempt has detected that
  // Android's location services (GPS) are turned off device-wide. Drives
  // the warning banner in _gpsCard() so this is surfaced passively next
  // time the user actually looks at the app, instead of a periodic
  // background timer popping an interruptive dialog with no warning.
  bool _locationServicesDisabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ChatNotificationsService.instance.markDashboardReady();
    });
    _loadUsageDashboard();
    _refreshSmsAlertStatus();
    _refreshSyncStatus();
    _connectivitySubscription = _syncStatusService.onlineStatusChanges.listen(
      _handleConnectivityChange,
    );
    _locationAutoShareTimer = Timer.periodic(
      _locationAutoShareInterval,
      (_) => _autoShareLocation(),
    );
    _usageAutoSyncTimer = Timer.periodic(
      _usageAutoSyncInterval,
      (_) => _autoSyncUsage(),
    );
    // A lightweight check-in is separate from the 15-minute usage recovery.
    // The parent derives Online/Offline from this server-authored timestamp.
    _presenceHeartbeatTimer = Timer.periodic(
      _presenceHeartbeatInterval,
      (_) => unawaited(_publishOnlineHeartbeat()),
    );
  }

  /// Starts mirroring per-app limits only for this signed-in child profile.
  /// This sync does not enforce blocking; the AccessibilityService must
  /// implement consumption of the `flutter.app_time_limits_json` cache.
  void _ensureAppTimeLimitSubscription(String childProfileId) {
    if (_timeLimitProfileId == childProfileId) return;
    _timeLimitProfileId = childProfileId;
    final generation = ++_timeLimitWatchGeneration;
    final previous = _appTimeLimitSubscription;
    _appTimeLimitSubscription = null;
    unawaited(
      _restartAppTimeLimitSubscription(previous, childProfileId, generation),
    );
  }

  Future<void> _restartAppTimeLimitSubscription(
    StreamSubscription<List<AppTimeLimit>>? previous,
    String childProfileId,
    int generation,
  ) async {
    await previous?.cancel();
    if (!mounted || generation != _timeLimitWatchGeneration) return;
    await _appTimeLimitService.prepareCacheForChild(childProfileId);
    // Register this child's FCM token before monitoring the parent-set limits.
    // Non-blocking: a notification permission/network problem must never
    // prevent time-limit enforcement or the dashboard from loading.
    unawaited(_limitNotifications.startForChild(childProfileId));
    if (!mounted ||
        generation != _timeLimitWatchGeneration ||
        childProfileId.isEmpty) {
      return;
    }
    // Mirror the registered child's real account name into the paired
    // profile, since Firestore users/{uid} is private to its owner.
    unawaited(_syncChildDisplayName(childProfileId));
    unawaited(_temporaryGrants.startForChild(childProfileId));
    _appTimeLimitSubscription = _appTimeLimitService
        .watchForChildAndCache(childProfileId)
        .listen(
          (_) {},
          onError: (Object error, StackTrace trace) {
            debugPrint('Could not mirror app time limits: $error');
          },
        );
  }

  Future<void> _syncChildDisplayName(String profileId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || profileId.isEmpty) return;
    try {
      final ownProfile = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();
      final name = (ownProfile.data()?['fullName'] ??
          user.displayName ?? '').toString().trim();
      if (name.isEmpty) return;
      await FirebaseFirestore.instance.collection('child_profiles')
          .doc(profileId).set({
        'childDisplayName': name,
      }, SetOptions(merge: true));
    } catch (error) {
      // Name is optional presentation data; never interfere with pairing,
      // blocking, or the existing time-limit sync.
      debugPrint('Could not synchronize child display name: $error');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pairingCodeController.dispose();
    emergencyReasonController.dispose();
    _connectivitySubscription?.cancel();
    _timeLimitWatchGeneration++;
    _appTimeLimitSubscription?.cancel();
    unawaited(_temporaryGrants.detach());
    _locationAutoShareTimer?.cancel();
    _usageAutoSyncTimer?.cancel();
    _presenceHeartbeatTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android's "Usage Access" permission is granted from system Settings,
    // outside the app, so there's no in-app callback for it. Re-check when
    // the user comes back to the app (e.g. after granting the permission)
    // instead of requiring a manual refresh every time.
    if (state == AppLifecycleState.resumed) {
      _loadUsageDashboard();
      _refreshSmsAlertStatus();
      _refreshSyncStatus();
      unawaited(_publishOnlineHeartbeat());
      final activeProfile = _timeLimitProfileId;
      if (activeProfile != null && activeProfile.isNotEmpty) {
        unawaited(_limitNotifications.startForChild(activeProfile));
      }
    }
  }

  /// Caches the paired parent's phone number locally (SharedPreferences),
  /// because WellScreenAccessibilityService.kt / SmsAlertSender.kt run in
  /// native Kotlin with no Firestore access of their own - they read the
  /// same "FlutterSharedPreferences" file the Flutter app writes to, the
  /// same pattern app_rules_service.dart already uses for restricted-app
  /// package lists. The number itself lives on users/{parentId}.phoneNumber
  /// (ProfileSettingsScreen), set by the parent on their own device.
  Future<void> _maybeSyncParentPhoneNumber(Map<String, dynamic> data) async {
    final parentId = (data['pairedParentId'] ?? '').toString();

    if (parentId.isEmpty || parentId == _syncedParentIdForPhoneNumber) {
      return;
    }

    _syncedParentIdForPhoneNumber = parentId;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(parentId)
          .get();

      final phoneNumber = (doc.data()?['phoneNumber'] ?? '').toString().trim();
      final prefs = await SharedPreferences.getInstance();

      if (phoneNumber.isEmpty) {
        await prefs.remove('parent_phone_number');
      } else {
        await prefs.setString('parent_phone_number', phoneNumber);
      }

      await _refreshSmsAlertStatus();
    } catch (_) {
      // Best-effort - if this fails, SmsAlertSender simply has no cached
      // number yet and skips sending, same as the "no number yet" state.
    }
  }

  Future<void> _refreshSmsAlertStatus() async {
    final status = await Permission.sms.status;
    final prefs = await SharedPreferences.getInstance();
    final phoneNumber = prefs.getString('parent_phone_number');
    final log = _decodeJsonList(prefs.getString('sms_alert_log_json'));

    if (!mounted) return;

    setState(() {
      _smsPermissionGranted = status.isGranted;
      _cachedParentPhoneNumber = (phoneNumber != null && phoneNumber.isNotEmpty)
          ? phoneNumber
          : null;
      _smsAlertLog = log;
    });
  }

  List<Map<String, dynamic>> _decodeJsonList(String? raw) {
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);

      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Updates the visible connection state. The Android scheduler, rather
  /// than this screen, waits 15 minutes after a validated reconnect and
  /// uploads fresh UsageStats. A manual Sync Usage remains available.
  /// Native Android monitors connectivity while the app process is alive.
  /// Do not immediately replay an old offline payload here: it can contain
  /// stale usage and bypass the requested 15-minute post-reconnect delay.
  /// JobScheduler collects a *fresh* UsageStats snapshot after that window.
  Future<void> _handleConnectivityChange(bool isOnline) async {
    if (!mounted) return;
    setState(() => _isOnline = isOnline);
    if (isOnline) {
      // Send only a presence update now. Android's reconnect job remains
      // responsible for uploading fresh usage after the 15-minute delay.
      unawaited(_publishOnlineHeartbeat());
    } else {
      // Ensure a quick check-in when the connection next returns.
      _lastPresenceWriteAttempt = null;
    }
  }

  /// Best-effort server heartbeat for the parent dashboard. No offline write:
  /// a disconnected phone cannot announce its own disconnection to Firestore.
  /// Native ScreenTimeReportJobService checks in even while Flutter UI is closed.
  Future<void> _publishOnlineHeartbeat() async {
    if (!_isOnline) return;
    final user = FirebaseAuth.instance.currentUser;
    final data = _cachedUserData;
    if (user == null || data == null || !isConnected(data)) return;
    final profileId = (data['pairedChildProfileId'] ?? '').toString();
    if (profileId.isEmpty) return;

    final now = DateTime.now();
    if (_lastPresenceWriteAttempt != null &&
        now.difference(_lastPresenceWriteAttempt!) <
            const Duration(minutes: 4)) {
      return;
    }
    _lastPresenceWriteAttempt = now;
    try {
      await FirebaseFirestore.instance
          .collection('child_profiles')
          .doc(profileId)
          .update({'lastSeenAt': FieldValue.serverTimestamp()})
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      _lastPresenceWriteAttempt = null;
      debugPrint('Child presence check-in failed: $error');
    }
  }

  Future<void> _queuePendingSync(
    String childProfileId,
    Map<String, dynamic> payload,
    int queuedAtMs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pending_sync_payload_json',
      jsonEncode({
        'childProfileId': childProfileId,
        'payload': payload,
        'queuedAtMs': queuedAtMs,
      }),
    );
  }

  Future<void> _clearPendingSync() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_sync_payload_json');
  }

  Future<void> _recordSyncOutcome({
    required String outcome,
    required String trigger,
    int? responseTimeMs,
    int? recoveryTimeMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final log = _decodeJsonList(prefs.getString('sync_log_json'));

    log.add({
      'outcome': outcome,
      'trigger': trigger,
      'responseTimeMs': ?responseTimeMs,
      'recoveryTimeMs': ?recoveryTimeMs,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    });

    final trimmed = log.length > 50 ? log.sublist(log.length - 50) : log;
    await prefs.setString('sync_log_json', jsonEncode(trimmed));
  }

  Future<void> _refreshSyncStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final log = _decodeJsonList(prefs.getString('sync_log_json'));
    final online = await _syncStatusService.isOnline();

    if (!mounted) return;
    setState(() {
      _syncLog = log;
      _isOnline = online;
    });
  }

  /// Single choke point for writing the usage/SMS/restriction snapshot to
  /// child_profiles/{childProfileId} - used by both syncUsageReport()'s
  /// manual button and periodic foreground synchronization.
  /// Android independently uploads fresh usage after reconnect.
  ///
  /// Always caches the payload locally BEFORE attempting the write (cleared
  /// only on confirmed success), and wraps the write in a timeout, because
  /// cloud_firestore's set() hangs forever offline instead of throwing
  /// (firebase/flutterfire#17643) - without this, a sync attempted while
  /// offline would spin the loading indicator forever with no error and no
  /// way to recover except restarting the app.
  ///
  /// [payload] must not contain FieldValue sentinels (e.g.
  /// FieldValue.serverTimestamp()) - those aren't JSON-encodable for the
  /// local cache; the server timestamp is added here, right before the
  /// real Firestore write.
  Future<bool> _attemptFirestoreSync({
    required String childProfileId,
    required Map<String, dynamic> payload,
    required String trigger,
    int? queuedAtMs,
  }) async {
    final stopwatch = Stopwatch()..start();
    final attemptStartMs = DateTime.now().millisecondsSinceEpoch;
    final effectiveQueuedAtMs = queuedAtMs ?? attemptStartMs;
    String outcome;

    await _queuePendingSync(childProfileId, payload, effectiveQueuedAtMs);

    try {
      final online = await _syncStatusService.isOnline();

      if (!online) {
        outcome = 'queued_offline';
      } else {
        await FirebaseFirestore.instance
            .collection('child_profiles')
            .doc(childProfileId)
            .set({
              ...payload,
              'usageReportUpdatedAt': FieldValue.serverTimestamp(),
              'lastSeenAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));

        await _clearPendingSync();
        outcome = 'synced';
      }
    } on TimeoutException {
      outcome = 'failed_timeout';
    } catch (_) {
      outcome = 'failed_exception';
    }

    stopwatch.stop();

    final recoveryTimeMs = (outcome == 'synced' && queuedAtMs != null)
        ? DateTime.now().millisecondsSinceEpoch - queuedAtMs
        : null;

    await _recordSyncOutcome(
      outcome: outcome,
      trigger: trigger,
      responseTimeMs: stopwatch.elapsedMilliseconds,
      recoveryTimeMs: recoveryTimeMs,
    );

    if (!mounted) return outcome == 'synced';

    if (outcome == 'synced') {
      if (trigger == 'auto_reconnect') {
        showMessage(
          'Usage data synced automatically now that you\'re back online.',
        );
        await _loadUsageDashboard();
        await _refreshSmsAlertStatus();
      }
    } else if (outcome == 'queued_offline') {
      showMessage(
        'You\'re offline - this data is saved on your device and will '
        'sync automatically once you\'re back online.',
      );
    } else if (outcome == 'failed_timeout') {
      showMessage(
        'Sync is taking too long - your data is saved locally and will '
        'retry automatically when the connection improves.',
      );
    } else {
      showMessage(
        'Sync failed. Your data is saved locally - try again shortly.',
      );
    }

    await _refreshSyncStatus();

    return outcome == 'synced';
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();

    if (!mounted) return;

    setState(() => _smsPermissionGranted = status.isGranted);

    showMessage(
      status.isGranted
          ? 'SMS backup alerts enabled.'
          : 'SMS permission was not granted. Backup alerts will stay off '
                'until it\'s allowed.',
    );
  }

  String _maskPhoneNumber(String phone) {
    if (phone.length <= 4) return phone;
    return '${'*' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
  }

  Future<void> _loadUsageDashboard() async {
    if (!mounted) return;
    setState(() => _loadingUsageDashboard = true);

    try {
      final state = await _usageDashboardController.loadTodayDashboardState();
      if (!mounted) return;
      setState(() {
        _usageDashboardState = state;
        _loadingUsageDashboard = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingUsageDashboard = false);
    }
  }

  Future<void> pairWithParent() async {
    final code = pairingCodeController.text.trim().replaceAll(' ', '');
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    if (code.length != 6) {
      showMessage('Please enter a valid 6-digit pairing code.');
      return;
    }

    setState(() => isPairing = true);

    String newlyPairedParentId = '';
    String newlyPairedProfileId = '';

    try {
      final firestore = FirebaseFirestore.instance;

      final codeRef = firestore.collection('pairing_codes').doc(code);
      final userRef = firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((transaction) async {
        final codeSnapshot = await transaction.get(codeRef);

        if (!codeSnapshot.exists) {
          throw Exception('Pairing code not found.');
        }

        final codeData = codeSnapshot.data() ?? <String, dynamic>{};

        final status = (codeData['status'] ?? '').toString();
        final parentId = (codeData['parentId'] ?? '').toString();
        final childProfileId = (codeData['childId'] ?? '').toString();
        final expiresAt = codeData['expiresAt'];

        if (status != 'active') {
          throw Exception('This pairing code is no longer active.');
        }

        if (parentId.isEmpty || childProfileId.isEmpty) {
          throw Exception('Invalid pairing code data.');
        }

        newlyPairedParentId = parentId;
        newlyPairedProfileId = childProfileId;

        if (expiresAt is Timestamp) {
          final expiryDate = expiresAt.toDate();

          if (DateTime.now().isAfter(expiryDate)) {
            throw Exception('This pairing code has expired.');
          }
        }

        final childProfileRef = firestore
            .collection('child_profiles')
            .doc(childProfileId);

        transaction.set(userRef, {
          'uid': user.uid,
          'email': user.email,
          'fullName': user.displayName ?? 'Student User',
          'role': 'child',
          'pairingStatus': 'connected',
          'pairedParentId': parentId,
          'pairedChildProfileId': childProfileId,
          'pairingCode': code,
          'pairedAt': FieldValue.serverTimestamp(),
          'lastLoginAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(codeRef, {
          'status': 'connected',
          'childAccountId': user.uid,
          'childEmail': user.email,
          'connectedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        transaction.set(childProfileRef, {
          'childAccountId': user.uid,
          'childEmail': user.email,
          'pairingStatus': 'connected',
          'connectedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      pairingCodeController.clear();

      if (!mounted) return;

      showConnectedSuccessDialog(
        parentId: newlyPairedParentId,
        childProfileId: newlyPairedProfileId,
      );
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      showMessage(message);
    } finally {
      if (mounted) {
        setState(() => isPairing = false);
      }
    }
  }

  /// Opens [QrScanScreen] and, if a code was scanned, fills it into
  /// [pairingCodeController] and immediately runs it through the same
  /// [pairWithParent] validation/submit path used for manual entry - QR is
  /// only a faster way to fill in the code, not a separate pairing route.
  Future<void> scanQrCode() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );

    if (scannedCode == null || !mounted) return;

    pairingCodeController.text = scannedCode;
    await pairWithParent();
  }

  /// Requests the device's real GPS position via [Geolocator] and shares it
  /// to the parent dashboard. Replaces the previous shareDemoLocation, which
  /// wrote a hardcoded constant coordinate regardless of the device's actual
  /// position - see the WellScreen re-audit notes for why that was a
  /// data-integrity problem, not just a missing feature.
  Future<void> shareCurrentLocation(Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (childProfileId.isEmpty) {
      showMessage('Pair this device first before sharing GPS location.');
      return;
    }

    setState(() => isSharingLocation = true);

    try {
      final position = await _getCurrentPositionOrThrow();

      if (mounted && _locationServicesDisabled) {
        setState(() => _locationServicesDisabled = false);
      }

      await _writeSharedLocation(
        userUid: user.uid,
        childProfileId: childProfileId,
        position: position,
      );

      if (!mounted) return;

      showMessage('Current GPS location shared to parent dashboard.');

      final parentId = (data['pairedParentId'] ?? '').toString();
      unawaited(
        _alertNotificationClient.notifyParent(
          parentUid: parentId,
          title: 'New location shared',
          body: 'Your child\'s device just shared its current location.',
          alertType: 'location_shared',
          childProfileId: childProfileId,
        ),
      );
    } on LocationServicesDisabledException {
      if (!mounted) return;
      setState(() => _locationServicesDisabled = true);
      _showEnableLocationServicesDialog();
    } on TimeoutException {
      if (!mounted) return;
      showMessage(
        'Sharing location is taking too long - check your connection and '
        'try again.',
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isSharingLocation = false);
      }
    }
  }

  /// Silent, periodic counterpart to [shareCurrentLocation], fired every
  /// [_locationAutoShareInterval] by the Timer.periodic started in
  /// initState(). Deliberately does NOT show any snackbar on success (would
  /// be noisy every 15 minutes) and does NOT send the paired parent a
  /// "New location shared" push notification on every automatic cycle
  /// (would spam the parent's phone all day) - that notification stays
  /// exclusive to the manual "Share GPS" button, an explicit user action
  /// worth telling the parent about. It also never pops a dialog: a
  /// background timer interrupting whatever screen the user is currently
  /// on would be bad UX, so on a services-disabled failure it only raises
  /// the passive _locationServicesDisabled banner (see _gpsCard()) for the
  /// user to notice and act on next time they open the app. Any other
  /// failure (no permission, paired but offline, no fix within the
  /// timeout, not paired yet) is swallowed silently and simply retried on
  /// the next tick - there is no user-facing error path for a background
  /// process the user didn't directly trigger.
  Future<void> _autoShareLocation() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    final data = _cachedUserData;

    if (user == null || data == null) return;

    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (childProfileId.isEmpty) return;

    try {
      final position = await _getCurrentPositionOrThrow();

      if (mounted && _locationServicesDisabled) {
        setState(() => _locationServicesDisabled = false);
      }

      await _writeSharedLocation(
        userUid: user.uid,
        childProfileId: childProfileId,
        position: position,
      );
    } on LocationServicesDisabledException {
      if (!mounted) return;
      setState(() => _locationServicesDisabled = true);
    } catch (_) {
      // Silent by design - see doc comment above.
    }
  }

  /// Shared Firestore write used by both the manual button
  /// (shareCurrentLocation) and the periodic background timer
  /// (_autoShareLocation), so the mergeFields fix (see the comment inside)
  /// only has to be correct in one place.
  Future<void> _writeSharedLocation({
    required String userUid,
    required String childProfileId,
    required Position position,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final userRef = firestore.collection('users').doc(userUid);
    final childProfileRef = firestore
        .collection('child_profiles')
        .doc(childProfileId);

    final sharedLocation = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracyMeters': position.accuracy,
      'capturedAt': position.timestamp.toIso8601String(),
    };

    // Location isn't queued/auto-retried like usage data (see
    // _attemptFirestoreSync) - a stale GPS fix replayed automatically
    // after reconnecting would show the parent an outdated position
    // without saying so, which is worse than just failing visibly. It
    // still gets a timeout instead of hanging forever, though - same
    // underlying cloud_firestore bug (set()/runTransaction() never
    // complete offline: firebase/flutterfire#17643) applies here too.
    // Deliberately NOT SetOptions(merge: true) here. Firestore's plain
    // merge:true does a RECURSIVE merge on nested map fields - it only
    // overwrites the keys actually sent (latitude/longitude/etc.) and
    // silently keeps any other existing keys already inside
    // latestLocation untouched. That's exactly why a leftover 'label'
    // field from the old, removed shareDemoLocation() function
    // ("Mandaue City, Cebu demo location") kept winning over real GPS
    // coordinates forever, even after a real share succeeded -
    // locationText() prefers 'label' when present. mergeFields tells
    // Firestore to fully REPLACE the latestLocation/locationUpdatedAt
    // fields wholesale (while leaving every other field on the document
    // alone), so a real share now actually clears any stale label.
    await firestore
        .runTransaction((transaction) async {
          transaction.set(
            userRef,
            {
              'latestLocation': sharedLocation,
              'locationUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(mergeFields: ['latestLocation', 'locationUpdatedAt']),
          );

          transaction.set(
            childProfileRef,
            {
              'latestLocation': sharedLocation,
              'locationUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(mergeFields: ['latestLocation', 'locationUpdatedAt']),
          );
        })
        .timeout(const Duration(seconds: 10));
  }

  /// Shown only from the manual "Share GPS" flow (the periodic auto-share
  /// never interrupts the user - see _autoShareLocation's doc comment).
  /// Offers a direct path into Android's location-services settings via
  /// Geolocator.openLocationSettings() instead of just telling the user to
  /// go find the toggle themselves.
  void _showEnableLocationServicesDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Turn on location services'),
          content: const Text(
            'Location services (GPS) are turned off on this device. '
            'WellScreen needs them on to share your location with your '
            'parent.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await Geolocator.openLocationSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  /// Walks the full geolocator permission/service flow and returns a real
  /// device [Position], or throws a user-readable Exception describing
  /// exactly which step failed (services off, permission denied, permission
  /// permanently denied, or a timeout getting a fix).
  ///
  /// NOT verified on a physical device or emulator - this sandbox has no
  /// Android runtime to test against. The permission flow and API calls
  /// follow the documented geolocator ^14.x contract, but this needs a real
  /// on-device pass (indoors AND outdoors, and with location services
  /// toggled off) before this row can honestly move to "Done" in the
  /// tracker.
  Future<Position> _getCurrentPositionOrThrow() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw LocationServicesDisabledException();
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception(
        'Location permission was denied. Allow location access for WellScreen and try again.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Enable it from this device\'s App Settings > Permissions.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  /// Builds the 7-feature input vector for MlRiskClassifierService, using
  /// only data the app can genuinely compute today - see
  /// ml/generate_dataset.py's doc comment for which of the manuscript's
  /// Table 6 indicators are included and which are still deferred
  /// (harmful-category real-time detection isn't built yet, so it's not
  /// faked here).
  Map<String, num> _buildMlFeatures({
    required UsageReport report,
    required List<AppUsageSummary> summaries,
    required List<Map<String, dynamic>> restrictionLog,
    required int dailyLimitMinutes,
    required int maxAppOpensToday,
  }) {
    var lateNightMinutes = 0;
    var longestSessionMinutes = 0;

    for (final app in summaries) {
      final minutes = app.usageDuration.inMinutes;

      if (minutes > longestSessionMinutes) {
        longestSessionMinutes = minutes;
      }

      final lastUsed = app.lastTimeUsed;
      if (lastUsed != null && (lastUsed.hour >= 22 || lastUsed.hour < 5)) {
        // Best-effort proxy: AppUsageSummary only exposes a last-used
        // timestamp, not a minute-by-minute breakdown, so an app last
        // touched in the late-night window has its whole usage duration
        // counted toward late-night minutes. Same underlying signal
        // PatternDetectionService._hasLateNightUsage already uses (a
        // last-used-hour check), just summed into a duration instead of
        // left as a boolean.
        lateNightMinutes += minutes;
      }
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    var attemptsToday = 0;
    var violations7d = 0;

    for (final entry in restrictionLog) {
      if (entry['outcome'] != 'blocked') continue;

      final timestampMs = entry['timestampMs'];
      if (timestampMs is! int) continue;

      final eventTime = DateTime.fromMillisecondsSinceEpoch(timestampMs);

      if (!eventTime.isBefore(startOfDay)) {
        attemptsToday++;
      }
      if (eventTime.isAfter(sevenDaysAgo)) {
        violations7d++;
      }
    }

    return {
      'total_screen_time_minutes': report.totalUsageDuration.inMinutes,
      'daily_limit_minutes': dailyLimitMinutes,
      'late_night_minutes': lateNightMinutes,
      'longest_session_minutes': longestSessionMinutes,
      'restricted_app_attempts_today': attemptsToday,
      'rule_violations_7d': violations7d,
      'frequent_app_opens_today': maxAppOpensToday,
    };
  }

  /// Syncs today's real on-device usage data to
  /// child_profiles/{childProfileId}.latestUsageReport, so the parent
  /// dashboard (ParentDashboardScreen's Screen Time/Usage Pattern/Top Apps
  /// cards and UsageSummaryScreen) can display it. Mirrors the
  /// shareCurrentLocation pattern above - same childProfileId lookup, same
  /// Firestore transaction shape.
  ///
  /// Requires Android's special "Usage Access" permission, which can only
  /// be granted from system Settings (not a normal runtime permission
  /// dialog). If it isn't granted yet, this opens that settings screen and
  /// asks the user to come back and tap again - didChangeAppLifecycleState
  /// above will also silently refresh the local dashboard when they return.
  ///
  /// [silent] is set by [_autoSyncUsage]'s periodic timer below - a
  /// background sync should never interrupt the user with a SnackBar, and
  /// absolutely must never spontaneously open the Usage Access settings
  /// screen out from under them (that's only acceptable as a direct
  /// response to a manual tap). The guard/error-log/success-message
  /// behavior for the manual "Sync Usage" button tap is unchanged.
  Future<void> syncUsageReport(
    Map<String, dynamic> data, {
    bool silent = false,
  }) async {
    // Guards against the periodic auto-sync timer firing on top of an
    // already-in-progress sync (manual or auto) - without this, a slow
    // sync plus a short auto-sync interval could stack overlapping
    // Firestore writes.
    if (isSyncingUsage) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!silent) showMessage('Please log in again.');
      return;
    }

    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (childProfileId.isEmpty) {
      if (!silent) {
        showMessage('Pair this device first before syncing usage data.');
      }
      return;
    }

    setState(() => isSyncingUsage = true);

    try {
      final hasPermission = await _usageTrackingService.hasUsagePermission();

      if (!hasPermission) {
        if (silent) return;
        await _usageTrackingService.openUsageAccessSettings();
        if (!mounted) return;
        showMessage(
          'Grant "WellScreen" access under Usage Access in Settings, then '
          'come back and tap Sync Usage again.',
        );
        return;
      }

      // The existing report model still uses its top-ten summary; the
      // dedicated All Apps screen needs the complete uncapped list.
      final allSummaries = await _usageTrackingService.getAllTodayUsage();
      final summaries = allSummaries.take(10).toList();
      final report = await _usageTrackingService.getTodayUsageReport();
      // Ask Android for the actual installed label/icon for each PACKAGE.
      // Do not infer names such as Orca or Trill from package suffixes.
      final appMetadata = await const InstalledAppMetadataService().lookup(
        allSummaries.map((app) => app.packageName),
      );
      // Keep image data only once in allApps to avoid duplicating icons
      // in topApps and pushing Firestore's document size limit.
      var remainingIconChars = 400000;

      final topApps = summaries
          .map(
            (AppUsageSummary app) => {
              'packageName': app.packageName,
              'displayName':
                  appMetadata[app.packageName]?['displayName'] ??
                  app.packageName,
              'usageDurationMs': app.usageDuration.inMilliseconds,
              'lastTimeUsed': app.lastTimeUsed?.toIso8601String(),
            },
          )
          .toList();

      final allApps = allSummaries.map((app) {
        final icon = appMetadata[app.packageName]?['iconBase64'];
        final keepIcon = icon != null && icon.length <= remainingIconChars;
        if (keepIcon) remainingIconChars -= icon.length;
        return <String, dynamic>{
          'packageName': app.packageName,
          'displayName':
              appMetadata[app.packageName]?['displayName'] ?? app.packageName,
          'usageDurationMs': app.usageDuration.inMilliseconds,
          'lastTimeUsed': app.lastTimeUsed?.toIso8601String(),
          if (keepIcon) 'iconBase64': icon,
        };
      }).toList();
      final allAppsTotalMs = allSummaries.fold<int>(
        0,
        (runningTotal, app) => runningTotal + app.usageDuration.inMilliseconds,
      );

      final usageReportData = {
        'totalUsageDurationMs': report.totalUsageDuration.inMilliseconds,
        'topApps': topApps,
        'allApps': allApps,
        'allAppsTotalUsageDurationMs': allAppsTotalMs,
        'unhealthyAppCount': report.unhealthyAppCount,
        'patternStatus': report.patternStatus.name,
        'recommendationMessage': report.recommendationMessage,
        'capturedAt': report.generatedAt.toIso8601String(),
      };

      // Also push the local SMS backup-alert log (written natively by
      // SmsSentReceiver/SmsDeliveredReceiver), the restriction enforcement
      // log (written natively by RestrictionLogger when
      // WellScreenAccessibilityService blocks a restricted app), and this
      // device's own sync-attempt log (see _recordSyncOutcome) so the
      // parent can see real sent/delivered/failed, blocked/failed, and
      // synced/queued-offline/failed outcomes with response times, not
      // just whether the features are turned on. Reuses this same sync
      // button rather than adding separate ones.
      final prefs = await SharedPreferences.getInstance();
      final smsAlertLog = _decodeJsonList(
        prefs.getString('sms_alert_log_json'),
      );
      final restrictionLog = _decodeJsonList(
        prefs.getString('restriction_log_json'),
      );
      final syncLog = _decodeJsonList(prefs.getString('sync_log_json'));

      // Browsed domains captured natively by BrowserUrlExtractor /
      // BrowsingLogger (see WellScreenAccessibilityService.kt), then
      // classified here against the real, cleaned UT1 dataset via
      // SiteCategoryService (see data_cleaned/site_categories/ and
      // ml/site_category/README.md). This tags each entry with a category
      // (gambling/drugs/dangerous_material) when it matches, and alerts the
      // parent below when one does - it does NOT block the page from
      // loading, since that would need this same check running natively,
      // before the page renders, which isn't built yet.
      final browsingLog = _decodeJsonList(prefs.getString('browsing_log_json'));
      // Only alert for harmful entries newer than the last one already
      // alerted on - without this watermark, every sync would re-scan the
      // whole rolling (up to 50-entry) log and re-fire a push for the same
      // old visit every time "Sync Usage" is pressed, which would falsely
      // read as "this just happened again."
      final lastAlertedMs =
          prefs.getInt('last_browsing_alert_timestamp_ms') ?? 0;
      var newestAlertedMs = lastAlertedMs;

      final categorizedBrowsingLog = <Map<String, dynamic>>[];
      String? mostRecentHarmfulCategory;
      String? mostRecentHarmfulDomain;
      for (final entry in browsingLog) {
        final domain = (entry['domain'] ?? '').toString();
        final timestampMs = entry['timestampMs'];
        SiteCategoryMatch? match;
        if (domain.isNotEmpty) {
          try {
            match = await _siteCategoryService.classify(domain);
          } catch (_) {
            // Best-effort - a classification failure just leaves this one
            // entry uncategorized, it never blocks the real sync.
          }
        }
        // 'detectionSource' ('lookup' vs 'keyword' vs 'ml') and
        // 'mlConfidence' let the parent-facing UI show which mechanism
        // actually caught this one - see alerts_reports_screen.dart's
        // browsing activity list. A 'lookup' match is exact (the domain is
        // literally in the real dataset); a 'keyword' match is
        // AdultKeywordDetector catching a pornography-related substring
        // (the technique our manuscript describes for that category, see
        // that class's doc comment); an 'ml' match is the live classifier
        // generalizing to a domain the dataset has never seen, already
        // filtered to only the 'gambling' predictions it's actually
        // reliable at (see SiteCategoryMlClassifier's doc comment for
        // the measured reasoning behind that restriction, including why
        // 'drugs' was tested and deliberately held back).
        categorizedBrowsingLog.add({
          ...entry,
          'category': ?match?.category,
          'detectionSource': ?match?.source,
          'mlConfidence': ?match?.confidence,
        });
        if (match != null &&
            timestampMs is num &&
            timestampMs > lastAlertedMs) {
          mostRecentHarmfulCategory = match.category;
          mostRecentHarmfulDomain = domain;
          if (timestampMs > newestAlertedMs) {
            newestAlertedMs = timestampMs.toInt();
          }
        }
      }

      // Proposed ML Extension (manuscript Ch. 3) - a real, trained,
      // evaluated Random Forest classifier (see ml/train_model.py and
      // ml/output/evaluation_report.txt), run on-device via
      // MlRiskClassifierService. Supplements PatternDetectionService's
      // rule-based status above; doesn't replace it. Best-effort: a
      // classification failure (e.g. the asset failing to load) should
      // never block the real sync.
      Map<String, dynamic>? mlRiskAssessmentData;
      try {
        final dailyLimit = await _dailyScreenTimeLimitService.getDailyLimit();
        final maxAppOpensToday = await _usageTrackingService
            .getTodayMaxAppOpenCount();
        final mlFeatures = _buildMlFeatures(
          report: report,
          summaries: summaries,
          restrictionLog: restrictionLog,
          dailyLimitMinutes: dailyLimit.inMinutes,
          maxAppOpensToday: maxAppOpensToday,
        );
        final assessment = await _mlRiskClassifierService.classify(mlFeatures);

        mlRiskAssessmentData = {
          'label': assessment.label,
          'confidence': assessment.confidence,
          'classProbabilities': assessment.classProbabilities,
          'modelVersion': assessment.modelVersion,
          'inputFeatures': mlFeatures,
          'timestampMs': DateTime.now().millisecondsSinceEpoch,
        };
      } catch (_) {
        // Best-effort - see above. The rule-based status still syncs.
      }

      // _attemptFirestoreSync handles offline detection, the write timeout
      // (cloud_firestore's set() hangs forever offline instead of throwing
      // - firebase/flutterfire#17643), local queuing for automatic retry on
      // reconnect, and outcome logging - see its doc comment above.
      final synced = await _attemptFirestoreSync(
        childProfileId: childProfileId,
        payload: {
          'latestUsageReport': usageReportData,
          if (smsAlertLog.isNotEmpty) 'smsAlertLog': smsAlertLog,
          if (restrictionLog.isNotEmpty) 'restrictionLog': restrictionLog,
          if (syncLog.isNotEmpty) 'syncLog': syncLog,
          if (categorizedBrowsingLog.isNotEmpty)
            'browsingLog': categorizedBrowsingLog,
          'mlRiskAssessment': ?mlRiskAssessmentData,
        },
        trigger: 'manual',
      );

      if (synced) {
        // Backend validates the paired child and de-duplicates usage events.
        // Dispatch is independent of whether this screen is still mounted.
        unawaited(_monitoringUsageAlerts.reportUsage(
          childProfileId: childProfileId,
          report: report,
          appSummaries: allSummaries,
        ));
      }

      if (!mounted) return;

      if (synced) {
        if (!silent) {
          showMessage('Today\'s usage report synced to the parent dashboard.');
        }
        await _loadUsageDashboard();
        await _refreshSmsAlertStatus();
      }

      // Same reasoning as the unhealthy-pattern push above, for a harmful
      // site category found by SiteCategoryService just now. This is an
      // after-the-fact alert (the page was already viewed - see
      // SiteCategoryService's doc comment on why this doesn't block in real
      // time yet), not a prevention, and that's said plainly in the alert
      // body rather than implied.
      if (mostRecentHarmfulCategory != null) {
        final parentId = (data['pairedParentId'] ?? '').toString();
        unawaited(
          _alertNotificationClient.notifyParent(
            parentUid: parentId,
            title: 'Harmful site category detected',
            body:
                'Visited a site categorized as '
                '$mostRecentHarmfulCategory'
                '${mostRecentHarmfulDomain != null && mostRecentHarmfulDomain.isNotEmpty ? ' ($mostRecentHarmfulDomain)' : ''}.',
            alertType: 'harmful_site_category',
            childProfileId: childProfileId,
          ),
        );
        await prefs.setInt('last_browsing_alert_timestamp_ms', newestAlertedMs);
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isSyncingUsage = false);
      }
    }
  }

  /// Periodic automatic sync - the "why do I have to press Sync Usage
  /// every time" fix. Same Timer.periodic pattern and same honest
  /// limitation as [_autoShareLocation]/[_locationAutoShareTimer]: this
  /// only runs while the app's process is alive (foreground, or
  /// backgrounded-but-not-yet-killed by the OS), not a true kill-proof
  /// background service. Deliberately calls the same [syncUsageReport]
  /// the manual button uses (not a separate code path) so both stay in
  /// sync with each other by construction - just with [silent] set so it
  /// never pops a SnackBar or a Settings screen on its own.
  ///
  /// 5 minutes, not 15 like location - browsing/category detection is a
  /// safety-relevant alert, not a passive status update, so a parent
  /// finding out sooner rather than later matters more here than it does
  /// for "where is my kid right now."
  static const Duration _usageAutoSyncInterval = Duration(minutes: 5);
  Timer? _usageAutoSyncTimer;

  Future<void> _autoSyncUsage() async {
    final data = _cachedUserData;
    if (data == null) return;
    final prefs = await SharedPreferences.getInstance();
    // The Kotlin JobScheduler writes this key outside Dart's pref cache.
    await prefs.reload();
    final dueAtMs = prefs.getInt('wellscreen_reconnect_due_ms') ?? 0;
    if (dueAtMs > DateTime.now().millisecondsSinceEpoch) return;
    await syncUsageReport(data, silent: true);
  }

  Future<void> logout() async {
    // Native AccessibilityService cannot read FirebaseAuth session state.
    // Clear its child-specific rule cache before signing out.
    _timeLimitWatchGeneration++;
    final previous = _appTimeLimitSubscription;
    _appTimeLimitSubscription = null;
    _timeLimitProfileId = null;
    await previous?.cancel();
    await _appTimeLimitService.clearCachedLimits();
    await _temporaryGrants.stop();
    await _limitNotifications.stopForSignOut();
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void openFamilyChat() {
    final childProfileId = (_cachedUserData?['pairedChildProfileId'] ?? '')
        .toString();
    if (childProfileId.isEmpty) {
      showMessage('Pair with a parent to start chatting.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParentChildChatScreen(
          childProfileId: childProfileId,
          isParent: false,
        ),
      ),
    );
  }

  void handleBottomNavTap(int index) {
    if (index == 0) {
      setState(() => currentIndex = 0);
      return;
    }

    if (index == 1) {
      final data = _cachedUserData;
      if (data != null && isConnected(data)) {
        // Already paired - there's no separate "pairing" destination once
        // connected, so surface the same connection-status dialog shown
        // right after pairing succeeds rather than a dead-end message.
        showConnectedSuccessDialog();
      } else {
        _scrollToSection(_pairingSectionKey);
      }
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      );
    }
  }

  /// Shows the actual pairing and identity-verification state. Missing
  /// parent name/email is NOT proof that the pairing was disconnected.
  /// Those fields are copied by the owning parent into the child profile.
  void showConnectedSuccessDialog({String? parentId, String? childProfileId}) {
    final linkedParentId =
        parentId ?? (_cachedUserData?['pairedParentId'] ?? '').toString();
    final linkedProfileId =
        childProfileId ??
        (_cachedUserData?['pairedChildProfileId'] ?? '').toString();
    final signedInChildId = FirebaseAuth.instance.currentUser?.uid;

    if (linkedParentId.isEmpty ||
        linkedProfileId.isEmpty ||
        signedInChildId == null) {
      showMessage('This device has no linked parent account.');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) =>
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('child_profiles')
                .doc(linkedProfileId)
                .snapshots(),
            builder: (context, snapshot) {
              final loading = !snapshot.hasData && !snapshot.hasError;
              final loadFailed = snapshot.hasError;
              final profile = snapshot.data?.data();
              final paired =
                  !loading &&
                  !loadFailed &&
                  snapshot.data?.exists == true &&
                  profile?['parentId'] == linkedParentId &&
                  profile?['childAccountId'] == signedInChildId &&
                  profile?['pairingStatus'] == 'connected';
              final parentName = paired
                  ? (profile?['parentDisplayName'] ?? '').toString().trim()
                  : '';
              final parentEmail = paired
                  ? (profile?['parentEmail'] ?? '').toString().trim()
                  : '';
              final identityReady =
                  parentName.isNotEmpty && parentEmail.isNotEmpty;
              final verified = paired && identityReady;
              final statusText = loading
                  ? 'Checking...'
                  : loadFailed
                  ? 'Verification Unavailable'
                  : !paired
                  ? 'Not Connected'
                  : !identityReady
                  ? 'Not Verified'
                  : 'Connected';
              final statusColor = loading || loadFailed
                  ? const Color(0xFFB7791F)
                  : verified
                  ? const Color(0xFF05884A)
                  : AppColors.danger;
              final statusBackground = loading || loadFailed
                  ? const Color(0xFFFFF2D6)
                  : verified
                  ? const Color(0xFFD0FBE5)
                  : const Color(0xFFFFE1E1);
              final heading = verified
                  ? 'Parent Account\nConnected'
                  : loading
                  ? 'Checking Parent\nAccount'
                  : !paired && !loadFailed
                  ? 'Parent Account\nNot Connected'
                  : 'Parent Account\nNot Verified';
              final helpText = loading
                  ? 'Checking the linked parent account...'
                  : loadFailed
                  ? 'Could not verify account details. Check your internet '
                        'connection and try again.'
                  : !paired
                  ? 'This parent link is missing or no longer valid. '
                        'Please pair this device again.'
                  : !identityReady
                  ? 'The device is paired, but the parent name and '
                        'email have not synced. Ask your parent to open '
                        'Devices and tap Sync Parent Details.'
                  : 'Parent account details verified for this pairing.';

              return Dialog(
                backgroundColor: Colors.white,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 49,
                            backgroundColor: verified
                                ? const Color(0xFFDDF7EB)
                                : statusBackground,
                            child: loading
                                ? const CircularProgressIndicator(color: purple)
                                : Icon(
                                    verified
                                        ? Icons.check_circle_rounded
                                        : Icons.error_rounded,
                                    color: statusColor,
                                    size: 77,
                                  ),
                          ),
                          const SizedBox(height: 22),
                          Text(
                            heading,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: darkText,
                              fontSize: 27,
                              height: 1.14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'This device is linked to the following parent account:',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: grayText,
                              fontSize: 15,
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECF4FF),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: const Color(0xFFD2E4FC),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const CircleAvatar(
                                  backgroundColor: Color(0xFFCCE2FF),
                                  radius: 31,
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 36,
                                    color: Color(0xFF2665C4),
                                  ),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        parentName.isNotEmpty
                                            ? parentName
                                            : 'Parent name not available',
                                        style: const TextStyle(
                                          color: darkText,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        parentEmail.isNotEmpty
                                            ? parentEmail
                                            : 'Email not available',
                                        softWrap: true,
                                        style: const TextStyle(
                                          color: grayText,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(height: 11),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusBackground,
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              color: statusColor,
                                              size: 9,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              statusText,
                                              style: TextStyle(
                                                color: statusColor,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!verified) ...[
                            const SizedBox(height: 12),
                            Text(
                              helpText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: grayText,
                              ),
                            ),
                          ],
                          const SizedBox(height: 26),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2963C3),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Continue',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
    );
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _scrollToSection(GlobalKey key) {
    final sectionContext = key.currentContext;
    if (sectionContext == null) return;

    Scrollable.ensureVisible(
      sectionContext,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  String formatDate(dynamic value) {
    if (value is Timestamp) {
      final date = value.toDate();
      final month = date.month.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final year = date.year.toString();
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$month/$day/$year $hour:$minute';
    }

    return 'Not available';
  }

  String locationText(Map<String, dynamic> data) {
    final latestLocation = data['latestLocation'];

    if (latestLocation is Map) {
      final label = latestLocation['label'];
      final latitude = latestLocation['latitude'];
      final longitude = latestLocation['longitude'];

      if (label != null && label.toString().isNotEmpty) {
        return label.toString();
      }

      if (latitude != null && longitude != null) {
        return '${formatCoordinate(latitude)}, ${formatCoordinate(longitude)}';
      }
    }

    return 'Not shared yet';
  }

  String locationUpdatedText(Map<String, dynamic> data) {
    final updatedAt = data['locationUpdatedAt'];

    if (updatedAt is Timestamp) {
      return formatDate(updatedAt);
    }

    return 'Waiting for update';
  }

  String formatCoordinate(dynamic value) {
    if (value is num) {
      return value.toStringAsFixed(5);
    }

    return value.toString();
  }

  bool isConnected(Map<String, dynamic> data) {
    final parentId = (data['pairedParentId'] ?? '').toString().trim();
    final profileId = (data['pairedChildProfileId'] ?? '').toString().trim();
    return data['pairingStatus'] == 'connected' &&
        parentId.isNotEmpty &&
        profileId.isNotEmpty;
  }

  String appTitle(AppRule rule) {
    final name = rule.appName.trim();

    if (name.isNotEmpty) {
      return name;
    }

    return rule.packageName.trim().isNotEmpty
        ? rule.packageName
        : 'Unknown App';
  }

  IconData appIconForName(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('youtube')) {
      return Icons.play_arrow_rounded;
    }

    if (lower.contains('tiktok') || lower.contains('music')) {
      return Icons.music_note_rounded;
    }

    if (lower.contains('facebook') || lower.contains('meta')) {
      return Icons.public_rounded;
    }

    if (lower.contains('game') ||
        lower.contains('mobile legends') ||
        lower.contains('roblox')) {
      return Icons.sports_esports_rounded;
    }

    if (lower.contains('chrome') ||
        lower.contains('browser') ||
        lower.contains('google')) {
      return Icons.language_rounded;
    }

    if (lower.contains('message') || lower.contains('chat')) {
      return Icons.chat_bubble_rounded;
    }

    return Icons.apps_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            // Deliberately does NOT block on ConnectionState.waiting the
            // way reports_screen.dart/parent_dashboard_screen.dart do -
            // this screen's ongoing background work (auto-location-share
            // timer, parent-phone-number sync below) depends on
            // _cachedUserData being kept current every time this builder
            // runs, so gating the whole subtree on "waiting" would delay
            // that. A genuine read failure is still surfaced rather than
            // silently rendering as an empty/unpaired profile.
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppErrorState(
                    title: 'Could Not Load Profile',
                    message:
                        'Something went wrong loading your '
                        'profile.\n\n${snapshot.error}',
                  ),
                ),
              );
            }

            final data = snapshot.data?.data() ?? <String, dynamic>{};
            final connected = isConnected(data);

            // Cached outside of build so _autoShareLocation() (fired by a
            // Timer.periodic with no widget context of its own) always has
            // the latest pairedParentId/pairedChildProfileId without
            // depending on this StreamBuilder being on-screen at the exact
            // moment the timer fires.
            _cachedUserData = data;

            if (connected) {
              _maybeSyncParentPhoneNumber(data);
              // First paired screen load can happen after the connectivity
              // status check. Defer a check-in until after this build.
              if (_lastPresenceWriteAttempt == null && _isOnline) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) unawaited(_publishOnlineHeartbeat());
                });
              }
            }
            _ensureAppTimeLimitSubscription(
              connected ? (data['pairedChildProfileId'] ?? '').toString() : '',
            );

            return ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                _topBar(),
                const SizedBox(height: 18),
                _studentProfileCard(data, connected),
                if (connected) ...[
                  const SizedBox(height: 14),
                  _monitoringDisclosureCard(),
                ],
                const SizedBox(height: 22),
                if (!connected)
                  KeyedSubtree(key: _pairingSectionKey, child: _pairingCard()),
                if (!connected) const SizedBox(height: 22),
                _screenTimeAndRiskSection(),
                const SizedBox(height: 18),
                _gpsCard(data, connected),
                if (connected) const SizedBox(height: 22),
                if (connected) _smsAlertsCard(),
                if (connected) const SizedBox(height: 22),
                if (connected) _activeRulesCard(data),
                if (connected) const SizedBox(height: 22),
                if (connected) _emergencyAccessCard(data),
                const SizedBox(height: 22),
                _topAppsSection(),
                const SizedBox(height: 22),
                _weeklyTrendSection(),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: WellScreenBottomNav(
        currentIndex: currentIndex,
        items: const [
          WellScreenNavItem(icon: Icons.home_rounded, label: 'Home'),
          WellScreenNavItem(icon: Icons.link_rounded, label: 'Pairing'),
          WellScreenNavItem(icon: Icons.settings_rounded, label: 'Settings'),
        ],
        onTap: handleBottomNavTap,
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [purple, deepPurple],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          // Long-press (not a visible button) opens the raw capture debug
          // log - this screen is rendered on the CHILD's device, and that
          // log is the child's own monitored browsing/usage data, so it
          // must not be one visible tap away from the child themselves.
          // Kept reachable at all (rather than deleted outright) only
          // because a researcher/parent doing hands-on troubleshooting may
          // still need it; a plain button here previously made it visible
          // to the monitored child during ordinary use, which defeats the
          // point of parental monitoring.
          GestureDetector(
            onLongPress: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CaptureDebugScreen()),
              );
            },
            child: _logoBox(),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'WellScreen',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ChatNotificationsScreen(),
              ),
            ),
            icon: const ChatUnreadBell(color: Colors.white, size: 29),
          ),
          IconButton(
            tooltip: 'Profile',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileSettingsScreen(),
                ),
              );
            },
            icon: const Icon(
              Icons.account_circle_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBox() {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(31),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(31),
        child: Image.asset(
          'assets/icons/wellscreen_icon.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.health_and_safety_rounded,
              color: purple,
              size: 38,
            );
          },
        ),
      ),
    );
  }

  /// Visible disclosure before a child visits system monitoring controls.
  /// Android's actual uninstall/permission dialogs belong to Android;
  /// WellScreen does not intercept or obstruct those system actions.
  Widget _monitoringDisclosureCard() {
    return _whiteCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.warning,
            size: 26,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Monitoring notice: Disabling WellScreen permissions, turning off '
              'monitoring, or uninstalling WellScreen will interrupt screen-time '
              'tracking and usage reports. Your parent may be notified if this '
              'device stops reporting. Android controls the uninstall process.',
              style: TextStyle(color: darkText, fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentProfileCard(Map<String, dynamic> data, bool connected) {
    final user = FirebaseAuth.instance.currentUser;

    final fullName = (data['fullName'] ?? user?.displayName ?? 'Student User')
        .toString();

    final email = (data['email'] ?? user?.email ?? '').toString();

    final photoUrl = (data['profilePhotoUrl'] ?? user?.photoURL ?? '')
        .toString();

    return _whiteCard(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 430;

          final profileRow = Row(
            children: [
              _profileAvatar(photoUrl, connected),
              const SizedBox(width: 14),
              Expanded(
                child: _profileInfo(
                  fullName: fullName,
                  email: email,
                  connected: connected,
                ),
              ),
            ],
          );

          final buttons = Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _smallPurpleButton(
                      label: connected ? 'Share GPS' : 'Pair Device',
                      onTap: () {
                        if (connected) {
                          shareCurrentLocation(data);
                        } else {
                          showMessage('Enter the pairing code below.');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _smallPurpleButton(
                      label: 'Profile',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ProfileSettingsScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (connected) ...[
                const SizedBox(height: 10),
                // Match the size of Share GPS / Profile without changing
                // existing Pairing, Settings, or Sync Usage controls.
                LayoutBuilder(
                  builder: (context, available) => Center(
                    child: SizedBox(
                      width: (available.maxWidth - 10) / 2,
                      child: _smallPurpleButton(
                        label: 'Chatbox',
                        onTap: openFamilyChat,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: _smallPurpleButton(
                    label: isSyncingUsage ? 'Syncing...' : 'Sync Usage',
                    onTap: isSyncingUsage ? null : () => syncUsageReport(data),
                  ),
                ),
                _syncStatusIndicator(),
              ],
            ],
          );

          if (compact) {
            return Column(
              children: [profileRow, const SizedBox(height: 14), buttons],
            );
          }

          return Row(
            children: [
              Expanded(child: profileRow),
              const SizedBox(width: 14),
              SizedBox(width: 250, child: buttons),
            ],
          );
        },
      ),
    );
  }

  Widget _profileAvatar(String photoUrl, bool connected) {
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 40,
        backgroundColor: connected ? softGreen : softBlue,
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                connected ? Icons.person_rounded : Icons.person_add_alt_rounded,
                color: connected ? teal : purple,
                size: 45,
              );
            },
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 40,
      backgroundColor: connected ? softGreen : softBlue,
      child: Icon(
        connected ? Icons.person_rounded : Icons.person_add_alt_rounded,
        color: connected ? teal : purple,
        size: 45,
      ),
    );
  }

  Widget _profileInfo({
    required String fullName,
    required String email,
    required bool connected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$fullName's Phone",
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: darkText,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: connected
                    ? (_isOnline ? teal : AppColors.danger)
                    : Colors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                connected
                    ? (_isOnline ? 'Online - $email' : 'Offline - $email')
                    : 'Waiting for parent pairing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: grayText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _smallPurpleButton({
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 40,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: purple,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _pairingCard() {
    return _whiteCard(
      child: Column(
        children: [
          const Icon(Icons.link_rounded, color: purple, size: 62),
          const SizedBox(height: 12),
          const Text(
            'Connect to Parent Dashboard',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkText,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter the 6-digit pairing code generated from the parent account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: grayText,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: pairingCodeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              letterSpacing: 7,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isPairing ? null : pairWithParent,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.verified_rounded),
              label: Text(
                isPairing ? 'Connecting...' : 'Pair Student Device',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: isPairing ? null : scanQrCode,
              style: OutlinedButton.styleFrom(
                foregroundColor: purple,
                side: const BorderSide(color: purple, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text(
                'Scan QR Code Instead',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _durationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${duration.inSeconds}s';
  }

  Widget _screenTimeAndRiskSection() {
    if (_loadingUsageDashboard) {
      return const SizedBox(
        height: 170,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final state = _usageDashboardState;

    if (state == null || !state.viewModel.hasUsagePermission) {
      return _usageAccessPrompt(state);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _screenTimeCard(state)),
        const SizedBox(width: 14),
        Expanded(child: _riskCard(state)),
      ],
    );
  }

  /// Shown when Android's "Usage Access" permission (a special permission
  /// only grantable from system Settings, not a normal runtime dialog)
  /// hasn't been granted yet - real device usage stats can't be read
  /// without it. loadTodayDashboardState() (usage_dashboard_service.dart)
  /// already falls back to a cached report when this happens; if there's
  /// no cache either, this prompts the child to grant access.
  Widget _usageAccessPrompt(UsageDashboardControllerState? state) {
    return _whiteCard(
      child: Column(
        children: [
          const Icon(Icons.bar_chart_rounded, color: purple, size: 42),
          const SizedBox(height: 10),
          Text(
            state?.viewModel.errorMessage ??
                'Usage access permission is required to show real screen '
                    'time data.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _smallPurpleButton(
            label: 'Grant Usage Access',
            onTap: () async {
              await _usageTrackingService.openUsageAccessSettings();
            },
          ),
        ],
      ),
    );
  }

  Widget _screenTimeCard(UsageDashboardControllerState state) {
    final goal = state.screenTimeGoalResult;
    final totalLabel = state.viewModel.totalUsageLabel;
    final limitLabel = _durationLabel(state.dailyScreenTimeLimit);
    final progress = (goal?.progressPercent ?? 0).clamp(0.0, 1.0);

    return _whiteCard(
      child: SizedBox(
        height: 170,
        child: Column(
          children: [
            const Text(
              'Screen Time\nToday',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: darkText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.25,
              ),
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                totalLabel,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Daily Limit: $limitLabel',
              style: const TextStyle(
                color: grayText,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                color: purple,
                backgroundColor: AppColors.track,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _riskCard(UsageDashboardControllerState state) {
    final status = state.viewModel.statusLabel;

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'Unhealthy':
        statusColor = AppColors.danger;
        statusIcon = Icons.warning_rounded;
        break;
      case 'Warning':
        statusColor = AppColors.warning;
        statusIcon = Icons.shield_moon_rounded;
        break;
      default:
        statusColor = teal;
        statusIcon = Icons.shield_rounded;
    }

    return _whiteCard(
      child: SizedBox(
        height: 170,
        child: Column(
          children: [
            const Text(
              'Usage Pattern',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: darkText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Icon(statusIcon, color: statusColor, size: 62),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                status,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                state.viewModel.unhealthyAppCountLabel,
                style: const TextStyle(
                  color: darkText,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsCard(Map<String, dynamic> data, bool connected) {
    final location = locationText(data);
    final updated = locationUpdatedText(data);

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: connected ? softGreen : softRed,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  connected
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: connected ? teal : Colors.redAccent,
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GPS Location',
                      style: TextStyle(
                        color: darkText,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      connected ? location : 'Pair device first',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: grayText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      connected
                          ? 'Updated: $updated'
                          : 'Location sharing becomes available after pairing.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: grayText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: connected && !isSharingLocation
                    ? () => shareCurrentLocation(data)
                    : null,
                icon: Icon(
                  isSharingLocation
                      ? Icons.sync_rounded
                      : Icons.my_location_rounded,
                  color: connected ? purple : grayText,
                  size: 30,
                ),
              ),
            ],
          ),
          // Passive nudge set by either the manual "Share GPS" button or
          // the periodic background auto-share timer detecting Android's
          // location services are off device-wide - see
          // _autoShareLocation()'s doc comment for why the background path
          // never pops an interruptive dialog on its own and relies on this
          // banner being visible whenever the user next opens the app.
          if (connected && _locationServicesDisabled) ...[
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _showEnableLocationServicesDialog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Location services are off - tap to enable GPS.',
                        style: TextStyle(
                          color: darkText,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Compact real online/offline + last-sync-outcome line shown right under
  /// the Sync Usage button, sourced from SyncStatusService (_isOnline) and
  /// _recordSyncOutcome's local log (_syncLog) - not a decorative always-on
  /// indicator. Full history with response/recovery times lives on
  /// ReportsScreen's Alerts tab (Synchronization Status card).
  Widget _syncStatusIndicator() {
    final lastOutcome = _syncLog.isNotEmpty
        ? _syncLog.last['outcome']?.toString()
        : null;

    String label;
    if (!_isOnline) {
      label =
          'Offline - usage data will sync automatically once '
          'reconnected.';
    } else if (lastOutcome == 'synced') {
      label =
          'Online - last sync succeeded. Also auto-syncs every '
          '${_usageAutoSyncInterval.inMinutes} min.';
    } else if (lastOutcome == 'queued_offline' ||
        lastOutcome == 'failed_timeout') {
      label = 'Online - usage recovery will run automatically when scheduled.';
    } else if (lastOutcome != null) {
      label = 'Online - last sync failed. Tap Sync Usage to retry.';
    } else {
      label =
          'Online - auto-syncs every '
          '${_usageAutoSyncInterval.inMinutes} min, or tap Sync Usage now.';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: _isOnline ? teal : Colors.redAccent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: grayText, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Backup SMS alert status. The actual send happens natively (see
  /// SmsAlertSender.kt, triggered from WellScreenAccessibilityService when
  /// a restricted app is blocked) so it keeps working even if this Flutter
  /// screen isn't open - this card only shows whether it's actually able to
  /// fire (permission + a cached parent phone number) and a running tally
  /// from the real local delivery log.
  Widget _smsAlertsCard() {
    final hasPhoneNumber = _cachedParentPhoneNumber != null;
    final sentCount = _smsAlertLog
        .where(
          (entry) =>
              entry['outcome'] == 'sent' || entry['outcome'] == 'delivered',
        )
        .length;
    final failedCount = _smsAlertLog
        .where(
          (entry) => (entry['outcome'] as String? ?? '').startsWith('failed'),
        )
        .length;

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sms_rounded, color: purple, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SMS Backup Alerts',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            !_smsPermissionGranted
                ? 'Off. Grant SMS permission so a backup text alert can '
                      'reach your parent even without internet, when a '
                      'restricted app is opened.'
                : hasPhoneNumber
                ? 'Enabled. Blocked-app alerts will text '
                      '${_maskPhoneNumber(_cachedParentPhoneNumber!)}.'
                : 'Permission granted, but your parent hasn\'t added a '
                      'phone number yet in their Profile Settings.',
            style: const TextStyle(
              color: grayText,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (!_smsPermissionGranted) ...[
            const SizedBox(height: 12),
            _smallPurpleButton(
              label: 'Enable SMS Alerts',
              onTap: _requestSmsPermission,
            ),
          ],
          if (_smsAlertLog.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Recent attempts: $sentCount sent, $failedCount failed',
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Child-requests-temporary-bypass card (EmergencyAccessService). Only
  /// shown once paired - a request needs a parent to notify and a
  /// child_profiles doc to write the status onto, same precondition as
  /// _activeRulesCard right below.
  Widget _emergencyAccessCard(Map<String, dynamic> data) {
    final parentId = (data['pairedParentId'] ?? '').toString();
    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (parentId.isEmpty || childProfileId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _emergencyAccessService.watchStatus(childProfileId),
      builder: (context, snapshot) {
        final status = (snapshot.data?['status'] ?? 'none').toString();

        return _whiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: softRed,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.lock_open_rounded,
                      color: AppColors.danger,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Emergency Access',
                      style: TextStyle(
                        color: darkText,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _emergencyAccessBody(
                status,
                snapshot.data ?? const {},
                childProfileId,
                parentId,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _emergencyAccessBody(
    String status,
    Map<String, dynamic> statusData,
    String childProfileId,
    String parentId,
  ) {
    switch (status) {
      case 'requested':
        return const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: purple),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Waiting for your parent to respond to your request...',
                style: TextStyle(
                  color: grayText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        );
      case 'approved':
        final grantedUntil = statusData['grantedUntil'];
        final until = grantedUntil is Timestamp ? grantedUntil.toDate() : null;
        final stillActive = until != null && until.isAfter(DateTime.now());

        if (stillActive) {
          final hh = until.hour.toString().padLeft(2, '0');
          final mm = until.minute.toString().padLeft(2, '0');
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: softGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Approved - restrictions are lifted until $hh:$mm.',
                    style: const TextStyle(
                      color: darkText,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return _emergencyAccessRequestForm(childProfileId, parentId);
      case 'denied':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: softRed,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cancel_rounded, color: AppColors.danger, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your parent denied your last request.',
                      style: TextStyle(
                        color: darkText,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _emergencyAccessRequestForm(childProfileId, parentId),
          ],
        );
      case 'none':
      default:
        return _emergencyAccessRequestForm(childProfileId, parentId);
    }
  }

  Widget _emergencyAccessRequestForm(String childProfileId, String parentId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Need a restricted app for something urgent? Ask your parent to '
          'temporarily lift restrictions.',
          style: TextStyle(
            color: grayText,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: emergencyReasonController,
          maxLength: 140,
          decoration: InputDecoration(
            hintText: 'Reason (optional) - e.g. "need calculator app"',
            isDense: true,
            filled: true,
            fillColor: pageBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            counterText: '',
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isRequestingEmergencyAccess
                ? null
                : () => requestEmergencyAccess(childProfileId, parentId),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: isRequestingEmergencyAccess
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.lock_open_rounded, size: 19),
            label: Text(
              isRequestingEmergencyAccess ? 'Sending...' : 'Request Access',
            ),
          ),
        ),
      ],
    );
  }

  Future<void> requestEmergencyAccess(
    String childProfileId,
    String parentId,
  ) async {
    setState(() => isRequestingEmergencyAccess = true);

    try {
      await _emergencyAccessService.requestAccess(
        childProfileId: childProfileId,
        parentId: parentId,
        reason: emergencyReasonController.text,
      );
      emergencyReasonController.clear();
      showMessage('Request sent - your parent has been notified.');
    } catch (e) {
      showMessage('Could not send request: $e');
    } finally {
      if (mounted) {
        setState(() => isRequestingEmergencyAccess = false);
      }
    }
  }

  Widget _activeRulesCard(Map<String, dynamic> data) {
    final parentId = (data['pairedParentId'] ?? '').toString();

    if (parentId.isEmpty) {
      return _rulesMessageCard(
        icon: Icons.sync_problem_rounded,
        title: 'Rules Sync Waiting',
        message:
            'The parent account is connected, but the rule source is not ready yet.',
      );
    }

    return StreamBuilder<List<AppRule>>(
      stream: _rulesService.watchRulesForParent(parentId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _rulesMessageCard(
            icon: Icons.warning_rounded,
            title: 'Rules Sync Error',
            message: 'Unable to load monitored and restricted apps right now.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _whiteCard(
            child: const Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: purple,
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Loading parent app rules...',
                    style: TextStyle(
                      color: grayText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final rules = snapshot.data ?? <AppRule>[];

        final activeRules =
            rules
                .where((rule) => rule.monitorEnabled || rule.restrictEnabled)
                .toList()
              ..sort(
                (a, b) => appTitle(
                  a,
                ).toLowerCase().compareTo(appTitle(b).toLowerCase()),
              );

        final monitoredCount = activeRules
            .where((rule) => rule.monitorEnabled)
            .length;

        final restrictedCount = activeRules
            .where((rule) => rule.restrictEnabled)
            .length;

        final restrictedRules = activeRules
            .where((rule) => rule.restrictEnabled)
            .toList();

        final monitoredOnlyRules = activeRules
            .where((rule) => rule.monitorEnabled && !rule.restrictEnabled)
            .toList();

        if (activeRules.isEmpty) {
          return _rulesMessageCard(
            icon: Icons.rule_folder_rounded,
            title: 'No Active App Rules',
            message:
                'When the parent selects Monitor or Restrict in View Rules, the apps will appear here.',
          );
        }

        return _whiteCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: softBlue,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: purple,
                      size: 31,
                    ),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Parent App Rules',
                          style: TextStyle(
                            color: darkText,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Synced from parent dashboard',
                          style: TextStyle(
                            color: grayText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ruleCountBadge(
                      label: 'Monitored',
                      count: monitoredCount,
                      icon: Icons.visibility_rounded,
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ruleCountBadge(
                      label: 'Restricted',
                      count: restrictedCount,
                      icon: Icons.block_rounded,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
              if (restrictedRules.isNotEmpty) const SizedBox(height: 18),
              if (restrictedRules.isNotEmpty)
                _appRuleGroup(
                  title: 'Restricted Apps',
                  rules: restrictedRules,
                  color: AppColors.danger,
                  icon: Icons.block_rounded,
                ),
              if (monitoredOnlyRules.isNotEmpty) const SizedBox(height: 18),
              if (monitoredOnlyRules.isNotEmpty)
                _appRuleGroup(
                  title: 'Monitored Apps',
                  rules: monitoredOnlyRules,
                  color: AppColors.info,
                  icon: Icons.visibility_rounded,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _rulesMessageCard({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return _whiteCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: softBlue,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: purple, size: 31),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: darkText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: grayText,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruleCountBadge({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$count $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _appRuleGroup({
    required String title,
    required List<AppRule> rules,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(width: 7),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...rules.map((rule) => _appRuleRow(rule)),
      ],
    );
  }

  Widget _appRuleRow(AppRule rule) {
    final name = appTitle(rule);
    final restricted = rule.restrictEnabled;
    final color = restricted ? AppColors.danger : AppColors.info;

    final status = restricted
        ? rule.monitorEnabled
              ? 'Blocked + Monitored'
              : 'Blocked'
        : 'Monitored';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: pageBg,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: color,
            child: Icon(appIconForName(name), color: Colors.white, size: 26),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  rule.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: grayText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Was explicitly labeled "Demo Data" with four hardcoded rows - honest
  /// about being fake, but still fake. Now reads
  /// UsageDashboardControllerState.appUsageList, the real top-10
  /// UsageStats-backed list loaded in _loadUsageDashboard().
  Widget _topAppsSection() {
    final apps = (_usageDashboardState?.appUsageList ?? []).take(4).toList();
    final maxDurationMs = apps
        .map((app) => app.usageDuration.inMilliseconds)
        .fold<int>(0, (highest, value) => value > highest ? value : highest);

    return _whiteCard(
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Top Apps Today',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loadingUsageDashboard)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No app usage recorded yet today.',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w600),
              ),
            )
          else
            ...apps.map((app) {
              final ratio = maxDurationMs > 0
                  ? app.usageDuration.inMilliseconds / maxDurationMs
                  : 0.0;

              return _appUsageRow(
                icon: _iconForAppName(app.displayName),
                iconColor: purple,
                appName: app.displayName,
                time: app.usageLabel,
                value: ratio.clamp(0.0, 1.0),
              );
            }),
        ],
      ),
    );
  }

  IconData _iconForAppName(String name) {
    final lower = name.toLowerCase();

    if (lower.contains('youtube') || lower.contains('video')) {
      return Icons.play_arrow_rounded;
    }
    if (lower.contains('tiktok') || lower.contains('music')) {
      return Icons.music_note_rounded;
    }
    if (lower.contains('facebook') ||
        lower.contains('chrome') ||
        lower.contains('browser')) {
      return Icons.public_rounded;
    }
    if (lower.contains('game') ||
        lower.contains('legends') ||
        lower.contains('pubg')) {
      return Icons.sports_esports_rounded;
    }

    return Icons.apps_rounded;
  }

  Widget _appUsageRow({
    required IconData icon,
    required Color iconColor,
    required String appName,
    required String time,
    required double value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 17),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: iconColor,
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    color: purple,
                    backgroundColor: AppColors.track,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Same fabricated Mon-Sun bar chart as the parent dashboard's version -
  /// see the note on ParentDashboardScreen._weeklyTrendSection. No daily
  /// history is stored yet, so this is an honest placeholder instead.
  Widget _weeklyTrendSection() {
    return _whiteCard(
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Weekly Trend',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Icon(Icons.bar_chart_rounded, color: grayText, size: 42),
          const SizedBox(height: 10),
          const Text(
            'Weekly trends aren\'t available yet',
            textAlign: TextAlign.center,
            style: TextStyle(color: darkText, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'This needs several days of usage reports stored per day. '
            'Today\'s data only, for now.',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _whiteCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: child,
    );
  }
}
