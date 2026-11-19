import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/wellscreen_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_notifications_screen.dart';
import '../utils/child_name.dart';
import '../services/parent_alert_badge_service.dart';
import '../theme/app_theme.dart';

/// Parent notification center.
///
/// Displays:
/// - Parent-child chat messages
/// - App access requests and decisions
/// - Security and monitoring alerts
/// - Usage alerts
/// - Historical SMS backup attempts
///
/// Chat notifications are stored under:
/// users/{parentUid}/notifications
///
/// Monitoring alerts are stored under:
/// child_profiles/{profileId}/monitoring_alerts
class ParentNotificationsScreen extends StatefulWidget {
  const ParentNotificationsScreen({super.key});

  @override
  State<ParentNotificationsScreen> createState() =>
      _ParentNotificationsScreenState();
}

class _ParentNotificationsScreenState
    extends State<ParentNotificationsScreen> {
  static const Color _primary = AppColors.primary;
  static const Color _pageBackground = AppColors.background;

  final Set<String> _readAlerts = <String>{};

  String? _loadedForUid;

  @override
  void initState() {
    super.initState();

    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid != null) {
      _loadedForUid = uid;
      _loadReadState(uid);
      // Opening Notifications clears the bell's count.
      unawaited(ParentAlertBadgeService.markSeen(uid));
    }
  }

  @override
  void dispose() {
    final uid = _loadedForUid;
    if (uid != null) unawaited(ParentAlertBadgeService.markSeen(uid));
    super.dispose();
  }

  /// Restore local read/unread state for security alerts.
  Future<void> _loadReadState(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final saved =
          prefs.getStringList(
            'parent_notification_read_ids_$uid',
          ) ??
          const <String>[];

      if (!mounted || _loadedForUid != uid) {
        return;
      }

      setState(() {
        _readAlerts
          ..clear()
          ..addAll(saved);
      });
    } catch (error) {
      debugPrint(
        'Could not read local notification state: $error',
      );
    }
  }

  /// Mark a security alert as read.
  ///
  /// Chat notifications use Firestore readAt instead.
  Future<void> _markRead(String uid, String key) async {
    if (_readAlerts.contains(key)) {
      return;
    }

    setState(() {
      _readAlerts.add(key);
    });

    // Mark the canonical parent inbox item as read too, so the existing
    // ChatUnreadBell badge decreases when an alert is opened here.
    final separator = key.indexOf(':');
    if (separator > 0 && !key.contains(':legacy_sms:')) {
      final profileId = key.substring(0, separator);
      final alertId = key.substring(separator + 1);
      if (alertId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('notifications')
              .doc('monitor_${profileId}_$alertId')
              .update({'readAt': FieldValue.serverTimestamp()});
        } catch (error) {
          // Older monitoring alerts may predate the parent inbox.
          debugPrint('Monitoring inbox read sync unavailable: $error');
        }
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final cacheKey =
          'parent_notification_read_ids_$uid';

      final existing =
          prefs.getStringList(cacheKey) ??
          const <String>[];

      await prefs.setStringList(
        cacheKey,
        <String>{...existing, key}.toList(),
      );
    } catch (error) {
      debugPrint(
        'Could not save local notification read state: $error',
      );
    }
  }

  String _formatTime(dynamic value) {
    DateTime? date;

    if (value is Timestamp) {
      date = value.toDate();
    }

    if (value is DateTime) {
      date = value;
    }

    if (value is num && value.toInt() > 0) {
      date = DateTime.fromMillisecondsSinceEpoch(
        value.toInt(),
      );
    }

    if (date == null) {
      return 'Time unavailable';
    }

    final local = date.toLocal();

    String two(int number) =>
        number.toString().padLeft(2, '0');

    return '${local.year}-'
        '${two(local.month)}-'
        '${two(local.day)} '
        '${two(local.hour)}:'
        '${two(local.minute)}';
  }

  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'gps_location_stale':
        return Icons.location_off_outlined;

      case 'no_recent_connection':
      case 'monitoring_permission_disabled':
        return Icons.shield_outlined;

      case 'usage_warning_threshold':
      case 'usage_high_threshold':
      case 'unhealthy_usage_pattern':
      case 'screen_time_limit_exceeded':
        return Icons.hourglass_bottom_rounded;

      case 'late_night_usage':
        return Icons.bedtime_outlined;

      case 'repeated_restricted_app_access':
        return Icons.block_rounded;

      case 'restricted_content_attempt':
        return Icons.public_off_rounded;

      default:
        return Icons.notifications_outlined;
    }
  }

  // The child app stores healthy/warning/unhealthy. "Danger" is a parent-side
  // presentation label for the existing unhealthy classification; it does not
  // change the pattern-detection thresholds or logic.
  String? _severityForAlertKind(String kind) {
    switch (kind) {
      case 'usage_warning_threshold':
        return 'Warning';
      case 'usage_high_threshold':
      case 'unhealthy_usage_pattern':
        return 'Danger';
      default:
        return null;
    }
  }

  Widget _severityBadge(String status) {
    Color foreground = AppColors.textSecondary;
    Color background = AppColors.border;
    if (status == 'Healthy') {
      foreground = AppColors.success;
      background = AppColors.successBg;
    } else if (status == 'Warning') {
      foreground = const Color(0xFF9A6400);
      background = const Color(0xFFFFF1D4);
    } else if (status == 'Danger') {
      foreground = const Color(0xFFB5252C);
      background = const Color(0xFFFDE6E8);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  /// Live last-synced status, not a manufactured historical event.
  /// Warning/Danger incident history continues to come from monitoring_alerts.
  Widget _usagePatternStatusCard(Map<String, dynamic> child) {
    final rawReport = child['latestUsageReport'];
    final report = rawReport is Map ? rawReport : null;
    final rawStatus = (report?['patternStatus'] ?? '').toString().toLowerCase();

    String status = report == null ? 'Awaiting data' : 'Unavailable';
    IconData icon = Icons.help_outline_rounded;
    Color iconColor = AppColors.textSecondary;
    if (rawStatus == 'healthy') {
      status = 'Healthy';
      icon = Icons.verified_user_outlined;
      iconColor = AppColors.success;
    } else if (rawStatus == 'warning') {
      status = 'Warning';
      icon = Icons.warning_amber_rounded;
      iconColor = const Color(0xFF9A6400);
    } else if (rawStatus == 'unhealthy') {
      status = 'Danger';
      icon = Icons.error_outline_rounded;
      iconColor = const Color(0xFFB5252C);
    }

    final syncedAt = child['usageReportUpdatedAt'];
    final syncLabel = syncedAt == null
        ? 'Last sync time unavailable'
        : 'Last synced: ${_formatTime(syncedAt)}';
    final flagged = report?['unhealthyAppCount'];
    final count = flagged is num ? flagged.toInt() : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: AppColors.background,
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Latest Usage Pattern',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                _severityBadge(status),
                const SizedBox(height: 6),
                Text(
                  syncLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$count app${count == 1 ? '' : 's'} flagged',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _deliveryLabel(
    String channel,
    String status,
  ) {
    if (status.isEmpty || status == 'pending') {
      return '$channel: pending';
    }

    if (channel == 'SMS') {
      switch (status) {
        case 'accepted':
          return 'SMS: submitted to provider '
              '(delivery unconfirmed)';

        case 'backup_not_needed':
          return 'SMS: backup not needed';

        case 'not_enabled':
          return 'SMS: disabled';

        case 'missing_verified_consent_or_phone':
          return 'SMS: number/consent not verified';

        case 'provider_not_configured':
          return 'SMS: provider not configured';

        case 'failed':
          return 'SMS: request failed';
      }
    }

    if (channel == 'Push' && status == 'sent') {
      return 'Push: submitted (delivery unconfirmed)';
    }

    if (status == 'not_requested') return '$channel: Not requested';
    return '$channel: $status';
  }

  /// Display one security, usage, or SMS alert.
  Widget _alertTile({
    required String parentUid,
    required String key,
    required String title,
    required String body,
    required String kind,
    required dynamic occurredAt,
    required String pushStatus,
    required String smsStatus,
    bool legacySms = false,
  }) {
    final read = _readAlerts.contains(key);

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(
          color: AppColors.border,
        ),
      ),
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded) {
            _markRead(parentUid, key);
          }
        },
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryLight,
          child: Icon(
            _iconForKind(kind),
            color: _primary,
            size: 22,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: read
                      ? FontWeight.w700
                      : FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (!read)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.circle,
                  color: _primary,
                  size: 9,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _formatTime(occurredAt),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          18,
          0,
          18,
          16,
        ),
        expandedCrossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          if (_severityForAlertKind(kind) != null) ...[
            _severityBadge(_severityForAlertKind(kind)!),
            const SizedBox(height: 8),
          ],
          Text(
            body,
            style: const TextStyle(height: 1.45),
          ),
          const SizedBox(height: 10),
          Text(
            legacySms
                ? 'Legacy child-device SMS log'
                : _deliveryLabel('Push', pushStatus),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            legacySms
                ? 'SMS: $smsStatus'
                : _deliveryLabel('SMS', smsStatus),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  /// Monitoring and historical alerts for one paired child.
  Widget _devicePanel({
    required String uid,
    required String profileId,
    required Map<String, dynamic> child,
  }) {
    final name =
        (child['deviceName'] ??
                childNameOf(child, fallback: 'Child device'))
            .toString();

    final oldSms = child['smsAlertLog'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: 20,
            bottom: 10,
          ),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        _usagePatternStatusCard(child),
        const SizedBox(height: 10),
        StreamBuilder<
            QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('child_profiles')
              .doc(profileId)
              .collection('monitoring_alerts')
              .orderBy(
                'createdAt',
                descending: true,
              )
              .limit(100)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              debugPrint(
                'Monitoring history error for '
                '$profileId: ${snapshot.error}',
              );

              return const Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 12,
                ),
                child: Text(
                  'Cannot load security history. '
                  'Check the monitoring_alerts '
                  'Firestore read rule and the '
                  'signed-in parent account.',
                  style: TextStyle(
                    color: Colors.redAccent,
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 16,
                ),
                child: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final alerts = snapshot.data!.docs;

            if (alerts.isEmpty &&
                (oldSms is! List || oldSms.isEmpty)) {
              return const Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 14,
                ),
                child: Text(
                  'No historical monitoring alerts '
                  'for this device yet.',
                ),
              );
            }

            final newAlerts = alerts
                .where(
                  (doc) => !_readAlerts.contains(
                    '$profileId:${doc.id}',
                  ),
                )
                .toList();

            final historyAlerts = alerts
                .where(
                  (doc) => _readAlerts.contains(
                    '$profileId:${doc.id}',
                  ),
                )
                .toList();

            Widget buildGroup(
              String title,
              List<
                  QueryDocumentSnapshot<
                    Map<String, dynamic>
                  >> rows,
            ) {
              if (rows.isEmpty) {
                return const SizedBox.shrink();
              }

              return Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      2,
                      10,
                      2,
                      8,
                    ),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  for (final doc in rows)
                    _alertTile(
                      parentUid: uid,
                      key: '$profileId:${doc.id}',
                      title:
                          (doc.data()['title'] ??
                                  'WellScreen alert')
                              .toString(),
                      body:
                          (doc.data()['body'] ?? '')
                              .toString(),
                      kind:
                          (doc.data()['kind'] ?? '')
                              .toString(),
                      occurredAt:
                          doc.data()['createdAt'] ??
                          doc.data()['occurredAt'],
                      pushStatus:
                          (doc.data()['pushStatus'] ??
                                  '')
                              .toString(),
                      smsStatus:
                          (doc.data()['smsStatus'] ??
                                  '')
                              .toString(),
                    ),
                ],
              );
            }

            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                buildGroup('New', newAlerts),
                buildGroup(
                  'Previously viewed',
                  historyAlerts,
                ),

                if (oldSms is List &&
                    oldSms.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      2,
                      14,
                      2,
                      8,
                    ),
                    child: Text(
                      'Earlier SMS attempts '
                      '(child device)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  for (
                    var i = oldSms.length - 1;
                    i >= 0;
                    i--
                  )
                    if (oldSms[i] is Map)
                      _alertTile(
                        parentUid: uid,
                        key:
                            '$profileId:legacy_sms:$i',
                        title:
                            'SMS backup attempt',
                        body:
                            'A child-device SMS '
                            'alert was attempted. '
                            'Check the delivery '
                            'status below.',
                        kind: 'sms_backup',
                        occurredAt:
                            (oldSms[i] as Map)[
                              'timestampMs'
                            ],
                        pushStatus: '',
                        smsStatus:
                            ((oldSms[i] as Map)[
                                      'outcome'
                                    ] ??
                                    'unknown')
                                .toString(),
                        legacySms: true,
                      ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// Load the paired child's security histories.
  ///
  /// This widget is independent from ChatNotificationsPanel.
  /// A monitoring error must not hide the family chat inbox.
  Widget _monitoringHistory(String parentUid) {
    return StreamBuilder<
        QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('child_profiles')
          .where(
            'parentId',
            isEqualTo: parentUid,
          )
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            'Could not load paired children: '
            '${snapshot.error}',
          );

          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Could not load paired child '
              'devices for security history.',
              style: TextStyle(
                color: Colors.redAccent,
              ),
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final children = snapshot.data!.docs;

        if (children.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No paired child devices. '
              'Pair a device to see its alerts.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            for (final child in children)
              _devicePanel(
                uid: parentUid,
                profileId: child.id,
                child: child.data(),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final user =
        FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: const WellScreenAppBar.subPage(title: 'Notifications'),
      body: user == null
          ? const Center(
              child: Text(
                'Sign in to view notifications.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                18,
                12,
                18,
                28,
              ),
              children: [
                // Parent-child messages and app requests.
                //
                // This stays visible independently of
                // monitoring alerts and their Firestore rules.
                const ChatNotificationsPanel(hideMonitoringAlerts: true),

                const SizedBox(height: 14),

                // Existing security and SMS alerts.
                const Padding(
                  padding: EdgeInsets.only(
                    top: 6,
                    bottom: 6,
                  ),
                  child: Text(
                    'Security, usage, '
                    'and SMS alert history',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),

                _monitoringHistory(user.uid),
              ],
            ),
    );
  }
}
