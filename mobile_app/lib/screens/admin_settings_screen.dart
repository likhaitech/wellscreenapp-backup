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
      appBar: WellScreenAppBar.subPage(
        title: 'WellScreen Admin',
        showBack: false,
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: isChecking
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : RefreshIndicator(
              onRefresh: loadStats,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _header(),
                  const SizedBox(height: 16),
                  _statsSection(),
                  const SizedBox(height: 20),
                  BentoCard(
                    padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
                          child: Text(
                            'Quick Actions',
                            style: TextStyle(
                              color: darkText,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _menuCard(
                          icon: Icons.manage_accounts_outlined,
                          title: 'Manage Users',
                          subtitle:
                              'View, update, deactivate, or delete user accounts.',
                          onTap: () => open(const AdminUsersScreen()),
                        ),
                        const Divider(indent: 52),
                        _menuCard(
                          icon: Icons.system_update_alt_rounded,
                          title: 'System Patch',
                          subtitle: 'Validate and apply a configuration patch.',
                          onTap: () => open(const AdminPatchScreen()),
                        ),
                        const Divider(indent: 52),
                        _menuCard(
                          icon: Icons.receipt_long_outlined,
                          title: 'System Logs',
                          subtitle: 'Search activity, error, and sync logs.',
                          onTap: () => open(const AdminLogsScreen()),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _recentActivity(),
                ],
              ),
            ),
    );
  }

  Widget _header() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'Administrator';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Welcome, Administrator',
          style: TextStyle(
            color: darkText,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: grayText, fontSize: 13),
        ),
        const SizedBox(height: 8),
        const StatusPill(
          label: 'Admin Access',
          tone: StatusTone.info,
          icon: Icons.verified_user_outlined,
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
            _statTile('Total Users', users.length, Icons.groups_outlined,
                purple),
            const SizedBox(width: 12),
            _statTile('Guardians', guardians, Icons.shield_outlined,
                AppColors.info),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statTile('Children', children, Icons.face_outlined,
                AppColors.success),
            const SizedBox(width: 12),
            _statTile('Deactivated', deactivated, Icons.block_rounded,
                deactivated > 0 ? AppColors.danger : grayText),
          ],
        ),
        if (admins > 0) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '$admins administrator account${admins == 1 ? '' : 's'}',
              style: const TextStyle(color: grayText),
            ),
          ),
        ],
      ],
    );
  }

  Widget _statTile(String label, int value, IconData icon, Color color) {
    return Expanded(
      child: BentoCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(
              '$value',
              style: const TextStyle(
                color: darkText,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                height: 1.1,
                fontFeatures: kTabularFigures,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: grayText, fontSize: 13),
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
              AppSectionHeader(
                icon: Icons.history_rounded,
                iconColor: purple,
                title: 'Recent Activity',
                trailing: TextButton(
                  onPressed: () => open(const AdminLogsScreen()),
                  child: const Text('View all'),
                ),
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
      when = '${d.month.toString().padLeft(2, '0')}/'
          '${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Icon(
            isProblem ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            size: 18,
            color: isProblem ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              (data['action'] ?? 'Unknown action').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: darkText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(when, style: const TextStyle(color: grayText, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Icon(icon, color: darkText, size: 22),
      minLeadingWidth: 22,
      title: Text(
        title,
        style: const TextStyle(
          color: darkText,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: grayText, fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textDisabled,
      ),
      onTap: onTap,
    );
  }
}
