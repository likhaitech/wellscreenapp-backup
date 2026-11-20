import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'alert_notification_client.dart';
import 'grant_countdown_notifier.dart';

/// Child-requests-temporary-bypass Emergency Access workflow.
///
/// The parent-side on/off switch for this feature already existed before
/// this file (see rule_settings_screen.dart's `emergencyAccess` and
/// admin_settings_screen.dart's `emergencyAccessEnabled`) but nothing acted
/// on it - it was a setting that saved to Firestore and did nothing else.
/// This is the actual workflow: a child on a restricted app can ask for a
/// temporary lift, the parent gets notified the same way a restricted-app
/// block does (AlertNotificationClient, same as SMS/push alerts) and can
/// approve or deny it from their dashboard, and an approval is honored on
/// the child device by WellScreenAccessibilityService.kt checking a
/// granted-until timestamp before blocking anything - not just a Firestore
/// flag that only the Flutter UI happens to read.
///
/// State lives on `child_profiles/{childProfileId}.emergencyAccess`:
///   status: 'none' | 'requested' | 'approved' | 'denied'
///   reason: guardian-readable text the child typed, may be empty
///   requestedAt / respondedAt: server timestamps
///   grantedUntil: server timestamp the bypass expires at (approved only)
class EmergencyAccessService {
  static const String _grantedUntilKey = 'emergency_access_granted_until_ms';
  static const String _durationKey = 'emergency_access_duration_ms';

  static const Duration defaultGrantDuration = Duration(minutes: 30);

  /// Child side: submits a request and best-effort notifies the parent.
  /// The Firestore write is what actually creates the pending request -
  /// the push notification is a convenience on top, same tradeoff
  /// AlertNotificationClient already documents for every other alert type.
 Future<void> requestAccess({
  required String childProfileId,
  required String parentId,
  String reason = '',
}) async {
  const requestCooldown = Duration(minutes: 5);
  const dailyRequestLimit = 5;

  if (childProfileId.isEmpty) {
    throw StateError('Not paired with a parent yet.');
  }

  final trimmedReason = reason.trim();
  final firestore = FirebaseFirestore.instance;

  final childRef = firestore
      .collection('child_profiles')
      .doc(childProfileId);

  final rejectionMessage = await firestore.runTransaction<String?>(
    (transaction) async {
      final snapshot = await transaction.get(childRef);

      if (!snapshot.exists) {
        return 'Child profile not found.';
      }

      final raw = snapshot.data()?['emergencyAccess'];

      final emergencyAccess = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      final now = DateTime.now();

      final previousTimestamp = emergencyAccess['requestedAt'];

      final lastRequestedAt = previousTimestamp is Timestamp
          ? previousTimestamp.toDate().toLocal()
          : null;

      final storedCount = emergencyAccess['dailyRequestCount'];

      final isSameDay = lastRequestedAt != null &&
          lastRequestedAt.year == now.year &&
          lastRequestedAt.month == now.month &&
          lastRequestedAt.day == now.day;

      final dailyCount = isSameDay
          ? (storedCount is int && storedCount > 0
              ? storedCount
              : 1)
          : 0;

      // Enforce the daily request limit.
      if (dailyCount >= dailyRequestLimit) {
        return 'Daily emergency access limit reached. '
            'You can request again tomorrow.';
      }

      // Enforce the cooldown between requests.
      if (lastRequestedAt != null) {
        if (now.isBefore(lastRequestedAt)) {
          return 'Please check your device date and time.';
        }

        final elapsed = now.difference(lastRequestedAt);

        if (elapsed < requestCooldown) {
          final remaining = requestCooldown - elapsed;

          final minutesRemaining =
              (remaining.inMilliseconds /
                      Duration.millisecondsPerMinute)
                  .ceil();

          return 'Please wait $minutesRemaining minute(s) '
              'before sending another emergency access request.';
        }
      }

      // Store the accepted request and updated counter together.
      transaction.set(
        childRef,
        {
          'emergencyAccess': {
            'status': 'requested',
            'reason': trimmedReason,
            'requestedAt': FieldValue.serverTimestamp(),
            'respondedAt': null,
            'grantedUntil': null,
            'dailyRequestCount': dailyCount + 1,
          },
        },
        SetOptions(merge: true),
      );

      return null;
    },
  );

  if (rejectionMessage != null) {
    throw StateError(rejectionMessage);
  }

  if (parentId.isEmpty) return;

  try {
    await AlertNotificationClient().notifyParent(
      parentUid: parentId,
      title: 'Emergency access requested',
      body: trimmedReason.isEmpty
          ? 'Your child is requesting temporary emergency access.'
          : 'Your child is requesting temporary emergency access: '
                '$trimmedReason',
      alertType: 'emergency_access_request',
      childProfileId: childProfileId,
    );
  } catch (_) {
    // The request is already saved in Firestore.
    // Notification remains best-effort.
  }
}
  /// Parent side: approves (for [duration], default 30 minutes) or denies
  /// the currently pending request for this child.
  Future<void> respondToRequest({
    required String childProfileId,
    required bool approve,
    Duration duration = defaultGrantDuration,
  }) async {
    if (childProfileId.isEmpty) return;

    final grantedUntil = approve
        ? Timestamp.fromDate(DateTime.now().add(duration))
        : null;

    await FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .set({
          'emergencyAccess': {
            'status': approve ? 'approved' : 'denied',
            'respondedAt': FieldValue.serverTimestamp(),
            'grantedUntil': grantedUntil,
            // Lets the child phone end access on time even if its clock
            // is changed (see GrantClock.kt).
            'durationMinutes': approve ? duration.inMinutes : null,
          },
        }, SetOptions(merge: true));
  }

