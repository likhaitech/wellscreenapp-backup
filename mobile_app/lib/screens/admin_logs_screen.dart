import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';

/// System-wide audit log for admins - every action recorded server-side
/// (grant_admin.py, backend services, etc.) into the `system_logs`
/// collection. Laid out like the design D "System logs" mockup: search,
/// pill tabs (All / Activity / Errors / Sync) and one card of rows, each
/// with a coloured kind pill. Raw details stay collapsed until tapped.
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
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    final ampm = date.hour < 12 ? 'AM' : 'PM';

    return '${months[date.month - 1]} ${date.day} · '
        '$hour:$minute:$second $ampm';
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

  /// Pill label + colours for a log row, as in the mockup:
  /// Error (red), Warning (amber), Sync (teal), Activity (indigo).
  (String, Color, Color) _kind(Map<String, dynamic> data) {
    final level = (data['level'] ?? 'info').toString().toLowerCase();
    if (level == 'error') {
      return ('Error', AppColors.danger, AppColors.dangerBg);
    }
    if (level == 'warning') {
      return ('Warning', AppColors.warning, AppColors.warningBg);
    }
    if (_isSync(data)) {
      return ('Sync', AppColors.success, AppColors.successBg);
    }
    return ('Activity', AppColors.primary, AppColors.primaryLight);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WellScreenAppBar.subPage(title: 'System logs'),
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
              icon: Icons.description_outlined,
              title: 'System logs',
              message: 'No system logs recorded yet.',
            );
          }

          final attentionCount = documents.where((doc) {
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _searchField(),
                const SizedBox(height: 12),
                WellScreenPillTabs(
                  labels: [
                    'All',
                    'Activity',
                    'Errors ($attentionCount)',
                    'Sync',
                  ],
                  selected: _filter.index,
                  onChanged: (i) =>
                      setState(() => _filter = _LevelFilter.values[i]),
                ),
                const SizedBox(height: 12),
                if (visibleDocs.isEmpty)
                  const AppEmptyState(
                    icon: Icons.check_circle_rounded,
                    title: 'No matching logs',
                    message: 'No entries match this filter or search in the '
                        'most recent 100 log entries.',
                  )
                else
                  BentoCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < visibleDocs.length; i++)
                          _logRow(visibleDocs[i], first: i == 0),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Search logs',
        prefixIcon: const Icon(Icons.search_rounded),
        prefixIconColor: AppColors.textSecondary,
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

  Widget _logRow(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    bool first = false,
  }) {
    final data = document.data();

    final action = (data['action'] ?? 'Unknown action').toString();
    final message = (data['message'] ?? '').toString();
    final actorUid = data['actor_uid']?.toString();
    final timestamp = _formatTimestamp(data['timestamp']);
    final details = _formatDetails(data['details']);
    final (label, color, background) = _kind(data);
    final expanded = _expandedDocIds.contains(document.id);
    final hasMore =
        details.isNotEmpty || (actorUid != null && actorUid.isNotEmpty);

    return InkWell(
      onTap: hasMore
          ? () => setState(() {
                if (expanded) {
                  _expandedDocIds.remove(document.id);
                } else {
                  _expandedDocIds.add(document.id);
                }
              })
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 74,
              child: Align(
                alignment: Alignment.topLeft,
                child: AppBadge(
                  label: label,
                  color: color,
                  background: background,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.isNotEmpty ? '$action: $message' : action,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timestamp,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        [
                          if (actorUid != null && actorUid.isNotEmpty)
                            'actor: $actorUid',
                          if (details.isNotEmpty) details,
                        ].join('\n'),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (hasMore)
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}
