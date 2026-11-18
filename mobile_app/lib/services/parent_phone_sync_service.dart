import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Copies the guardian's VERIFIED mobile number (Firebase Auth
/// user.phoneNumber, set by PhoneVerificationScreen) onto each of their
/// child profiles as `parentPhoneNumber`, so the child's phone knows where
/// to send backup SMS alerts.
///
/// Why: the child cannot read the guardian's private users/{uid} record
/// (Firestore rules), and the verified number was never stored there anyway.
/// The child may read its own child profile, and the rules do NOT let a
/// child write `parentPhoneNumber`, so a child cannot redirect alerts to
/// another number.
class ParentPhoneSyncService {
  ParentPhoneSyncService._();

  static const String field = 'parentPhoneNumber';

  /// The number to store if the profile is out of date, or null if it
  /// already matches. An empty string means "remove the stored number".
  static String? numberToStore({
    required String? verifiedPhone,
    required Object? storedPhone,
  }) {
    final wanted = (verifiedPhone ?? '').trim();
    final current = (storedPhone ?? '').toString().trim();
    return wanted == current ? null : wanted;
  }

  /// Best effort; returns how many child profiles were updated.
  static Future<int> syncToChildProfiles() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    try {
      await user.reload();
      final verified = FirebaseAuth.instance.currentUser?.phoneNumber;

      final profiles = await FirebaseFirestore.instance
          .collection('child_profiles')
          .where('parentId', isEqualTo: user.uid)
          .get();

      var updated = 0;
      for (final doc in profiles.docs) {
        final number = numberToStore(
          verifiedPhone: verified,
          storedPhone: doc.data()[field],
        );
        if (number == null) continue;
        await doc.reference.update({
          field: number.isEmpty ? FieldValue.delete() : number,
        });
        updated++;
      }
      return updated;
    } catch (_) {
      // Never break the dashboard or settings over this.
      return 0;
    }
  }
}
