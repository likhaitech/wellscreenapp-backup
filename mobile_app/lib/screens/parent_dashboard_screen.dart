import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/emergency_access_service.dart';
import '../widgets/app_usage_icon.dart';
import '../services/pattern_detection_service.dart';
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

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
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
                _weeklyTrendSection(),
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
        builder: (context, unread) => FloatingPillDock(
        currentIndex: currentIndex,
        items: [
          const DockItem(icon: Icons.home_outlined, label: 'Home'),
          DockItem(
            icon: Icons.chat_bubble_outline_rounded,
            label: 'Chat',
            showBadge:
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
          icon: const ChatUnreadBell(color: darkText, size: 24),
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
    final name = (alert['deviceName'] ?? child['name'] ?? 'Child device')
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
    final childName = (child['name'] ?? 'Your child').toString();

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

  Widget _deviceProfileCard(Map<String, dynamic>? child) {
    final childName = (child?['name'] ?? 'Child Profile').toString();
    final childEmail = (child?['childEmail'] ?? 'Pair a child account first')
        .toString();
    final connected = child != null && isChildConnected(child);

    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          _profileAvatar(connected),
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
    final online = _childRecentlyOnline(child);
    if (online == null) return 'Awaiting device check-in';
    final seen = child?['lastSeenAt'];
    final when = seen is Timestamp ? _relativeTime(seen.toDate()) : '';
    if (online) return when.isEmpty ? 'Online' : 'Online • $when';
    return when.isEmpty ? 'Offline' : 'Offline • $when';
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
    final online = _childRecentlyOnline(child);
    if (online == null) return AppColors.warning;
    return online ? AppColors.success : AppColors.danger;
  }

  Widget _profileAvatar(bool connected) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: connected ? softGreen : softBlue,
      child: Icon(
        connected ? Icons.person_rounded : Icons.person_add_alt_rounded,
        color: connected ? AppColors.success : purple,
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
          connected ? "$childName's Phone" : childName,
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

  Widget _screenTimeAndRiskSection(Map<String, dynamic>? child) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _screenTimeCard(child)),
          const SizedBox(width: 12),
          Expanded(child: _riskCard(child)),
        ],
      ),
    );
  }

  Widget _cardTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: darkText,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  /// Real data synced from the paired child's device via
  /// [PatternDetectionService] / [UsageTrackingService] (see
  /// child_home_screen.dart's syncUsageReport). Shows an honest
  /// "no data yet" state instead of a placeholder number when nothing has
  /// synced.
  Widget _screenTimeCard(Map<String, dynamic>? child) {
    final hasReport = hasSyncedUsageReport(child);
    final totalDuration = usageTotalDuration(child);
    const warningLimit = PatternDetectionService.warningTotalUsageLimit;
    final progress = hasReport
        ? (totalDuration.inMilliseconds / warningLimit.inMilliseconds).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    final limitHours = warningLimit.inHours;
    final limitMinutes = warningLimit.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');

    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Screen Time'),
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
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
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      color: purple,
                      backgroundColor: AppColors.border,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasReport ? '${hours}h ${minutes}m' : 'No data',
                        style: TextStyle(
                          color: hasReport ? darkText : grayText,
                          fontSize: hasReport ? 20 : 15,
                          fontWeight: FontWeight.w800,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'of ${limitHours}h ${limitMinutes}m',
                        style: const TextStyle(
                          color: grayText,
                          fontSize: 12,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Real pattern status synced from the child device. There is no 0-100
  /// numeric "risk score" anywhere in the real detection logic
  /// ([PatternDetectionService] only produces healthy/warning/unhealthy),
  /// so this intentionally does not fabricate one.
  Widget _riskCard(Map<String, dynamic>? child) {
    final hasReport = hasSyncedUsageReport(child);
    final statusRaw = usagePatternStatus(child);
    final unhealthyCount = usageUnhealthyAppCount(child);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    StatusTone tone;

    if (!hasReport) {
      statusColor = AppColors.textDisabled;
      statusLabel = 'No Data';
      statusIcon = Icons.shield_outlined;
      tone = StatusTone.neutral;
    } else if (statusRaw == 'unhealthy') {
      statusColor = AppColors.danger;
      statusLabel = 'Unhealthy';
      statusIcon = Icons.gpp_maybe_rounded;
      tone = StatusTone.danger;
    } else if (statusRaw == 'warning') {
      statusColor = AppColors.warning;
      statusLabel = 'Warning';
      statusIcon = Icons.gpp_maybe_rounded;
      tone = StatusTone.warning;
    } else {
      statusColor = AppColors.success;
      statusLabel = 'Healthy';
      statusIcon = Icons.verified_user_rounded;
      tone = StatusTone.success;
    }

    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Safety Status'),
          const SizedBox(height: 12),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 60),
                const SizedBox(height: 10),
                StatusPill(label: statusLabel, tone: tone),
                const SizedBox(height: 6),
                Text(
                  hasReport
                      ? '$unhealthyCount app${unhealthyCount == 1 ? '' : 's'} flagged'
                      : 'Awaiting sync',
                  style: const TextStyle(color: grayText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Location footer shown under Top Apps: pin, place name and a
  /// "View Map" link. The full map lives on the Live Location screen.
  Widget _locationFooter(Map<String, dynamic>? child) {
    final hasLocation = hasSharedLocation(child);
    final location = locationText(child);

    return Row(
      children: [
        const Icon(Icons.location_on_outlined, color: grayText, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            hasLocation
                ? 'Location • $location'
                : 'Location • waiting for GPS update',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: darkText, fontSize: 13),
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

  /// Only today's report is synced and stored (see syncUsageReport in
  /// child_home_screen.dart) - there is no per-day history collection, so
  /// a real weekly chart can't be drawn honestly. Shows the card in the new
  /// style with an empty state instead of made-up bars.
  Widget _weeklyTrendSection() {
    const warningLimit = PatternDetectionService.warningTotalUsageLimit;

    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _cardTitle('Weekly Screen Time')),
              Text(
                '${warningLimit.inHours}h Limit',
                style: const TextStyle(color: grayText, fontSize: 12),
              ),
            ],
          ),
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
              'Weekly trends aren\'t available yet',
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
              'Only today\'s report is stored so far.',
              textAlign: TextAlign.center,
              style: TextStyle(color: grayText, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
