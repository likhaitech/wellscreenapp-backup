import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// System-wide audit log for admins - every action recorded server-side
/// (grant_admin.py, backend services, etc.) into the `system_logs`
/// collection. Previously a raw ListView.separated of plain Material
/// Cards showing every entry fully expanded, all at once, in strict
/// chronological order - fine for a handful of entries but read as an
/// undifferentiated wall of text once there were dozens, with no way to
/// tell whether anything actually needed attention without reading every
/// entry. Redesigned to match the rest of the app's AppTheme card
/// language (AppCard/AppSectionHeader/AppBadge) and to apply the same
/// "important things first, detail behind a tap" pattern already used on
/// the parent Reports tab's Alerts section (see reports_screen.dart):
/// a summary card up top counts entries needing attention, an
/// "Errors & warnings only" filter hides routine info-level noise, and
/// each entry's raw details payload stays collapsed until tapped instead
/// of always rendering a multi-line key:value dump inline.
class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

enum _LevelFilter { all, activity, errors, sync }

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  _LevelFilter _filter = _LevelFilter.all;
  String _search = '';

  // Keyed by Firestore document id (stable and unique) rather than list
  // position, so which entries are expanded survives the list reordering
  // itself when new log entries stream in.
  final Set<String> _expandedDocIds = {};

  Query<Map<String, dynamic>> get _logsQuery {
    return FirebaseFirestore.instance
        .collection('system_logs')
        .orderBy('timestamp', descending: true)
        .limit(100);
  }

  String _formatTimestamp(dynamic value) {
    if (value is! Timestamp) {
      return 'No timestamp';
    }

    final date = value.toDate().toLocal();

    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');

    return '$year-$month-$day $hour:$minute:$second';
  }

  String _formatDetails(dynamic details) {
    if (details == null) {
      return '';
    }

    if (details is Map) {
      return details.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join('\n');
    }

    return details.toString();
  }

  bool _isSync(Map<String, dynamic> data) {
    final action = (data['action'] ?? '').toString().toLowerCase();
    return action.contains('sync') ||
        action.contains('sweep') ||
        action.contains('dispatch') ||
        action.contains('notification') ||
        action.contains('monitoring');
  }

  bool _matches(Map<String, dynamic> data) {
    final level = (data['level'] ?? 'info').toString();
    final isError = _needsAttention(level);

    switch (_filter) {
      case _LevelFilter.errors:
        if (!isError) return false;
        break;
      case _LevelFilter.sync:
        if (!_isSync(data)) return false;
        break;
      case _LevelFilter.activity:
        if (isError || _isSync(data)) return false;
        break;
      case _LevelFilter.all:
        break;
    }

    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return true;

    final haystack = [
      data['action'],
      data['message'],
      data['actor_uid'],
      data['level'],
      _formatDetails(data['details']),
    ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');

    return haystack.contains(q);
  }

  bool _needsAttention(String level) {
    final normalized = level.toLowerCase();
    return normalized == 'error' || normalized == 'warning';
  }

  IconData _levelIcon(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return Icons.error_outline;
      case 'warning':
        return Icons.warning_amber_outlined;
      default:
        return Icons.info_outline;
    }
  }

  (Color, Color) _levelColors(String level) {
    switch (level.toLowerCase()) {
      case 'error':
        return (AppColors.danger, AppColors.dangerBg);
      case 'warning':
        return (AppColors.warning, AppColors.warningBg);
      default:
        return (AppColors.info, AppColors.infoBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Logs')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _logsQuery.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Unable to load system logs.\n\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final documents = snapshot.data?.docs ?? [];

          if (documents.isEmpty) {
            return const AppEmptyState(
              icon: Icons.shield_rounded,
              title: 'System Logs',
              message: 'No system logs recorded yet.',
            );
          }

          final attentionCount =
              documents.where((doc) {
                final level = (doc.data()['level'] ?? 'info').toString();
                return _needsAttention(level);
              }).length;

          final visibleDocs =
              documents.where((doc) => _matches(doc.data())).toList();

          return RefreshIndicator(
            onRefresh: () async {
              await _logsQuery.get();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _summaryCard(total: documents.length, attentionCount: attentionCount),
                const SizedBox(height: AppSpacing.md),
                if (visibleDocs.isEmpty)
                  const AppEmptyState(
                    icon: Icons.check_circle_rounded,
                    title: 'No Matching Logs',
                    message: 'No entries match this filter or search in the '
                        'most recent 100 log entries.',
                  )
                else
                  for (final document in visibleDocs) ...[
                    _logEntryCard(document),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryCard({required int total, required int attentionCount}) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.shield_rounded,
            iconColor: AppColors.primary,
            title: 'System Logs',
            trailing: attentionCount > 0
                ? AppBadge(
                    label:
                        '$attentionCount need${attentionCount == 1 ? 's' : ''} attention',
                    color: AppColors.danger,
                    background: AppColors.dangerBg,
                    icon: Icons.error_rounded,
                  )
                : const AppBadge(
                    label: 'All OK',
                    color: AppColors.success,
                    background: AppColors.successBg,
                    icon: Icons.check_circle_rounded,
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Most recent $total entr${total == 1 ? 'y' : 'ies'} recorded server-side.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search logs',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filterChip(
                label: 'All',
                selected: _filter == _LevelFilter.all,
                onTap: () => setState(() => _filter = _LevelFilter.all),
              ),
              _filterChip(
                label: 'Activity',
                selected: _filter == _LevelFilter.activity,
                onTap: () => setState(() => _filter = _LevelFilter.activity),
              ),
              _filterChip(
                label: 'Errors ($attentionCount)',
                selected: _filter == _LevelFilter.errors,
                onTap: () => setState(() => _filter = _LevelFilter.errors),
              ),
              _filterChip(
                label: 'Sync',
                selected: _filter == _LevelFilter.sync,
                onTap: () => setState(() => _filter = _LevelFilter.sync),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _logEntryCard(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final data = document.data();

    final level = (data['level'] ?? 'info').toString();
    final action = (data['action'] ?? 'Unknown action').toString();
    final message = (data['message'] ?? '').toString();
    final actorUid = data['actor_uid']?.toString();
    final timestamp = _formatTimestamp(data['timestamp']);
    final details = _formatDetails(data['details']);
    final (color, background) = _levelColors(level);
    final expanded = _expandedDocIds.contains(document.id);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_levelIcon(level), color: color, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  action,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              AppBadge(
                label: level.toUpperCase(),
                color: color,
                background: background,
              ),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            actorUid != null && actorUid.isNotEmpty
                ? '$timestamp · actor $actorUid'
                : timestamp,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.button),
              onTap: () => setState(() {
                if (expanded) {
                  _expandedDocIds.remove(document.id);
                } else {
                  _expandedDocIds.add(document.id);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      expanded ? 'Hide details' : 'Show details',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: AppColors.primary,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              const Divider(height: AppSpacing.lg),
              SelectableText(
                details,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
