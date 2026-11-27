import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/login_backend.dart';
import '../services/login_error_message.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';
import 'admin_home_screen.dart';
import 'child_home_screen.dart';
import 'parent_dashboard_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.backend, this.openHome});

  /// Where sign-in happens. Defaults to Firebase; tests pass a double.
  final LoginBackend? backend;

  /// Opens the home screen for 'admin', 'parent' or 'child'. Defaults to
  /// the Admin, Guardian Dashboard and child home screens.
  final void Function(BuildContext context, String role)? openHome;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
      final backend = widget.backend ?? FirebaseLoginBackend();
      final uid = await backend.signIn(email, password);

      if (uid == null) {
        throw Exception('Login failed. Please try again.');
      }

      // Admin accounts go directly to the admin app.
      if (await backend.isAdmin()) {
        if (!mounted) return;
        _openHome('admin');
        return;
      }

      // Normal parent / child accounts use their Firestore role.
      final role = await backend.role(uid);

      if (!mounted) return;

      if (role == 'parent') {
        _openHome('parent');
      } else if (role == 'child' || role == 'student') {
        _openHome('child');
      } else {
        showMessage('Account role not found. Please contact the developer.');
      }
    } on FirebaseAuthException catch (e) {
      showMessage(loginErrorMessage(e.code));
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
      await (widget.backend ?? FirebaseLoginBackend())
          .sendPasswordReset(email);
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

  void _openHome(String role) {
    if (widget.openHome != null) {
      widget.openHome!(context, role);
      return;
    }
    final Widget home = switch (role) {
      'admin' => const AdminHomeScreen(),
      'parent' => const ParentDashboardScreen(),
      _ => const ChildHomeScreen(),
    };
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => home),
    );
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
    return const WellScreenBrandHeader(
      title: 'Welcome back',
      tagline: 'Log in to keep your family\u2019s screen time healthy.',
    );
  }

  Widget _loginCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WellScreenField(
                label: 'Email address',
                hintText: 'you@example.com',
                prefixIcon: const Icon(Icons.mail_outline_rounded, size: 20),
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              WellScreenField(
                label: 'Password',
                prefixIcon: const Icon(Icons.key_rounded, size: 20),
                controller: passwordController,
                obscureText: obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (!isLoading) {
                    loginUser();
                  }
                },
                suffixIcon: IconButton(
                  tooltip: obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: () {
                    setState(() => obscurePassword = !obscurePassword);
                  },
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: grayText,
                    size: 20,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: isLoading ? null : resetPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
            ],
        ),
        const SizedBox(height: 12),
        AppPillButton(
          label: 'Log in',
          expand: true,
          loading: isLoading,
          onPressed: loginUser,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'New here?',
              style: TextStyle(color: grayText, fontSize: 13),
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
              child: const Text('Create account'),
            ),
          ],
        ),
      ],
    );
  }
}
