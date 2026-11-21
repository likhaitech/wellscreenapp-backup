import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/wellscreen_ui.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../services/phone_auth_error.dart';

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

  String _friendlyAuthError(FirebaseAuthException error) =>
      phoneAuthErrorMessage(error.code, error.message);

  /// Six rounded digit boxes drawn over one hidden text field, so the
  /// existing single [_codeController] (and SMS autofill) keeps working.
  Widget _otpBoxes() {
    return Stack(
      alignment: Alignment.center,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _codeController,
          builder: (context, value, _) {
            final code = value.text;

            return Row(
              children: [
                for (var i = 0; i < 6; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      height: 54,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: i == code.length
                              ? AppColors.primary
                              : AppColors.border,
                          width: i == code.length ? 1.5 : 1,
                        ),
                      ),
                      child: Text(
                        i < code.length ? code[i] : '',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
        Positioned.fill(
          child: Opacity(
            opacity: 0,
            child: TextField(
              controller: _codeController,
              enabled: !_busy,
              maxLength: 6,
              showCursor: false,
              enableInteractiveSelection: false,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                counterText: '',
                labelText: '6-digit verification code',
              ),
              onSubmitted: (_) => _confirmCode(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final waitingForCode = _verificationId != null && !_completed;
    final hasVerifiedPhone = _verifiedPhone?.isNotEmpty == true;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WellScreenAppBar.subPage(title: 'Verify Mobile Number'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            // Design D header: violet phone icon and why the number matters.
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.violetBg,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.phone_iphone_rounded,
                  color: AppColors.violet,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your verified number lets WellScreen send SMS alerts when '
              'the internet is down.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            BentoCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Mobile number',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      StatusPill(
                        label: hasVerifiedPhone ? 'Verified' : 'Not verified',
                        tone: hasVerifiedPhone
                            ? StatusTone.success
                            : StatusTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    hasVerifiedPhone
                        ? _verifiedPhone!
                        : 'Add a Philippine mobile number and verify it with '
                              'the SMS code.',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (!_loadingAccount && _accountUid != null) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneController,
                      enabled: !_busy && !waitingForCode && !_completed,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      style: const TextStyle(
                        fontSize: 16,
                        fontFeatures: kTabularFigures,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: AppColors.surface,
                        labelText: 'Philippine mobile number',
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                        hintText: '+639171234567',
                        prefixIcon: const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 8, 0),
                          child: Text(
                            '\u{1F1F5}\u{1F1ED}',
                            style: TextStyle(fontSize: 20),
                          ),
                        ),
                        prefixIconConstraints: const BoxConstraints(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loadingAccount)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (_accountUid == null)
              const Text('Please sign in before registering a mobile number.')
            else ...[
              if (!waitingForCode && !_completed)
                AppPillButton(
                  label: _sending
                      ? 'Requesting code...'
                      : 'Send verification code',
                  style: AppPillStyle.brand,
                  expand: true,
                  onPressed: _busy ? null : _sendCode,
                ),
              if (waitingForCode) ...[
                Text(
                  'Enter the 6-digit code sent to ${_requestedPhone ?? ''}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                _otpBoxes(),
                const SizedBox(height: 16),
                AppPillButton(
                  label: _applyingCredential
                      ? 'Verifying...'
                      : 'Verify & Continue',
                  style: AppPillStyle.brand,
                  expand: true,
                  onPressed: _busy ? null : _confirmCode,
                ),
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.center,
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
              if (_completed)
                AppPillButton(
                  label: 'Done',
                  expand: true,
                  onPressed: () => Navigator.pop(context, true),
                ),
              if (_message != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _message!,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const BentoCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sms_outlined,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SMS Backup Alerts',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'A verified phone does not turn on SMS alerts by '
                            'itself. Alerts need separate SMS consent. '
                            'Verification needs internet and a number that '
                            'can receive SMS; provider charges may apply.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
