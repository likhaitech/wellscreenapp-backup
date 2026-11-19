import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/chat_unread_service.dart';
import '../services/daily_usage_history.dart';
import '../services/emergency_access_service.dart';
import '../services/parent_alert_badge_service.dart';
import '../widgets/app_usage_icon.dart';
import '../services/pattern_detection_service.dart';
import '../services/parent_phone_sync_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';
import 'all_apps_screen.dart';
import 'device_pairing_screen.dart';
import 'gps_map_screen.dart';
import 'login_screen.dart';
import 'parent_notifications_screen.dart';
import 'parent_child_chat_screen.dart';
import '../services/chat_notifications_service.dart';
import 'profile_settings_screen.dart';
import 'reports_screen.dart';
import 'rules/rules_screen.dart';
import '../utils/child_name.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // Aliased onto the shared AppColors palette (theme/app_theme.dart) rather
  // than the ad hoc literals this screen used to declare on its own - same
  // names so the body below didn't need a line-by-line rewrite, but now
  // every value traces back to the one shared source of truth.
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;
  static const Color _amberFill = Color(0xFFFDF6EC);
  static const Color _amberBorder = Color(0xFFFDE9C8);
  static const Color softGreen = AppColors.successBg;
  static const Color softBlue = AppColors.infoBg;


  int currentIndex = 0;

  // Tracked from the latest childProfilesStream build so bottom-nav/menu
  // taps (which run outside build()) know which paired child's usage
  // report to open. Real Firestore doc id, not a fabricated field.
  String? _primaryChildId;

  final PushNotificationService _pushNotificationService =
      PushNotificationService();
  final EmergencyAccessService _emergencyAccessService =
      EmergencyAccessService();

  // Guards the Approve/Deny buttons so a double-tap can't fire
  // respondToRequest() twice for the same request.
  bool _isRespondingToEmergencyAccess = false;
  // Cached so the dock's unread dot does not resubscribe on every rebuild.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _unreadStream;
  Stream<bool>? _chatUnreadStream;
  String? _chatUnreadProfileId;
  Timer? _presenceRefreshTimer;
  // Android periodically checks in while online; this is an inference,
  // not an instantaneous network-disconnect signal.
  static const Duration _presenceFreshness = Duration(minutes: 30);

  @override
  void initState() {
    super.initState();
    // Registers this device for push (saves an fcmToken to
    // users/{uid}), and starts listening for foreground messages so real
    // alerts sent via backend/app/services/notification_service.py
    // actually show up while the app is open. See push_notification_service.dart.
    _pushNotificationService.initialize();
    // Keep each child's copy of the verified guardian number current, so
    // the child's phone can send backup SMS alerts.
    ParentPhoneSyncService.syncToChildProfiles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ChatNotificationsService.instance.markDashboardReady();
    });
    // Refresh the visible stale/online state even without a new Firestore write.
    _presenceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _presenceRefreshTimer?.cancel();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> childProfilesStream(String uid) {
    return FirebaseFirestore.instance
        .collection('child_profiles')
        .where('parentId', isEqualTo: uid)
        .snapshots();
  }

  bool isChildConnected(Map<String, dynamic> data) {
    final pairingStatus = (data['pairingStatus'] ?? '').toString();
    final childEmail = (data['childEmail'] ?? '').toString();
    final childAccountId = (data['childAccountId'] ?? '').toString();

    return pairingStatus == 'connected' ||
        childEmail.isNotEmpty ||
        childAccountId.isNotEmpty;
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

  Map<String, dynamic>? latestLocation(Map<String, dynamic>? data) {
    if (data == null) return null;

    final latestLocation = data['latestLocation'];

    if (latestLocation is Map<String, dynamic>) {
      return latestLocation;
    }

    if (latestLocation is Map) {
      return Map<String, dynamic>.from(latestLocation);
    }

    return null;
  }

  bool hasSharedLocation(Map<String, dynamic>? data) {
    final location = latestLocation(data);

    if (location == null) return false;

    return location['latitude'] != null && location['longitude'] != null;
  }

  double locationLatitude(Map<String, dynamic>? data) {
    final location = latestLocation(data);
    final latitude = location?['latitude'];

    if (latitude is num) {
      return latitude.toDouble();
    }

    return 0;
  }

  double locationLongitude(Map<String, dynamic>? data) {
    final location = latestLocation(data);
    final longitude = location?['longitude'];

    if (longitude is num) {
      return longitude.toDouble();
    }

    return 0;
  }

  String locationText(Map<String, dynamic>? data) {
    final location = latestLocation(data);

    if (location == null) return 'No shared GPS yet';

    final label = location['label'];
    final latitude = location['latitude'];
    final longitude = location['longitude'];

    if (label != null && label.toString().isNotEmpty) {
      return label.toString();
    }

    if (latitude is num && longitude is num) {
      return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
    }

    return 'No shared GPS yet';
  }

  String locationUpdatedText(Map<String, dynamic>? data) {
    if (data == null) return 'Waiting for update';

    final updatedAt = data['locationUpdatedAt'];

    if (updatedAt is Timestamp) {
      return formatDate(updatedAt);
    }

    return 'Waiting for update';
  }

  Map<String, dynamic>? latestUsageReport(Map<String, dynamic>? data) {
    if (data == null) return null;

    final report = data['latestUsageReport'];

    if (report is Map<String, dynamic>) {
      return report;
    }

    if (report is Map) {
      return Map<String, dynamic>.from(report);
    }

    return null;
  }

  bool hasSyncedUsageReport(Map<String, dynamic>? data) {
    return latestUsageReport(data) != null;
  }

  List<Map<String, dynamic>> usageTopApps(Map<String, dynamic>? data) {
    final report = latestUsageReport(data);
    final rawApps = report?['topApps'];

    if (rawApps is! List) {
      return [];
    }

    return rawApps
        .whereType<Map>()
        .map((app) => Map<String, dynamic>.from(app))
        .toList();
  }

  String? _usageIconForPackage(Map<String, dynamic>? child, String pkg) {
    final allApps = latestUsageReport(child)?['allApps'];
    if (allApps is! List) return null;
    for (final raw in allApps) {
      if (raw is Map && raw['packageName'] == pkg) {
        final icon = raw['iconBase64'];
        if (icon is String && icon.isNotEmpty) return icon;
      }
    }
    return null;
  }

  Duration usageTotalDuration(Map<String, dynamic>? data) {
    final report = latestUsageReport(data);
    final ms = report?['totalUsageDurationMs'];

    if (ms is num) {
      return Duration(milliseconds: ms.toInt());
    }

    return Duration.zero;
  }

  /// The stored status comes from the child app's last full sync, but the
  /// background job keeps updating the total while the app is closed. Use
  /// whichever is worse, so 6 hours of use can never show as "Healthy".
  String usagePatternStatus(Map<String, dynamic>? data) {
    final report = latestUsageReport(data);
    final stored = (report?['patternStatus'] ?? '').toString();
    final total = usageTotalDuration(data);

    String fromTotal = 'healthy';
    if (total >= PatternDetectionService.unhealthyTotalUsageLimit) {
      fromTotal = 'unhealthy';
    } else if (total >= PatternDetectionService.warningTotalUsageLimit) {
      fromTotal = 'warning';
    }

    const rank = {'healthy': 0, 'warning': 1, 'unhealthy': 2};
    if (!rank.containsKey(stored)) return fromTotal;
    return rank[fromTotal]! > rank[stored]! ? fromTotal : stored;
  }

  int usageUnhealthyAppCount(Map<String, dynamic>? data) {
    final report = latestUsageReport(data);
    final count = report?['unhealthyAppCount'];

    if (count is num) {
      return count.toInt();
    }

    return 0;
  }

  String usageUpdatedText(Map<String, dynamic>? data) {
    if (data == null) return 'Waiting for update';

    final updatedAt = data['usageReportUpdatedAt'];

    if (updatedAt is Timestamp) {
      return formatDate(updatedAt);
    }

    return 'Waiting for update';
  }

  String formatDurationLabel(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m';
    return '${duration.inSeconds}s';
  }

  void openGpsMap(Map<String, dynamic>? child) {
    // Never open the map on a made-up point: with no shared GPS there is
    // nothing real to show.
    if (!hasSharedLocation(child)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No location shared yet. Tap Share GPS on your child\'s phone.',
          ),
        ),
      );
      return;
    }
    final latitude = locationLatitude(child);
    final longitude = locationLongitude(child);
    final label = locationText(child);
    final updatedAt = locationUpdatedText(child);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GpsMapScreen(
          latitude: latitude,
          longitude: longitude,
          label: label,
          updatedAt: updatedAt,
          hasLocation: hasSharedLocation(child),
        ),
      ),
    );
  }

  /// Unread dot for the Chat tab, kept per paired child (see
  /// ChatUnreadService). Recreated only when the paired child changes.
  Stream<bool> _chatUnreadFor(String uid) {
    final profileId = _primaryChildId ?? '';
    if (_chatUnreadStream == null || _chatUnreadProfileId != profileId) {
      _chatUnreadProfileId = profileId;
      _chatUnreadStream = ChatUnreadService.hasUnread(profileId, uid);
    }
    return _chatUnreadStream!;
  }

  void openFamilyChat() {
    final childProfileId = _primaryChildId;
    if (childProfileId == null || childProfileId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pair a child to start chatting.')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ParentChildChatScreen(
          childProfileId: childProfileId,
          isParent: true,
        ),
      ),
    );
  }

  void openRulesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RulesScreen()),
    );
  }

  void handleBottomNavTap(int index) {
    if (index == 0) {
      setState(() => currentIndex = 0);
      return;
    }

    if (index == 1) {
      openFamilyChat();
    } else if (index == 2) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
      );
    } else if (index == 3) {
      // Was UsageSummaryScreen - a screen that showed usage data but not
      // the browsing-activity/category-detection data a parent actually
      // needs to review, which lived on a completely different screen
      // reachable only through the bell icon. ReportsScreen merges both
      // into the one screen this tab's label ("Reports") actually implies.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportsScreen(childProfileId: _primaryChildId ?? ''),
        ),
      );
    } else if (index == 4) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
      );
    }
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? getPrimaryChildDoc(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> childDocs,
  ) {
    if (childDocs.isEmpty) return null;

    for (final doc in childDocs) {
      if (isChildConnected(doc.data())) return doc;
    }

    return childDocs.first;
  }

  @override
  Widget build(BuildContext context) {
    final parentUser = FirebaseAuth.instance.currentUser;

    if (parentUser == null) {
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
      key: _scaffoldKey,
      drawer: _menuDrawer(),
      backgroundColor: pageBg,
      appBar: _topBar(),
      body: SafeArea(
        top: false,
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: childProfilesStream(parentUser.uid),
          builder: (context, snapshot) {
            // Previously this StreamBuilder had no loading or error
            // handling at all - on first load, every card below briefly
            // rendered its own "No data yet" placeholder instead of a
            // spinner, and a genuine Firestore failure was invisible
            // (silently fell through to the same empty-list default).
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AppErrorState(
                    title: 'Could Not Load Dashboard',
                    message:
                        'Something went wrong loading your child '
                        'profiles.\n\n${snapshot.error}',
                  ),
                ),
              );
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }

            final childDocs = snapshot.data?.docs ?? [];
            final primaryChildDoc = getPrimaryChildDoc(childDocs);
            final primaryChild = primaryChildDoc?.data();
            _primaryChildId = primaryChildDoc?.id;
            // The Chat tab's unread dot is built outside this stream, so
            // redraw it once the paired child is known.
            if (_primaryChildId != null &&
                _primaryChildId != _chatUnreadProfileId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() {});
              });
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _greetingHeader(),
                const SizedBox(height: 12),
                _deviceProfileCard(primaryChild),
                if (_isMonitoringSecurityAlertActive(primaryChild)) ...[
                  const SizedBox(height: 14),
                  _monitoringSecurityAlertCard(primaryChild!),
                ],
                if (_hasPendingEmergencyAccessRequest(primaryChild)) ...[
                  const SizedBox(height: 14),
                  _emergencyAccessRequestCard(
                    _primaryChildId ?? '',
                    primaryChild!,
                  ),
                ],
                const SizedBox(height: 14),
                _screenTimeAndRiskSection(primaryChild),
                const SizedBox(height: 14),
                _weeklyTrendSection(primaryChild),
                const SizedBox(height: 14),
                _topAppsSection(primaryChild),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _unreadStream ??= ChatNotificationsService.instance
            .unreadStream(parentUser.uid),
        builder: (context, unread) => StreamBuilder<bool>(
        stream: _chatUnreadFor(parentUser.uid),
        builder: (context, chatUnread) => FloatingPillDock(
        currentIndex: currentIndex,
        items: [
          const DockItem(icon: Icons.home_outlined, label: 'Home'),
          DockItem(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
            showBadge:
                chatUnread.data == true ||
                (unread.data?.docs.any(
                  (doc) => doc.data()['type'] == 'parent_child_chat',
                ) ??
                false),
          ),
          const DockItem(icon: Icons.link_rounded, label: 'Devices'),
          const DockItem(icon: Icons.bar_chart_rounded, label: 'Reports'),
          const DockItem(icon: Icons.settings_outlined, label: 'Settings'),
        ],
        onTap: handleBottomNavTap,
        ),
        ),
      ),
    );
  }

  PreferredSizeWidget _topBar() {
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;

    return WellScreenAppBar.primary(
      onMenu: () => _scaffoldKey.currentState?.openDrawer(),
      onAvatar: () => handleBottomNavTap(4),
      avatar: photoUrl == null || photoUrl.isEmpty
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
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ParentNotificationsScreen(),
              ),
            );
          },
          // Counts monitoring alerts too, not only inbox items.
          icon: ParentAlertsBell(
            uid: FirebaseAuth.instance.currentUser?.uid ?? '',
            color: darkText,
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _menuDrawer() {
    void closeAnd(VoidCallback action) {
      Navigator.pop(context);
      action();
    }

    return Drawer(
      backgroundColor: pageBg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 16),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: darkText,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            BentoCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _menuTile(
                    Icons.chat_bubble_outline_rounded,
                    'Chat',
                    () => closeAnd(openFamilyChat),
                  ),
                  const Divider(indent: 56),
                  _menuTile(
                    Icons.notifications_none_rounded,
                    'Notifications',
                    () => closeAnd(() {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ParentNotificationsScreen(),
                        ),
                      );
                    }),
                  ),
                  const Divider(indent: 56),
                  _menuTile(
                    Icons.tune_rounded,
                    'App Rules',
                    () => closeAnd(openRulesScreen),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuTile(IconData icon, String label, VoidCallback? onTap) {
    return ListTile(
      enabled: onTap != null,
      onTap: onTap,
      leading: Icon(icon, color: darkText, size: 22),
      title: Text(
        label,
        style: const TextStyle(
          color: darkText,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textDisabled,
      ),
    );
  }

  /// True when this child has a live, unanswered Emergency Access request
  /// (EmergencyAccessService.requestAccess on the child side). Read directly
  /// off the childProfilesStream doc already in hand here rather than a
  /// second stream - this dashboard already rebuilds on every change to
  /// that doc, so the pending-request card appears/disappears live for
  /// free as soon as the parent responds.
  /// The backend creates a server-owned alert when lastSeenAt is stale.
  /// A newer check-in dismisses this banner without claiming uninstall.
  bool _isMonitoringSecurityAlertActive(Map<String, dynamic>? child) {
    final raw = child?['monitoringSecurityAlert'];
    if (raw is! Map || raw['type'] != 'no_recent_connection') return false;
    final alertedLastSeen = raw['lastSeenAt'];
    final nowLastSeen = child?['lastSeenAt'];
    if (alertedLastSeen is! Timestamp) return false;
    if (nowLastSeen is Timestamp &&
        nowLastSeen.toDate().isAfter(alertedLastSeen.toDate())) {
      return false;
    }
    return true;
  }

  Widget _monitoringSecurityAlertCard(Map<String, dynamic> child) {
    final alert = child['monitoringSecurityAlert'] as Map;
    final name = (alert['deviceName'] ?? childNameOf(child, fallback: 'Child device'))
        .toString();
    final seen = alert['lastSeenAt'];
    return BentoCard(
      color: _amberFill,
      borderColor: _amberBorder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No recent connection',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$name has stopped reporting. The device may be offline, '
                  'powered off, or monitoring may be disabled or removed. '
                  'Last seen: ${formatDate(seen)}',
                  style: const TextStyle(
                    color: grayText,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _hasPendingEmergencyAccessRequest(Map<String, dynamic>? child) {
    final raw = child?['emergencyAccess'];
    if (raw is! Map) return false;

    return (raw['status'] ?? '').toString() == 'requested';
  }

  /// Parent-side approve/deny surface for a pending Emergency Access
  /// request. Only rendered by build() while status == 'requested', so it
  /// reads as a real "action needed" banner rather than a permanent fixture.
  Widget _emergencyAccessRequestCard(
    String childProfileId,
    Map<String, dynamic> child,
  ) {
    final emergencyAccess = child['emergencyAccess'];
    final reason = emergencyAccess is Map
        ? (emergencyAccess['reason'] ?? '').toString()
        : '';
    final childName = childNameOf(child, fallback: 'Your child');

    return BentoCard(
      color: _amberFill,
      borderColor: _amberBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.warning,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$childName requested emergency access',
                      style: const TextStyle(
                        color: darkText,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        '"$reason"',
                        style: const TextStyle(color: grayText, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppPillButton(
                  label: 'Approve (30 min)',
                  compact: true,
                  onPressed: _isRespondingToEmergencyAccess
                      ? null
                      : () => _respondToEmergencyAccess(
                          childProfileId,
                          approve: true,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppPillButton(
                  label: 'Deny',
                  compact: true,
                  style: AppPillStyle.soft,
                  onPressed: _isRespondingToEmergencyAccess
                      ? null
                      : () => _respondToEmergencyAccess(
                          childProfileId,
                          approve: false,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _respondToEmergencyAccess(
    String childProfileId, {
    required bool approve,
  }) async {
    setState(() => _isRespondingToEmergencyAccess = true);

    try {
      await _emergencyAccessService.respondToRequest(
        childProfileId: childProfileId,
        approve: approve,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not respond to request: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRespondingToEmergencyAccess = false);
      }
    }
  }

  /// "Good evening" + today's date, as in design D.
  Widget _greetingHeader() {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : (now.hour < 18 ? 'Good afternoon' : 'Good evening');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}',
            style: const TextStyle(color: grayText, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            greeting,
            style: const TextStyle(
              fontFamily: AppFonts.heading,
              color: darkText,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceProfileCard(Map<String, dynamic>? child) {
    final childName = childNameOf(child, fallback: 'Child Profile');
    final childEmail = (child?['childEmail'] ?? 'Pair a child account first')
        .toString();
    final connected = child != null && isChildConnected(child);

    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _profileAvatar(connected, childName),
              const SizedBox(width: 12),
              Expanded(
                child: _profileInfo(
                  childName: childName,
                  childEmail: childEmail,
                  connected: connected,
                  presenceText: _childPresenceLabel(child, connected, childEmail),
                  presenceColor: _childPresenceColor(child, connected),
                ),
              ),
              const SizedBox(width: 10),
              AppPillButton(
                label: connected ? 'App Rules' : 'Pair',
                compact: true,
                style: AppPillStyle.brand,
                onPressed: connected
                    ? openRulesScreen
                    : () => handleBottomNavTap(2),
              ),
            ],
          ),
          if (connected) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                child?['accessibilityEnabled'] == false
                    ? const StatusPill(label: 'Blocking off', tone: StatusTone.danger)
                    : const StatusPill(label: 'Protection on', tone: StatusTone.success),
                if (child?['usageAccessEnabled'] == false)
                  const StatusPill(label: 'Usage Access off', tone: StatusTone.danger),
                if (child?['smsPermissionGranted'] == false)
                  const StatusPill(label: 'SMS backup off', tone: StatusTone.warning),
                if (child?['locationEnabled'] == false)
                  const StatusPill(label: 'Location off', tone: StatusTone.warning),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Pairing status and device connectivity are different concepts.
  /// Null means we have not received a server-side check-in yet.
  bool? _childRecentlyOnline(Map<String, dynamic>? child) {
    final seen = child?['lastSeenAt'];
    if (seen is! Timestamp) return null;
    final elapsed = DateTime.now().difference(seen.toDate());
    if (elapsed.isNegative) return true; // Server clock slightly ahead.
    return elapsed <= _presenceFreshness;
  }

  String _childPresenceLabel(
    Map<String, dynamic>? child,
    bool paired,
    String childEmail,
  ) {
    if (!paired) return 'Waiting for pairing';
    // Reported by the child's phone with its heartbeat: all blocking runs
    // in WellScreen's Accessibility service, so "off" means nothing is
    // being blocked even if the phone still shows as online.
    if (child?['accessibilityEnabled'] == false) {
      return 'Blocking is off \u2022 Accessibility disabled';
    }
    if (child?['usageAccessEnabled'] == false) {
      return 'Limited apps are paused \u2022 Usage Access disabled';
    }
    final online = _childRecentlyOnline(child);
    if (online == null) return 'Awaiting device check-in';
    final seen = child?['lastSeenAt'];
    final when = seen is Timestamp ? _relativeTime(seen.toDate()) : '';
    // SMS backup alerts cannot be sent without the child's SMS permission.
    final smsNote = child?['smsPermissionGranted'] == false
        ? ' • SMS backup off'
        : '';
    final status = online ? 'Online' : 'Offline';
    final base = when.isEmpty ? status : '$status • $when';
    return '$base$smsNote';
  }

  /// Warning shown next to the location (G2, G3), or null.
  String? _locationWarning(Map<String, dynamic>? child) {
    final location = latestLocation(child);
    if (location?['isMocked'] == true) return 'may be faked (fake GPS app)';
    if (child?['locationEnabled'] == false) return 'turned off on child phone';
    return null;
  }

  /// "2m ago" style label for the device card and the location footer.
  String _relativeTime(DateTime time) {
    final elapsed = DateTime.now().difference(time);
    if (elapsed.isNegative || elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  Color _childPresenceColor(Map<String, dynamic>? child, bool paired) {
    if (!paired) return AppColors.warning;
    if (child?['accessibilityEnabled'] == false) return AppColors.danger;
    if (child?['usageAccessEnabled'] == false) return AppColors.danger;
    final online = _childRecentlyOnline(child);
    if (online == null) return AppColors.warning;
    return online ? AppColors.success : AppColors.danger;
  }

  Widget _profileAvatar(bool connected, String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.primaryLight,
      child: connected && parts.isNotEmpty
          ? Text(
              parts,
              style: const TextStyle(
                fontFamily: AppFonts.heading,
                color: AppColors.primary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            )
          : const Icon(
              Icons.person_add_alt_rounded,
              color: AppColors.primary,
              size: 26,
            ),
    );
  }

  Widget _profileInfo({
    required String childName,
    required String childEmail,
    required bool connected,
    required String presenceText,
    required Color presenceColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          childName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: darkText,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: presenceColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                presenceText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: grayText, fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Design D hero: the logo's indigo-to-violet gradient, today's screen
  /// time against the goal, and the synced safety status. Same data as the
  /// two cards it replaces (PatternDetectionService status, no made-up
  /// score).
  Widget _screenTimeAndRiskSection(Map<String, dynamic>? child) {
    final hasReport = hasSyncedUsageReport(child);
    final total = usageTotalDuration(child);
    const goal = PatternDetectionService.warningTotalUsageLimit;
    final progress = hasReport
        ? (total.inMilliseconds / goal.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = total >= goal ? Duration.zero : goal - total;
    final statusRaw = usagePatternStatus(child);
    final flagged = usageUnhealthyAppCount(child);
    final String statusLabel;
    final IconData statusIcon;
    if (!hasReport) {
      statusLabel = 'Awaiting sync';
      statusIcon = Icons.hourglass_empty_rounded;
    } else if (statusRaw == 'unhealthy') {
      statusLabel = 'Unhealthy';
      statusIcon = Icons.gpp_maybe_rounded;
    } else if (statusRaw == 'warning') {
      statusLabel = 'Warning';
      statusIcon = Icons.gpp_maybe_rounded;
    } else {
      statusLabel = 'Healthy';
      statusIcon = Icons.verified_user_rounded;
    }

    Widget stat(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontFamily: AppFonts.heading,
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFeatures: kTabularFigures,
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.card + 4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Screen time today',
                  style: TextStyle(
                    fontFamily: AppFonts.heading,
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 112,
                height: 112,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 112,
                      height: 112,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 10,
                        strokeCap: StrokeCap.round,
                        color: AppColors.teal,
                        backgroundColor: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasReport ? formatDurationLabel(total) : 'No data',
                          style: const TextStyle(
                            fontFamily: AppFonts.heading,
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            fontFeatures: kTabularFigures,
                          ),
                        ),
                        Text(
                          'of ${goal.inHours}h goal',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    stat('Safety status', statusLabel),
                    const SizedBox(height: 10),
                    stat('Apps flagged', hasReport ? '$flagged' : '—'),
                    const SizedBox(height: 10),
                    stat(
                      'Left before goal',
                      hasReport ? formatDurationLabel(remaining) : '—',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cardTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: AppFonts.heading,
        color: darkText,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// Location footer shown under Top Apps: pin, place name and a
  /// "View Map" link. The full map lives on the Live Location screen.
  Widget _locationFooter(Map<String, dynamic>? child) {
    final hasLocation = hasSharedLocation(child);
    final location = locationText(child);
    final warning = _locationWarning(child);
    final locationLine = hasLocation
        ? 'Location • $location'
        : 'Location • waiting for GPS update';

    return Row(
      children: [
        Icon(
          warning == null
              ? Icons.location_on_outlined
              : Icons.location_off_outlined,
          color: warning == null ? grayText : AppColors.danger,
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            warning == null
                ? locationLine
                : '$locationLine\n⚠ Location $warning',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: warning == null ? darkText : AppColors.danger,
              fontSize: 13,
            ),
          ),
        ),
        TextButton(
          onPressed: () => openGpsMap(child),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('View Map'),
        ),
      ],
    );
  }

  /// Real per-app usage synced from the child device (see
  /// child_home_screen.dart's syncUsageReport, which writes
  /// child_profiles/{id}.latestUsageReport.topApps from
  /// UsageTrackingService.getTodayUsage()).
  Widget _topAppsSection(Map<String, dynamic>? child) {
    final apps = usageTopApps(child).take(4).toList();

    return BentoCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _cardTitle('Top Apps')),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AllAppsScreen(childProfileId: _primaryChildId ?? ''),
                    ),
                  );
                },
                child: const Text('See All'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (apps.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'No usage data synced yet. Ask your child to open '
                      'WellScreen so today\'s usage can sync.',
                      style: TextStyle(color: grayText, fontSize: 13),
                    ),
                  )
                else
                  ..._buildTopAppRows(apps, child),
                const Divider(height: 18),
              ],
            ),
          ),
          _locationFooter(child),
        ],
      ),
    );
  }

  List<Widget> _buildTopAppRows(
    List<Map<String, dynamic>> apps,
    Map<String, dynamic>? child,
  ) {
    final maxDurationMs = apps
        .map((app) => (app['usageDurationMs'] as num?)?.toInt() ?? 0)
        .fold<int>(0, (highest, value) => value > highest ? value : highest);

    return apps.map((app) {
      final durationMs = (app['usageDurationMs'] as num?)?.toInt() ?? 0;
      final packageName = (app['packageName'] ?? '').toString();
      final name = (app['displayName'] ?? '').toString().trim();
      final displayName = name.isNotEmpty
          ? name
          : (packageName.isEmpty ? 'Unknown app' : packageName);
      final ratio = maxDurationMs > 0 ? durationMs / maxDurationMs : 0.0;

      return _appUsageRow(
        icon: _iconForApp(displayName),
        iconColor: purple,
        iconBase64: _usageIconForPackage(child, packageName),
        packageName: packageName,
        appName: displayName,
        time: formatDurationLabel(Duration(milliseconds: durationMs)),
        value: ratio.clamp(0.0, 1.0),
      );
    }).toList();
  }

  IconData _iconForApp(String name) {
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
    String? iconBase64,
    String? packageName,
    required String appName,
    required String time,
    required double value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          AppUsageIcon(
            encoded: iconBase64,
            fallback: icon,
            fallbackColor: iconColor,
            size: 34,
            label: appName,
            packageName: packageName,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: darkText,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time,
                      style: const TextStyle(
                        color: grayText,
                        fontSize: 13,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(
                    value: value,
                    minHeight: 4,
                    color: purple,
                    backgroundColor: AppColors.border,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Last 7 days of screen time from the child's synced `dailyUsageTotals`
  /// (see DailyUsageHistory), plus a 30-day average of completed days.
  /// Today's bar uses the same live total as the Screen Time card above.
  /// Days with no reading stay empty rather than being guessed, and the
  /// card falls back to an empty state until the child's phone has synced.
  Widget _weeklyTrendSection(Map<String, dynamic>? child) {
    const warningLimit = PatternDetectionService.warningTotalUsageLimit;
    const dayLabels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const maxBarHeight = 110.0;

    final now = DateTime.now();
    final totals = DailyUsageHistory.parse(child?['dailyUsageTotals']);
    final liveToday = usageTotalDuration(child);
    if (totals.isNotEmpty && liveToday > Duration.zero) {
      final todayKey = DailyUsageHistory.dayKey(now);
      if ((totals[todayKey] ?? 0) < liveToday.inMilliseconds) {
        totals[todayKey] = liveToday.inMilliseconds;
      }
    }
    final days = DailyUsageHistory.lastSevenDays(totals, now);
    final hasData = days.any((day) => day.value != null);
    final average = DailyUsageHistory.averageOfCompletedDays(totals, now);

    var maxMs = warningLimit.inMilliseconds;
    for (final day in days) {
      final ms = day.value?.inMilliseconds ?? 0;
      if (ms > maxMs) maxMs = ms;
    }

    final header = Row(
      children: [
        Expanded(child: _cardTitle('Weekly Screen Time')),
        Text(
          '${warningLimit.inHours}h warning level',
          style: const TextStyle(color: grayText, fontSize: 12),
        ),
      ],
    );

    if (!hasData) {
      return BentoCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 14),
            const Center(
              child: Icon(
                Icons.bar_chart_rounded,
                color: AppColors.textDisabled,
                size: 40,
              ),
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'No daily history yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: darkText,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'The chart fills in after the child\'s phone syncs usage.',
                textAlign: TextAlign.center,
                style: TextStyle(color: grayText, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }

    final warningTop =
        maxBarHeight * warningLimit.inMilliseconds / maxMs;

    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 14),
          SizedBox(
            height: maxBarHeight + 40,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 20 + warningTop,
                  child: Container(height: 1, color: AppColors.warning),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              days[i].value == null
                                  ? '-'
                                  : formatDurationLabel(days[i].value!)
                                      .split(' ')
                                      .first,
                              style: const TextStyle(
                                color: grayText,
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 18,
                              height: days[i].value == null
                                  ? 2
                                  : (maxBarHeight *
                                            days[i].value!.inMilliseconds /
                                            maxMs)
                                        .clamp(2.0, maxBarHeight),
                              decoration: BoxDecoration(
                                color: days[i].value == null
                                    ? AppColors.border
                                    : days[i].value! >= warningLimit
                                    ? AppColors.warning
                                    : purple,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              i == days.length - 1
                                  ? 'Today'
                                  : dayLabels[days[i].key.weekday - 1],
                              style: TextStyle(
                                color: i == days.length - 1
                                    ? darkText
                                    : grayText,
                                fontSize: 11,
                                fontWeight: i == days.length - 1
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            average == null
                ? 'Last 30 days: not enough history yet.'
                : 'Last 30 days: average '
                      '${formatDurationLabel(average.average)} per day '
                      '(${average.daysCounted} '
                      '${average.daysCounted == 1 ? 'day' : 'days'} recorded)',
            style: const TextStyle(color: grayText, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
