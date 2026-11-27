import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Child side: shows a live "time left" countdown in the notification shade
/// while approved extra time is running, so the child can see it from
/// inside the app they were given time for (not only on WellScreen's Home).
///
/// Uses Android's built-in countdown chronometer, so the notification ticks
/// down on its own and disappears when the time is up - nothing has to keep
/// running in WellScreen for it to stay accurate.
class GrantCountdownNotifier {
  GrantCountdownNotifier._();
  static final GrantCountdownNotifier instance = GrantCountdownNotifier._();

  static const String _channelId = 'wellscreen_time_left';
  static const String _channelName = 'Time left';
  static const String _channelDescription =
      'Countdown for extra time your guardian approved';

  /// Notification id for Emergency Access; app grants use their own ids.
  static const int emergencyId = 74001;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  final Map<int, int> _shownUntil = <int, int>{};

  static int idForPackage(String packageName) =>
      74100 + (packageName.hashCode & 0x7ff);

  Future<void> _ensureReady() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.low,
          ),
        );
    _ready = true;
  }

  /// Shows (or keeps) the countdown until [until]. Calling again with the
  /// same expiry does nothing, so it is safe to call on every update.
  Future<void> show({
    required int id,
    required String title,
    required DateTime until,
  }) async {
    final untilMs = until.millisecondsSinceEpoch;
    final remainingMs = untilMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return;
    if (_shownUntil[id] == untilMs) return;
    try {
      await _ensureReady();
      final hh = until.hour.toString().padLeft(2, '0');
      final mm = until.minute.toString().padLeft(2, '0');
      await _plugin.show(
        id: id,
        title: title,
        body: 'Ends at $hh:$mm - harmful websites stay blocked',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            onlyAlertOnce: true,
            showWhen: true,
            when: untilMs,
            usesChronometer: true,
            chronometerCountDown: true,
            timeoutAfter: remainingMs,
          ),
        ),
      );
      _shownUntil[id] = untilMs;
    } catch (error) {
      debugPrint('Time-left notification failed: $error');
    }
  }
}

/// "14:05 left" / "1:02:30 left" for the on-screen countdown.
String formatTimeLeft(Duration left) {
  if (left.isNegative) return '0:00';
  final h = left.inHours;
  final m = left.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
  final s = left.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
