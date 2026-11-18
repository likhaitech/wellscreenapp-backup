import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Asks the user to open the verification link. Returns true once the
/// email is verified, false if they cancel.
///
/// [resend] sends a new link; [checkVerified] reloads the account and
/// reports whether the link was opened. Both are plain callbacks so the
/// dialog can be tested without Firebase.
Future<bool> showVerifyEmailDialog(
  BuildContext context, {
  required String email,
  required Future<void> Function() resend,
  required Future<bool> Function() checkVerified,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _VerifyEmailDialog(
      email: email,
      resend: resend,
      checkVerified: checkVerified,
    ),
  );
  return result ?? false;
}

/// [showVerifyEmailDialog] wired to a signed-in Firebase [user].
Future<bool> showVerifyEmailDialogFor(BuildContext context, User user) {
  return showVerifyEmailDialog(
    context,
    email: user.email ?? 'your email',
    resend: () => user.sendEmailVerification(),
    checkVerified: () async {
      await user.reload();
      final fresh = FirebaseAuth.instance.currentUser;
      return fresh?.emailVerified ?? false;
    },
  );
}

class _VerifyEmailDialog extends StatefulWidget {
  const _VerifyEmailDialog({
    required this.email,
    required this.resend,
    required this.checkVerified,
  });

  final String email;
  final Future<void> Function() resend;
  final Future<bool> Function() checkVerified;

  @override
  State<_VerifyEmailDialog> createState() => _VerifyEmailDialogState();
}

class _VerifyEmailDialogState extends State<_VerifyEmailDialog> {
  bool _busy = false;
  String? _status;
  bool _statusIsError = false;

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final verified = await widget.checkVerified();
      if (!mounted) return;
      if (verified) {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _status = 'Not verified yet. Open the link in your email first, '
            'then tap "I\'ve verified".';
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not check. Please check your internet connection.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await widget.resend();
      if (!mounted) return;
      setState(() {
        _status = 'A new link was sent to ${widget.email}. '
            'Check your inbox and spam folder.';
        _statusIsError = false;
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _status = e.code == 'too-many-requests'
            ? 'Too many requests. Please wait a few minutes and try again.'
            : 'Could not send the link. Please try again.';
        _statusIsError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = 'Could not send the link. Please try again.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      icon: const Icon(
        Icons.mark_email_unread_outlined,
        color: AppColors.primary,
        size: 32,
      ),
      title: const Text(
        'Verify your email',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'We sent a verification link to ${widget.email}. '
            'Open it, then come back and tap "I\'ve verified".',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _statusIsError ? AppColors.danger : AppColors.success,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
      actions: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPillButton(
              label: "I've verified",
              style: AppPillStyle.brand,
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _check,
            ),
            const SizedBox(height: 8),
            AppPillButton(
              label: 'Resend link',
              style: AppPillStyle.soft,
              expand: true,
              onPressed: _busy ? null : _resend,
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
