import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_overview_api_service.dart';
import '../services/admin_users_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_activity_widgets.dart';
import '../widgets/admin_ui.dart';
import '../widgets/wellscreen_ui.dart';
import 'admin_logs_screen.dart';
import 'admin_health_screen.dart';
import 'admin_users_screen.dart';
import 'login_screen.dart';

/// Admin app (design: "WellScreen Admin UI"). Same shell as the guardian
/// and child apps - logo app bar and floating pill dock - with four tabs
/// matching the admin modules: Home (View Admin Dashboard), Users (Manage
/// Users), Health (Monitor System Health, view only) and Logs (Monitor
/// System Logs). Sign out is in the app bar and under the avatar.
///
/// The admin watches the system and manages accounts. It cannot change
/// how the system works: updates and bug fixes are made by the developers.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;

  bool isChecking = true;
  int _tab = 0;

  final AdminUsersApiService _usersApi = AdminUsersApiService();
  List<AdminManagedUser>? _users;
  String? _usersError;
  bool _usersLoading = false;

  final AdminOverviewApiService _overviewApi = AdminOverviewApiService();
  AdminOverview? _overview;
  String? _overviewError;
  bool _overviewLoading = false;
  int _range = 7;

  /// Home refreshes itself while it is open, so new sign-ins and active
  /// users show up without pulling down.
  static const Duration _autoRefreshEvery = Duration(seconds: 60);
  Timer? _autoRefresh;

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
    _autoRefresh = Timer.periodic(_autoRefreshEvery, (_) {
      if (mounted && _tab == 0 && !_usersLoading && !_overviewLoading) {
        loadStats();
      }
    });
    loadStats();
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> loadStats() async {
    await Future.wait([_loadUsers(), _loadOverview()]);
  }

  Future<void> _loadOverview() async {
    setState(() {
      _overviewLoading = true;
      _overviewError = null;
    });
    final range = _range;
    try {
      final overview = await _overviewApi.getOverview(days: range);
      if (!mounted || range != _range) return;
      setState(() => _overview = overview);
    } catch (_) {
      if (!mounted) return;
      setState(() => _overviewError = 'Could not load activity.');
    } finally {
      if (mounted) setState(() => _overviewLoading = false);
    }
  }

  void _setRange(int days) {
    setState(() {
      _range = days;
      _overview = null;
    });
    _loadOverview();
  }

  Future<void> _loadUsers() async {
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

  void _accountSheet() {
    final email = FirebaseAuth.instance.currentUser?.email ?? 'admin';
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.verified_user_outlined),
              title: const Text('Administrator'),
              subtitle: Text(email),
            ),
            ListTile(
              leading: const Icon(
                Icons.logout_rounded,
                color: AppColors.danger,
              ),
              title: const Text(
                'Sign out',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmLogout();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    if (await confirmAdminSignOut(context)) await logout();
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
        onAvatar: _accountSheet,
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _homeTab(),
          const AdminUsersScreen(embedded: true),
          AdminHealthScreen(embedded: true, onViewLogs: () => _goTo(3)),
          const AdminLogsScreen(embedded: true),
        ],
      ),
      bottomNavigationBar: FloatingPillDock(
        currentIndex: _tab,
        items: const [
          DockItem(icon: Icons.home_outlined, label: 'Home'),
          DockItem(icon: Icons.group_outlined, label: 'Users'),
          DockItem(icon: Icons.monitor_heart_outlined, label: 'Health'),
          DockItem(icon: Icons.receipt_long_outlined, label: 'Logs'),
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
          AdminActiveUsersChart(
            days: _overview?.daily ?? const [],
            range: _range,
            onRangeChanged: _setRange,
            loading: _overviewLoading,
            error: _overviewError,
            onRetry: _loadOverview,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _quickLink(
                  icon: Icons.group_outlined,
                  tint: AppColors.primaryLight,
                  color: AppColors.primary,
                  title: 'Manage users',
                  subtitle: 'Edit, reset, deactivate',
                  onTap: () => _goTo(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickLink(
                  icon: Icons.monitor_heart_outlined,
                  tint: AppColors.violetBg,
                  color: AppColors.violet,
                  title: 'System health',
                  subtitle: 'Server and jobs',
                  onTap: () => _goTo(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickLink(
                  icon: Icons.receipt_long_outlined,
                  tint: AppColors.warningBg,
                  color: AppColors.warning,
                  title: 'System logs',
                  subtitle: 'Errors and sync',
                  onTap: () => _goTo(3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AdminSystemStatusCard(
            overview: _overview,
            loading: _overviewLoading,
            failed: _overviewError != null,
            onTap: () => _goTo(2),
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
    final online = _usersError == null || _overview != null;

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
                      _usersLoading && users == null && _overview == null
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
                    onPressed: () => _goTo(3),
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
}

/// The "Sign out?" confirmation. True when the administrator confirms.
Future<bool> confirmAdminSignOut(BuildContext context) async {
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
  return ok == true;
}
