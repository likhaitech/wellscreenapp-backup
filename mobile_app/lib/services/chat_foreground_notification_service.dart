import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Child-only foreground chat notices. Parent's existing PushNotificationService
/// already presents foreground FCM notification payloads; starting this only
/// from ChildHomeScreen avoids double notifications on the parent device.
class ChatForegroundNotificationService {
  ChatForegroundNotificationService._();
  static final ChatForegroundNotificationService instance =
      ChatForegroundNotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<RemoteMessage>? _subscription;

  Future<void> start() async {
    if (_subscription != null) return;
    try {
      await _local.initialize(settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      _subscription = FirebaseMessaging.onMessage.listen((message) {
        if (message.data['type'] != 'parent_child_chat' || message.notification == null) {
          return;
        }
        unawaited(_local.show(
          id: (message.data['eventId'] ?? message.messageId ?? '').hashCode,
          title: message.notification?.title ?? 'WellScreen Chat',
          body: message.notification?.body ?? 'New message',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'wellscreen_chat', 'WellScreen Chat',
              channelDescription: 'Parent and child messages and access requests',
              importance: Importance.high, priority: Priority.high,
            ),
          ),
        ));
      });
    } catch (error) {
      debugPrint('Child chat notification initialization failed: $error');
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
