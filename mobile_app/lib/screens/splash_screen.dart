import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'admin_settings_screen.dart';
import 'child_home_screen.dart';
import 'login_screen.dart';
import 'parent_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Color purple = AppColors.primary;
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;

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
          MaterialPageRoute(builder: (_) => const AdminSettingsScreen()),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SizedBox.expand(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 150,
                        height: 150,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(42),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(36),
                          child: Image.asset(
                            'assets/icons/wellscreen_icon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      const Text(
                        'WellScreen',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: purple,
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 10),
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
                      const SizedBox(height: 42),
                      const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(teal),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Text(
                  'Digital wellness support for families',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: purple, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
