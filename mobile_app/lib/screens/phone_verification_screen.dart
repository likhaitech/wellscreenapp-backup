import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Verifies a mobile number and links it to the CURRENT Firebase Auth user.
///
/// Never sign in with the phone credential here: that could replace the
/// existing parent/child session with another Firebase account. Firebase Auth's
/// linked User.phoneNumber is the verification source of truth; editable
/// Firestore profile fields must not be used as proof of SMS eligibility.
class PhoneVerificationScreen extends StatefulWidget {
  const PhoneVerificationScreen({super.key});

  @override
  State<PhoneVerificationScreen> createState() =>
      _PhoneVerificationScreenState();
}

class _PhoneVerificationScreenState extends State<PhoneVerificationScreen> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  String? _accountUid;
  String? _verifiedPhone;
  String? _requestedPhone;
  String? _verificationId;
  int? _resendToken;
  DateTime? _lastRequestAt;
  String? _message;

  bool _loadingAccount = true;
  bool _sending = false;
  bool _applyingCredential = false;
  bool _completed = false;
  int _requestGeneration = 0;

  bool get _busy => _sending || _applyingCredential;

  @override
  void initState() {
    super.initState();
    _accountUid = FirebaseAuth.instance.currentUser?.uid;
    _loadLinkedPhone();
  }

  @override
  void dispose() {
    // Ignore any late Firebase phone-auth callbacks from this screen.
    _requestGeneration++;
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  bool _isActiveRequest(int generation) =>
      mounted && generation == _requestGeneration && !_completed;

  Future<void> _loadLinkedPhone() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != _accountUid) {
      if (mounted) {
        setState(() {
          _loadingAccount = false;
          _message = 'Please sign in again before verifying your phone.';
        });
      }
      return;
    }

    // Reload rather than trusting a potentially stale Firebase Auth snapshot.
    // A network failure is safe: no phone is newly marked verified.
    String? reloadError;
    try {
      await user.reload();
    } on FirebaseAuthException {
      reloadError = 'Could not refresh account status. Check your connection.';
    } catch (_) {
      reloadError = 'Could not refresh account status. Check your connection.';
    }

    if (!mounted) return;
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.uid != _accountUid) {
      setState(() {
        _loadingAccount = false;
        _message = 'The signed-in account changed. Please reopen Settings.';
      });
      return;
    }

    final existingPhone = current.phoneNumber?.trim();
    setState(() {
      _verifiedPhone = existingPhone?.isNotEmpty == true ? existingPhone : null;
      _loadingAccount = false;
      _message = reloadError;
    });
    if (_verifiedPhone != null) {
      _phoneController.text = _verifiedPhone!;
    }
  }

  /// This release's SMS region policy allows Philippines (+63) only.
  /// Accept local mobile formats 09XXXXXXXXX and 9XXXXXXXXX as well as E.164.
  String? _normalizePhilippineMobile(String input) {
    var value = input.trim().replaceAll(RegExp(r'[\s().-]'), '');
    if (RegExp(r'^09\d{9}$').hasMatch(value)) {
      value = '+63${value.substring(1)}';
    } else if (RegExp(r'^9\d{9}$').hasMatch(value)) {
      value = '+63$value';
    } else if (RegExp(r'^639\d{9}$').hasMatch(value)) {
      value = '+$value';
    }
    return RegExp(r'^\+639\d{9}$').hasMatch(value) ? value : null;
  }

  void _changeNumber() {
    if (_busy) return;
    _requestGeneration++;
    setState(() {
      _requestedPhone = null;
      _verificationId = null;
      _resendToken = null;
      _codeController.clear();
      _message = null;
    });
  }

  Future<void> _sendCode() async {
    if (_busy || _loadingAccount || _completed) return;

    final phone = _normalizePhilippineMobile(_phoneController.text);
    if (phone == null) {
      setState(() {
        _message =
            'Enter a valid Philippine mobile number, e.g. +639171234567.';
      });
      return;
    }
    if (phone == _verifiedPhone) {
      setState(() {
        _message = 'This phone number is already verified for your account.';
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != _accountUid) {
      setState(() {
        _message = 'Your login session has changed. Please sign in again.';
      });
      return;
    }

    // Protect against accidental repeated taps and unnecessary paid OTPs.
    final now = DateTime.now();
    final lastRequest = _lastRequestAt;
    if (lastRequest != null &&
        now.difference(lastRequest) < const Duration(seconds: 60)) {
      final secondsLeft = 60 - now.difference(lastRequest).inSeconds;
      setState(() {
        _message =
            'Please wait $secondsLeft seconds before requesting another code.';
      });
      return;
    }

    _lastRequestAt = now;
    final generation = ++_requestGeneration;
    final resendToken = phone == _requestedPhone ? _resendToken : null;
    setState(() {
      _sending = true;
      _requestedPhone = phone;
      _verificationId = null;
      _resendToken = null;
      _codeController.clear();
      _message = null;
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        forceResendingToken: resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!_isActiveRequest(generation)) return;
          await _applyVerifiedCredential(credential, generation, phone);
        },
        verificationFailed: (FirebaseAuthException error) {
          if (!_isActiveRequest(generation)) return;
          _logFirebaseFailure('verificationFailed', error);
          setState(() {
            _sending = false;
            _lastRequestAt = null;
            _message = _friendlyAuthError(error);
          });
        },
        codeSent: (String verificationId, int? forceResendingToken) {
          if (!_isActiveRequest(generation)) return;
          setState(() {
            _sending = false;
            _verificationId = verificationId;
            _resendToken = forceResendingToken;
            _message =
                'Verification code requested for $phone. Enter the SMS code below.';
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          if (!_isActiveRequest(generation)) return;
          setState(() {
            _sending = false;
            _verificationId ??= verificationId;
          });
        },
      );
    } on FirebaseAuthException catch (error) {
      if (!_isActiveRequest(generation)) return;
      _logFirebaseFailure('requestCode', error);
      setState(() {
        _sending = false;
        _lastRequestAt = null;
        _message = _friendlyAuthError(error);
      });
    } catch (error, stackTrace) {
      if (!_isActiveRequest(generation)) return;
      // Keep provider details in debug logs, rather than guessing that all
      // unknown failures are network failures.
      debugPrint(
        'PhoneOTP requestCode unexpected: ${error.runtimeType}: $error',
      );
      debugPrintStack(stackTrace: stackTrace, label: 'PhoneOTP requestCode');
      setState(() {
        _sending = false;
        _lastRequestAt = null;
        _message = 'Could not request an SMS code. See Flutter debug logs.';
      });
    }
  }

  Future<void> _confirmCode() async {
    if (_busy || _completed) return;
    final id = _verificationId;
    final phone = _requestedPhone;
    final smsCode = _codeController.text.trim();
    if (id == null || phone == null || !RegExp(r'^\d{6}$').hasMatch(smsCode)) {
      setState(() {
        _message = 'Enter the 6-digit SMS code before verifying.';
      });
      return;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: id,
      smsCode: smsCode,
    );
    await _applyVerifiedCredential(credential, _requestGeneration, phone);
  }

  Future<void> _applyVerifiedCredential(
    PhoneAuthCredential credential,
    int generation,
    String expectedPhone,
  ) async {
    if (!_isActiveRequest(generation) || _applyingCredential) return;

    setState(() {
      _applyingCredential = true;
      _sending = false;
      _message = null;
    });

    try {
      var user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != _accountUid) {
        throw StateError(
          'The signed-in account changed. Please sign in again.',
        );
      }

      await user.reload();
      user = FirebaseAuth.instance.currentUser;
      if (user == null || user.uid != _accountUid) {
        throw StateError(
          'The signed-in account changed. Please sign in again.',
        );
      }

      if (user.phoneNumber != expectedPhone) {
        if (user.phoneNumber?.isNotEmpty == true) {
          // Replace an ALREADY linked phone after the new SMS is verified.
          await user.updatePhoneNumber(credential);
        } else {
          // Link instead of signInWithCredential: preserve the existing UID,
          // email/password login, parent/child role, and pairing relationship.
          await user.linkWithCredential(credential);
        }
      }

      final linkedUser = FirebaseAuth.instance.currentUser;
      await linkedUser?.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;
      if (updatedUser == null ||
          updatedUser.uid != _accountUid ||
          updatedUser.phoneNumber != expectedPhone) {
        throw StateError('Firebase could not confirm the linked phone number.');
      }
      if (!_isActiveRequest(generation)) return;

      _codeController.clear();
      setState(() {
        _verifiedPhone = expectedPhone;
        _verificationId = null;
        _resendToken = null;
        _completed = true;
        _message =
            'Phone verification succeeded. Your existing login is preserved.';
      });
    } on FirebaseAuthException catch (error) {
      if (!_isActiveRequest(generation)) return;
      _logFirebaseFailure('linkPhoneCredential', error);
      setState(() {
        _message = _friendlyAuthError(error);
      });
    } catch (error) {
      if (!_isActiveRequest(generation)) return;
      setState(() {
        _message = error is StateError
            ? error.message.toString()
            : 'Could not finish verification. Try again or sign in again.';
      });
    } finally {
      if (mounted) {
        setState(() => _applyingCredential = false);
      }
    }
  }

  void _logFirebaseFailure(String stage, FirebaseAuthException error) {
    // Log only the provider's code/message: never log phone numbers entered by
    // the user, Firebase verification IDs, or six-digit OTP values ourselves.
    // Firebase SDK errors can still include private details: redact before
    // sharing terminal screenshots or logs with other people.
    debugPrint('PhoneOTP $stage: code=${error.code}; message=${error.message}');
  }

  String _friendlyAuthError(FirebaseAuthException error) {
    switch (error.code) {
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
        final details = error.message?.trim() ?? '';
        // While running a debug APK, show the underlying Firebase message so
        // "unknown" can be diagnosed without modifying unrelated features.
        if (kDebugMode && details.isNotEmpty) {
          return 'Phone verification failed (${error.code}): $details';
        }
        return 'Phone verification failed (${error.code}). Check debug logs.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final waitingForCode = _verificationId != null && !_completed;
    final hasVerifiedPhone = _verifiedPhone?.isNotEmpty == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Mobile Number Verification'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        hasVerifiedPhone
                            ? Icons.verified_rounded
                            : Icons.phonelink_lock_rounded,
                        color: hasVerifiedPhone
                            ? const Color(0xFF177245)
                            : AppColors.primary,
                        size: 30,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          hasVerifiedPhone
                              ? 'Verified phone'
                              : 'Phone not verified',
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasVerifiedPhone
                        ? _verifiedPhone!
                        : 'Add a mobile number and verify it with the SMS code sent by Firebase.',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'A verified phone does not automatically enable SMS alerts. '
                    'Parental alerts will require separate SMS consent and backend setup.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loadingAccount)
              const Center(child: CircularProgressIndicator())
            else if (_accountUid == null)
              const Text('Please sign in before registering a mobile number.')
            else ...[
              TextField(
                controller: _phoneController,
                enabled: !_busy && !waitingForCode && !_completed,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: InputDecoration(
                  labelText: 'Philippine mobile number',
                  hintText: '+639171234567',
                  prefixIcon: const Icon(Icons.phone_android_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!waitingForCode && !_completed)
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _sendCode,
                    icon: const Icon(Icons.sms_rounded),
                    label: Text(
                      _sending
                          ? 'Requesting code...'
                          : 'Send verification code',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                  ),
                ),
              if (waitingForCode) ...[
                const SizedBox(height: 8),
                Text('Code sent to ${_requestedPhone ?? ''}'),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  enabled: !_busy,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '6-digit verification code',
                    prefixIcon: const Icon(Icons.password_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onSubmitted: (_) => _confirmCode(),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _busy ? null : _confirmCode,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: Text(
                      _applyingCredential
                          ? 'Verifying...'
                          : 'Verify and link phone',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: _busy ? null : _sendCode,
                      child: const Text('Resend code'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _changeNumber,
                      child: const Text('Change number'),
                    ),
                  ],
                ),
              ],
              if (_completed) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Done'),
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _message!,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'This verification requires internet access and an active number '
                'capable of receiving Firebase SMS. Codes may incur provider charges.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
