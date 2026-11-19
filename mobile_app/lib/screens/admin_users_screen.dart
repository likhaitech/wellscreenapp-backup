import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/admin_users_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';

enum _UserFilter { all, guardians, children, admins, deactivated }

/// Admin "Manage Users" module (manuscript use case "Manage Users"):
/// retrieve the user list, view a user's details, update a user record,
/// deactivate / reactivate an account, and delete an account.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

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
  _UserFilter _filter = _UserFilter.all;
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

  List<AdminManagedUser> get _visibleUsers {
    final query = _query.trim().toLowerCase();
    return _users.where((user) {
      switch (_filter) {
        case _UserFilter.all:
          break;
        case _UserFilter.guardians:
          if (user.role != 'parent') return false;
          break;
        case _UserFilter.children:
          if (user.role != 'child') return false;
          break;
        case _UserFilter.admins:
          if (user.role != 'admin') return false;
          break;
        case _UserFilter.deactivated:
          if (!user.disabled) return false;
          break;
      }
      if (query.isEmpty) return true;
      return user.email.toLowerCase().contains(query) ||
          user.displayName.toLowerCase().contains(query);
    }).toList();
  }

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
      _toast('User details updated.');
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
    if (newPassword.length < 6) {
      _toast('Password must be at least 6 characters.');
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

  void _openDetails(AdminManagedUser user) {
    final isSelf = user.uid == _currentUid;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayName.isEmpty ? user.email : user.displayName,
                    style: const TextStyle(
                      color: darkText,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(user.email, style: const TextStyle(color: grayText)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppBadge(
                        label: _roleLabel(user.role),
                        color: purple,
                        background: AppColors.primaryLight,
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
                  const SizedBox(height: 16),
                  _detailRow('User ID', user.uid),
                  _detailRow('Created', _formatDate(user.createdAt)),
                  _detailRow('Last sign-in', _formatDate(user.lastSignInAt)),
                  const SizedBox(height: 12),
                  _sheetAction(
                    icon: Icons.edit_rounded,
                    label: 'Edit details',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _editUser(user);
                    },
                  ),
                  _sheetAction(
                    icon: Icons.password_rounded,
                    label: 'Set new password',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _resetPassword(user);
                    },
                  ),
                  if (!isSelf)
                    _sheetAction(
                      icon: user.disabled
                          ? Icons.check_circle_outline_rounded
                          : Icons.block_rounded,
                      label: user.disabled
                          ? 'Reactivate account'
                          : 'Deactivate account',
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _toggleDisabled(user);
                      },
                    ),
                  if (!isSelf)
                    _sheetAction(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete account',
                      color: AppColors.danger,
                      onTap: () {
                        Navigator.pop(sheetContext);
                        _deleteUser(user);
                      },
                    ),
                  if (isSelf)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'This is your own admin account, so it cannot be '
                        'deactivated or deleted here.',
                        style: TextStyle(color: grayText),
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

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: grayText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: darkText)),
          ),
        ],
      ),
    );
  }

  Widget _sheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = darkText,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
      onTap: onTap,
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        hintText: 'Search by name or email',
        prefixIcon: const Icon(Icons.search_rounded),
        prefixIconColor: grayText,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Text(
                _initials(user.displayName.isEmpty
                    ? user.email
                    : user.displayName),
                style: const TextStyle(
                  fontFamily: AppFonts.heading,
                  color: purple,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: darkText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AppBadge(
                  label: _roleLabel(user.role),
                  color: roleFg,
                  background: roleBg,
                ),
                if (user.disabled) ...[
                  const SizedBox(height: 4),
                  const AppBadge(
                    label: 'Deactivated',
                    color: AppColors.danger,
                    background: AppColors.dangerBg,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleUsers;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: WellScreenAppBar.subPage(
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: _searchField(),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: WellScreenPillTabs(
                    labels: [
                      'All (${_users.length})',
                      'Guardians',
                      'Children',
                      'Admins',
                      'Deactivated',
                    ],
                    selected: _filter.index,
                    onChanged: (i) =>
                        setState(() => _filter = _UserFilter.values[i]),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: visible.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(20),
                            children: const [
                              AppEmptyState(
                                icon: Icons.people_outline_rounded,
                                title: 'No users found',
                                message:
                                    'Try a different search or filter.',
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            children: [
                              BentoCard(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
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
                ),
              ],
            ),
    );
  }
}
