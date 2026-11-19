import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_notifications_service.dart';

/// Count for the guardian's notification bell: monitoring alerts on any of
/// their children's profiles (repeated attempts, Usage Access off, fake GPS,
/// limits...) created since the guardian last opened Notifications, plus
/// any unread inbox items. Monitoring alerts live in
/// child_profiles/{id}/monitoring_alerts, which the inbox-only bell never
/// counted.
class ParentAlertBadgeService {
  ParentAlertBadgeService._();

  static final StreamController<void> _seenChanged =
      StreamController<void>.broadcast();

  static String _key(String uid) => 'wellscreen_parent_alerts_seen_ms_$uid';

  /// Call when the Notifications screen is opened and closed.
  static Future<void> markSeen(String uid) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(uid), DateTime.now().millisecondsSinceEpoch);
    _seenChanged.add(null);
  }

  /// Alerts newer than [seenMs]. Never seen: the last 24 hours count, so a
  /// long alert history doesn't show up as dozens of new alerts.
  static int countUnseen(
    Iterable<int> alertCreatedMs,
    int? seenMs,
    int nowMs,
  ) {
    final since = seenMs ?? nowMs - const Duration(hours: 24).inMilliseconds;
    return alertCreatedMs.where((ms) => ms > since).length;
  }

  static Stream<int> unseenCount(String uid) {
    if (uid.isEmpty) return Stream.value(0);
    late StreamController<int> controller;
    final subscriptions = <StreamSubscription<dynamic>>[];
    final perProfile = <String, StreamSubscription<dynamic>>{};
    final alertTimes = <String, List<int>>{};
    var inboxUnread = 0;

    Future<void> emit() async {
      final prefs = await SharedPreferences.getInstance();
      final seen = prefs.getInt(_key(uid));
      final count = countUnseen(
        alertTimes.values.expand((times) => times),
        seen,
        DateTime.now().millisecondsSinceEpoch,
      );
      if (!controller.isClosed) controller.add(count + inboxUnread);
    }

    controller = StreamController<int>(
      onListen: () {
        subscriptions.add(
          FirebaseFirestore.instance
              .collection('child_profiles')
              .where('parentId', isEqualTo: uid)
              .snapshots()
              .listen((profiles) {
                final ids = profiles.docs.map((doc) => doc.id).toSet();
                for (final gone in perProfile.keys
                    .where((id) => !ids.contains(id))
                    .toList()) {
                  unawaited(perProfile.remove(gone)?.cancel());
                  alertTimes.remove(gone);
                }
                for (final id in ids.where((id) => !perProfile.containsKey(id))) {
                  perProfile[id] = FirebaseFirestore.instance
                      .collection('child_profiles')
                      .doc(id)
                      .collection('monitoring_alerts')
                      .orderBy('createdAt', descending: true)
                      .limit(50)
                      .snapshots()
                      .listen((alerts) {
                        alertTimes[id] = [
                          for (final doc in alerts.docs)
                            if (doc.data()['createdAt'] is Timestamp)
                              (doc.data()['createdAt'] as Timestamp)
                                  .millisecondsSinceEpoch,
                        ];
                        unawaited(emit());
                      }, onError: (_) {});
                }
                unawaited(emit());
              }, onError: (_) {}),
        );
        subscriptions.add(
          ChatNotificationsService.instance.unreadStream(uid).listen((inbox) {
            // Monitoring items copied into the inbox are already counted
            // above; chat has its own dot on the Chat tab.
            inboxUnread = inbox.docs.where((doc) {
              final type = doc.data()['type'];
              return type != 'monitoring_alert' && type != 'parent_child_chat';
            }).length;
            unawaited(emit());
          }, onError: (_) {}),
        );
        subscriptions.add(_seenChanged.stream.listen((_) => unawaited(emit())));
      },
      onCancel: () async {
        for (final subscription in [...subscriptions, ...perProfile.values]) {
          await subscription.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }
}

/// The guardian's notification bell with the unseen-alert count.
class ParentAlertsBell extends StatefulWidget {
  const ParentAlertsBell({
    super.key,
    required this.uid,
    this.color = Colors.white,
    this.size = 29,
  });

  final String uid;
  final Color color;
  final double size;

  @override
  State<ParentAlertsBell> createState() => _ParentAlertsBellState();
}

class _ParentAlertsBellState extends State<ParentAlertsBell> {
  late Stream<int> _count = ParentAlertBadgeService.unseenCount(widget.uid);

  @override
  void didUpdateWidget(ParentAlertsBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _count = ParentAlertBadgeService.unseenCount(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _count,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              color: widget.color,
              size: widget.size,
            ),
            if (count > 0)
              Positioned(
                right: -8,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
