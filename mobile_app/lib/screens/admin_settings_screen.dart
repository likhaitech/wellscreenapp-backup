import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_users_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/wellscreen_ui.dart';
import 'admin_logs_screen.dart';
import 'admin_patch_screen.dart';
import 'admin_users_screen.dart';
import 'login_screen.dart';

/// Admin app (design: "WellScreen Admin UI"). Same shell as the guardian
/// and child apps - logo app bar and floating pill dock - with four tabs:
/// Home, Users, Logs and Settings. Matches the manuscript's admin module:
/// Manage Users, Manage System Settings (system patch) and Monitor System
/// Logs. The class name is kept because login/splash route admins here.
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;

  bool isChecking = true;
  int _tab = 0;

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

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await logout();
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

  void _goTo(int tab) {
    if (tab == 0 && _tab != 0) loadStats();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    if (isChecking) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: WellScreenAppBar.primary(
        title: 'WellScreen Admin',
        onAvatar: () => _goTo(3),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _homeTab(),
          const AdminUsersScreen(embedded: true),
          const AdminLogsScreen(embedded: true),
          _settingsTab(),
        ],
      ),
      bottomNavigationBar: FloatingPillDock(
        currentIndex: _tab,
        items: const [
          DockItem(icon: Icons.home_outlined, label: 'Home'),
          DockItem(icon: Icons.group_outlined, label: 'Users'),
          DockItem(icon: Icons.receipt_long_outlined, label: 'Logs'),
          DockItem(icon: Icons.settings_outlined, label: 'Settings'),
        ],
        onTap: _goTo,
      ),
    );
  }

  // ------------------------------------------------------------------ home

  Widget _homeTab() {
    return RefreshIndicator(
      onRefresh: loadStats,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, kAdminDockClearance),
        children: [
          _greeting(),
          const SizedBox(height: 14),
          _statusCard(),
          const SizedBox(height: 12),
          _statTiles(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _quickLink(
                  icon: Icons.group_outlined,
                  tint: AppColors.primaryLight,
                  color: AppColors.primary,
                  title: 'Manage users',
                  subtitle: 'Edit, reset password, deactivate',
                  onTap: () => _goTo(1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _quickLink(
                  icon: Icons.receipt_long_outlined,
                  tint: AppColors.warningBg,
                  color: AppColors.warning,
                  title: 'System logs',
                  subtitle: 'Activity, errors and sync',
                  onTap: () => _goTo(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _recentActivity(),
        ],
      ),
    );
  }

  Widget _greeting() {
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday',
    ];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : (now.hour < 18 ? 'Good afternoon' : 'Good evening');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}',
            style: const TextStyle(color: grayText, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            greeting,
            style: const TextStyle(
              fontFamily: AppFonts.heading,
              color: darkText,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  /// Gradient card: total users, signed in today, errors today.
  Widget _statusCard() {
    final users = _users;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final activeToday = users
        ?.where((u) =>
            u.lastSignInAt != null &&
            !u.lastSignInAt!.toLocal().isBefore(startOfDay))
        .length;
    final online = _usersError == null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'System status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online
                            ? AppColors.teal
                            : AppColors.warningBg,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _usersLoading && users == null
                          ? 'Checking server'
                          : (online ? 'Server online' : 'Server waking up'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _statusNumber(users?.length, 'Total users'),
              _statusNumber(activeToday, 'Signed in today'),
              Expanded(child: _errorsToday(startOfDay)),
            ],
          ),
          if (_usersError != null && users == null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: loadStats,
              child: const Text(
                'Could not load users. Tap to retry.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusNumber(int? value, String label) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value == null ? '-' : '$value',
            style: const TextStyle(
              fontFamily: AppFonts.heading,
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              fontFeatures: kTabularFigures,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  /// Error-level system logs since midnight (one range filter, so no
  /// composite index is needed; the level is counted on the phone).
  Widget _errorsToday(DateTime startOfDay) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system_logs')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
          )
          .limit(500)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs
            .where((d) =>
                (d.data()['level'] ?? '').toString().toLowerCase() == 'error')
            .length;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == null ? '-' : '$count',
              style: const TextStyle(
                fontFamily: AppFonts.heading,
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
                fontFeatures: kTabularFigures,
              ),
            ),
            const Text(
              'Errors today',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        );
      },
    );
  }

  Widget _statTiles() {
    final users = _users ?? const <AdminManagedUser>[];
    final loaded = _users != null;
    final guardians = users.where((u) => u.role == 'parent').length;
    final children = users.where((u) => u.role == 'child').length;
    final deactivated = users.where((u) => u.disabled).length;
    return Row(
      children: [
        _statTile(loaded ? guardians : null, 'Guardians', AppColors.primary),
        const SizedBox(width: 10),
        _statTile(loaded ? children : null, 'Children', AppColors.success),
        const SizedBox(width: 10),
        _statTile(
          loaded ? deactivated : null,
          'Deactivated',
          deactivated > 0 ? AppColors.danger : grayText,
        ),
      ],
    );
  }

  Widget _statTile(int? value, String label, Color color) {
    return Expanded(
      child: BentoCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value == null ? '-' : '$value',
              style: TextStyle(
                fontFamily: AppFonts.heading,
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w700,
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

  Widget _quickLink({
    required IconData icon,
    required Color tint,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return BentoCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
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
    );
  }

  Widget _recentActivity() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('system_logs')
          .orderBy('timestamp', descending: true)
          .limit(4)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        return BentoCard(
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
                    onPressed: () => _goTo(2),
                    child: const Text('View all'),
                  ),
                ],
              ),
              if (snapshot.hasError)
                const Text(
                  'Unable to load recent activity.',
                  style: TextStyle(color: grayText),
                )
              else if (docs.isEmpty)
                const Text(
                  'No activity recorded yet.',
                  style: TextStyle(color: grayText),
                )
              else
                for (final doc in docs) _activityRow(doc.data()),
            ],
          ),
        );
      },
    );
  }

  Widget _activityRow(Map<String, dynamic> data) {
    final (kind, color, tint) = adminLogKind(data);
    final icon = switch (kind) {
      'Error' => Icons.error_outline_rounded,
      'Warning' => Icons.warning_amber_rounded,
      'Sync' => Icons.sync_rounded,
      _ => Icons.bolt_rounded,
    };
    final day = adminLogDay(data['timestamp']);
    final time = adminLogTime(data['timestamp']);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  adminActionTitle(data['action']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: darkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [kind, if (time.isNotEmpty) '$day $time'].join(' · '),
                  style: const TextStyle(color: grayText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- settings

  Widget _settingsTab() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'admin';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, kAdminDockClearance),
      children: [
        const AdminPageTitle('Settings'),
        const SizedBox(height: 14),
        BentoCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _settingsRow(
                icon: Icons.tune_rounded,
                tint: AppColors.violetBg,
                color: AppColors.violet,
                title: 'System patch',
                subtitle: 'Age-group rules: daily goals and risky sites',
                onTap: () => open(const AdminPatchScreen()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        BentoCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_outlined, color: grayText),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Signed in as $email',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: darkText, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.surfaceMuted),
              _settingsRow(
                icon: Icons.logout_rounded,
                tint: AppColors.dangerBg,
                color: AppColors.danger,
                title: 'Sign out',
                onTap: _confirmLogout,
                danger: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required Color tint,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    style: TextStyle(
                      color: danger ? AppColors.danger : darkText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(color: grayText, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            if (!danger)
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
