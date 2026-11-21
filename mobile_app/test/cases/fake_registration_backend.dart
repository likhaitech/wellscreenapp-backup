// Test double for Firebase in the Register Account cases. It records what
// the REAL Register screen asked Firebase to do, so a test can check it.

import 'package:app/services/registration_backend.dart';

class FakeRegistrationBackend implements RegistrationBackend {
  String? createdEmail;
  String? createdPassword;
  String? displayName;
  String? savedUid;
  Map<String, dynamic>? savedProfile;
  bool verificationSent = false;
  bool deleted = false;

  @override
  Future<String?> createAccount(String email, String password) async {
    createdEmail = email;
    createdPassword = password;
    return 'test-uid-001';
  }

  @override
  Future<void> setDisplayName(String fullName) async => displayName = fullName;

  @override
  Future<void> saveProfile(String uid, Map<String, dynamic> data) async {
    savedUid = uid;
    savedProfile = data;
  }

  @override
  Future<void> deleteAccount() async => deleted = true;

  @override
  Future<void> sendVerificationEmail() async => verificationSent = true;
}
