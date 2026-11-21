import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// What the Register screen needs from Firebase to create an account.
/// The app uses [FirebaseRegistrationBackend]; tests pass a test double so
/// the screen's real registration steps can run without a live Firebase.
abstract class RegistrationBackend {
  /// Creates the sign-in account and returns its user ID (null on failure).
  /// Throws FirebaseAuthException, e.g. "email-already-in-use".
  Future<String?> createAccount(String email, String password);
  Future<void> setDisplayName(String fullName);
  Future<void> saveProfile(String uid, Map<String, dynamic> data);

  /// Removes the just-created account when saving the profile failed.
  Future<void> deleteAccount();
  Future<void> sendVerificationEmail();
}

class FirebaseRegistrationBackend implements RegistrationBackend {
  User? _user;

  @override
  Future<String?> createAccount(String email, String password) async {
    final credential = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);
    _user = credential.user;
    return _user?.uid;
  }

  @override
  Future<void> setDisplayName(String fullName) async =>
      _user?.updateDisplayName(fullName);

  @override
  Future<void> saveProfile(String uid, Map<String, dynamic> data) =>
      FirebaseFirestore.instance.collection('users').doc(uid).set(data);

  @override
  Future<void> deleteAccount() async => _user?.delete();

  @override
  Future<void> sendVerificationEmail() async => _user?.sendEmailVerification();
}
