import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/login_screen.dart';

/// The "Log out?" confirmation the child sees. Returns true when the user
/// taps Logout.
Future<bool> confirmLogoutDialog(
  BuildContext context, {
  Color confirmColor = const Color(0xFFE5675C),
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text(
        'You will need to sign in again to use WellScreen on this device.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: confirmColor),
          child: const Text('Logout'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Signs out and opens the Login screen, clearing every screen behind it.
/// [signOut] defaults to Firebase; tests pass a test double.
Future<void> signOutToLogin(
  BuildContext context, {
  Future<void> Function()? signOut,
}) async {
  await (signOut ?? FirebaseAuth.instance.signOut)();
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}
