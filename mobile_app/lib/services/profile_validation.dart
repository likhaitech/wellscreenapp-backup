import 'password_policy.dart';

/// Checks and messages for Profile Settings (edit profile and change
/// password). Pure so they can be unit tested; the screen shows them.
class ProfileValidation {
  ProfileValidation._();

  static const String nameRequired = 'Full name is required.';
  static const String profileSaved = 'Profile details updated successfully.';
  static const String enterCurrentPassword = 'Enter your current password.';
  static const String passwordsDoNotMatch =
      'New password and confirmation do not match.';
  static const String sameAsCurrent =
      'New password must be different from the current one.';
  static const String passwordChanged = 'Password changed successfully.';

  /// Marker for "the new password breaks the password rules": the screen
  /// shows the password requirements dialog instead of a message.
  static const String weakPassword = 'weak';

  static String? nameError(String fullName) =>
      fullName.trim().isEmpty ? nameRequired : null;

  /// The first problem with a password change, or null when it can be sent.
  static String? passwordChangeError({
    required String current,
    required String newPassword,
    required String confirm,
  }) {
    if (current.isEmpty) return enterCurrentPassword;
    if (!PasswordPolicy.isStrong(newPassword)) return weakPassword;
    if (newPassword != confirm) return passwordsDoNotMatch;
    if (newPassword == current) return sameAsCurrent;
    return null;
  }

  /// Message for a Firebase Auth error code from the password change.
  static String passwordChangeFailure(String code, [String? details]) =>
      switch (code) {
        'wrong-password' ||
        'invalid-credential' => 'Current password is incorrect.',
        'weak-password' => 'New password is too weak.',
        'requires-recent-login' =>
          'Please log out and log back in, then try again.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => 'Failed to change password: ${details ?? code}',
      };
}
