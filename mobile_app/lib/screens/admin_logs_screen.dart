import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/wellscreen_ui.dart';

/// System-wide audit log for admins - every action recorded server-side
/// (grant_admin.py, backend services, etc.) into the `system_logs`
/// collection. Laid out like the "WellScreen Admin UI" design: search,
/// filter pills (All / Activity / Warning / Error / Sync), entries grouped
/// by day with a coloured dot. Raw details stay collapsed until tapped.
class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key, this.embedded = false});

  /// True inside the admin home's tabs: no app bar of its own.
  final bool embedded;

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

enum AdminLogFilter { all, activity, warnings, errors, sync }

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  AdminLogFilter _filter = AdminLogFilter.all;
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

  String _level(Map<String, dynamic> data) => adminLogLevel(data);

  bool _matches(Map<String, dynamic> data) =>
      adminLogMatches(data, _filter, _search);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.embedded
          ? null
          : const WellScreenAppBar.subPage(title: 'System logs'),
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
          final warnings =
              documents.where((d) => _level(d.data()) == 'warning').length;
          final errors =
              documents.where((d) => _level(d.data()) == 'error').length;
          final visibleDocs =
              documents.where((doc) => _matches(doc.data())).toList();

          // Day groups, newest first (the query is already ordered).
          final groups =
              <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          for (final doc in visibleDocs) {
            groups
                .putIfAbsent(adminLogDay(doc.data()['timestamp']), () => [])
                .add(doc);
          }

          return RefreshIndicator(
            onRefresh: () async {
              await _logsQuery.get();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                widget.embedded ? 4 : 12,
                16,
                widget.embedded ? kAdminDockClearance : 24,
              ),
              children: [
                if (widget.embedded) ...[
                  const AdminPageTitle('System logs'),
                  const SizedBox(height: 14),
                ],
                AdminSearchField(
                  hint: 'Search logs',
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _chip('All', AdminLogFilter.all),
                    _chip('Activity', AdminLogFilter.activity),
                    _chip(
                      warnings > 0 ? 'Warning $warnings' : 'Warning',
                      AdminLogFilter.warnings,
                      color: AppColors.warning,
                    ),
                    _chip(
                      errors > 0 ? 'Error $errors' : 'Error',
                      AdminLogFilter.errors,
                      color: AppColors.danger,
                    ),
                    _chip('Sync', AdminLogFilter.sync),
                  ],
                ),
                const SizedBox(height: 4),
                if (documents.isEmpty)
                  const AppEmptyState(
                    icon: Icons.description_outlined,
                    title: 'System logs',
                    message: 'No system logs recorded yet.',
                  )
                else if (visibleDocs.isEmpty)
                  const AppEmptyState(
                    icon: Icons.check_circle_rounded,
                    title: 'No matching logs',
                    message: 'No entries match this filter or search in the '
                        'most recent 100 log entries.',
                  )
                else
                  for (final entry in groups.entries) ...[
                    const SizedBox(height: 12),
                    AdminSectionTitle(entry.key),
                    const SizedBox(height: 8),
                    BentoCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < entry.value.length; i++)
                            _logRow(entry.value[i], first: i == 0),
                        ],
                      ),
                    ),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label, AdminLogFilter filter, {Color? color}) {
    return AdminFilterChip(
      label: label,
      selected: _filter == filter,
      color: color,
      onTap: () => setState(() => _filter = filter),
    );
  }

  Widget _logRow(
    QueryDocumentSnapshot<Map<String, dynamic>> document, {
    bool first = false,
  }) {
    final data = document.data();

    final title = adminActionTitle(data['action']);
    final message = (data['message'] ?? '').toString();
    final actorUid = data['actor_uid']?.toString();
    final time = adminLogTime(data['timestamp']);
    final details = adminLogDetails(data['details']);
    final (kind, color, _) = adminLogKind(data);
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: first
              ? null
              : const Border(top: BorderSide(color: AppColors.surfaceMuted)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        time,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontFeatures: kTabularFigures,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message.isNotEmpty ? '$kind · $message' : kind,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
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
            if (hasMore) ...[
              const SizedBox(width: 4),
              Icon(
                expanded
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                color: AppColors.textSecondary,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String adminLogDetails(dynamic details) {
  if (details == null) return '';
  if (details is Map) {
    return details.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\n');
  }
  return details.toString();
}

String adminLogLevel(Map<String, dynamic> data) =>
    (data['level'] ?? 'info').toString().toLowerCase();

/// True when a log entry passes the chosen filter chip and search text.
bool adminLogMatches(
  Map<String, dynamic> data,
  AdminLogFilter filter,
  String search,
) {
  final level = adminLogLevel(data);
  final problem = level == 'error' || level == 'warning';
  switch (filter) {
    case AdminLogFilter.errors:
      if (level != 'error') return false;
    case AdminLogFilter.warnings:
      if (level != 'warning') return false;
    case AdminLogFilter.sync:
      if (!adminLogIsSync(data)) return false;
    case AdminLogFilter.activity:
      if (problem || adminLogIsSync(data)) return false;
    case AdminLogFilter.all:
      break;
  }
  final q = search.trim().toLowerCase();
  if (q.isEmpty) return true;
  final haystack = [
    data['action'],
    adminActionTitle(data['action']),
    data['message'],
    data['actor_uid'],
    data['level'],
    adminLogDetails(data['details']),
  ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
  return haystack.contains(q);
}
