import 'package:flutter/material.dart';

import '../../models/app_rule.dart';
import '../../models/installed_app_info.dart';
import '../../services/android_app_service.dart';
import '../../services/app_rules_service.dart';
import '../../services/site_category_service.dart';
import '../../theme/app_theme.dart';

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  final AndroidAppService _androidAppService = AndroidAppService();
  final AppRulesService _rulesService = AppRulesService();
  final SiteCategoryService _siteCategoryService = SiteCategoryService();
  final TextEditingController _websiteController = TextEditingController();

  WebsiteRules _websiteRules = const WebsiteRules();
  bool _loadingWebsites = true;
  bool _savingWebsite = false;
  String? _websiteError;

  bool _loading = true;
  bool _saving = false;
  String? _loadError;

  String _searchText = '';

  List<InstalledAppInfo> _installedApps = [];
  Map<String, AppRule> _rulesByPackage = {};

  @override
  void initState() {
    super.initState();
    _loadAppsAndRules();
    _loadWebsiteRules();
  }

  @override
  void dispose() {
    _websiteController.dispose();
    super.dispose();
  }

  Future<void> _loadWebsiteRules() async {
    if (_savingWebsite) return;
    setState(() {
      _loadingWebsites = true;
      _websiteError = null;
    });
    try {
      final rules = await _siteCategoryService.fetchGuardianWebsiteRules();
      if (!mounted) return;
      setState(() => _websiteRules = rules);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _websiteError =
            'Could not load website rules. Check your connection and retry.';
      });
    } finally {
      if (mounted) setState(() => _loadingWebsites = false);
    }
  }

  Future<void> _changeWebsiteRule(
    String input,
    WebsiteRuleAction? action,
  ) async {
    if (_savingWebsite || _loadingWebsites || _websiteError != null) return;
    final domain = WebsiteRules.normalizeDomain(input);
    if (domain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid website such as example.com.'),
        ),
      );
      return;
    }

    setState(() => _savingWebsite = true);
    try {
      final rules = await _siteCategoryService.updateGuardianWebsiteRule(
        domain,
        action,
      );
      if (!mounted) return;
      setState(() => _websiteRules = rules);
      if (action != null) _websiteController.clear();
      final message = switch (action) {
        WebsiteRuleAction.block => '$domain added to blocked websites.',
        WebsiteRuleAction.allow => '$domain added to allowed websites.',
        null => '$domain removed from custom website rules.',
      };
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : 'Could not save website rule. Check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _savingWebsite = false);
    }
  }

  Widget _websiteRuleList({
    required String title,
    required List<String> domains,
    required Color color,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              '$title (${domains.length})',
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        if (domains.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No websites added yet.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          )
        else
          ...domains.map(
            (domain) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(domain),
              trailing: IconButton(
                tooltip: 'Remove custom rule',
                onPressed: _savingWebsite
                    ? null
                    : () => _changeWebsiteRule(domain, null),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          ),
      ],
    );
  }

  Widget _websiteRulesCard() {
    final canEdit =
        !_loadingWebsites && !_savingWebsite && _websiteError == null;
    return Card(
      color: Colors.white,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const Icon(Icons.language_rounded, color: AppColors.primary),
        title: const Text(
          'Website Rules',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
        subtitle: const Text(
          'Block or allow specific websites.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        children: [
          if (_loadingWebsites)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            )
          else if (_websiteError != null) ...[
            Text(_websiteError!),
            TextButton(
              onPressed: _loadWebsiteRules,
              child: const Text('Retry'),
            ),
          ] else ...[
            const Text(
              'Rules apply to the website and its subdomains. '
              'Allowed websites override blocked and automatic category rules.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _websiteController,
              enabled: canEdit,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Website or URL',
                hintText: 'example.com',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canEdit
                        ? () => _changeWebsiteRule(
                            _websiteController.text,
                            WebsiteRuleAction.block,
                          )
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.danger,
                    ),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Block'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: canEdit
                        ? () => _changeWebsiteRule(
                            _websiteController.text,
                            WebsiteRuleAction.allow,
                          )
                        : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Allow'),
                  ),
                ),
              ],
            ),
            if (_savingWebsite) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Website changes save immediately.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            _websiteRuleList(
              title: 'Blocked Websites',
              domains: _websiteRules.blockedDomains,
              color: AppColors.danger,
              icon: Icons.block_rounded,
            ),
            const Divider(),
            _websiteRuleList(
              title: 'Allowed Websites',
              domains: _websiteRules.allowedDomains,
              color: AppColors.primary,
              icon: Icons.check_circle_outline,
            ),
          ],
        ],
      ),
    );
  }

  /// Was previously missing a try/catch entirely: if getInstalledApps() or
  /// getRules() ever threw (both already guard their own known failure
  /// modes internally, but neither guarantees it can never throw - e.g. a
  /// SharedPreferences platform-channel failure in getRules() happens
  /// before its own try block), setState(_loading = false) was never
  /// reached and this screen was stuck on an infinite spinner with no way
  /// out except leaving it. Now surfaces a real, retryable error state
  /// instead.
  Future<void> _loadAppsAndRules() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final apps = await _androidAppService.getInstalledApps();
      // fetchCurrentRules(), not getRules() - this screen edits and then
      // saves the FULL rule set back to Firestore (a whole-array
      // overwrite, not a per-rule merge), so it must start from whatever
      // is actually authoritative there, not just this device's local
      // cache. See fetchCurrentRules()'s doc comment for the data-loss
      // scenario that created (a fresh install/second device/cleared app
      // data silently wiping every rule the child device was mirroring).
      final rules = await _rulesService.fetchCurrentRules();

      setState(() {
        _installedApps = apps;
        _rulesByPackage = {for (final rule in rules) rule.packageName: rule};
      });
    } catch (e) {
      setState(() {
        _loadError = 'Could not load apps and rules. $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveAllRules() async {
    setState(() {
      _saving = true;
    });

    final rules = _rulesByPackage.values
        .where((rule) => rule.monitorEnabled || rule.restrictEnabled)
        .toList();

    await _rulesService.saveRules(rules);

    setState(() {
      _saving = false;
    });

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Rules saved successfully.')));
  }

  void _updateMonitor(InstalledAppInfo app, bool value) {
    final existing = _rulesByPackage[app.packageName];

    final updated = AppRule(
      appName: app.appName,
      packageName: app.packageName,
      monitorEnabled: value,
      restrictEnabled: existing?.restrictEnabled ?? false,
    );

    setState(() {
      if (!updated.monitorEnabled && !updated.restrictEnabled) {
        _rulesByPackage.remove(app.packageName);
      } else {
        _rulesByPackage[app.packageName] = updated;
      }
    });
  }

  void _updateRestrict(InstalledAppInfo app, bool value) {
    final existing = _rulesByPackage[app.packageName];

    final updated = AppRule(
      appName: app.appName,
      packageName: app.packageName,
      monitorEnabled: existing?.monitorEnabled ?? true,
      restrictEnabled: value,
    );

    setState(() {
      if (!updated.monitorEnabled && !updated.restrictEnabled) {
        _rulesByPackage.remove(app.packageName);
      } else {
        _rulesByPackage[app.packageName] = updated;
      }
    });
  }

  Future<void> _clearRules() async {
    await _rulesService.clearRules();

    setState(() {
      _rulesByPackage.clear();
    });

    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('App rules cleared.')));
  }

  @override
  Widget build(BuildContext context) {
    final monitoredRules =
        _rulesByPackage.values.where((rule) => rule.monitorEnabled).toList()
          ..sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );

    final restrictedRules =
        _rulesByPackage.values.where((rule) => rule.restrictEnabled).toList()
          ..sort(
            (a, b) =>
                a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
          );

    final filteredApps = _installedApps.where((app) {
      final query = _searchText.toLowerCase().trim();

      if (query.isEmpty) {
        return true;
      }

      return app.appName.toLowerCase().contains(query) ||
          app.packageName.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Rules'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _loadingWebsites || _savingWebsite
                ? null
                : () {
                    _loadAppsAndRules();
                    _loadWebsiteRules();
                  },
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: _saving ? null : _saveAllRules,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'SAVE',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
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
                  title: 'Could Not Load Rules',
                  message: _loadError!,
                  onRetry: _loadAppsAndRules,
                ),
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _PermissionCard(
                        monitoredCount: monitoredRules.length,
                        restrictedCount: restrictedRules.length,
                        onOpenAccessibility:
                            _androidAppService.openAccessibilitySettings,
                        onOpenUsageAccess:
                            _androidAppService.openUsageAccessSettings,
                        onClearRules: _clearRules,
                      ),
                      _ActiveRulesCard(
                        monitoredRules: monitoredRules,
                        restrictedRules: restrictedRules,
                      ),
                      _websiteRulesCard(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: TextField(
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search apps',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchText = value;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (filteredApps.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      child: AppEmptyState(
                        icon: Icons.apps_rounded,
                        title: 'No Apps Found',
                        message: _searchText.trim().isEmpty
                            ? 'No installed apps were detected on this device.'
                            : 'No installed apps match "$_searchText".',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 18),
                    sliver: SliverList.separated(
                      itemCount: filteredApps.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final app = filteredApps[index];
                        final rule = _rulesByPackage[app.packageName];

                        return _AppRuleRow(
                          app: app,
                          monitorEnabled: rule?.monitorEnabled ?? false,
                          restrictEnabled: rule?.restrictEnabled ?? false,
                          onMonitorChanged: (value) {
                            _updateMonitor(app, value);
                          },
                          onRestrictChanged: (value) {
                            _updateRestrict(app, value);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final int monitoredCount;
  final int restrictedCount;
  final VoidCallback onOpenAccessibility;
  final VoidCallback onOpenUsageAccess;
  final VoidCallback onClearRules;

  const _PermissionCard({
    required this.monitoredCount,
    required this.restrictedCount,
    required this.onOpenAccessibility,
    required this.onOpenUsageAccess,
    required this.onClearRules,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primaryLight,
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'App Rules Control',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _CountBadge(
                    label: 'Monitored',
                    count: monitoredCount,
                    icon: Icons.visibility_rounded,
                    color: AppColors.info,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountBadge(
                    label: 'Restricted',
                    count: restrictedCount,
                    icon: Icons.block_rounded,
                    color: AppColors.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Enable WellScreen in Accessibility Settings so this device can detect restricted apps when they are opened.',
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onOpenAccessibility,
                    child: const Text(
                      'Accessibility',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onOpenUsageAccess,
                    child: const Text(
                      'Usage Access',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onClearRules,
                icon: const Icon(Icons.delete_outline),
                label: const Text(
                  'Clear app rules',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _CountBadge({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '$count $label',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveRulesCard extends StatelessWidget {
  final List<AppRule> monitoredRules;
  final List<AppRule> restrictedRules;

  const _ActiveRulesCard({
    required this.monitoredRules,
    required this.restrictedRules,
  });

  @override
  Widget build(BuildContext context) {
    final hasRules = monitoredRules.isNotEmpty || restrictedRules.isNotEmpty;

    return Card(
      color: Colors.white,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ExpansionTile(
        initiallyExpanded: hasRules,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: const Icon(
          Icons.rule_folder_rounded,
          color: AppColors.primary,
        ),
        title: const Text(
          'Active App Rules',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          hasRules
              ? 'View monitored and restricted apps'
              : 'No apps selected yet',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        children: [
          if (!hasRules)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Turn on Monitor or Restrict below to add app rules.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          if (monitoredRules.isNotEmpty) ...[
            _RuleGroup(
              title: 'Monitored Apps',
              icon: Icons.visibility_rounded,
              color: AppColors.info,
              rules: monitoredRules,
            ),
            const SizedBox(height: 12),
          ],
          if (restrictedRules.isNotEmpty)
            _RuleGroup(
              title: 'Restricted Apps',
              icon: Icons.block_rounded,
              color: AppColors.danger,
              rules: restrictedRules,
            ),
        ],
      ),
    );
  }
}

class _RuleGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<AppRule> rules;

  const _RuleGroup({
    required this.title,
    required this.icon,
    required this.color,
    required this.rules,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: rules.map((rule) {
            return Chip(
              avatar: CircleAvatar(
                backgroundColor: color,
                child: Text(
                  rule.appName.isNotEmpty ? rule.appName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              label: Text(
                rule.appName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
              backgroundColor: color.withValues(alpha: 0.08),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _AppRuleRow extends StatelessWidget {
  final InstalledAppInfo app;
  final bool monitorEnabled;
  final bool restrictEnabled;
  final ValueChanged<bool> onMonitorChanged;
  final ValueChanged<bool> onRestrictChanged;

  const _AppRuleRow({
    required this.app,
    required this.monitorEnabled,
    required this.restrictEnabled,
    required this.onMonitorChanged,
    required this.onRestrictChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      constraints: const BoxConstraints(minHeight: 86),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryLight,
            child: Text(
              app.appName.isNotEmpty ? app.appName[0].toUpperCase() : '?',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CompactRuleSwitch(
            label: 'Monitor',
            value: monitorEnabled,
            onChanged: onMonitorChanged,
          ),
          const SizedBox(width: 6),
          _CompactRuleSwitch(
            label: 'Restrict',
            value: restrictEnabled,
            onChanged: onRestrictChanged,
          ),
        ],
      ),
    );
  }
}

class _CompactRuleSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactRuleSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Transform.scale(
            scale: 0.72,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
