// Test double for Firebase in the Login Account and Reset Password cases.
// It answers like Firebase would and records what the REAL Login screen
// asked it to do.

import 'package:app/services/login_backend.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FakeLoginBackend implements LoginBackend {
  FakeLoginBackend({
    this.accounts = const {},
    this.roles = const {},
  });

  /// email -> password of the accounts that exist.
  final Map<String, String> accounts;

  /// email -> role saved in users/{uid}.
  final Map<String, String> roles;

  String? signedInEmail;
  String? resetSentTo;

  @override
  Future<String?> signIn(String email, String password) async {
    if (!accounts.containsKey(email)) {
      throw FirebaseAuthException(code: 'user-not-found');
    }
    if (accounts[email] != password) {
      throw FirebaseAuthException(code: 'wrong-password');
    }
    signedInEmail = email;
    return 'uid-$email';
  }

  @override
  Future<bool> isAdmin() async => roles[signedInEmail] == 'admin';

  @override
  Future<String> role(String uid) async => roles[signedInEmail] ?? '';

  @override
  Future<void> sendPasswordReset(String email) async => resetSentTo = email;
}
