import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Shared pieces of the admin screens (design: "WellScreen Admin UI"
/// canvas), in the same palette and shapes as the guardian and child apps.

/// Bottom padding of a tab's list (the dock sits below the body, as in
/// the guardian app, so no extra clearance is needed).
const double kAdminDockClearance = 24;

/// Big Outfit page title with an optional line on the right.
class AdminPageTitle extends StatelessWidget {
  const AdminPageTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontFamily: AppFonts.heading,
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Section heading inside a page ("Today", "Recent activity").
class AdminSectionTitle extends StatelessWidget {
  const AdminSectionTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppFonts.heading,
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Rounded white search box.
class AdminSearchField extends StatelessWidget {
  const AdminSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        prefixIconColor: AppColors.textSecondary,
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

/// One filter pill: filled indigo when selected, white otherwise.
class AdminFilterChip extends StatelessWidget {
  const AdminFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  /// Text colour when not selected (amber for warnings, red for errors).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.border,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : (color ?? AppColors.textPrimary),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "system_patch_applied" -> "System patch applied".
String adminActionTitle(Object? action) {
  final text = (action ?? '').toString().trim().replaceAll('_', ' ');
  if (text.isEmpty) return 'Unknown action';
  return text[0].toUpperCase() + text.substring(1);
}

/// Level colours used by the log list and Home's recent activity.
/// Error red, warning amber, sync green, activity indigo.
(String, Color, Color) adminLogKind(Map<String, dynamic> data) {
  final level = (data['level'] ?? 'info').toString().toLowerCase();
  if (level == 'error') return ('Error', AppColors.danger, AppColors.dangerBg);
  if (level == 'warning') {
    return ('Warning', AppColors.warning, AppColors.warningBg);
  }
  if (adminLogIsSync(data)) {
    return ('Sync', AppColors.success, AppColors.successBg);
  }
  return ('Activity', AppColors.primary, AppColors.primaryLight);
}

bool adminLogIsSync(Map<String, dynamic> data) {
  final action = (data['action'] ?? '').toString().toLowerCase();
  return action.contains('sync') ||
      action.contains('sweep') ||
      action.contains('dispatch') ||
      action.contains('notification') ||
      action.contains('monitoring');
}

/// "05:12" for today and yesterday, "21 Nov 05:12" otherwise.
String adminLogTime(Object? value) {
  if (value is! Timestamp) return '';
  final d = value.toDate().toLocal();
  final hm = '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
  return hm;
}

/// "Today", "Yesterday" or "21 Nov 2026" - the day groups in the logs.
String adminLogDay(Object? value, {DateTime? now}) {
  if (value is! Timestamp) return 'Earlier';
  final d = value.toDate().toLocal();
  final today = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final start = DateTime(today.year, today.month, today.day);
  final diff = start.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
