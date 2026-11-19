import '../services/pairing_api_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';

import '../models/app_rule.dart';
import '../models/app_time_limit.dart';
import '../models/app_usage_summary.dart';
import '../models/usage_report.dart';
import '../services/alert_notification_client.dart';
import '../services/android_app_service.dart';
import '../services/monitoring_usage_alert_service.dart';
import '../services/installed_app_metadata_service.dart';
import '../services/location_geocoding_service.dart';
import '../services/app_rules_service.dart';
import '../services/app_time_limit_service.dart';
import '../services/app_time_limit_notification_service.dart';
import '../services/daily_screen_time_limit_service.dart';
import '../services/daily_usage_history.dart';
import '../services/emergency_access_service.dart';
import '../services/ml_risk_classifier_service.dart';
import '../services/site_category_service.dart';
import '../services/sync_status_service.dart';
import '../services/usage_dashboard_controller_service.dart';
import '../services/usage_tracking_service.dart';
import '../services/temporary_app_grant_service.dart';
import '../services/chat_notifications_service.dart';
import '../services/chat_unread_service.dart';
import '../services/parent_phone_sync_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';
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
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;
  static const Color softBlue = AppColors.infoBg;

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
  // Real on/off state of WellScreen's Accessibility service (null = unknown)
  // and the value last sent to the guardian.
  bool? _accessibilityEnabled;
  bool? _reportedAccessibilityEnabled;
  // Same for Android's Usage Access permission (daily limits need it).
  bool? _usageAccessEnabled;
  bool? _reportedUsageAccessEnabled;
  // Setup checklist only (not sent to the guardian).
  bool? _batteryUnrestricted;
  bool? _deviceAdminActive;
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
  String? _syncedProfileIdForPhoneNumber;

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

  // ---------------------------------------------------------------------
  // Presentation-only tokens and state for the redesigned child UI.
  // Nothing below changes what is written to Firestore, SharedPreferences,
  // or the native layer - it only decides how existing data is drawn.
  // ---------------------------------------------------------------------
  static const Color _brandIndigo = AppColors.primary;
  static const Color _ink = AppColors.textPrimary;
  static const Color _slate = AppColors.textSecondary;
  static const Color _hairline = AppColors.border;
  static const Color _emerald = Color(0xFF10B981);
  static const Color _emeraldTint = Color(0xFFECFDF5);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _amberTint = Color(0xFFFFFBEB);
  static const Color _coral = Color(0xFFEF4444);
  static const Color _coralTint = Color(0xFFFEE2E2);
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  final LocationGeocodingService _geocodingService = LocationGeocodingService();
  final AndroidAppService _androidAppService = AndroidAppService();

  // Reverse-geocoded address for the Safety tab's GPS card (read-side only;
  // the shared location document is untouched).
  String? _geocodeKey;
  String? _geocodedAddress;

  // Real installed-app labels/icons (InstalledAppMetadataService), cached so
  // chips and rows do not re-decode icons on every rebuild.
  final Map<String, String> _appLabelCache = <String, String>{};
  final Map<String, Uint8List> _appIconCache = <String, Uint8List>{};
  final Set<String> _appMetadataRequested = <String>{};

  // Mon-Sun screen time for the current week, read from Android's own usage
  // history. null = no reading for that day (future day or not available).
  List<Duration?> _weeklyUsage = List<Duration?>.filled(7, null);
  bool _weeklyUsageLoaded = false;

  // Last values seen from the rules / time-limit streams, so the chip row
  // keeps its content while a stream re-subscribes after a rebuild.
  List<AppRule>? _lastRules;
  List<AppTimeLimit>? _lastTimeLimits;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Store this child device's FCM token so approve/decline pushes can arrive.
    unawaited(PushNotificationService().registerDeviceToken());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ChatNotificationsService.instance.markDashboardReady();
    });
    _loadUsageDashboard();
    _loadWeeklyUsage();
    _refreshSmsAlertStatus();
    _refreshSyncStatus();
    unawaited(_refreshAccessibilityStatus());
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
      (_) {
        unawaited(_refreshAccessibilityStatus());
        unawaited(_publishOnlineHeartbeat());
      },
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
      _loadWeeklyUsage();
      _refreshSmsAlertStatus();
      _refreshSyncStatus();
      unawaited(_refreshAccessibilityStatus());
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
  /// package lists. The number is the guardian's verified number, copied
  /// onto this child's profile by ParentPhoneSyncService.
  Future<void> _maybeSyncParentPhoneNumber(Map<String, dynamic> data) async {
    // The guardian's verified number is copied onto this child's own
    // profile (child_profiles/{id}.parentPhoneNumber) by the guardian's app
    // - see ParentPhoneSyncService. The child cannot read the guardian's
    // private users/{uid} record, and cannot change this field itself.
    final profileId = (data['pairedChildProfileId'] ?? '').toString();

    if (profileId.isEmpty || profileId == _syncedProfileIdForPhoneNumber) {
      return;
    }

    _syncedProfileIdForPhoneNumber = profileId;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('child_profiles')
          .doc(profileId)
          .get();

      final phoneNumber =
          (doc.data()?[ParentPhoneSyncService.field] ?? '').toString().trim();
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
  Future<void> _refreshAccessibilityStatus() async {
    final enabled = await _androidAppService.isAccessibilityServiceEnabled();
    bool? usageEnabled;
    try {
      usageEnabled = await _usageTrackingService.hasUsagePermission();
    } catch (_) {
      usageEnabled = null;
    }
    final batteryUnrestricted =
        await _androidAppService.isIgnoringBatteryOptimizations();
    final deviceAdminActive = await _androidAppService.isDeviceAdminActive();
    if (!mounted) return;
    if (enabled != _accessibilityEnabled ||
        usageEnabled != _usageAccessEnabled ||
        batteryUnrestricted != _batteryUnrestricted ||
        deviceAdminActive != _deviceAdminActive) {
      setState(() {
        _accessibilityEnabled = enabled;
        _usageAccessEnabled = usageEnabled;
        _batteryUnrestricted = batteryUnrestricted;
        _deviceAdminActive = deviceAdminActive;
      });
    }
    // Tell the guardian straight away when either changes.
    final accessibilityChanged =
        enabled != null && enabled != _reportedAccessibilityEnabled;
    final usageChanged =
        usageEnabled != null && usageEnabled != _reportedUsageAccessEnabled;
    if (accessibilityChanged || usageChanged) {
      _lastPresenceWriteAttempt = null;
      unawaited(_publishOnlineHeartbeat());
    }
  }

  /// Protection status fields sent with the heartbeat. Written separately
  /// from lastSeenAt, so if the Firestore rules on the server are older and
  /// refuse a new field, the "online" check-in itself still succeeds.
  Future<void> _publishProtectionStatus(String profileId) async {
    final usageEnabled = _usageAccessEnabled;

    // Location: phone GPS switched on AND WellScreen allowed to use it.
    bool? locationEnabled;
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      locationEnabled =
          serviceOn &&
          (permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse);
    } catch (_) {
      locationEnabled = null;
    }

    // SMS backup alerts need the SMS permission on this phone.
    bool? smsGranted;
    try {
      smsGranted = (await Permission.sms.status).isGranted;
    } catch (_) {
      smsGranted = null;
    }

    final update = <String, dynamic>{
      'usageAccessEnabled': ?usageEnabled,
      'locationEnabled': ?locationEnabled,
      'smsPermissionGranted': ?smsGranted,
    };
    if (update.isEmpty) return;
    update['usageAccessCheckedAt'] = FieldValue.serverTimestamp();

    try {
      await FirebaseFirestore.instance
          .collection('child_profiles')
          .doc(profileId)
          .update(update)
          .timeout(const Duration(seconds: 10));
      if (usageEnabled != null) _reportedUsageAccessEnabled = usageEnabled;
    } catch (error) {
      debugPrint('Child protection status update failed: $error');
    }
  }

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
          .update({
            'lastSeenAt': FieldValue.serverTimestamp(),
            if (_accessibilityEnabled != null) ...{
              'accessibilityEnabled': _accessibilityEnabled,
              'accessibilityCheckedAt': FieldValue.serverTimestamp(),
            },
          })
          .timeout(const Duration(seconds: 10));
      if (_accessibilityEnabled != null) {
        _reportedAccessibilityEnabled = _accessibilityEnabled;
      }
    } catch (error) {
      _lastPresenceWriteAttempt = null;
      debugPrint('Child presence check-in failed: $error');
      return;
    }
    await _publishProtectionStatus(profileId);
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
    if (isPairing) return;

    final code = pairingCodeController.text.trim().replaceAll(' ', '');
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    if (!RegExp(r'^[0-9]{6}$').hasMatch(code)) {
      showMessage('Please enter a valid 6-digit pairing code.');
      return;
    }

    setState(() => isPairing = true);

    try {
      final result = await PairingApiService().redeemCode(
        code: code,
      );

      if (!mounted) return;

      pairingCodeController.clear();

      showConnectedSuccessDialog(
        parentId: result.parentId,
        childProfileId: result.childProfileId,
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(e.toString().replaceFirst('Exception: ', ''));
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
      // True when a fake-GPS app supplied this location (G2).
      'isMocked': position.isMocked,
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

      // The guardian's App Rules screen lists the apps installed on THIS
      // phone (not the guardian's). Best-effort: an empty list is simply
      // not sent, so a platform-channel hiccup never erases the last one.
      List<Map<String, String>> installedApps = const [];
      try {
        installedApps = (await _androidAppService.getInstalledApps())
            .where((app) => app.packageName.isNotEmpty)
            .map(
              (app) => {
                'packageName': app.packageName,
                'appName': app.appName.isEmpty ? app.packageName : app.appName,
              },
            )
            .toList();
      } catch (_) {
        // Keep the previously synced list.
      }

      Map<String, int> dailyUsageTotals = const {};
      try {
        dailyUsageTotals = await _dailyUsageTotalsForSync(
          report.totalUsageDuration,
        );
      } catch (_) {
        // Best-effort: the guardian's weekly chart just keeps its last data.
      }

      // _attemptFirestoreSync handles offline detection, the write timeout
      // (cloud_firestore's set() hangs forever offline instead of throwing
      // - firebase/flutterfire#17643), local queuing for automatic retry on
      // reconnect, and outcome logging - see its doc comment above.
      final synced = await _attemptFirestoreSync(
        childProfileId: childProfileId,
        payload: {
          'latestUsageReport': usageReportData,
          if (installedApps.isNotEmpty) 'installedApps': installedApps,
          if (smsAlertLog.isNotEmpty) 'smsAlertLog': smsAlertLog,
          if (restrictionLog.isNotEmpty) 'restrictionLog': restrictionLog,
          if (syncLog.isNotEmpty) 'syncLog': syncLog,
          if (categorizedBrowsingLog.isNotEmpty)
            'browsingLog': categorizedBrowsingLog,
          'mlRiskAssessment': ?mlRiskAssessmentData,
          if (dailyUsageTotals.isNotEmpty) 'dailyUsageTotals': dailyUsageTotals,
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
          restrictionLog: restrictionLog,
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
    // Daily limits stay in the native cache after sign-out on purpose:
    // the native AccessibilityService keeps enforcing them, so signing out
    // is not a way around the guardian's limits. The cache is replaced when
    // a different child profile is opened (prepareCacheForChild).
    _timeLimitWatchGeneration++;
    final previous = _appTimeLimitSubscription;
    _appTimeLimitSubscription = null;
    _timeLimitProfileId = null;
    await previous?.cancel();
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
    // Chat is the existing full-screen Parent-Child Chatbox, pushed on top
    // of the tabs so its own app bar, input field and keyboard handling
    // stay exactly as they were.
    if (index == 1) {
      openFamilyChat();
      return;
    }

    if (index == currentIndex) return;

    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    setState(() => currentIndex = index);
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
                              borderRadius: BorderRadius.circular(20),
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
                                    color: Color(0xFF2563EB),
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
                                backgroundColor: const Color(0xFF2563EB),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: const StadiumBorder(),
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

    // System gesture/3-button inset, read above the Scaffold so the floating
    // navigation pill never covers the last card of a tab.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: pageBg,
      extendBody: true,
      body: SafeArea(
        bottom: false,
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
            // moment the timer fires. This builder stays mounted on every
            // tab (Home / Safety / Settings) for the same reason.
            _cachedUserData = data;
            // The Chat tab's unread dot is built outside this stream, so
            // redraw it once the paired profile is known.
            final pairedProfile = (data['pairedChildProfileId'] ?? '')
                .toString();
            if (pairedProfile != (_chatUnreadProfileId ?? '')) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }

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

            final List<Widget> tabChildren;
            switch (currentIndex) {
              case 2:
                tabChildren = _safetyTab(data, connected);
                break;
              case 3:
                tabChildren = _settingsTab(data, connected);
                break;
              default:
                tabChildren = _homeTab(data, connected);
            }

            return Column(
              children: [
                _topBar(data),
                Expanded(
                  child: ListView(
                    key: ValueKey<int>(currentIndex),
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 112 + bottomInset),
                    children: tabChildren,
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: _bottomNav(user.uid),
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
                shape: const StadiumBorder(),
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
                shape: const StadiumBorder(),
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

  /// Shown when Android's "Usage Access" permission (a special permission
  /// only grantable from system Settings, not a normal runtime dialog)
  /// hasn't been granted yet - real device usage stats can't be read
  /// without it. loadTodayDashboardState() (usage_dashboard_service.dart)
  /// already falls back to a cached report when this happens; if there's
  /// no cache either, this prompts the child to grant access.
  Widget _usageAccessPrompt(UsageDashboardControllerState? state) {
    return _whiteCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFFDBEAFE),
            child: Icon(Icons.bar_chart_rounded, color: purple, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Screen time needs access',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  state?.viewModel.errorMessage ??
                      'Allow usage access to show real screen time.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: grayText, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: FilledButton(
              onPressed: () async {
                await _usageTrackingService.openUsageAccessSettings();
              },
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Allow',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
          ),
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
      label = 'Offline - will sync when reconnected';
    } else if (lastOutcome == 'synced') {
      label = 'Synced - auto-syncs every ${_usageAutoSyncInterval.inMinutes} min';
    } else if (lastOutcome == 'queued_offline' ||
        lastOutcome == 'failed_timeout') {
      label = 'Online - usage recovery will run automatically when scheduled.';
    } else if (lastOutcome != null) {
      label = 'Online - last sync failed. Tap Sync Usage to retry.';
    } else {
      label = 'Auto-syncs every ${_usageAutoSyncInterval.inMinutes} min';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
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
                      borderRadius: BorderRadius.circular(20),
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
              borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
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

  // =====================================================================
  // Redesigned presentation layer (Home / Safety / Settings tabs).
  // Every value shown here is read from the same state, streams and
  // services the previous layout used.
  // =====================================================================

  // ------------------------------ helpers ------------------------------

  /// Total screen time between [start] and [end] from Android's
  /// UsageStats, summarized the same way as today's total.
  Future<Duration> _usageTotalForRange(DateTime start, DateTime end) async {
    final usage = await UsageStats.queryAndAggregateUsageStats(start, end);
    final milliseconds = <String, int>{
      for (final entry in usage.entries)
        entry.key: int.tryParse(entry.value.totalTimeInForeground ?? '0') ?? 0,
    };
    return _usageTrackingService
        .summarizeUsage(milliseconds)
        .fold<Duration>(
          Duration.zero,
          (total, app) => total + app.usageDuration,
        );
  }

  /// Per-day totals for the guardian's 7-day chart and 30-day average
  /// (see DailyUsageHistory). Today comes from the report being synced;
  /// the previous 6 days are re-read from UsageStats once a day (Android
  /// keeps about a week of daily history) and older days stay as last
  /// stored. Best-effort: on any error the stored map is returned as-is.
  Future<Map<String, int>> _dailyUsageTotalsForSync(Duration today) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final stored = DailyUsageHistory.parse(
      prefs.getString(DailyUsageHistory.prefsKey),
    );
    final fresh = <String, int>{
      DailyUsageHistory.dayKey(todayStart): today.inMilliseconds,
    };
    final todayKey = DailyUsageHistory.dayKey(todayStart);
    try {
      if (prefs.getString(DailyUsageHistory.refreshedDayKey) != todayKey) {
        for (var i = 1; i <= 6; i++) {
          final start = DateTime(now.year, now.month, now.day - i);
          final end = DateTime(now.year, now.month, now.day - i + 1);
          final total = await _usageTotalForRange(start, end);
          fresh[DailyUsageHistory.dayKey(start)] = total.inMilliseconds;
        }
        await prefs.setString(DailyUsageHistory.refreshedDayKey, todayKey);
      }
    } catch (error) {
      debugPrint('Could not read past daily usage: $error');
    }
    final merged = DailyUsageHistory.merge(stored, fresh, now);
    await prefs.setString(DailyUsageHistory.prefsKey, jsonEncode(merged));
    return merged;
  }

  /// Mon-Sun totals for the current week from Android's own usage history
  /// (the same UsageStats source and top-app summary used for today's
  /// total), so the Weekly Summary chart shows real readings only.
  Future<void> _loadWeeklyUsage() async {
    try {
      if (!await _usageTrackingService.hasUsagePermission()) return;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final week = List<Duration?>.filled(7, null);

      for (var i = 0; i < 7; i++) {
        final start = DateTime(monday.year, monday.month, monday.day + i);
        if (start.isAfter(today)) break;
        final end = start.isAtSameMomentAs(today)
            ? now
            : DateTime(monday.year, monday.month, monday.day + i + 1);

        week[i] = await _usageTotalForRange(start, end);
      }

      if (!mounted) return;
      setState(() {
        _weeklyUsage = week;
        _weeklyUsageLoaded = true;
      });
    } catch (error) {
      debugPrint('Could not load weekly usage: $error');
      if (!mounted) return;
      setState(() => _weeklyUsageLoaded = true);
    }
  }

  /// Looks up real app labels/icons once per package for display.
  void _ensureAppMetadata(Iterable<String> packageNames) {
    final missing = <String>[];
    for (final packageName in packageNames) {
      if (packageName.isEmpty) continue;
      if (_appMetadataRequested.add(packageName)) missing.add(packageName);
    }
    if (missing.isEmpty) return;
    unawaited(_fetchAppMetadata(missing));
  }

  Future<void> _fetchAppMetadata(List<String> packageNames) async {
    final metadata = await const InstalledAppMetadataService().lookup(
      packageNames,
    );
    if (!mounted || metadata.isEmpty) return;

    final labels = <String, String>{};
    final icons = <String, Uint8List>{};
    for (final entry in metadata.entries) {
      final label = entry.value['displayName'];
      if (label != null && label.isNotEmpty && label != entry.key) {
        labels[entry.key] = label;
      }
      final icon = entry.value['iconBase64'];
      if (icon != null && icon.isNotEmpty) {
        try {
          icons[entry.key] = base64Decode(icon);
        } on FormatException {
          // Malformed icon data: the initial-letter avatar is used instead.
        }
      }
    }

    setState(() {
      _appLabelCache.addAll(labels);
      _appIconCache.addAll(icons);
    });
  }

  /// Hides Android system / launcher packages from display lists only. The
  /// underlying usage data and reports are not filtered.
  bool _isSystemPackage(String packageName) {
    final package = packageName.toLowerCase();
    return package.contains('launcher') ||
        package.contains('permissioncontroller') ||
        package.contains('systemui') ||
        package.contains('packageinstaller') ||
        package.endsWith('.settings');
  }

  List<AppUsageSummary> _visibleTodayApps() {
    return (_usageDashboardState?.appUsageList ?? <AppUsageSummary>[])
        .where((app) => !_isSystemPackage(app.packageName))
        .toList();
  }

  String _appLabel(String packageName, String fallback) {
    return _appLabelCache[packageName] ?? fallback;
  }

  Widget _appAvatar({
    required String packageName,
    required String name,
    required double size,
  }) {
    final bytes = _appIconCache[packageName];
    if (bytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              _initialAvatar(name, size),
        ),
      );
    }
    return _initialAvatar(name, size);
  }

  Widget _initialAvatar(String name, double size) {
    const palette = <Color>[
      Color(0xFF2563EB),
      Color(0xFF0D9488),
      Color(0xFFDB2777),
      Color(0xFFD97706),
      Color(0xFF7C3AED),
      Color(0xFF059669),
    ];
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final color = palette[trimmed.hashCode.abs() % palette.length];

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.5,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  String _lastSyncLabel() {
    int? lastSyncedMs;
    for (final entry in _syncLog.reversed) {
      final timestamp = entry['timestampMs'];
      if (entry['outcome'] == 'synced' && timestamp is int) {
        lastSyncedMs = timestamp;
        break;
      }
    }
    if (lastSyncedMs == null) return 'Not synced yet';

    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(lastSyncedMs),
    );
    if (elapsed.inMinutes < 1) return 'Synced just now';
    if (elapsed.inMinutes < 60) return 'Synced ${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return 'Synced ${elapsed.inHours}h ago';
    return 'Synced ${elapsed.inDays}d ago';
  }

  String? _coordinatesText(Map<String, dynamic> data) {
    final latestLocation = data['latestLocation'];
    if (latestLocation is! Map) return null;
    final latitude = latestLocation['latitude'];
    final longitude = latestLocation['longitude'];
    if (latitude == null || longitude == null) return null;
    return '${formatCoordinate(latitude)}, ${formatCoordinate(longitude)}';
  }

  /// Resolves a readable address for the latest shared coordinates using
  /// the existing LocationGeocodingService. Display only.
  void _ensureGeocodedAddress(Map<String, dynamic> data) {
    final latestLocation = data['latestLocation'];
    if (latestLocation is! Map) return;
    final latitude = latestLocation['latitude'];
    final longitude = latestLocation['longitude'];
    if (latitude is! num || longitude is! num) return;

    final key =
        '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}';
    if (key == _geocodeKey) return;
    _geocodeKey = key;
    _geocodedAddress = null;
    unawaited(_resolveAddress(key, latitude.toDouble(), longitude.toDouble()));
  }

  Future<void> _resolveAddress(
    String key,
    double latitude,
    double longitude,
  ) async {
    final address = await _geocodingService.reverseGeocode(
      latitude: latitude,
      longitude: longitude,
    );
    if (!mounted || key != _geocodeKey) return;
    setState(() => _geocodedAddress = address);
  }

  Future<void> _openAccessibilitySettings() async {
    try {
      await _androidAppService.openAccessibilitySettings();
    } catch (_) {
      showMessage(
        'Could not open Accessibility settings. Open them from the '
        'Android Settings app.',
      );
    }
  }

  Future<void> _openBatterySettings() async {
    final opened = await _androidAppService.openBatteryOptimizationSettings();
    if (!opened) {
      showMessage(
        'Could not open battery settings. Open Settings > Apps > '
        'Special app access > Battery optimization and set WellScreen '
        'to Not optimized.',
      );
    }
  }

  Future<void> _requestDeviceAdmin() async {
    final opened = await _androidAppService.requestDeviceAdmin();
    if (!opened) {
      showMessage(
        'Could not open uninstall protection. Open Settings > Security > '
        'Device admin apps and turn on WellScreen.',
      );
    }
  }

  void _goToSafetyTab({bool scrollToPairing = false}) {
    handleBottomNavTap(2);
    if (!scrollToPairing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToSection(_pairingSectionKey);
    });
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to use WellScreen on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _coral),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) await logout();
  }

  // ------------------------- shared building blocks ----------------------

  Widget _whiteCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    double radius = AppRadius.card,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A111827),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(
    String title, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (actionLabel != null)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  color: _brandIndigo,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pill({
    required String label,
    required Color background,
    required Color foreground,
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    double fontSize = 11,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontFeatures: _tabular,
        ),
      ),
    );
  }

  Widget _sheetGrabber() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: _hairline,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  // ------------------------------- top bar -------------------------------

  PreferredSizeWidget _topBar(Map<String, dynamic> data) {
    final user = FirebaseAuth.instance.currentUser;
    final photoUrl = (data['profilePhotoUrl'] ?? user?.photoURL ?? '')
        .toString();

    return WellScreenAppBar.primary(
      onMenu: () => _showMenuSheet(data),
      // Developer builds only: long-press opens the raw capture debug log.
      // Release APKs have no way in, since that log is the child's own
      // monitored browsing data.
      onTitleLongPress: kDebugMode
          ? () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CaptureDebugScreen()),
              );
            }
          : null,
      onAvatar: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      ),
      avatar: photoUrl.isEmpty
          ? null
          : Image.network(
              photoUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: AppColors.primaryLight,
                child: Icon(
                  Icons.person_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
            ),
      actions: [
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatNotificationsScreen()),
          ),
          icon: _notificationBell(),
        ),
      ],
    );
  }

  /// The two-line menu: only actions that fit here and are not already on
  /// the dock's own tabs.
  void _showMenuSheet(Map<String, dynamic> data) {
    final connected = isConnected(data);

    Widget tile(IconData icon, String label, VoidCallback? onTap) {
      return ListTile(
        enabled: onTap != null,
        leading: Icon(icon, color: _ink, size: 22),
        title: Text(
          label,
          style: const TextStyle(
            color: _ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.textDisabled,
        ),
        onTap: onTap == null
            ? null
            : () {
                Navigator.pop(context);
                onTap();
              },
      );
    }

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            tile(Icons.chat_bubble_outline_rounded, 'Chat', openFamilyChat),
            tile(
              Icons.my_location_rounded,
              'Share GPS',
              connected ? () => shareCurrentLocation(data) : null,
            ),
            tile(
              Icons.sync_rounded,
              'Sync usage',
              connected ? () => syncUsageReport(data) : null,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _notificationBell() {
    const bell = Icon(Icons.notifications_none_rounded, color: _ink, size: 22);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return bell;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatNotificationsService.instance.unreadStream(uid),
      builder: (context, snapshot) {
        final hasUnread = (snapshot.data?.docs.length ?? 0) > 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            bell,
            if (hasUnread)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _coral,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _bottomNav(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatNotificationsService.instance.unreadStream(uid),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs;
        final hasUnreadChat =
            docs != null &&
            docs.any((doc) => doc.data()['type'] == 'parent_child_chat');

        return StreamBuilder<bool>(
          stream: _chatUnreadFor(uid),
          builder: (context, chatUnread) => FloatingPillDock(
          currentIndex: currentIndex,
          items: [
            const DockItem(icon: Icons.home_outlined, label: 'Home'),
            DockItem(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Chat',
              showBadge: hasUnreadChat || chatUnread.data == true,
            ),
            const DockItem(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Pair',
            ),
            const DockItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
            ),
          ],
          onTap: handleBottomNavTap,
          ),
        );
      },
    );
  }

  Stream<bool>? _chatUnreadStream;
  String? _chatUnreadProfileId;

  /// Unread dot for the Chat tab (see ChatUnreadService). Recreated only
  /// when the paired profile changes.
  Stream<bool> _chatUnreadFor(String uid) {
    final profileId = (_cachedUserData?['pairedChildProfileId'] ?? '')
        .toString();
    if (_chatUnreadStream == null || _chatUnreadProfileId != profileId) {
      _chatUnreadProfileId = profileId;
      _chatUnreadStream = ChatUnreadService.hasUnread(profileId, uid);
    }
    return _chatUnreadStream!;
  }

  // =============================== HOME TAB ==============================

  List<Widget> _homeTab(Map<String, dynamic> data, bool connected) {
    return [
      if (connected) ...[_monitoringStrip(), const SizedBox(height: 12)],
      _deviceStatusCard(data, connected),
      const SizedBox(height: 14),
      if (!connected) ...[_pairPromptBanner(), const SizedBox(height: 14)],
      _heroCard(),
      if (connected) ...[
        const SizedBox(height: 14),
        _activeRulesBento(data),
        const SizedBox(height: 14),
        _emergencyAccessBanner(data),
      ],
      const SizedBox(height: 14),
      _weeklySummaryCard(),
      const SizedBox(height: 14),
      _topAppsCard(),
    ];
  }

  Widget _deviceStatusCard(Map<String, dynamic> data, bool connected) {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = (data['fullName'] ?? user?.displayName ?? 'Student User')
        .toString();
    final subtitle = connected
        ? '${_isOnline ? 'Online' : 'Offline'} \u2022 ${_lastSyncLabel()}'
        : 'Waiting for parent pairing';

    return _whiteCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ProfileSettingsScreen(),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: AppColors.successBg,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: AppColors.success,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "$fullName's Phone",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _slate,
                            fontSize: 12,
                            fontFeatures: _tabular,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            onTap: connected
                ? _showMonitoringSheet
                : () => _goToSafetyTab(scrollToPairing: true),
            child: StatusPill(
              label: !connected
                  ? 'Setup Needed'
                  : (_isOnline ? 'Synced' : 'Offline'),
              tone: !connected
                  ? StatusTone.warning
                  : (_isOnline ? StatusTone.success : StatusTone.neutral),
            ),
          ),
        ],
      ),
    );
  }

  /// Replaces the permanent yellow banner: the same monitoring notice, plus
  /// what is monitored and the privacy boundary, opened on demand.
  void _showMonitoringSheet() {
    Widget point(IconData icon, Color color, String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget heading(String text) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: _slate,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetGrabber(),
                  const Text(
                    'Monitoring is on',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'This phone is paired with a parent account.',
                    style: TextStyle(color: _slate, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  heading('What your parent can see'),
                  point(
                    Icons.timelapse_rounded,
                    _brandIndigo,
                    'Screen time and which apps are used, and for how long.',
                  ),
                  point(
                    Icons.rule_rounded,
                    _brandIndigo,
                    'App rules set by your parent: monitored, blocked, or '
                    'time-limited apps.',
                  ),
                  point(
                    Icons.location_on_outlined,
                    _brandIndigo,
                    'This phone\'s location, when location sharing is on.',
                  ),
                  heading('Privacy boundary'),
                  point(
                    Icons.lock_outline_rounded,
                    _emerald,
                    'WellScreen does not read messages, passwords, calls, '
                    'photos, or sensitive files.',
                  ),
                  heading('Good to know'),
                  point(
                    Icons.info_outline_rounded,
                    _amber,
                    'Disabling WellScreen permissions, turning off '
                    'monitoring, or uninstalling WellScreen will interrupt '
                    'screen-time tracking and usage reports. Your parent may '
                    'be notified if this device stops reporting. Android '
                    'controls the uninstall process.',
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: FilledButton.styleFrom(
                        backgroundColor: _brandIndigo,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Got it',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pairPromptBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _amberTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, color: _amber, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Not paired yet',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Connect this phone to a parent account.',
                  style: TextStyle(color: Color(0xFF374151), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () => _goToSafetyTab(scrollToPairing: true),
            style: FilledButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: const StadiumBorder(),
            ),
            child: const Text(
              'Pair Device',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------- screen time + usage pattern ---------------------

  /// "Device monitored by your guardian" strip. Tapping it opens the full
  /// monitoring and privacy explanation.
  Widget _monitoringStrip() {
    return Material(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _showMonitoringSheet,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.primaryDark,
                size: 18,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Device monitored by your guardian',
                  style: TextStyle(
                    color: AppColors.primaryDark,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heroCard() {
    final state = _usageDashboardState;

    if (!_loadingUsageDashboard &&
        (state == null || !state.viewModel.hasUsagePermission)) {
      return _usageAccessPrompt(state);
    }

    if (state == null) {
      return _whiteCard(
        child: const SizedBox(
          height: 150,
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _whiteCard(
              padding: const EdgeInsets.all(14),
              child: _heroScreenTime(state),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _whiteCard(
              padding: const EdgeInsets.all(14),
              child: _heroUsagePattern(state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 2,
        style: const TextStyle(
          color: _ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }

  Widget _heroScreenTime(UsageDashboardControllerState state) {
    final goal = state.screenTimeGoalResult;
    final progress = (goal?.progressPercent ?? 0).clamp(0.0, 1.0).toDouble();
    final hasLimit = state.dailyScreenTimeLimit > Duration.zero;
    final limitLabel = hasLimit
        ? 'of ${_durationLabel(state.dailyScreenTimeLimit)} daily goal'
        : 'No daily goal set';

    return Column(
      children: [
        _heroLabel('Screen Time Today'),
        const SizedBox(height: 12),
        SizedBox(
          width: 104,
          height: 104,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: _hairline,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        state.viewModel.totalUsageLabel,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        limitLabel,
                        style: const TextStyle(
                          color: _slate,
                          fontSize: 11,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroUsagePattern(UsageDashboardControllerState state) {
    final status = state.viewModel.statusLabel;

    Color tint;
    IconData icon;
    StatusTone tone;
    switch (status) {
      case 'Unhealthy':
        tint = AppColors.danger;
        icon = Icons.gpp_maybe_rounded;
        tone = StatusTone.danger;
        break;
      case 'Warning':
        tint = AppColors.warning;
        icon = Icons.gpp_maybe_rounded;
        tone = StatusTone.warning;
        break;
      case 'Healthy':
        tint = AppColors.success;
        icon = Icons.verified_user_rounded;
        tone = StatusTone.success;
        break;
      default:
        tint = AppColors.textDisabled;
        icon = Icons.shield_outlined;
        tone = StatusTone.neutral;
    }

    return Column(
      children: [
        _heroLabel('Risk Level'),
        const SizedBox(height: 12),
        Icon(icon, color: tint, size: 58),
        const SizedBox(height: 10),
        StatusPill(label: status, tone: tone),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            state.viewModel.unhealthyAppCountLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _slate,
              fontSize: 11,
              fontFeatures: _tabular,
            ),
          ),
        ),
      ],
    );
  }

  /// Active Rules card: the rule chips plus the two quick actions.
  Widget _activeRulesBento(Map<String, dynamic> data) {
    return _whiteCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _activeRulesRow(data),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppPillButton(
                  label: isSharingLocation ? 'Sharing...' : 'Share GPS',
                  compact: true,
                  style: AppPillStyle.soft,
                  softTint: true,
                  onPressed: isSharingLocation
                      ? null
                      : () => shareCurrentLocation(data),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppPillButton(
                  label: 'Request Access',
                  compact: true,
                  style: AppPillStyle.soft,
                  softTint: true,
                  onPressed: openFamilyChat,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --------------------------- active app rules --------------------------

  Widget _activeRulesRow(Map<String, dynamic> data) {
    final parentId = (data['pairedParentId'] ?? '').toString();
    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Active Rules',
          actionLabel: 'View All',
          onAction: () => _showRulesSheet(data),
        ),
        const SizedBox(height: 8),
        StreamBuilder<List<AppRule>>(
          stream: _rulesService.watchRulesForParent(parentId),
          builder: (context, rulesSnapshot) {
            if (rulesSnapshot.hasData) _lastRules = rulesSnapshot.data;

            return StreamBuilder<List<AppTimeLimit>>(
              stream: _appTimeLimitService.watchLimits(childProfileId),
              builder: (context, limitsSnapshot) {
                if (limitsSnapshot.hasData) {
                  _lastTimeLimits = limitsSnapshot.data;
                }

                final rules = _lastRules;
                final limits = _lastTimeLimits ?? <AppTimeLimit>[];

                if (rules == null) {
                  if (rulesSnapshot.hasError) {
                    return _rulesInfoPill(
                      icon: Icons.warning_amber_rounded,
                      color: _amber,
                      text: 'Unable to load app rules right now',
                    );
                  }
                  return _rulesInfoPill(
                    icon: Icons.sync_rounded,
                    color: _slate,
                    text: 'Loading parent app rules...',
                  );
                }

                final chips = _buildRuleChips(rules, limits);
                if (chips.isEmpty) {
                  return _rulesInfoPill(
                    icon: Icons.check_rounded,
                    color: _emerald,
                    text: 'No active app restrictions right now',
                  );
                }

                return SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: chips.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) => chips[index],
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  List<Widget> _buildRuleChips(List<AppRule> rules, List<AppTimeLimit> limits) {
    final blocked = rules.where((rule) => rule.restrictEnabled).toList()
      ..sort(
        (a, b) =>
            appTitle(a).toLowerCase().compareTo(appTitle(b).toLowerCase()),
      );
    final blockedPackages = blocked.map((rule) => rule.packageName).toSet();

    final limited =
        limits
            .where((limit) => !blockedPackages.contains(limit.packageName))
            .toList()
          ..sort(
            (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );
    final limitedPackages = limited.map((limit) => limit.packageName).toSet();

    final monitored =
        rules
            .where(
              (rule) =>
                  rule.monitorEnabled &&
                  !rule.restrictEnabled &&
                  !limitedPackages.contains(rule.packageName),
            )
            .toList()
          ..sort(
            (a, b) =>
                appTitle(a).toLowerCase().compareTo(appTitle(b).toLowerCase()),
          );

    _ensureAppMetadata([
      ...blocked.map((rule) => rule.packageName),
      ...limited.map((limit) => limit.packageName),
      ...monitored.map((rule) => rule.packageName),
    ]);

    return [
      for (final rule in blocked)
        _ruleChip(
          packageName: rule.packageName,
          name: appTitle(rule),
          status: 'Blocked',
          statusBackground: _coralTint,
          statusForeground: const Color(0xFFDC2626),
        ),
      for (final limit in limited)
        _ruleChip(
          packageName: limit.packageName,
          name: limit.appName.trim().isEmpty ? limit.packageName : limit.appName,
          status: _durationLabel(Duration(minutes: limit.limitMinutes)),
          statusBackground: const Color(0xFFF1F5F9),
          statusForeground: const Color(0xFF4B5563),
        ),
      for (final rule in monitored)
        _ruleChip(
          packageName: rule.packageName,
          name: appTitle(rule),
          status: 'Monitored',
          statusBackground: const Color(0xFFDBEAFE),
          statusForeground: const Color(0xFF2563EB),
        ),
    ];
  }

  Widget _ruleChip({
    required String packageName,
    required String name,
    required String status,
    required Color statusBackground,
    required Color statusForeground,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _appAvatar(packageName: packageName, name: name, size: 18),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _pill(
            label: status,
            background: statusBackground,
            foreground: statusForeground,
          ),
        ],
      ),
    );
  }

  Widget _rulesInfoPill({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _hairline),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "View All": the full parent rules card (monitored / restricted groups)
  /// plus daily time limits, in a sheet.
  void _showRulesSheet(Map<String, dynamic> data) {
    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: pageBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetGrabber(),
                  _activeRulesCard(data),
                  const SizedBox(height: 14),
                  StreamBuilder<List<AppTimeLimit>>(
                    stream: _appTimeLimitService.watchLimits(childProfileId),
                    builder: (context, snapshot) {
                      final limits = snapshot.data ?? <AppTimeLimit>[];
                      if (limits.isEmpty) return const SizedBox.shrink();

                      return _whiteCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Daily Time Limits',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            for (final limit in limits)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Row(
                                  children: [
                                    _appAvatar(
                                      packageName: limit.packageName,
                                      name: limit.appName,
                                      size: 28,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        limit.appName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _ink,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    _pill(
                                      label: _durationLabel(
                                        Duration(minutes: limit.limitMinutes),
                                      ),
                                      background: const Color(0xFFF1F5F9),
                                      foreground: const Color(0xFF4B5563),
                                      fontSize: 12,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --------------------------- emergency access --------------------------

  /// Child-requests-temporary-bypass banner (EmergencyAccessService). Only
  /// shown once paired - a request needs a parent to notify and a
  /// child_profiles doc to write the status onto.
  Widget _emergencyAccessBanner(Map<String, dynamic> data) {
    final parentId = (data['pairedParentId'] ?? '').toString();
    final childProfileId = (data['pairedChildProfileId'] ?? '').toString();

    if (parentId.isEmpty || childProfileId.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<Map<String, dynamic>>(
      stream: _emergencyAccessService.watchStatus(childProfileId),
      builder: (context, snapshot) {
        final statusData = snapshot.data ?? const <String, dynamic>{};
        final status = (statusData['status'] ?? 'none').toString();
        final grantedUntil = statusData['grantedUntil'];
        final until = grantedUntil is Timestamp ? grantedUntil.toDate() : null;

        if (status == 'approved' &&
            until != null &&
            until.isAfter(DateTime.now())) {
          final hh = until.hour.toString().padLeft(2, '0');
          final mm = until.minute.toString().padLeft(2, '0');

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _emeraldTint,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: _emerald,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Urgent Access Approved',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Restrictions are lifted until $hh:$mm.',
                        style: const TextStyle(
                          color: Color(0xFF374151),
                          fontSize: 12,
                          fontFeatures: _tabular,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final pending = status == 'requested';
        final String title;
        final String subtitle;
        if (pending) {
          title = 'Request Sent';
          subtitle = 'Waiting for your parent to respond';
        } else if (status == 'denied') {
          title = 'Need Urgent Access?';
          subtitle = 'Your last request was denied. You can ask again.';
        } else {
          title = 'Need Urgent Access?';
          subtitle = 'Request temporary time from parent';
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFDF6EC),
            border: Border.all(color: const Color(0xFFFDE9C8)),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: pending || isRequestingEmergencyAccess
                    ? null
                    : () => _showEmergencyRequestSheet(
                        childProfileId,
                        parentId,
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0x66111827),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  pending ? 'Pending' : 'Request',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showEmergencyRequestSheet(String childProfileId, String parentId) {
    const presets = <String>['Schoolwork', 'Call Parent', 'Urgent'];
    String? selectedPreset;
    var sending = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sheetGrabber(),
                      const Text(
                        'Request Emergency Access',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Need a restricted app for something urgent? Ask '
                        'your parent to temporarily lift restrictions.',
                        style: TextStyle(
                          color: _slate,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final preset in presets)
                            ChoiceChip(
                              label: Text(preset),
                              selected: selectedPreset == preset,
                              showCheckmark: false,
                              backgroundColor: Colors.white,
                              selectedColor: const Color(0xFFDBEAFE),
                              side: BorderSide(
                                color: selectedPreset == preset
                                    ? _brandIndigo
                                    : _hairline,
                              ),
                              labelStyle: TextStyle(
                                color: selectedPreset == preset
                                    ? const Color(0xFF2563EB)
                                    : _ink,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              onSelected: (selected) {
                                setSheetState(() {
                                  selectedPreset = selected ? preset : null;
                                });
                                if (selected) {
                                  emergencyReasonController.text = preset;
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emergencyReasonController,
                        maxLength: 140,
                        decoration: InputDecoration(
                          hintText: 'Reason (optional) - e.g. need calculator',
                          isDense: true,
                          filled: true,
                          fillColor: pageBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: sending
                              ? null
                              : () async {
                                  setSheetState(() => sending = true);
                                  await requestEmergencyAccess(
                                    childProfileId,
                                    parentId,
                                  );
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: const StadiumBorder(),
                          ),
                          child: Text(
                            sending ? 'Sending...' : 'Send Request',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------- weekly summary ---------------------------

  Widget _weeklySummaryCard() {
    const dayLabels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const maxBarHeight = 120.0;

    final state = _usageDashboardState;
    final limit = state?.dailyScreenTimeLimit ?? Duration.zero;
    final todayIndex = DateTime.now().weekday - 1;

    // Today's bar uses the same total as the Screen Time ring above.
    final days = List<Duration?>.of(_weeklyUsage);
    final todayUsed = state?.screenTimeGoalResult?.usedDuration;
    if (todayUsed != null) days[todayIndex] = todayUsed;

    final hasData = days.any((day) => day != null);

    var maxMs = limit.inMilliseconds;
    for (final day in days) {
      if (day != null && day.inMilliseconds > maxMs) maxMs = day.inMilliseconds;
    }
    if (maxMs <= 0) maxMs = 1;

    Widget body;
    if (!hasData) {
      final waiting = _loadingUsageDashboard || !_weeklyUsageLoaded;
      final noPermission =
          state != null && !state.viewModel.hasUsagePermission;
      body = SizedBox(
        height: 96,
        child: Center(
          child: waiting && !noPermission
              ? const CircularProgressIndicator()
              : Text(
                  noPermission
                      ? 'Allow usage access to see this week\'s screen time.'
                      : 'No screen time recorded yet this week.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _slate, fontSize: 13),
                ),
        ),
      );
    } else {
      final limitBottom = limit > Duration.zero
          ? ((limit.inMilliseconds / maxMs) * maxBarHeight - 7).clamp(
              0.0,
              maxBarHeight,
            )
          : 0.0;

      body = Column(
        children: [
          SizedBox(
            height: maxBarHeight + 14,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 44),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: _weeklyBar(
                                label: dayLabels[i],
                                duration: days[i],
                                isToday: i == todayIndex,
                                maxMs: maxMs,
                                maxBarHeight: maxBarHeight,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (limit > Duration.zero)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: limitBottom.toDouble(),
                    height: 14,
                    child: const Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 1,
                            child: CustomPaint(painter: _DashedLinePainter()),
                          ),
                        ),
                        SizedBox(width: 6),
                        SizedBox(
                          width: 38,
                          child: Text(
                            'Limit',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: _slate, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(right: 44),
            child: Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Text(
                      dayLabels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: i == todayIndex ? _ink : _slate,
                        fontSize: 11,
                        fontWeight: i == todayIndex
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Weekly Summary',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          body,
        ],
      ),
    );
  }

  Widget _weeklyBar({
    required String label,
    required Duration? duration,
    required bool isToday,
    required int maxMs,
    required double maxBarHeight,
  }) {
    final milliseconds = duration?.inMilliseconds ?? 0;
    final hasReading = milliseconds > 0;
    final height = hasReading
        ? ((milliseconds / maxMs) * maxBarHeight)
              .clamp(4.0, maxBarHeight)
              .toDouble()
        : 4.0;

    return Tooltip(
      triggerMode: TooltipTriggerMode.tap,
      message: duration == null
          ? '$label: no reading'
          : '$label: ${_durationLabel(duration)}',
      child: Container(
        width: 18,
        height: height,
        decoration: BoxDecoration(
          color: !hasReading
              ? _hairline
              : (isToday ? _brandIndigo : const Color(0xFFC7D2FE)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ),
    );
  }

  // ----------------------------- top apps today --------------------------

  Widget _topAppsCard() {
    final apps = _visibleTodayApps();
    final topApps = apps.take(3).toList();
    _ensureAppMetadata(apps.map((app) => app.packageName));

    final maxDurationMs = topApps
        .map((app) => app.usageDuration.inMilliseconds)
        .fold<int>(0, (highest, value) => value > highest ? value : highest);

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'Top Apps Today',
            actionLabel: apps.isEmpty ? null : 'See All >',
            onAction: () => _showAllAppsSheet(apps),
          ),
          const SizedBox(height: 8),
          if (_loadingUsageDashboard && _usageDashboardState == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (topApps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No app usage recorded yet today.',
                style: TextStyle(color: _slate, fontSize: 13),
              ),
            )
          else
            for (final app in topApps)
              _appUsageRow(app: app, maxDurationMs: maxDurationMs),
        ],
      ),
    );
  }

  Widget _appUsageRow({
    required AppUsageSummary app,
    required int maxDurationMs,
  }) {
    final name = _appLabel(app.packageName, app.displayName);
    final ratio = maxDurationMs > 0
        ? (app.usageDuration.inMilliseconds / maxDurationMs)
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          _appAvatar(packageName: app.packageName, name: name, size: 36),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    color: _brandIndigo,
                    backgroundColor: _hairline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 58,
            child: Text(
              app.usageLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: _tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAllAppsSheet(List<AppUsageSummary> apps) {
    final maxDurationMs = apps
        .map((app) => app.usageDuration.inMilliseconds)
        .fold<int>(0, (highest, value) => value > highest ? value : highest);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetGrabber(),
                  const Text(
                    'Apps Used Today',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  for (final app in apps)
                    _appUsageRow(app: app, maxDurationMs: maxDurationMs),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================== SAFETY TAB =============================

  List<Widget> _safetyTab(Map<String, dynamic> data, bool connected) {
    if (connected) _ensureGeocodedAddress(data);

    return [
      if (!connected) ...[
        KeyedSubtree(key: _pairingSectionKey, child: _pairingCard()),
        const SizedBox(height: 14),
      ],
      _gpsCard(data, connected),
      const SizedBox(height: 14),
      _protectionChecklistCard(connected),
    ];
  }

  Widget _gpsCard(Map<String, dynamic> data, bool connected) {
    final coordinates = _coordinatesText(data);
    final updated = locationUpdatedText(data);
    final fallback = locationText(data);
    final primary = connected
        ? (_geocodedAddress ?? fallback)
        : 'Pair device first';

    final String secondary;
    if (!connected) {
      secondary = 'Location sharing becomes available after pairing.';
    } else if (coordinates != null && primary != coordinates) {
      secondary = '$coordinates \u2022 Updated: $updated';
    } else {
      secondary = 'Updated: $updated';
    }

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: connected ? _emeraldTint : _coralTint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  connected
                      ? Icons.location_on_rounded
                      : Icons.location_off_rounded,
                  color: connected ? _emerald : _coral,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GPS LOCATION',
                      style: TextStyle(
                        color: _slate,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      primary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      secondary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _slate,
                        fontSize: 12,
                        fontFeatures: _tabular,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Share GPS now',
                onPressed: connected && !isSharingLocation
                    ? () => shareCurrentLocation(data)
                    : null,
                icon: Icon(
                  isSharingLocation
                      ? Icons.sync_rounded
                      : Icons.my_location_rounded,
                  color: connected ? _brandIndigo : _slate,
                  size: 26,
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
                  color: _amberTint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: _amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location services are off - tap to enable GPS.',
                        style: TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w600,
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

  /// One checklist for everything that keeps protection working: pairing,
  /// SMS backup alerts (SmsAlertSender.kt sends natively; this only shows
  /// whether it is able to fire), usage access and the accessibility
  /// service.
  Widget _protectionChecklistCard(bool connected) {
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

    String smsSubtitle;
    if (!connected) {
      smsSubtitle = 'Available after this phone is paired with a parent.';
    } else if (!_smsPermissionGranted) {
      smsSubtitle =
          'Off. Grant SMS permission so a backup text alert can reach your '
          'parent even without internet, when a restricted app is opened.';
    } else if (hasPhoneNumber) {
      smsSubtitle =
          'Enabled. Blocked-app alerts will text '
          '${_maskPhoneNumber(_cachedParentPhoneNumber!)}.';
    } else {
      smsSubtitle =
          'Permission granted, but your parent hasn\'t added a phone number '
          'yet in their Profile Settings.';
    }
    if (connected && _smsAlertLog.isNotEmpty) {
      smsSubtitle =
          '$smsSubtitle\nRecent attempts: $sentCount sent, $failedCount failed';
    }

    final usageState = _usageDashboardState;
    final bool? usageGranted = usageState == null
        ? (_loadingUsageDashboard ? null : false)
        : usageState.viewModel.hasUsagePermission;

    return _whiteCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Protection & Setup',
            style: TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          _checklistRow(
            icon: Icons.link_rounded,
            title: 'Device Pairing',
            subtitle: connected
                ? 'Connected to a parent account. Tap to view details.'
                : 'Not paired yet. Enter the code from the parent account.',
            done: connected,
            actionLabel: connected ? null : 'Pair Device',
            onAction: connected
                ? null
                : () => _scrollToSection(_pairingSectionKey),
            onTap: connected ? showConnectedSuccessDialog : null,
          ),
          const Divider(height: 1, color: _hairline),
          _checklistRow(
            icon: Icons.sms_outlined,
            title: 'SMS Backup Alerts',
            subtitle: smsSubtitle,
            done: connected && _smsPermissionGranted && hasPhoneNumber,
            actionLabel: connected && !_smsPermissionGranted ? 'Enable' : null,
            onAction: connected && !_smsPermissionGranted
                ? _requestSmsPermission
                : null,
          ),
          const Divider(height: 1, color: _hairline),
          _checklistRow(
            icon: Icons.bar_chart_rounded,
            title: 'Usage Access',
            subtitle: usageGranted == true
                ? 'Allowed. Screen time is read from this phone.'
                : 'Needed to show real screen time and app usage.',
            done: usageGranted,
            actionLabel: usageGranted == false ? 'Allow' : null,
            onAction: usageGranted == false
                ? () => _usageTrackingService.openUsageAccessSettings()
                : null,
          ),
          const Divider(height: 1, color: _hairline),
          _checklistRow(
            icon: Icons.accessibility_new_rounded,
            title: 'Accessibility Service',
            subtitle: _accessibilityEnabled == true
                ? 'On. Restricted apps and websites are blocked.'
                : 'Needed to block restricted apps. Switch WellScreen on in '
                      'Android Accessibility settings.',
            done: _accessibilityEnabled,
            actionLabel: _accessibilityEnabled == true ? null : 'Open',
            onAction: _openAccessibilitySettings,
          ),
          const Divider(height: 1, color: _hairline),
          _checklistRow(
            icon: Icons.battery_charging_full_rounded,
            title: 'Run in Background',
            subtitle: _batteryUnrestricted == true
                ? 'Allowed. Battery saver will not stop WellScreen.'
                : 'Set WellScreen to "Not optimized" / "Unrestricted" so '
                      'battery saver does not stop protection.',
            done: _batteryUnrestricted,
            actionLabel: _batteryUnrestricted == false ? 'Open' : null,
            onAction: _batteryUnrestricted == false
                ? _openBatterySettings
                : null,
          ),
          const Divider(height: 1, color: _hairline),
          _checklistRow(
            icon: Icons.shield_outlined,
            title: 'Uninstall Protection',
            subtitle: _deviceAdminActive == true
                ? 'On. WellScreen cannot be uninstalled without turning '
                      'this off, and your guardian is told.'
                : 'Optional. Stops WellScreen from being uninstalled '
                      'without your guardian knowing.',
            done: _deviceAdminActive,
            actionLabel: _deviceAdminActive == false ? 'Turn On' : null,
            onAction: _deviceAdminActive == false
                ? _requestDeviceAdmin
                : null,
          ),
        ],
      ),
    );
  }

  /// [done]: true = emerald check, false = amber "Setup Needed" badge,
  /// null = status not known to the app (no badge).
  Widget _checklistRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool? done,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
  }) {
    final Color iconColor;
    final Color iconTint;
    if (done == true) {
      iconColor = _emerald;
      iconTint = _emeraldTint;
    } else if (done == false) {
      iconColor = _amber;
      iconTint = _amberTint;
    } else {
      iconColor = _slate;
      iconTint = const Color(0xFFF1F5F9);
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (done == false)
                        _pill(
                          label: 'Setup Needed',
                          background: _amberTint,
                          foreground: const Color(0xFFB45309),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _slate,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (actionLabel != null)
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandIndigo,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              )
            else if (done == true)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Icon(
                  Icons.check_circle_rounded,
                  color: _emerald,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================= SETTINGS TAB ============================

  List<Widget> _settingsTab(Map<String, dynamic> data, bool connected) {
    final user = FirebaseAuth.instance.currentUser;
    final fullName = (data['fullName'] ?? user?.displayName ?? 'Student User')
        .toString();
    final email = (data['email'] ?? user?.email ?? '').toString();
    final hasPhoneNumber = _cachedParentPhoneNumber != null;

    void openProfile() {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      );
    }

    return [
      _settingsGroup('Account', [
        _settingsTile(
          icon: Icons.person_outline_rounded,
          title: fullName,
          subtitle: email.isEmpty ? 'Account and profile' : email,
          onTap: openProfile,
        ),
        _settingsTile(
          icon: Icons.sms_outlined,
          title: 'Parent Phone Number (SMS Backup)',
          subtitle: hasPhoneNumber
              ? 'Backup alerts text '
                    '${_maskPhoneNumber(_cachedParentPhoneNumber!)}'
              : 'Not added yet. Your parent sets this in their Profile '
                    'Settings.',
        ),
      ]),
      const SizedBox(height: 14),
      _settingsGroup('App', [
        _settingsTile(
          icon: Icons.notifications_none_rounded,
          title: 'Notifications',
          subtitle: 'Messages and alerts from your parent',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatNotificationsScreen()),
          ),
        ),
        if (connected)
          _settingsTile(
            icon: Icons.sync_rounded,
            title: isSyncingUsage ? 'Syncing...' : 'Sync Usage Now',
            subtitleWidget: _syncStatusIndicator(),
            onTap: isSyncingUsage ? null : () => syncUsageReport(data),
          ),
      ]),
      const SizedBox(height: 14),
      _settingsGroup('Privacy', [
        _settingsTile(
          icon: Icons.privacy_tip_outlined,
          title: 'Privacy & Monitoring Notice',
          subtitle: 'What WellScreen monitors and what it never reads',
          onTap: _showMonitoringSheet,
        ),
      ]),
      const SizedBox(height: 14),
      _settingsGroup(null, [
        _settingsTile(
          icon: Icons.logout_rounded,
          title: 'Logout',
          subtitle: 'Sign out from this WellScreen account',
          destructive: true,
          onTap: _confirmLogout,
        ),
      ]),
    ];
  }

  Widget _settingsGroup(String? title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: _slate,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: _hairline),
          ),
          child: Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: 64, color: _hairline),
                tiles[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? subtitleWidget,
    VoidCallback? onTap,
    bool destructive = false,
  }) {
    final accent = destructive ? _coral : _brandIndigo;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: destructive ? _coralTint : const Color(0xFFE0E7FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: accent, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: destructive ? const Color(0xFFDC2626) : _ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle:
          subtitleWidget ??
          (subtitle == null
              ? null
              : Text(
                  subtitle,
                  style: const TextStyle(color: _slate, fontSize: 12),
                )),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, color: _slate, size: 22),
    );
  }
}

/// Dashed horizontal rule used for the daily-limit line on the weekly chart.
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 4.0;
    final y = size.height / 2;

    for (var x = 0.0; x < size.width; x += dash + gap) {
      final end = x + dash < size.width ? x + dash : size.width;
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => false;
}
