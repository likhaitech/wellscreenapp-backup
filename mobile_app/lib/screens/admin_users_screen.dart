import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_users_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/wellscreen_ui.dart';

enum AdminUserFilter { all, guardians, children, admins, deactivated }

/// Admin "Manage Users" module (manuscript use case "Manage Users"):
/// retrieve the user list, view a user's details, update a user record,
/// deactivate / reactivate an account, and delete an account.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, this.embedded = false});

  /// True inside the admin home's tabs: no app bar of its own.
  final bool embedded;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;

  final AdminUsersApiService _api = AdminUsersApiService();
  final TextEditingController _searchController = TextEditingController();

  List<AdminManagedUser> _users = <AdminManagedUser>[];
  bool _loading = true;
  String? _loadError;
  AdminUserFilter _filter = AdminUserFilter.all;
  String _query = '';

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final users = await _api.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = _api.errorMessage(error);
        _loading = false;
      });
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  List<AdminManagedUser> get _visibleUsers =>
      filterAdminUsers(_users, _query, _filter);

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'parent':
        return 'Guardian';
      case 'child':
        return 'Child';
      default:
        return 'User';
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Never';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$month/$day/${date.year} $hour:$minute';
  }

  void _replaceUser(AdminManagedUser updated) {
    setState(() {
      _users = _users
          .map((user) => user.uid == updated.uid ? updated : user)
          .toList();
    });
  }

  Future<void> _toggleDisabled(AdminManagedUser user) async {
    final deactivate = !user.disabled;
    final confirmed = await _confirm(
      title: deactivate ? 'Deactivate account?' : 'Reactivate account?',
      message: deactivate
          ? '${user.email} will no longer be able to sign in until the '
                'account is reactivated.'
          : '${user.email} will be able to sign in again.',
      confirmLabel: deactivate ? 'Deactivate' : 'Reactivate',
      danger: deactivate,
    );
    if (confirmed != true) return;
    try {
      await _api.updateUser(user.uid, disabled: deactivate);
      _replaceUser(user.copyWith(disabled: deactivate));
      _toast(deactivate ? 'Account deactivated.' : 'Account reactivated.');
    } catch (error) {
      _toast(_api.errorMessage(error));
    }
  }

  Future<void> _deleteUser(AdminManagedUser user) async {
    final confirmed = await _confirm(
      title: 'Delete account?',
      message:
          'This permanently deletes ${user.email}. This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (confirmed != true) return;
    try {
      await _api.deleteUser(user.uid);
      if (!mounted) return;
      setState(() {
        _users = _users.where((item) => item.uid != user.uid).toList();
      });
      _toast('Account deleted.');
    } catch (error) {
      _toast(_api.errorMessage(error));
    }
  }

  Future<void> _editUser(AdminManagedUser user) async {
    final nameController = TextEditingController(text: user.displayName);
    final emailController = TextEditingController(text: user.email);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit user details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    final newName = nameController.text.trim();
    final newEmail = emailController.text.trim();
    nameController.dispose();
    emailController.dispose();
    if (saved != true) return;

    final nameChanged = newName != user.displayName;
    final emailChanged = newEmail.isNotEmpty && newEmail != user.email;
    if (!nameChanged && !emailChanged) return;

    try {
      await _api.updateUser(
        user.uid,
        displayName: nameChanged ? newName : null,
        email: emailChanged ? newEmail : null,
      );
      _replaceUser(
        user.copyWith(
          displayName: nameChanged ? newName : null,
          email: emailChanged ? newEmail : null,
        ),
      );
      _toast(adminUserUpdatedMessage);
    } catch (error) {
      _toast(_api.errorMessage(error));
    }
  }

  Future<void> _resetPassword(AdminManagedUser user) async {
    final passwordController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Set a new password'),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password (at least 6 characters)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Set password'),
            ),
          ],
        );
      },
    );
    final newPassword = passwordController.text;
    passwordController.dispose();
    if (confirmed != true) return;
    final passwordError = adminPasswordError(newPassword);
    if (passwordError != null) {
      _toast(passwordError);
      return;
    }
    try {
      await _api.updateUser(user.uid, password: newPassword);
      _toast('Password updated.');
    } catch (error) {
      _toast(_api.errorMessage(error));
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: danger
                  ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  /// Full "User details" page (design screen 3). Actions close the page
  /// and run the same confirm dialogs as before.
  void _openDetails(AdminManagedUser user) {
    final isSelf = user.uid == _currentUid;
    final title = user.displayName.isEmpty ? user.email : user.displayName;
    final (roleFg, roleBg) = _roleColors(user.role);

    void run(BuildContext pageContext, Future<void> Function() action) {
      Navigator.pop(pageContext);
      action();
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: const WellScreenAppBar.subPage(title: 'User details'),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              BentoCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _avatar(user, size: 68, fontSize: 24),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppFonts.heading,
                        color: darkText,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        AppBadge(
                          label: _roleLabel(user.role),
                          color: roleFg,
                          background: roleBg,
                        ),
                        AppBadge(
                          label: user.disabled ? 'Deactivated' : 'Active',
                          color: user.disabled
                              ? AppColors.danger
                              : AppColors.success,
                          background: user.disabled
                              ? AppColors.dangerBg
                              : AppColors.successBg,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              BentoCard(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _detailRow('Email', user.email),
                    _detailRow(
                      'Email verified',
                      user.emailVerified ? 'Yes' : 'No',
                    ),
                    if (user.paired != null)
                      _detailRow(
                        'Pairing',
                        user.paired! ? 'Paired' : 'Not paired',
                      ),
                    _detailRow('Created', _formatDate(user.createdAt)),
                    _detailRow('Last sign-in', _formatDate(user.lastSignInAt)),
                    _detailRow('User ID', user.uid, last: true, mono: true),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () => run(pageContext, () => _editUser(user)),
                      child: const Text('Edit details'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryLight,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(50),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: () =>
                          run(pageContext, () => _resetPassword(user)),
                      child: const Text('New password'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              BentoCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Account access',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSelf
                          ? 'This is your own admin account, so it cannot be '
                              'deactivated or deleted here.'
                          : 'Deactivating signs the user out and blocks '
                              'sign-in. You can reactivate later. Deleting '
                              'removes the account for good.',
                      style: const TextStyle(
                        color: grayText,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    if (!isSelf) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                backgroundColor: user.disabled
                                    ? AppColors.successBg
                                    : AppColors.dangerBg,
                                foregroundColor: user.disabled
                                    ? AppColors.success
                                    : AppColors.danger,
                                minimumSize: const Size.fromHeight(46),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () => run(
                                pageContext,
                                () => _toggleDisabled(user),
                              ),
                              child: Text(
                                user.disabled ? 'Reactivate' : 'Deactivate',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.danger,
                                minimumSize: const Size.fromHeight(46),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () =>
                                  run(pageContext, () => _deleteUser(user)),
                              child: const Text('Delete account'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    bool last = false,
    bool mono = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.surfaceMuted)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: grayText, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: SelectableText(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: darkText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(AdminManagedUser user, {double size = 40, double fontSize = 14}) {
    final (fg, bg) = user.disabled
        ? (AppColors.textSecondary, AppColors.surfaceMuted)
        : _roleColors(user.role);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        _initials(user.displayName.isEmpty ? user.email : user.displayName),
        style: TextStyle(
          fontFamily: AppFonts.heading,
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  (Color, Color) _roleColors(String role) {
    switch (role) {
      case 'child':
        return (AppColors.success, AppColors.successBg);
      case 'admin':
        return (AppColors.violet, AppColors.violetBg);
      default:
        return (purple, AppColors.primaryLight);
    }
  }

  String _initials(String text) {
    final parts = text
        .split(RegExp(r'[\s@._-]+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  Widget _userCard(AdminManagedUser user, {bool first = false}) {
    final title = user.displayName.isEmpty ? user.email : user.displayName;
    final (roleFg, roleBg) = _roleColors(user.role);
    return InkWell(
      onTap: () => _openDetails(user),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.surfaceMuted)),
        ),
        child: Row(
          children: [
            _avatar(user),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: user.disabled ? grayText : darkText,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (user.displayName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: grayText, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            user.disabled
                ? const AppBadge(
                    label: 'Deactivated',
                    color: AppColors.danger,
                    background: AppColors.dangerBg,
                  )
                : AppBadge(
                    label: _roleLabel(user.role),
                    color: roleFg,
                    background: roleBg,
                  ),
          ],
        ),
      ),
    );
  }

  int _count(AdminUserFilter filter) {
    switch (filter) {
      case AdminUserFilter.all:
        return _users.length;
      case AdminUserFilter.guardians:
        return _users.where((u) => u.role == 'parent').length;
      case AdminUserFilter.children:
        return _users.where((u) => u.role == 'child').length;
      case AdminUserFilter.admins:
        return _users.where((u) => u.role == 'admin').length;
      case AdminUserFilter.deactivated:
        return _users.where((u) => u.disabled).length;
    }
  }

  static const Map<AdminUserFilter, String> _filterLabels = {
    AdminUserFilter.all: 'All',
    AdminUserFilter.guardians: 'Guardians',
    AdminUserFilter.children: 'Children',
    AdminUserFilter.admins: 'Admins',
    AdminUserFilter.deactivated: 'Deactivated',
  };

  @override
  Widget build(BuildContext context) {
    final visible = _visibleUsers;
    final bottom = widget.embedded ? kAdminDockClearance : 24.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.embedded
          ? null
          : WellScreenAppBar.subPage(
              title: 'Manage users',
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AppErrorState(
                  title: 'Could Not Load Users',
                  message: _loadError!,
                  onRetry: _load,
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  16,
                  widget.embedded ? 4 : 12,
                  16,
                  bottom,
                ),
                children: [
                  if (widget.embedded) ...[
                    AdminPageTitle(
                      'Users',
                      trailing: Text(
                        '${_users.length} account${_users.length == 1 ? '' : 's'}',
                        style: const TextStyle(color: grayText, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  AdminSearchField(
                    hint: 'Search by name or email',
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in AdminUserFilter.values)
                        AdminFilterChip(
                          label: '${_filterLabels[filter]} ${_count(filter)}',
                          selected: _filter == filter,
                          onTap: () => setState(() => _filter = filter),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    const AppEmptyState(
                      icon: Icons.people_outline_rounded,
                      title: 'No users found',
                      message: 'Try a different search or filter.',
                    )
                  else
                    BentoCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < visible.length; i++)
                            _userCard(visible[i], first: i == 0),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Users shown for the chosen filter chip and search text (email or name).
List<AdminManagedUser> filterAdminUsers(
  List<AdminManagedUser> users,
  String query,
  AdminUserFilter filter,
) {
  final q = query.trim().toLowerCase();
  return users.where((user) {
    switch (filter) {
      case AdminUserFilter.all:
        break;
      case AdminUserFilter.guardians:
        if (user.role != 'parent') return false;
      case AdminUserFilter.children:
        if (user.role != 'child') return false;
      case AdminUserFilter.admins:
        if (user.role != 'admin') return false;
      case AdminUserFilter.deactivated:
        if (!user.disabled) return false;
    }
    if (q.isEmpty) return true;
    return user.email.toLowerCase().contains(q) ||
        user.displayName.toLowerCase().contains(q);
  }).toList();
}

/// Why an administrator's new password for a user is refused, or null.
String? adminPasswordError(String password) =>
    password.length < 6 ? 'Password must be at least 6 characters.' : null;

const String adminUserUpdatedMessage = 'User details updated.';
