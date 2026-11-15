import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_settings_screen.dart';
import 'child_home_screen.dart';
import 'parent_dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> loginUser() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      showMessage('Please enter your email and password.');
      return;
    }

    setState(() => isLoading = true);

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('Login failed. Please try again.');
      }

      // Refresh Firebase ID token so the latest custom claims are loaded.
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? <String, dynamic>{};

      final isAdmin = claims['admin'] == true || claims['role'] == 'admin';

      if (!mounted) return;

      // Admin accounts go directly to the Admin System Settings screen.
      if (isAdmin) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
        );

        return;
      }

      // Normal parent / child accounts use their Firestore role.
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = userDoc.data() ?? <String, dynamic>{};
      final role = (data['role'] ?? '').toString().toLowerCase();

      if (!mounted) return;

      if (role == 'parent') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
        );
      } else if (role == 'child' || role == 'student') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChildHomeScreen()),
        );
      } else {
        showMessage('Account role not found. Please contact the developer.');
      }
    } on FirebaseAuthException catch (e) {
      showMessage(authErrorMessage(e.code));
    } catch (e) {
      showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      showMessage('Enter your email above, then tap Forgot password.');
      return;
    }

    setState(() => isLoading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      showMessage(
        'If an account exists for $email, a password reset link has been '
        'sent. Check your inbox and spam folder.',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-email') {
        showMessage('Invalid email address.');
      } else if (e.code == 'network-request-failed') {
        showMessage('Network error. Please check your internet connection.');
      } else {
        showMessage('Could not send reset email. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  String authErrorMessage(String code) {
    if (code == 'user-not-found') {
      return 'No account found with this email.';
    }

    if (code == 'wrong-password') {
      return 'Incorrect password.';
    }

    if (code == 'invalid-email') {
      return 'Invalid email address.';
    }

    if (code == 'invalid-credential') {
      return 'Invalid email or password.';
    }

    if (code == 'user-disabled') {
      return 'This account has been disabled.';
    }

    if (code == 'network-request-failed') {
      return 'Network error. Please check your internet connection.';
    }

    return 'Login failed. Please try again.';
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Column(
              children: [
                _logoHeader(),
                const SizedBox(height: 30),
                _loginCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _logoHeader() {
    return Column(
      children: [
        Container(
          width: 132,
          height: 132,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(38),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Image.asset(
              'assets/icons/wellscreen_icon.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'WellScreen',
          style: TextStyle(
            color: purple,
            fontSize: 38,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Smart Parental Control\nfor Digital Wellness',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: darkText,
            fontSize: 17,
            height: 1.35,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _loginCard() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Login',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: darkText,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Access your WellScreen account',
            textAlign: TextAlign.center,
            style: TextStyle(color: grayText, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.email_rounded, color: purple),
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: passwordController,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!isLoading) {
                loginUser();
              }
            },
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_rounded, color: purple),
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => obscurePassword = !obscurePassword);
                },
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: grayText,
                ),
              ),
              filled: true,
              fillColor: pageBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: purple, width: 2),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : resetPassword,
              child: const Text(
                'Forgot password?',
                style: TextStyle(color: purple, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: isLoading ? null : loginUser,
              style: FilledButton.styleFrom(
                backgroundColor: purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                isLoading ? 'Logging in...' : 'Login',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'No account yet?',
                style: TextStyle(color: grayText, fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegisterScreen(),
                          ),
                        );
                      },
                child: const Text(
                  'Register',
                  style: TextStyle(color: purple, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
