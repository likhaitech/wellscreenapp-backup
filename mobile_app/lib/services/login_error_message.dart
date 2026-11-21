/// The message the Login screen shows for a Firebase sign-in error code.
///
/// Note: with Firebase's email enumeration protection (on by default for
/// new projects), a wrong password and an unknown email both come back as
/// "invalid-credential", so the user sees "Invalid email or password." -
/// Firebase does not reveal which emails have accounts.
String loginErrorMessage(String code) {
  switch (code) {
    case 'user-not-found':
      return 'No account found with this email.';
    case 'wrong-password':
      return 'Incorrect password.';
    case 'invalid-email':
      return 'Invalid email address.';
    case 'invalid-credential':
      return 'Invalid email or password.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'network-request-failed':
      return 'Network error. Please check your internet connection.';
    default:
      return 'Login failed. Please try again.';
  }
}