  /// Child side: live status for this child's own profile, and - as a
  /// side effect of each update - keeps the native side's local bypass
  /// flag in sync with whatever `grantedUntil` Firestore currently has.
  /// Mirrors AppRulesService.watchRulesForParent's "stream from Firestore,
  /// mirror into SharedPreferences for the native service" pattern.
  Stream<Map<String, dynamic>> watchStatus(String childProfileId) {
    if (childProfileId.isEmpty) return Stream.value(const {});

    return FirebaseFirestore.instance
        .collection('child_profiles')
        .doc(childProfileId)
        .snapshots()
        .asyncMap((snapshot) async {
          final raw = snapshot.data()?['emergencyAccess'];
          final status = raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};

          final grantedUntil = status['grantedUntil'];
          final durationMinutes = status['durationMinutes'];
          if (status['status'] == 'approved' && grantedUntil is Timestamp) {
            await GrantCountdownNotifier.instance.show(
              id: GrantCountdownNotifier.emergencyId,
              title: 'Emergency Access - apps unlocked',
              until: grantedUntil.toDate(),
            );
          }
          await syncGrantedUntilLocally(
            grantedUntil is Timestamp ? grantedUntil.toDate() : null,
            durationMinutes: durationMinutes is num
                ? durationMinutes.toInt()
                : null,
          );

          return status;
        });
  }

  /// Writes (or clears) the local bypass-expiry flag that
  /// WellScreenAccessibilityService.kt reads before blocking a restricted
  /// app. Public (not just called from [watchStatus]) so a caller that
  /// already has the child profile data in hand (e.g. right after
  /// [respondToRequest] on a device that's somehow also the child device)
  /// can sync it without waiting for the next stream tick.
  Future<void> syncGrantedUntilLocally(
    DateTime? grantedUntil, {
    int? durationMinutes,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (grantedUntil == null || grantedUntil.isBefore(DateTime.now())) {
      await prefs.remove(_grantedUntilKey);
      await prefs.remove(_durationKey);
      return;
    }

    if (durationMinutes != null && durationMinutes > 0) {
      await prefs.setInt(_durationKey, durationMinutes * 60000);
    } else {
      await prefs.remove(_durationKey);
    }

    // Android native AccessibilityService reads this local key.
    // On Android, shared_preferences stores it as:
    // flutter.emergency_access_granted_until_ms
    await prefs.setInt(
      _grantedUntilKey,
      grantedUntil.millisecondsSinceEpoch,
    );
  }
}
