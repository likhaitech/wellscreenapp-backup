import 'package:firebase_auth/firebase_auth.dart';

/// The message the Register screen shows when Firebase refuses to create
/// an account. Known codes get WellScreen's own wording; anything else
/// falls back to Firebase's message.
String registerErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'email-already-in-use':
      return 'This email is already in use. Log in instead, or use a '
          'different email.';
    case 'invalid-email':
      return 'Invalid email address.';
    case 'weak-password':
      return 'Password is too weak.';
    case 'network-request-failed':
      return 'Network error. Please check your internet connection.';
    default:
      return e.message ?? 'Registration failed.';
  }
}
