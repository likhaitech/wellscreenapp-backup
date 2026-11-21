import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_home_screen.dart';
import 'child_home_screen.dart';
import 'login_screen.dart';
import 'parent_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();
    startSplash();
  }

  Future<void> startSplash() async {
    await Future.delayed(const Duration(milliseconds: 1800));

    if (!mounted) return;

    if (Firebase.apps.isEmpty) {
      goToLogin();
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        goToLogin();
        return;
      }

      // Check custom claims first, same as login_screen.dart - without
      // this, an already-signed-in admin (grant_admin.py sets Firestore
      // role: 'admin', which matches neither 'parent' nor 'child'/'student'
      // below) fell through to goToLogin() on every cold start, even
      // though logging in again from there would route them correctly.
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? <String, dynamic>{};
      final isAdmin = claims['admin'] == true || claims['role'] == 'admin';

      if (!mounted) return;

      if (isAdmin) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      final data = userDoc.data() ?? <String, dynamic>{};
      final role = (data['role'] ?? '').toString().toLowerCase();

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
        goToLogin();
      }
    } catch (_) {
      if (!mounted) return;
      goToLogin();
    }
  }

  void goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Design D splash: logo, "Well" + teal "Screen", tagline, and a slim
    // brand-colored progress bar near the bottom.
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icons/wellscreen_icon.png',
                      width: 132,
                      height: 132,
                      semanticLabel: 'WellScreen',
                    ),
                    const SizedBox(height: 20),
                    Text.rich(
                      const TextSpan(
                        children: [
                          TextSpan(
                            text: 'Well',
                            style: TextStyle(color: AppColors.textPrimary),
                          ),
                          TextSpan(
                            text: 'Screen',
                            style: TextStyle(color: AppColors.success),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppFonts.heading,
                        fontSize: 38,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Healthy screen time, together.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Center(
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: const LinearProgressIndicator(
                      minHeight: 6,
                      color: AppColors.primary,
                      backgroundColor: AppColors.primaryLight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
