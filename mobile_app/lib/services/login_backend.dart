import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// What the Login screen needs from Firebase. The app uses
/// [FirebaseLoginBackend]; tests pass a test double so the screen's real
/// login and password-reset steps can run without a live Firebase.
abstract class LoginBackend {
  /// Signs in and returns the user ID (null on failure).
  /// Throws FirebaseAuthException, e.g. "user-disabled".
  Future<String?> signIn(String email, String password);

  /// True when the signed-in account is an admin (custom claims).
  Future<bool> isAdmin();

  /// The role saved in users/{uid} ('parent', 'child', ...).
  Future<String> role(String uid);

  Future<void> sendPasswordReset(String email);
}

class FirebaseLoginBackend implements LoginBackend {
  User? _user;

  @override
  Future<String?> signIn(String email, String password) async {
    final credential = await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: email, password: password);
    _user = credential.user;
    return _user?.uid;
  }

  @override
  Future<bool> isAdmin() async {
    // Refresh the ID token so the latest custom claims are loaded.
    final tokenResult = await _user?.getIdTokenResult(true);
    final claims = tokenResult?.claims ?? <String, dynamic>{};
    return claims['admin'] == true || claims['role'] == 'admin';
  }

  @override
  Future<String> role(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data() ?? <String, dynamic>{};
    return (data['role'] ?? '').toString().toLowerCase();
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      FirebaseAuth.instance.sendPasswordResetEmail(email: email);
}
