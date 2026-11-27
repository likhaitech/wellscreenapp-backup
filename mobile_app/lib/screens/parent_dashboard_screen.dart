import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/daily_goal.dart';
import '../services/child_location_text.dart';
import '../services/guardian_dashboard_text.dart';
import '../services/chat_unread_service.dart';
import '../services/daily_usage_history.dart';
import '../services/weekly_summary.dart';
import '../services/emergency_access_service.dart';
import '../services/parent_alert_badge_service.dart';
import '../widgets/app_usage_icon.dart';
import '../services/guardian_activity_service.dart';
import '../services/parent_phone_sync_service.dart';
import '../services/push_notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/daily_goal_sheet.dart';
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
import '../utils/primary_child.dart';
import '../utils/status_tone.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen>
    with WidgetsBindingObserver {
  // Aliased onto the shared AppColors palette (theme/app_theme.dart) rather
  // than the ad hoc literals this screen used to declare on its own - same
  // names so the body below didn't need a line-by-line rewrite, but now
  // every value traces back to the one shared source of truth.
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;
  static const Color _amberFill = AppColors.warningBg;
  static const Color _amberBorder = Color(0xFFF6DDAF);


  int currentIndex = 0;

  // Tracked from the latest childProfilesStream build so bottom-nav/menu
  // taps (which run outside build()) know which paired child's usage
  // report to open. Real Firestore doc id, not a fabricated field.
  String? _primaryChildId;

  // The child the guardian picked in the Connected Devices popup. Null
  // means the automatic choice (most recently active child). Kept only
  // while the app is open.
  String? _selectedChildId;

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
    // Counts this guardian as active today on the admin dashboard.
    WidgetsBinding.instance.addObserver(this);
    GuardianActivityService.instance.markActive();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ChatNotificationsService.instance.markDashboardReady();
    });
    // Refresh the visible stale/online state even without a new Firestore write.
    _presenceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      GuardianActivityService.instance.markActive();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceRefreshTimer?.cancel();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> childProfilesStream(String uid) {
    return FirebaseFirestore.instance
        .collection('child_profiles')
        .where('parentId', isEqualTo: uid)
        .snapshots();
  }

  bool isChildConnected(Map<String, dynamic> data) =>
      childLooksConnected(data);

  String formatDate(dynamic value) => formatDashboardDate(value);

  Map<String, dynamic>? latestLocation(Map<String, dynamic>? data) =>
      latestLocationOf(data);

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

  String locationText(Map<String, dynamic>? data) => locationTextOf(data);

  String locationUpdatedText(Map<String, dynamic>? data) =>
      locationUpdatedTextOf(data);

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

  /// When the child's phone last sent its usage report (server time).
  DateTime? usageReportTime(Map<String, dynamic>? data) {
    final value = data?['usageReportUpdatedAt'];
    return value is Timestamp ? value.toDate().toLocal() : null;
  }

  /// The report is a running total for one day, so after midnight the last
  /// report belongs to yesterday and must not be shown as today's time.
  bool usageReportIsFromToday(Map<String, dynamic>? data, {DateTime? now}) {
    final time = usageReportTime(data);
    if (time == null) return hasSyncedUsageReport(data); // older profiles
    final today = now ?? DateTime.now();
    return time.year == today.year &&
        time.month == today.month &&
        time.day == today.day;
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

    // This child's own goal (age group or the guardian's value).
    final goal = DailyGoal.durationFor(data);
    String fromTotal = 'healthy';
    if (total >= goal + DailyGoal.highAlertExtra) {
      fromTotal = 'unhealthy';
    } else if (total >= goal) {
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
    final records = childDocs.map((doc) => doc.data()).toList();
    // The child the guardian picked in the popup, while still paired.
    final picked = selectedChildIndex(
      childDocs.map((doc) => doc.id).toList(),
      records,
      _selectedChildId,
    );
    if (picked >= 0) return childDocs[picked];
    // Otherwise the most recently active connected child, not simply the
    // first one - see primary_child.dart.
    final index = pickPrimaryChildIndex(records, isChildConnected);
    return index < 0 ? null : childDocs[index];
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
                _deviceProfileCard(primaryChild, childDocs),
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
    final asked = emergencyAccess is Map
        ? emergencyAccess['requestedMinutes']
        : null;
    final askedMinutes = asked is num ? asked.toInt() : null;
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
                    if (askedMinutes != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        askedForLabel(askedMinutes),
                        style: const TextStyle(
                          color: darkText,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
                  label: 'Approve...',
                  compact: true,
                  onPressed: _isRespondingToEmergencyAccess
                      ? null
                      : () => _approveEmergencyAccess(
                          childProfileId,
                          askedMinutes: askedMinutes,
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

  /// The guardian picks how long Emergency Access lasts.
  Future<void> _approveEmergencyAccess(
    String childProfileId, {
    int? askedMinutes,
  }) async {
    final options = emergencyMinuteChoices(askedMinutes);
    // Starts on what the child asked for; the guardian can change it.
    var minutes =
        askedMinutes != null && options.contains(askedMinutes) ? askedMinutes : 15;
    final customMinutes = TextEditingController();
    final chosen = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How long?',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Blocked apps, focus mode, bedtime and time limits are '
                  'lifted for this time. Adult, gambling, drug and other '
                  'harmful websites stay blocked.',
                  style: TextStyle(color: grayText, fontSize: 13, height: 1.35),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in options)
                      ChoiceChip(
                        label: Text(
                          option < 60
                              ? '$option min'
                              : (option % 60 == 0
                                    ? '${option ~/ 60} hr'
                                    : '${option ~/ 60} hr ${option % 60} min'),
                        ),
                        selected: minutes == option,
                        onSelected: (_) => setSheet(() {
                          minutes = option;
                          customMinutes.clear();
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: customMinutes,
                    keyboardType: TextInputType.number,
                    maxLength: 3,
                    decoration: const InputDecoration(
                      hintText: 'Or type minutes',
                      suffixText: 'min',
                      isDense: true,
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (text) {
                      final typed = int.tryParse(text.trim());
                      if (typed != null && isValidEmergencyMinutes(typed)) {
                        setSheet(() => minutes = typed);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Any time from 1 to 120 minutes.',
                  style: TextStyle(color: grayText, fontSize: 12),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: AppPillButton(
                    label: 'Approve $minutes min',
                    onPressed: () => Navigator.pop(sheetContext, minutes),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    await _respondToEmergencyAccess(
      childProfileId,
      approve: true,
      duration: Duration(minutes: chosen),
    );
  }

  Future<void> _respondToEmergencyAccess(
    String childProfileId, {
    required bool approve,
    Duration duration = EmergencyAccessService.defaultGrantDuration,
  }) async {
    setState(() => _isRespondingToEmergencyAccess = true);

    try {
      await _emergencyAccessService.respondToRequest(
        childProfileId: childProfileId,
        approve: approve,
        duration: duration,
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

  Widget _deviceProfileCard(
    Map<String, dynamic>? child,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> childDocs,
  ) {
    final childName = childNameOf(child, fallback: 'Child Profile');
    final childEmail = (child?['childEmail'] ?? pairChildFirst)
        .toString();
    final connected = child != null && isChildConnected(child);

    return BentoCard(
      padding: const EdgeInsets.all(14),
      // Tapping the child opens the list of paired child devices.
      onTap: connected ? () => _showConnectedDevices(childDocs) : null,
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
                for (final label in protectionStatusLabels(child))
                  StatusPill(
                    label: label,
                    tone: switch (label) {
                      'Protection on' => StatusTone.success,
                      'SMS backup off' => StatusTone.warning,
                      _ => StatusTone.danger,
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Popup listing every child phone paired to this guardian account: just
  /// the child's name and Online/Offline. Tapping a child switches the
  /// whole dashboard (and Reports, All Apps, Live Location, Chat) to them.
  Future<void> _showConnectedDevices(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> childDocs,
  ) {
    final records = childDocs.map((doc) => doc.data()).toList();
    final order = connectedDeviceIndexes(records);

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.devices_rounded, color: AppColors.primary),
                SizedBox(width: 10),
                Text(
                  connectedDevicesTitle,
                  style: TextStyle(
                    fontFamily: AppFonts.heading,
                    color: darkText,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              switchChildHint,
              style: TextStyle(color: grayText, fontSize: 13),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: order.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    noConnectedDevices,
                    style: TextStyle(color: grayText, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: order.length,
                  itemBuilder: (_, i) {
                    final doc = childDocs[order[i]];
                    return _connectedDeviceRow(
                      doc.data(),
                      isShown: doc.id == _primaryChildId,
                      onTap: () {
                        Navigator.of(dialogContext).pop();
                        if (doc.id != _primaryChildId) {
                          setState(() => _selectedChildId = doc.id);
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _connectedDeviceRow(
    Map<String, dynamic> child, {
    required bool isShown,
    required VoidCallback onTap,
  }) {
    final name = childNameOf(child, fallback: 'Child device');
    final online = _childRecentlyOnline(child);
    final seen = child['lastSeenAt'];
    final when = seen is Timestamp ? _relativeTime(seen.toDate()) : '';
    final String status;
    final Color color;
    if (online == null) {
      status = 'Awaiting device check-in';
      color = AppColors.warning;
    } else if (online) {
      status = 'Online';
      color = AppColors.success;
    } else {
      status = when.isEmpty ? 'Offline' : 'Offline • $when';
      color = AppColors.danger;
    }

    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: isShown ? AppColors.primaryLight : null,
      leading: _profileAvatar(true, name),
      title: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: darkText,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      trailing: isShown
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : const Icon(Icons.chevron_right_rounded, color: grayText),
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
        Row(
          children: [
            Flexible(
              child: Text(
                childName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: darkText,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Shows the card opens the Connected Devices switcher.
            if (connected)
              const Icon(
                Icons.expand_more_rounded,
                color: grayText,
                size: 20,
              ),
          ],
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
    final hasAnyReport = hasSyncedUsageReport(child);
    final hasReport = hasAnyReport && usageReportIsFromToday(child);
    // Yesterday's total is not today's screen time.
    final total = hasReport ? usageTotalDuration(child) : Duration.zero;
    final lastReportAt = usageReportTime(child);
    final goal = DailyGoal.durationFor(child);
    final progress = hasReport
        ? (total.inMilliseconds / goal.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final remaining = total >= goal ? Duration.zero : goal - total;
    final statusRaw = usagePatternStatus(child);
    final flagged = usageUnhealthyAppCount(child);
    // Red card for Unhealthy, amber for Warning (only for today's report).
    final tone = hasReport ? cardToneOf(statusRaw) : CardTone.normal;
    final over = total > goal ? total - goal : Duration.zero;
    final String statusLabel;
    final IconData statusIcon;
    if (hasAnyReport && !hasReport) {
      statusLabel = 'No report today';
      statusIcon = Icons.hourglass_empty_rounded;
    } else if (!hasReport) {
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
        gradient: cardGradient(tone),
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
                        color: cardProgressColor(tone),
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
                          'of ${DailyGoal.label(goal.inMinutes)} goal',
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
                      over > Duration.zero ? 'Over goal by' : 'Left before goal',
                      !hasReport
                          ? '—'
                          : formatDurationLabel(
                              over > Duration.zero ? over : remaining,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasAnyReport && !hasReport && lastReportAt != null) ...[
            const SizedBox(height: 12),
            Text(
              'No report from the child\'s phone yet today. Last report: '
              '${_shortDateTime(lastReportAt)}.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (_primaryChildId != null) ...[
            const SizedBox(height: 14),
            Material(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                onTap: () => _editDailyGoal(child),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Daily goal: ${DailyGoal.summary(child)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Edit',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _shortDateTime(DateTime t) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final minute = t.minute.toString().padLeft(2, '0');
    return '${months[t.month - 1]} ${t.day}, $hour:$minute '
        '${t.hour < 12 ? 'AM' : 'PM'}';
  }

  /// Same goal editor as Devices: age group + the guardian's own value.
  Future<void> _editDailyGoal(Map<String, dynamic>? child) async {
    final profileId = _primaryChildId;
    if (profileId == null) return;
    final update = await showDailyGoalSheet(
      context,
      childName: childNameOf(child, fallback: 'your child'),
      profile: child,
    );
    if (update == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('child_profiles')
          .doc(profileId)
          .update({
            ...update,
            DailyGoal.updatedAtField: FieldValue.serverTimestamp(),
          })
          .timeout(const Duration(seconds: 10));
      messenger.showSnackBar(
        const SnackBar(content: Text('Daily goal saved.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save the daily goal. Check your connection.'),
        ),
      );
    }
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
    final locationLine = hasLocation
        ? 'Location • $location'
        : 'Location • waiting for GPS update';

    return Row(
      children: [
        const Icon(Icons.location_on_outlined, color: grayText, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            locationLine,
            maxLines: 2,
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
  /// Daily totals for the chart and the weekly summary, with today's live
  /// total when it is newer than the stored one.
  Map<String, int> _weeklyTotals(Map<String, dynamic>? child, DateTime now) {
    final totals = DailyUsageHistory.parse(child?['dailyUsageTotals']);
    final liveToday = usageTotalDuration(child);
    if (totals.isNotEmpty && liveToday > Duration.zero) {
      final todayKey = DailyUsageHistory.dayKey(now);
      if ((totals[todayKey] ?? 0) < liveToday.inMilliseconds) {
        totals[todayKey] = liveToday.inMilliseconds;
      }
    }
    return totals;
  }

  static const List<String> _weekdayNames = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];
  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _dayLabel(DateTime day) =>
      '${_weekdayNames[day.weekday - 1]}, ${_monthNames[day.month - 1]} ${day.day}';

  /// "This week" sheet: totals, average, days over the goal, busiest and
  /// lightest day, comparison with the 30-day average, and the top apps.
  void _showWeeklySummary(Map<String, dynamic>? child) {
    final now = DateTime.now();
    final goal = DailyGoal.durationFor(child);
    final report = latestUsageReport(child);
    final week = WeeklySummary.from(
      totals: _weeklyTotals(child, now),
      goal: goal,
      now: now,
      weeklyTopApps: report?['weeklyTopApps'],
      weeklyAppsTotalMs: report?['weeklyAppsTotalMs'],
    );
    final first = week.days.first.key;
    final childName = childNameOf(child, fallback: 'Your child');

    Widget tile(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: grayText, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontFamily: AppFonts.heading,
                color: darkText,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: kTabularFigures,
              ),
            ),
          ],
        ),
      ),
    );

    Widget line(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: grayText, fontSize: 13),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: darkText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    String vsUsual() {
      final percent = week.percentVsUsual;
      if (percent == null) return 'Not enough days yet';
      if (percent == 0) return 'Same as usual';
      return percent > 0 ? '▲ $percent% above usual' : '▼ ${-percent}% below usual';
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              Text(
                'This week',
                style: const TextStyle(
                  fontFamily: AppFonts.heading,
                  color: darkText,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '$childName · ${_dayLabel(first)} to ${_dayLabel(now)}',
                style: const TextStyle(color: grayText, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (week.daysWithData == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No screen time synced this week yet. Ask your child to '
                    'open WellScreen and tap Sync usage now.',
                    style: TextStyle(color: grayText, fontSize: 14),
                  ),
                )
              else ...[
                Row(
                  children: [
                    tile('Total this week', formatDurationLabel(week.total)),
                    const SizedBox(width: 10),
                    tile(
                      'Daily average',
                      formatDurationLabel(week.dailyAverage!),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                line(
                  Icons.flag_outlined,
                  'Days over the ${DailyGoal.label(goal.inMinutes)} goal',
                  '${week.daysOverGoal} of ${week.daysWithData}',
                ),
                if (week.busiest != null)
                  line(
                    Icons.trending_up_rounded,
                    'Busiest day',
                    '${_dayLabel(week.busiest!.key)} · '
                        '${formatDurationLabel(week.busiest!.value)}',
                  ),
                if (week.lightest != null)
                  line(
                    Icons.trending_down_rounded,
                    'Lightest day',
                    '${_dayLabel(week.lightest!.key)} · '
                        '${formatDurationLabel(week.lightest!.value)}',
                  ),
                line(
                  Icons.compare_arrows_rounded,
                  week.usualAverage == null
                      ? 'Compared with usual'
                      : 'Compared with the 30-day average '
                            '(${formatDurationLabel(week.usualAverage!)} a day)',
                  vsUsual(),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Most used apps this week',
                  style: TextStyle(
                    color: darkText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                if (week.topApps.isEmpty)
                  const Text(
                    'Appears after the child\'s phone syncs (open WellScreen '
                    'and tap Sync usage now).',
                    style: TextStyle(color: grayText, fontSize: 13),
                  )
                else
                  for (final app in week.topApps)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  app.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: darkText,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                '${formatDurationLabel(app.duration)} · '
                                '${(app.share * 100).round()}%',
                                style: const TextStyle(
                                  color: grayText,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: app.share.clamp(0.0, 1.0),
                              minHeight: 6,
                              color: AppColors.primary,
                              backgroundColor: AppColors.primaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                const SizedBox(height: 10),
                const Text(
                  'Days with no reading are not counted. WellScreen itself '
                  'is not counted as screen time.',
                  style: TextStyle(color: grayText, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _weeklyTrendSection(Map<String, dynamic>? child) {
    final warningLimit = DailyGoal.durationFor(child);
    const dayLabels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const maxBarHeight = 110.0;

    final now = DateTime.now();
    final totals = _weeklyTotals(child, now);
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
          '${DailyGoal.label(warningLimit.inMinutes)} daily goal',
          style: const TextStyle(color: grayText, fontSize: 12),
        ),
        // The card opens the weekly summary.
        const Icon(Icons.chevron_right_rounded, color: grayText, size: 20),
      ],
    );

    if (!hasData) {
      return BentoCard(
      // Tapping the card opens the weekly summary.
      onTap: () => _showWeeklySummary(child),
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
      // Tapping the card opens the weekly summary.
      onTap: () => _showWeeklySummary(child),
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
