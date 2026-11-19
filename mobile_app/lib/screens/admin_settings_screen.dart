import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_users_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';
import 'admin_logs_screen.dart';
import 'admin_patch_screen.dart';
import 'admin_users_screen.dart';
import 'login_screen.dart';

/// Admin dashboard. Matches the manuscript's admin module: Manage Users,
/// Manage System Settings (system patch) and Monitor System Logs. The
/// class name is kept because login/splash route admins here.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;

  bool isChecking = true;

  final AdminUsersApiService _usersApi = AdminUsersApiService();
  List<AdminManagedUser>? _users;
  String? _usersError;
  bool _usersLoading = false;

  @override
  void initState() {
    super.initState();
    verifyAdmin();
  }

  Future<void> verifyAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    var isAdmin = false;

    if (user != null) {
      final tokenResult = await user.getIdTokenResult(true);
      final claims = tokenResult.claims ?? <String, dynamic>{};
      isAdmin = claims['admin'] == true || claims['role'] == 'admin';
    }

    if (!isAdmin) {
      showMessage('Administrator access required.');
      if (mounted) await logout();
      return;
    }

    if (mounted) setState(() => isChecking = false);
    loadStats();
  }

  Future<void> loadStats() async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
    });

    try {
      final users = await _usersApi.listUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (!mounted) return;
      setState(() => _usersError = _usersApi.errorMessage(e));
    } finally {
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void open(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    ).then((_) {
      if (mounted) loadStats();
    });
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
        child: isChecking
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: loadStats,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  _statsSection(),
                  const SizedBox(height: 12),
                  BentoCard(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _menuCard(
                          icon: Icons.group_outlined,
                          tint: AppColors.primaryLight,
                          color: AppColors.primary,
                          title: 'Manage users',
                          subtitle: 'Edit, reset password, deactivate',
                          onTap: () => open(const AdminUsersScreen()),
                        ),
                        _menuCard(
                          icon: Icons.code_rounded,
                          tint: AppColors.violetBg,
                          color: AppColors.violet,
                          title: 'System patch',
                          subtitle: 'Validate and apply a configuration patch',
                          onTap: () => open(const AdminPatchScreen()),
                        ),
                        _menuCard(
                          icon: Icons.description_outlined,
                          tint: AppColors.successBg,
                          color: AppColors.success,
                          title: 'System logs',
                          subtitle: 'Activity, errors and sync',
                          onTap: () => open(const AdminLogsScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _recentActivity(),
                ],
              ),
            ),
      ),
    );
  }

  Widget _header() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'admin';

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'WellScreen Admin',
                style: TextStyle(
                  fontFamily: AppFonts.heading,
                  color: darkText,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Signed in as $email',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: grayText, fontSize: 13),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Logout',
          onPressed: logout,
          icon: const Icon(Icons.logout_rounded, color: grayText),
        ),
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: const Text(
            'AD',
            style: TextStyle(
              fontFamily: AppFonts.heading,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statsSection() {
    if (_usersLoading && _users == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_usersError != null && _users == null) {
      return AppCard(
        onTap: loadStats,
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Could not load user statistics. The server may be waking '
                'up - tap to retry.',
              ),
            ),
            const Icon(Icons.refresh_rounded, color: grayText),
          ],
        ),
      );
    }

    final users = _users ?? const <AdminManagedUser>[];
    final guardians = users.where((u) => u.role == 'parent').length;
    final children = users.where((u) => u.role == 'child').length;
    final admins = users.where((u) => u.role == 'admin').length;
    final deactivated = users.where((u) => u.disabled).length;

    return Column(
      children: [
        Row(
          children: [
            _statTile('Users', users.length, purple),
            const SizedBox(width: 10),
            _statTile('Children', children, AppColors.success),
            const SizedBox(width: 10),
            _statTile('Deactivated', deactivated,
                deactivated > 0 ? AppColors.danger : grayText),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '$guardians guardian${guardians == 1 ? '' : 's'} · '
            '$admins administrator${admins == 1 ? '' : 's'}',
            style: const TextStyle(color: grayText, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _statTile(String label, int value, Color color) {
    return Expanded(
      child: BentoCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontFamily: AppFonts.heading,
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.1,
                fontFeatures: kTabularFigures,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: grayText, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentActivity() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system_logs')
          .orderBy('timestamp', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Recent activity',
                      style: TextStyle(
                        fontFamily: AppFonts.heading,
                        color: darkText,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => open(const AdminLogsScreen()),
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (snapshot.hasError)
                const Text('Unable to load recent activity.')
              else if (docs.isEmpty)
                const Text('No activity recorded yet.')
              else
                for (final doc in docs) _activityRow(doc.data()),
            ],
          ),
        );
      },
    );
  }

  Widget _activityRow(Map<String, dynamic> data) {
    final level = (data['level'] ?? 'info').toString().toLowerCase();
    final isProblem = level == 'error' || level == 'warning';
    final ts = data['timestamp'];
    var when = '';

    if (ts is Timestamp) {
      final d = ts.toDate().toLocal();
      final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
      when = '${d.month}/${d.day} $hour:'
          '${d.minute.toString().padLeft(2, '0')} '
          '${d.hour < 12 ? 'AM' : 'PM'}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              (data['action'] ?? 'Unknown action').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isProblem ? AppColors.danger : darkText,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(when, style: const TextStyle(color: grayText, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required Color tint,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: darkText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: grayText, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: grayText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
