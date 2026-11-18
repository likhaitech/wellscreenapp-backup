import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/emergency_access_service.dart';
import '../widgets/app_usage_icon.dart';
import '../services/pattern_detection_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_bottom_nav.dart';
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
  // Aliased onto the shared AppColors palette (theme/app_theme.dart) rather
  // than the ad hoc literals this screen used to declare on its own - same
  // names so the body below didn't need a line-by-line rewrite, but now
  // every value traces back to the one shared source of truth.
  static const Color purple = AppColors.primary;
  static const Color deepPurple = AppColors.primaryDark;
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;
  static const Color softGreen = AppColors.successBg;
  static const Color softBlue = AppColors.infoBg;

  static const double cebuLatitude = 10.31570;
  static const double cebuLongitude = 123.88540;

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

    return cebuLatitude;
  }

  double locationLongitude(Map<String, dynamic>? data) {
    final location = latestLocation(data);
    final longitude = location?['longitude'];

    if (longitude is num) {
      return longitude.toDouble();
    }

    return cebuLongitude;
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

  String usagePatternStatus(Map<String, dynamic>? data) {
    final report = latestUsageReport(data);
    return (report?['patternStatus'] ?? '').toString();
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
    final latitude = locationLatitude(child);
    final longitude = locationLongitude(child);
    final label = hasSharedLocation(child)
        ? locationText(child)
        : 'Cebu City, Philippines preview';
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
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DevicePairingScreen()),
      );
    } else if (index == 2) {
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
    } else if (index == 3) {
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
      backgroundColor: pageBg,
      body: SafeArea(
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
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              children: [
                _topBar(),
                const SizedBox(height: 18),
                _deviceProfileCard(primaryChild),
                if (_isMonitoringSecurityAlertActive(primaryChild)) ...[
                  const SizedBox(height: 14),
                  _monitoringSecurityAlertCard(primaryChild!),
                ],
                if (_hasPendingEmergencyAccessRequest(primaryChild)) ...[
                  const SizedBox(height: 22),
                  _emergencyAccessRequestCard(
                    _primaryChildId ?? '',
                    primaryChild!,
                  ),
                ],
                const SizedBox(height: 22),
                _screenTimeAndRiskSection(primaryChild),
                const SizedBox(height: 18),
                _gpsMapCard(primaryChild),
                const SizedBox(height: 22),
                _topAppsSection(primaryChild),
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
          WellScreenNavItem(
            icon: Icons.phone_android_rounded,
            label: 'Devices',
          ),
          WellScreenNavItem(icon: Icons.analytics_rounded, label: 'Reports'),
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
          _logoBox(),
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ParentNotificationsScreen(),
                ),
              );
            },
            icon: const ChatUnreadBell(color: Colors.white, size: 33),
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
    return _whiteCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.warning,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No Recent Connection',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: darkText,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '$name has stopped reporting. The device may be offline, '
                  'powered off, or monitoring may be disabled or removed. '
                  'Last seen: ${formatDate(seen)}',
                  style: const TextStyle(color: grayText, height: 1.35),
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
  /// reads as a real "action needed" card rather than a permanent fixture.
  Widget _emergencyAccessRequestCard(
    String childProfileId,
    Map<String, dynamic> child,
  ) {
    final emergencyAccess = child['emergencyAccess'];
    final reason = emergencyAccess is Map
        ? (emergencyAccess['reason'] ?? '').toString()
        : '';
    final childName = (child['name'] ?? 'Your child').toString();

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
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: AppColors.danger,
                  size: 29,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Emergency Access Requested',
                      style: TextStyle(
                        color: darkText,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      reason.isEmpty
                          ? '$childName wants restrictions temporarily lifted.'
                          : '$childName: "$reason"',
                      style: const TextStyle(
                        color: grayText,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
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
              Expanded(
                child: OutlinedButton(
                  onPressed: _isRespondingToEmergencyAccess
                      ? null
                      : () => _respondToEmergencyAccess(
                          childProfileId,
                          approve: false,
                        ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Deny'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isRespondingToEmergencyAccess
                      ? null
                      : () => _respondToEmergencyAccess(
                          childProfileId,
                          approve: true,
                        ),
                  style: FilledButton.styleFrom(
                    backgroundColor: purple,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Approve (30 min)'),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 430;

        return _whiteCard(
          padding: const EdgeInsets.all(18),
          child: compact
              ? Column(
                  children: [
                    Row(
                      children: [
                        _profileAvatar(connected),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _profileInfo(
                            childName: childName,
                            childEmail: childEmail,
                            connected: connected,
                            presenceText: _childPresenceLabel(
                              child,
                              connected,
                              childEmail,
                            ),
                            presenceColor: _childPresenceColor(
                              child,
                              connected,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _smallPurpleButton(
                            label: 'View Map',
                            onTap: () => openGpsMap(child),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _smallPurpleButton(
                            label: 'View Rules',
                            onTap: openRulesScreen,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Same width/height as View Map, centered directly below.
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
                  ],
                )
              : Row(
                  children: [
                    _profileAvatar(connected),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _profileInfo(
                        childName: childName,
                        childEmail: childEmail,
                        connected: connected,
                        presenceText: _childPresenceLabel(
                          child,
                          connected,
                          childEmail,
                        ),
                        presenceColor: _childPresenceColor(child, connected),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      children: [
                        SizedBox(
                          width: 130,
                          child: _smallPurpleButton(
                            label: 'View Map',
                            onTap: () => openGpsMap(child),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 130,
                          child: _smallPurpleButton(
                            label: 'View Rules',
                            onTap: openRulesScreen,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 130,
                          child: _smallPurpleButton(
                            label: 'Chatbox',
                            onTap: openFamilyChat,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
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
    final online = _childRecentlyOnline(child);
    if (online == null) return 'Status unknown - awaiting device check-in';
    if (online) return 'Online - $childEmail';
    final seen = child?['lastSeenAt'];
    return seen is Timestamp
        ? 'Offline / not recently seen - last check-in: ${formatDate(seen)}'
        : 'Offline / not recently seen';
  }

  Color _childPresenceColor(Map<String, dynamic>? child, bool paired) {
    if (!paired) return Colors.orange;
    final online = _childRecentlyOnline(child);
    if (online == null) return AppColors.warning;
    return online ? teal : AppColors.danger;
  }

  Widget _profileAvatar(bool connected) {
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
                color: presenceColor,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                presenceText,
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
    required VoidCallback onTap,
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

  Widget _screenTimeAndRiskSection(Map<String, dynamic>? child) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _screenTimeCard(child)),
        const SizedBox(width: 14),
        Expanded(child: _riskCard(child)),
      ],
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

    return _whiteCard(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 170),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 18),
            hasReport
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$hours',
                            style: const TextStyle(
                              fontSize: 43,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(
                            text: 'h ',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          TextSpan(
                            text: '$minutes',
                            style: const TextStyle(
                              fontSize: 43,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const TextSpan(
                            text: 'm',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'No data yet',
                      style: TextStyle(
                        color: grayText,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
            const SizedBox(height: 8),
            const Text(
              'Warning threshold: 3h',
              textAlign: TextAlign.center,
              style: TextStyle(color: grayText, fontWeight: FontWeight.w800),
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

  /// Real pattern status synced from the child device. There is no 0-100
  /// numeric "risk score" anywhere in the real detection logic
  /// ([PatternDetectionService] only produces healthy/warning/unhealthy),
  /// so this intentionally does not fabricate one - the previous "32/100"
  /// here was a hardcoded placeholder, not a real computed score.
  Widget _riskCard(Map<String, dynamic>? child) {
    final hasReport = hasSyncedUsageReport(child);
    final statusRaw = usagePatternStatus(child);
    final unhealthyCount = usageUnhealthyAppCount(child);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (!hasReport) {
      statusColor = grayText;
      statusLabel = 'No Data';
      statusIcon = Icons.hourglass_empty_rounded;
    } else if (statusRaw == 'unhealthy') {
      statusColor = AppColors.danger;
      statusLabel = 'Unhealthy';
      statusIcon = Icons.warning_rounded;
    } else if (statusRaw == 'warning') {
      statusColor = AppColors.warning;
      statusLabel = 'Warning';
      statusIcon = Icons.shield_moon_rounded;
    } else {
      statusColor = teal;
      statusLabel = 'Healthy';
      statusIcon = Icons.shield_rounded;
    }

    return _whiteCard(
      // Keep the existing visual height as a minimum, but let the card grow
      // when a status label wraps or Android uses larger text scaling.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 170),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            // A fixed minimum gap works even with unbounded vertical space;
            // Spacer inside the former fixed-height column caused overflow.
            const SizedBox(height: 18),
            Icon(statusIcon, color: statusColor, size: 62),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                statusLabel,
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
                hasReport
                    ? '$unhealthyCount app${unhealthyCount == 1 ? '' : 's'} flagged'
                    : 'Awaiting sync',
                style: const TextStyle(
                  color: darkText,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsMapCard(Map<String, dynamic>? child) {
    final location = locationText(child);
    final updated = locationUpdatedText(child);
    final hasLocation = hasSharedLocation(child);
    final latitude = locationLatitude(child);
    final longitude = locationLongitude(child);

    return _whiteCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: softGreen,
                child: Icon(Icons.location_on_rounded, color: teal, size: 34),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GPS Location Map',
                      style: TextStyle(
                        color: darkText,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasLocation ? location : 'Waiting for child GPS update',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: grayText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Updated: $updated',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: grayText, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => openGpsMap(child),
                icon: const Icon(
                  Icons.open_in_full_rounded,
                  color: purple,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => openGpsMap(child),
            child: GpsMapPreview(
              latitude: latitude,
              longitude: longitude,
              hasLocation: hasLocation,
            ),
          ),
        ],
      ),
    );
  }

  /// Real per-app usage synced from the child device (see
  /// child_home_screen.dart's syncUsageReport, which writes
  /// child_profiles/{id}.latestUsageReport.topApps from
  /// UsageTrackingService.getTodayUsage()). Previously this rendered four
  /// hardcoded rows (YouTube/TikTok/Facebook/Mobile Game) with no data
  /// source at all.
  Widget _topAppsSection(Map<String, dynamic>? child) {
    final apps = usageTopApps(child).take(4).toList();

    return _whiteCard(
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Top Apps Today',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
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
                child: const Text(
                  'View All',
                  style: TextStyle(color: purple, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (apps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No usage data synced yet. Ask your child to open WellScreen '
                'and tap "Sync Usage".',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w600),
              ),
            )
          else
            ..._buildTopAppRows(apps, child),
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
      padding: const EdgeInsets.only(bottom: 17),
      child: Row(
        children: [
          AppUsageIcon(
            encoded: iconBase64,
            fallback: icon,
            fallbackColor: iconColor,
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

  /// Was a hardcoded bar chart (Mon-Sun, made-up hour values) with no data
  /// source. Only today's report is currently synced/stored (see
  /// syncUsageReport in child_home_screen.dart) - there is no per-day
  /// history collection yet, so a real weekly trend can't be computed
  /// honestly. Showing a placeholder instead of fabricated numbers until
  /// daily history storage is built.
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
            'This needs several days of synced usage reports stored per '
            'day. Today\'s report only.',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayText, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // Delegates to the shared AppCard (theme/app_theme.dart) instead of a
  // screen-local Container+BoxDecoration - this was the one competing card
  // style AppCard's doc comment calls out by name. Kept as a thin wrapper
  // (same name/signature) so none of the ~15 call sites above needed to
  // change.
  Widget _whiteCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(18),
  }) {
    return AppCard(padding: padding, child: child);
  }
}
