import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Registers the signed-in child for parent-created app limit FCM notices.
/// The deployed Cloud Function is responsible for sending the push;
/// local Android code is responsible for the five-minute usage reminder.
class AppTimeLimitNotificationService {
  AppTimeLimitNotificationService._();

  static final AppTimeLimitNotificationService instance =
      AppTimeLimitNotificationService._();

  static const MethodChannel _channel = MethodChannel(
    'wellscreen/app_limit_notifications',
  );

  String? _childUid;
  String? _childProfileId;
  StreamSubscription<String>? _tokenChanges;
  StreamSubscription<RemoteMessage>? _foregroundMessages;
  Future<void>? _registering;

  Future<void> startForChild(String childProfileId) async {
    if (childProfileId.trim().isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Avoid rewriting an unchanged token every time the child returns from
    // Android Settings or another application.
    if (_childUid == user.uid &&
        _childProfileId == childProfileId &&
        _foregroundMessages != null &&
        _tokenChanges != null) {
      return;
    }

    // Protect against multiple builds/resumes registering simultaneously.
    final inFlight = _registering;
    if (inFlight != null) return inFlight;
    _registering = _register(user.uid, childProfileId);
    try {
      await _registering;
    } finally {
      _registering = null;
    }
  }

  Future<void> _register(String uid, String childProfileId) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    _childUid = uid;
    _childProfileId = childProfileId;

    try {
      // This channel is deliberately LOW importance: no heads-up popup.
      await _channel.invokeMethod<bool>('ensureChannel');

      // Android 13+ requires POST_NOTIFICATIONS runtime permission.
      // Denying this permission must not interfere with enforcement.
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: false,
      );

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        await _storeToken(uid, token);
      }
      // A logout may have happened while FirebaseMessaging awaited a token.
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          _childUid != uid ||
          _childProfileId != childProfileId) {
        return;
      }

      // Child receives the push while the Flutter app is on-screen.
      // When it's backgrounded, Android automatically displays the FCM
      // notification payload using the quiet channel created above.
      _foregroundMessages ??= FirebaseMessaging.onMessage.listen((message) {
        unawaited(_showForegroundLimitMessage(message));
      });
      _tokenChanges ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) {
          if (FirebaseAuth.instance.currentUser?.uid == _childUid &&
              _childUid != null &&
              token.isNotEmpty) {
            unawaited(_storeToken(_childUid!, token));
          }
        },
        onError: (Object error) =>
            debugPrint('FCM token refresh failed for child: $error'),
      );
    } catch (error) {
      debugPrint('Time-limit push registration failed: $error');
      // No rethrow: the child app and native limits must still work.
    }
  }

  Future<void> _storeToken(String uid, String token) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({
            'limitNotificationToken': token,
            'limitNotificationTokenUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('Could not save child time-limit FCM token: $error');
    }
  }

  Future<void> _showForegroundLimitMessage(RemoteMessage message) async {
    if (message.data['type'] != 'app_time_limit_changed') return;
    if (FirebaseAuth.instance.currentUser?.uid != _childUid ||
        message.data['childProfileId'] != _childProfileId) {
      return;
    }

    final packageName = message.data['packageName'] ?? '';
    if (packageName.isEmpty) return;
    final appName = message.data['appName'] ?? packageName;
    final minutes = int.tryParse(message.data['limitMinutes'] ?? '');
    if (minutes == null || minutes < 1) return;
    final label = minutes % 60 == 0
        ? '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}'
        : minutes < 60
        ? '$minutes minute${minutes == 1 ? '' : 's'}'
        : '${minutes ~/ 60}h ${minutes % 60}m';
    final title = message.notification?.title ?? 'New App Time Limit';
    final body =
        message.notification?.body ??
        'Your guardian set a daily limit of $label for $appName.';

    try {
      await _channel.invokeMethod<bool>('showAssignedLimit', {
        'packageName': packageName,
        'title': title,
        'body': body,
      });
    } on PlatformException catch (error) {
      debugPrint('Could not show app limit notification: $error');
    } on MissingPluginException catch (error) {
      debugPrint('Native app limit notification bridge is unavailable: $error');
    }
  }

  /// Must run BEFORE FirebaseAuth.signOut(), including Settings → Logout.
  /// This prevents a subsequent parent login on the same emulator from
  /// receiving notifications addressed to the previous child account.
  Future<void> stopForSignOut() async {
    final uid = _childUid;
    _childUid = null;
    _childProfileId = null;
    await _foregroundMessages?.cancel();
    _foregroundMessages = null;
    await _tokenChanges?.cancel();
    _tokenChanges = null;

    if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
            'limitNotificationToken': FieldValue.delete(),
            'limitNotificationTokenUpdatedAt': FieldValue.delete(),
          })
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('Could not clear saved child FCM token: $error');
    }
    try {
      // Invalidate this device token even if remote deletion was offline.
      // Existing push functionality should re-register on the next login.
      await FirebaseMessaging.instance.deleteToken();
    } catch (error) {
      debugPrint('Could not invalidate child FCM token on sign-out: $error');
    }
  }
}
