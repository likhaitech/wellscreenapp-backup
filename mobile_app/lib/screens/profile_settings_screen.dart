import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
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

    // Clear the child-specific native limit cache before switching accounts.
    await AppTimeLimitService().clearCachedLimits();
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
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
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
        prefixIcon: Icon(icon, color: purple),
        filled: true,
        fillColor: pageBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: purple, width: 2),
        ),
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
      appBar: AppBar(
        title: const Text(
          'Profile Settings',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        backgroundColor: pageBg,
        foregroundColor: darkText,
        elevation: 0,
      ),
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                    iconColor: Colors.redAccent,
                    backgroundColor: softRed,
                    title: 'Logout',
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

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isChild
              ? const [purple, deepPurple]
              : const [purple, deepPurple],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x222557A7),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Stack(
            children: [
              _profileImage(photoUrl, isChild),
              Positioned(
                right: 0,
                bottom: 2,
                child: InkWell(
                  onTap: onEdit,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: teal,
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            fullName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            email,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.primaryLight,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              roleLabel,
              style: const TextStyle(
                color: purple,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _profileImage(String photoUrl, bool isChild) {
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 48,
        backgroundColor: Colors.white,
        child: ClipOval(
          child: Image.network(
            photoUrl,
            width: 92,
            height: 92,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                isChild
                    ? Icons.child_care_rounded
                    : Icons.family_restroom_rounded,
                color: purple,
                size: 54,
              );
            },
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 48,
      backgroundColor: Colors.white,
      child: Icon(
        isChild ? Icons.child_care_rounded : Icons.family_restroom_rounded,
        color: purple,
        size: 54,
      ),
    );
  }

  Widget _settingsSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: darkText,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        ...children,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: backgroundColor,
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          title,
          style: const TextStyle(color: darkText, fontWeight: FontWeight.w900),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: const TextStyle(
              color: grayText,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
