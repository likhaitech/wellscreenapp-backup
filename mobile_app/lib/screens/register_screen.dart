import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'child_home_screen.dart';
import 'parent_dashboard_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;

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
    if (password.length < 8) {
      showMessage('Password must be at least 8 characters.');
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

      if (!mounted) return;

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

  @override
  Widget build(BuildContext context) {
    final isParent = selectedRole == 'parent';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'User Registration',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: darkText,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            isParent
                ? 'Create Guardian Account'
                : 'Create Child Account',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: darkText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            roleDescription,
            style: const TextStyle(color: grayText, height: 1.4),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: nameController,
            decoration: InputDecoration(
              labelText: 'Full Name',
              prefixIcon: const Icon(Icons.person_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email Address',
              prefixIcon: const Icon(Icons.email_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                ),
                onPressed: () {
                  setState(() => obscurePassword = !obscurePassword);
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: selectedRole,
            decoration: InputDecoration(
              labelText: 'Role',
              prefixIcon: const Icon(Icons.family_restroom_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: 'parent',
                child: Text('Guardian'),
              ),
              DropdownMenuItem(value: 'child', child: Text('Child')),
            ],
            onChanged: isLoading
                ? null
                : (value) {
                    if (value == null) return;
                    setState(() => selectedRole = value);
                  },
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              selectedRole == 'parent'
                  ? 'After registration, this account will open the Parent Dashboard.'
                  : 'After registration, this account will open the Child Device Setup page where the pairing code can be entered.',
              style: const TextStyle(
                color: darkText,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: isLoading ? null : registerUser,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      isParent
                          ? 'Create Parent Account'
                          : 'Create Child Account',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
