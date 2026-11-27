import 'package:flutter/foundation.dart' show kDebugMode;

/// Plain-language message for a Firebase phone-verification error code.
String phoneAuthErrorMessage(String code, [String? message]) {
  switch (code) {
    case 'invalid-phone-number':
      return 'Firebase rejected the mobile number. Check the +63 format.';
    case 'invalid-verification-code':
      return 'The SMS verification code is incorrect. Please try again.';
    case 'session-expired':
    case 'invalid-verification-id':
      return 'This verification code has expired. Request a new code.';
    case 'credential-already-in-use':
    case 'account-exists-with-different-credential':
      return 'This phone is linked to another Firebase account. Use a different number.';
    case 'requires-recent-login':
      return 'For security, sign out and sign back in with your password, then retry.';
    case 'too-many-requests':
    case 'quota-exceeded':
      return 'Firebase temporarily limited SMS requests. Please try again later.';
    case 'operation-not-allowed':
      return 'Phone Authentication is not enabled for this Firebase project.';
    case 'app-not-authorized':
    case 'invalid-app-credential':
    case 'captcha-check-failed':
      return 'Android app verification failed. Check Firebase SHA fingerprints and Play services.';
    case 'network-request-failed':
      return 'Network unavailable. SMS verification requires internet access.';
    default:
      final details = message?.trim() ?? '';
      if (kDebugMode && details.isNotEmpty) {
        return 'Phone verification failed ($code): $details';
      }
      return 'Phone verification failed ($code). Check debug logs.';
  }
}
