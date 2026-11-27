import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Marks the signed-in guardian as active today (users/{uid}.lastActiveAt),
/// so the admin dashboard can count active guardians per day. Only a
/// timestamp is written - nothing about what the guardian looked at.
///
/// Called when the guardian dashboard opens and when the app comes back to
/// the foreground; writes at most once every [minGap].
class GuardianActivityService {
  GuardianActivityService({
    Future<void> Function(String uid)? write,
    String? Function()? currentUid,
    DateTime Function()? clock,
    this.minGap = const Duration(minutes: 10),
  }) : _write = write ?? _firestoreWrite,
       _currentUid = currentUid ?? _firebaseUid,
       _clock = clock ?? DateTime.now;

  static final GuardianActivityService instance = GuardianActivityService();

  final Future<void> Function(String uid) _write;
  final String? Function() _currentUid;
  final DateTime Function() _clock;
  final Duration minGap;

  String? _lastUid;
  DateTime? _lastWrite;

  static String? _firebaseUid() => FirebaseAuth.instance.currentUser?.uid;

  static Future<void> _firestoreWrite(String uid) {
    return FirebaseFirestore.instance.collection('users').doc(uid).set({
      'lastActiveAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// True when a write was made. Never throws.
  Future<bool> markActive() async {
    final uid = _currentUid();
    if (uid == null) return false;
    final now = _clock();
    final last = _lastWrite;
    if (uid == _lastUid && last != null && now.difference(last) < minGap) {
      return false;
    }
    try {
      await _write(uid);
      _lastUid = uid;
      _lastWrite = now;
      return true;
    } catch (_) {
      return false;
    }
  }
}
