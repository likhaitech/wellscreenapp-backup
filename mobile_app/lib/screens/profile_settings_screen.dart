import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/wellscreen_ui.dart';

import '../theme/app_theme.dart';
import '../services/app_rules_service.dart';
import '../services/app_time_limit_service.dart';
import '../services/app_time_limit_notification_service.dart';
import 'login_screen.dart';
import 'phone_verification_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  static const Color purple = AppColors.primary;
  static const Color deepPurple = AppColors.primaryDark;
  static const Color teal = AppColors.accent;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;
  static const Color softPurple = AppColors.primaryLight;
  static const Color softGreen = AppColors.successBg;
  static const Color softRed = Color(0xFFFFEFEF);
  static const Color softBlue = AppColors.infoBg;

  final fullNameController = TextEditingController();
  final profilePhotoUrlController = TextEditingController();
  final extraDetailController = TextEditingController();

  final currentPasswordController = TextEditingController();
  final newPasswordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isSaving = false;
  bool isChangingPassword = false;

  @override
  void dispose() {
    fullNameController.dispose();
    profilePhotoUrlController.dispose();
    extraDetailController.dispose();
    currentPasswordController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> saveProfileDetails(String role) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      showMessage('Please log in again.');
      return;
    }

    final fullName = fullNameController.text.trim();
    final photoUrl = profilePhotoUrlController.text.trim();
    final extraDetail = extraDetailController.text.trim();

    if (fullName.isEmpty) {
      showMessage('Full name is required.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final firestore = FirebaseFirestore.instance;
      final userRef = firestore.collection('users').doc(user.uid);

      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);
        final oldData = snapshot.data() ?? <String, dynamic>{};

        transaction.set(userRef, {
          ...oldData,
          'uid': user.uid,
          'email': user.email,
          'fullName': fullName,
          'profilePhotoUrl': photoUrl,
          // Phone verification is managed by Firebase Authentication.
          // Do not overwrite it with an unverified Edit Profile text value.
          if (role == 'child') 'gradeSection': extraDetail,
          if (role != 'child') 'relationship': extraDetail,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      await user.updateDisplayName(fullName);
      await user.updatePhotoURL(photoUrl.isEmpty ? null : photoUrl);

      // Keep linked child profiles consistent when the parent edits their name.
      // Child accounts cannot read the parent's private users/{uid} document.
      // If the sync fails, the profile save remains successful and the parent
      // can retry using Devices > Sync Parent Details.
      var identitySyncFailed = false;
      if (role == 'parent') {
        try {
          final email = (user.email ?? '').trim();
          if (email.isEmpty) {
            throw StateError('Parent email address is missing.');
          }
          final children = await firestore
              .collection('child_profiles')
              .where('parentId', isEqualTo: user.uid)
              .get(const GetOptions(source: Source.server));
          for (final child in children.docs) {
            if (child.data()['parentDisplayName'] != fullName ||
                child.data()['parentEmail'] != email) {
              await child.reference.set({
                'parentDisplayName': fullName,
                'parentEmail': email,
              }, SetOptions(merge: true));
            }
          }
        } catch (error) {
          debugPrint('Parent profile saved, identity sync failed: $error');
          identitySyncFailed = true;
        }
      }

      if (!mounted) return;

      Navigator.pop(context);
      showMessage(
        identitySyncFailed
            ? 'Profile saved. Open Devices and tap Sync Parent Details.'
            : 'Profile details updated successfully.',
      );
    } catch (e) {
      showMessage('Failed to update profile: $e');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  /// Changes the signed-in user's password via Firebase Auth.
  ///
  /// Firebase requires a "recent" sign-in before it will accept a password
  /// change (`requires-recent-login`), so this re-authenticates with the
  /// user's current password first via [EmailAuthProvider], then calls
  /// [User.updatePassword]. Nothing here touches Firestore - password
  /// changes only ever go through Firebase Auth itself, never through the
  /// app's own `users` collection, so there is no plaintext or hashed
  /// password anywhere in app data.
  Future<void> changePassword() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.email == null) {
      showMessage('Please log in again.');
      return;
    }

    final currentPassword = currentPasswordController.text;
    final newPassword = newPasswordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (currentPassword.isEmpty) {
      showMessage('Enter your current password.');
      return;
    }

    if (newPassword.length < 8) {
      showMessage('New password must be at least 8 characters.');
      return;
    }

    if (newPassword != confirmPassword) {
      showMessage('New password and confirmation do not match.');
      return;
    }

    if (newPassword == currentPassword) {
      showMessage('New password must be different from the current one.');
      return;
    }

    setState(() => isChangingPassword = true);

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      currentPasswordController.clear();
      newPasswordController.clear();
      confirmPasswordController.clear();

      if (!mounted) return;

      Navigator.pop(context);
      showMessage('Password changed successfully.');
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'wrong-password' ||
        'invalid-credential' => 'Current password is incorrect.',
        'weak-password' => 'New password is too weak.',
        'requires-recent-login' =>
          'Please log out and log back in, then try again.',
        'too-many-requests' => 'Too many attempts. Please try again later.',
        _ => 'Failed to change password: ${e.message ?? e.code}',
      };
      showMessage(message);
    } catch (e) {
      showMessage('Failed to change password: $e');
    } finally {
      if (mounted) {
        setState(() => isChangingPassword = false);
      }
    }
  }

  void showChangePasswordSheet() {
    currentPasswordController.clear();
    newPasswordController.clear();
    confirmPasswordController.clear();

    // Captured by the StatefulBuilder closure below so it survives across
    // setSheetState() rebuilds (a plain local re-declared inside the
    // builder callback would reset to its initial value every rebuild).
    var sheetIsSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD1D5DB),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Change Password',
                        style: TextStyle(
                          color: darkText,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'For your security, confirm your current password before setting a new one.',
                        style: TextStyle(
                          color: grayText,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _textField(
                        controller: currentPasswordController,
                        label: 'Current Password',
                        icon: Icons.lock_outline_rounded,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      _textField(
                        controller: newPasswordController,
                        label: 'New Password (min. 8 characters)',
                        icon: Icons.lock_rounded,
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      _textField(
                        controller: confirmPasswordController,
                        label: 'Confirm New Password',
                        icon: Icons.lock_rounded,
                        obscureText: true,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 54,
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: sheetIsSubmitting
                              ? null
                              : () async {
                                  setSheetState(() => sheetIsSubmitting = true);
                                  await changePassword();
                                  // On success, changePassword() already
                                  // popped this sheet - only reset the
                                  // local flag if it's still on screen
                                  // (e.g. it failed validation/auth).
                                  if (context.mounted) {
                                    setSheetState(
                                      () => sheetIsSubmitting = false,
                                    );
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: purple,
                            shape: const StadiumBorder(),
                          ),
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                            sheetIsSubmitting
                                ? 'Changing...'
                                : 'Change Password',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> logout() async {
    // Revoke the child's registered push token before leaving this account.
    await AppTimeLimitNotificationService.instance.stopForSignOut();

    // On a monitored child phone, keep the native limit cache so the
    // AccessibilityService keeps enforcing it after sign-out. Other phones
    // (e.g. a guardian's) clear it as before.
    if (!await AppRulesService.isMonitoredChildDevice()) {
      await AppTimeLimitService().clearCachedLimits();
    }
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void showEditProfileSheet(Map<String, dynamic> data, String role) {
    fullNameController.text =
        (data['fullName'] ??
                FirebaseAuth.instance.currentUser?.displayName ??
                '')
            .toString();

    profilePhotoUrlController.text =
        (data['profilePhotoUrl'] ??
                FirebaseAuth.instance.currentUser?.photoURL ??
                '')
            .toString();

    extraDetailController.text = role == 'child'
        ? (data['gradeSection'] ?? '').toString()
        : (data['relationship'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.track,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Edit Profile',
                    style: TextStyle(
                      color: darkText,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Update your account details. Changes are saved to Firestore using a transaction.',
                    style: TextStyle(
                      color: grayText,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _textField(
                    controller: fullNameController,
                    label: 'Full Name',
                    icon: Icons.person_rounded,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: profilePhotoUrlController,
                    label: 'Profile Photo URL',
                    icon: Icons.image_rounded,
                  ),
                  const SizedBox(height: 12),
                  _textField(
                    controller: extraDetailController,
                    label: role == 'child'
                        ? 'Grade / Section'
                        : 'Relationship to Child',
                    icon: role == 'child'
                        ? Icons.school_rounded
                        : Icons.family_restroom_rounded,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isSaving
                          ? null
                          : () => saveProfileDetails(role),
                      style: FilledButton.styleFrom(
                        backgroundColor: purple,
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.save_rounded),
                      label: Text(
                        isSaving ? 'Saving...' : 'Save Profile',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: grayText),
      ),
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
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: pageBg,
        body: Center(
          child: FilledButton(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: pageBg,
      appBar: const WellScreenAppBar.subPage(title: 'Settings'),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          // Deliberately does NOT block on ConnectionState.waiting the way
          // other screens' StreamBuilders do below - FirebaseAuth's `user`
          // already has a real displayName/email/photoURL to show
          // immediately, so a loading spinner here would just be a flash
          // before the same content re-renders. A genuine read failure is
          // still surfaced explicitly rather than silently falling back to
          // "look like an empty profile."
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppErrorState(
                  title: 'Could Not Load Profile',
                  message:
                      'Something went wrong loading your profile '
                      'details.\n\n${snapshot.error}',
                ),
              ),
            );
          }

          final data = snapshot.data?.data() ?? <String, dynamic>{};

          final fullName =
              (data['fullName'] ?? user.displayName ?? 'WellScreen User')
                  .toString();

          final email = (data['email'] ?? user.email ?? '').toString();

          final role = (data['role'] ?? 'user').toString();

          final photoUrl = (data['profilePhotoUrl'] ?? user.photoURL ?? '')
              .toString();

          final roleLabel = role == 'parent'
              ? 'Guardian'
              : role == 'child'
              ? 'Child Account'
              : 'User Account';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _profileHeader(
                fullName: fullName,
                email: email,
                roleLabel: roleLabel,
                role: role,
                photoUrl: photoUrl,
                onEdit: () => showEditProfileSheet(data, role),
              ),
              const SizedBox(height: 20),
              _settingsSection(
                title: 'Account Details',
                children: [
                  _settingsTile(
                    icon: Icons.edit_rounded,
                    iconColor: purple,
                    backgroundColor: softPurple,
                    title: 'Edit Profile',
                    subtitle: 'Change name, photo URL, and account details.',
                    onTap: () => showEditProfileSheet(data, role),
                  ),
                  _settingsTile(
                    icon: Icons.verified_user_rounded,
                    iconColor: teal,
                    backgroundColor: softGreen,
                    title: 'Mobile Number Verification',
                    subtitle:
                        FirebaseAuth
                                .instance
                                .currentUser
                                ?.phoneNumber
                                ?.isNotEmpty ==
                            true
                        ? 'Verified: ${FirebaseAuth.instance.currentUser!.phoneNumber}'
                        : 'Verify a mobile number with an SMS code.',
                    onTap: () async {
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PhoneVerificationScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _settingsSection(
                title: 'Privacy and System',
                children: [
                  _settingsTile(
                    icon: Icons.password_rounded,
                    iconColor: purple,
                    backgroundColor: softBlue,
                    title: 'Change Password',
                    subtitle: 'Update the password for this account.',
                    onTap: showChangePasswordSheet,
                  ),
                  _settingsTile(
                    icon: Icons.privacy_tip_rounded,
                    iconColor: teal,
                    backgroundColor: softGreen,
                    title: 'Privacy Boundary',
                    subtitle:
                        'WellScreen does not read messages, passwords, calls, photos, or sensitive files.',
                    onTap: () {},
                  ),
                  _settingsTile(
                    icon: Icons.logout_rounded,
                    iconColor: AppColors.danger,
                    backgroundColor: softRed,
                    title: 'Sign Out',
                    subtitle: 'Sign out from this WellScreen account.',
                    onTap: logout,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _profileHeader({
    required String fullName,
    required String email,
    required String roleLabel,
    required String role,
    required String photoUrl,
    required VoidCallback onEdit,
  }) {
    final isChild = role == 'child';

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            _profileImage(photoUrl, isChild),
            Positioned(
              right: -6,
              bottom: 0,
              child: Material(
                color: Colors.white,
                shape: const StadiumBorder(
                  side: BorderSide(color: AppColors.border),
                ),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: onEdit,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Text(
                      'Edit',
                      style: TextStyle(
                        color: darkText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          fullName,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: darkText,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          email,
          textAlign: TextAlign.center,
          style: const TextStyle(color: grayText, fontSize: 13),
        ),
        const SizedBox(height: 8),
        StatusPill(label: roleLabel, tone: StatusTone.info),
      ],
    );
  }

  Widget _profileImage(String photoUrl, bool isChild) {
    final fallback = Icon(
      isChild ? Icons.face_rounded : Icons.person_rounded,
      color: purple,
      size: 46,
    );

    return CircleAvatar(
      radius: 44,
      backgroundColor: softPurple,
      child: photoUrl.isEmpty
          ? fallback
          : ClipOval(
              child: Image.network(
                photoUrl,
                width: 88,
                height: 88,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
            ),
    );
  }

  /// Apple-style grouped list: a small caption, then one white inset card
  /// holding the rows with hairline dividers between them.
  Widget _settingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: grayText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        BentoCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: 52),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required Color iconColor,
    required Color backgroundColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final destructive = iconColor == AppColors.danger;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(
        icon,
        color: destructive ? AppColors.danger : darkText,
        size: 22,
      ),
      minLeadingWidth: 22,
      title: Text(
        title,
        style: TextStyle(
          color: destructive ? AppColors.danger : darkText,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: grayText, fontSize: 12, height: 1.3),
      ),
      trailing: destructive
          ? null
          : const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textDisabled,
            ),
      onTap: onTap,
    );
  }
}
