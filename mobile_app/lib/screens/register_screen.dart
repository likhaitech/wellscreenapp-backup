import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/password_policy.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';
import 'child_home_screen.dart';
import 'parent_dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String selectedRole = 'parent';

  bool isLoading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> registerUser() async {
    final fullName = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (fullName.isEmpty || email.isEmpty || password.isEmpty) {
      showMessage('Please complete all required fields.');
      return;
    }
    if (!PasswordPolicy.isStrong(password)) {
      await showPasswordRequirementsDialog(context, password);
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      final user = credential.user;

      if (user == null) {
        showMessage('Registration failed. Please try again.');
        return;
      }

      final userData = <String, dynamic>{
        'uid': user.uid,
        'fullName': fullName,
        'email': email,
        'role': selectedRole,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      };

      if (selectedRole == 'child') {
        userData.addAll({
          'pairingStatus': 'not_paired',
          'pairedParentId': null,
          'pairedChildProfileId': null,
        });
      }

      if (selectedRole == 'parent') {
        userData.addAll({'childrenCount': 0});
      }

      try {
        await user.updateDisplayName(fullName);

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(userData);
      } catch (setupError) {
        // createUserWithEmailAndPassword() above already created (and
        // signed in) the Auth account. If either write below it fails
        // (dropped connection, backgrounded app, a Firestore rule hiccup -
        // all realistic on mobile), that Auth account is left permanently
        // orphaned with no users/{uid} doc: re-registering the same email
        // fails with "email-already-in-use", and login_screen.dart shows
        // "Account role not found" forever, since nothing anywhere
        // auto-creates a missing profile doc. Delete the Auth account so
        // the user can cleanly retry from scratch instead of getting stuck.
        try {
          await user.delete();
        } catch (_) {
          // Best-effort cleanup - surface the original error either way.
        }
        rethrow;
      }

      // Soft verification: send Firebase's built-in verification email so
      // a mistyped or fake address is noticed, without blocking sign-in
      // (enforcing it would lock out accounts created before this change).
      // Best-effort - a failure here never undoes the registration.
      var verificationSent = false;
      try {
        await user.sendEmailVerification();
        verificationSent = true;
      } catch (_) {
        // The account works without it; the user can still reset password
        // only if the address is real.
      }

      if (!mounted) return;

      showMessage(
        verificationSent
            ? 'Account created. We sent a verification link to $email.'
            : 'Account created.',
      );

      if (selectedRole == 'parent') {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
          (route) => false,
        );
      } else {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      showMessage(e.message ?? 'Registration failed.');
    } catch (e) {
      showMessage('Registration error: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get roleDescription {
    if (selectedRole == 'parent') {
      return 'This account will create child profiles, pair monitored Android devices, receive alerts, and configure restrictions.';
    }

    return 'This account will be used on the child device and can be connected to a parent account using a pairing code.';
  }

  Widget _roleCard({
    required String role,
    required String label,
    required IconData icon,
  }) {
    final selected = selectedRole == role;

    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: isLoading ? null : () => setState(() => selectedRole = role),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 34,
                      color: selected
                          ? AppColors.primary
                          : AppColors.textDisabled,
                    ),
                    const SizedBox(height: 8),
                    ExcludeSemantics(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                    ),
                  ),
                ),
                if (selected)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          children: [
            const WellScreenBrandHeader(),
            const SizedBox(height: 28),
            BentoCard(
              child: Column(
                children: [
                  WellScreenField(
                    label: 'Full Name',
                    controller: nameController,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  WellScreenField(
                    label: 'Email Address',
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  WellScreenField(
                    label: 'Password',
                    controller: passwordController,
                    obscureText: obscurePassword,
                    suffixIcon: IconButton(
                      tooltip: obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() => obscurePassword = !obscurePassword);
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    PasswordPolicy.hint,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'I am registering as...',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _roleCard(
                  role: 'parent',
                  label: 'Guardian',
                  icon: Icons.family_restroom_rounded,
                ),
                const SizedBox(width: 12),
                _roleCard(
                  role: 'child',
                  label: 'Child',
                  icon: Icons.face_rounded,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              roleDescription,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            AppPillButton(
              label: 'Create Account',
              expand: true,
              loading: isLoading,
              onPressed: registerUser,
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Already have an account?',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                TextButton(
                  onPressed: isLoading ? null : () => Navigator.maybePop(context),
                  child: const Text('Log in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
