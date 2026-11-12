import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';
import 'app_time_limit_background_sync.dart';

/// Existing child background time-limit refresh; chat FCM notifications are
/// displayed by Android automatically while the app is backgrounded.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (message.data['type'] != 'app_time_limit_changed') return;

  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final childProfileId = message.data['childProfileId'];
    if (childProfileId == null || childProfileId.isEmpty) return;

    final synchronized = await AppTimeLimitBackgroundSync.refreshForChild(
      childProfileId,
    );
    if (synchronized) {
      await _showBackgroundLimitNotice(message);
    }
  } catch (error) {
    debugPrint('Background FCM app-limit refresh failed: $error');
  }
}

Future<void> _showBackgroundLimitNotice(RemoteMessage message) async {
  final appName = message.data['appName'] ?? 'your app';
  final minutes = int.tryParse(message.data['limitMinutes'] ?? '');
  if (minutes == null || minutes < 1 || minutes > 1440) return;

  final label = minutes % 60 == 0
      ? '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}'
      : minutes < 60
      ? '$minutes minute${minutes == 1 ? '' : 's'}'
      : '${minutes ~/ 60}h ${minutes % 60}m';

  final notifications = FlutterLocalNotificationsPlugin();
  const initialSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await notifications.initialize(settings: initialSettings);

  const android = AndroidNotificationDetails(
    'wellscreen_limit_updates',
    'App time limits',
    channelDescription: 'Quiet notices about daily app allowances',
    importance: Importance.low,
    priority: Priority.low,
    playSound: false,
    enableVibration: false,
  );
  await notifications.show(
    id: 'app_limit_${message.data['packageName'] ?? ''}'.hashCode,
    title: 'App Time Limit Updated',
    body: 'Your daily limit for $appName is now $label.',
    notificationDetails: const NotificationDetails(android: android),
  );
}

class PushNotificationService {
  static const String _channelId = 'wellscreen_alerts';
  static const String _channelName = 'WellScreen Alerts';
  static const String _channelDescription =
      'Real-time alerts about your child\'s device activity.';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _localNotifications.initialize(settings: initSettings);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );
    await _saveTokenToFirestore();
    FirebaseMessaging.instance.onTokenRefresh.listen(
      (_) => _saveTokenToFirestore(),
    );
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  Future<void> _saveTokenToFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      // Best effort, but never silent: a missing token is the #1 reason a
      // push is never delivered, so make the failure visible in the logs.
      debugPrint('WellScreen FCM token registration failed: $error');
    }
  }

  /// Child devices only need their token stored (to receive approve/decline
  /// pushes). No foreground listener or channel, so nothing is shown twice.
  Future<void> registerDeviceToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await _saveTokenToFirestore();
      FirebaseMessaging.instance.onTokenRefresh.listen(
        (_) => _saveTokenToFirestore(),
      );
    } catch (error) {
      debugPrint('WellScreen FCM device registration failed: $error');
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    // A single global chat handler displays chat FCM, avoiding duplicate
    // foreground notifications on the parent device.
    if (message.data['type'] == 'parent_child_chat') return;
    final notification = message.notification;
    if (notification == null) return;
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    await _localNotifications.show(
      id: message.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: const NotificationDetails(android: androidDetails),
    );
  }
}
