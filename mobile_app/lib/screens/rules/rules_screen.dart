import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/app_rule.dart';
import '../../models/installed_app_info.dart';
import '../../services/android_app_service.dart';
import '../../services/app_rules_service.dart';
import '../../services/quick_block_sites.dart';
import '../../services/site_category_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wellscreen_ui.dart';
import '../../widgets/brand_app_icon.dart';
import 'schedules_card.dart';

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

  /// True when no paired child has synced its app list yet, so the list
  /// shown is this phone's own apps.
  bool _usingLocalAppList = false;
  Map<String, AppRule> _rulesByPackage = {};
  /// Real icons from the child's usage report (see BrandAppIcon).
  final Map<String, String> _iconByPackage = {};

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

  /// Quick block: blocks (or unblocks) every website of a popular app in
  /// one tap, even if the child never installed the app.
  Future<void> _toggleQuickBlock(QuickBlockSite site) async {
    if (_savingWebsite || _loadingWebsites || _websiteError != null) return;
    final unblock = site.isBlockedIn(_websiteRules.blockedDomains);
    setState(() => _savingWebsite = true);
    try {
      var rules = _websiteRules;
      for (final domain in site.domains) {
        rules = await _siteCategoryService.updateGuardianWebsiteRule(
          domain,
          unblock ? null : WebsiteRuleAction.block,
        );
      }
      if (!mounted) return;
      setState(() => _websiteRules = rules);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unblock
                ? '${site.name} websites unblocked.'
                : '${site.name} websites blocked: ${site.domains.join(', ')}.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : 'Could not save website rule. Check your connection and try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      await _loadWebsiteRules();
    } finally {
      if (mounted) setState(() => _savingWebsite = false);
    }
  }

  Widget _quickBlockSection(bool canEdit) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick block',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        const Text(
          'Blocks the app\'s websites in every browser, even if the app is '
          'not installed. Tap again to unblock.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final site in quickBlockSites)
              FilterChip(
                avatar: BrandAppIcon(
                  label: site.name,
                  domain: site.domains.first,
                  size: 22,
                ),
                showCheckmark: false,
                label: Text(site.name),
                selected: site.isBlockedIn(_websiteRules.blockedDomains),
                onSelected: canEdit && !_savingWebsite
                    ? (_) => _toggleQuickBlock(site)
                    : null,
              ),
          ],
        ),
      ],
    );
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
              leading: BrandAppIcon(label: domain, domain: domain, size: 32),
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
    return BentoCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
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
                floatingLabelBehavior: FloatingLabelBehavior.never,
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide.none,
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
                      backgroundColor: AppColors.ink,
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
            const SizedBox(height: 14),
            _quickBlockSection(canEdit),
            const SizedBox(height: 8),
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
  /// Apps to show for rule editing: the apps installed on the guardian's
  /// paired children's phones (synced as `installedApps`, plus anything
  /// they used today from `latestUsageReport.allApps`), not the apps on
  /// this guardian's own phone. Falls back to this phone's list only when
  /// no child has synced yet, and says so in [_usingLocalAppList].
  Future<List<InstalledAppInfo>> _loadChildApps() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final byPackage = <String, InstalledAppInfo>{};

    if (uid != null) {
      final children = await FirebaseFirestore.instance
          .collection('child_profiles')
          .where('parentId', isEqualTo: uid)
          .get();

      void add(dynamic raw, String nameKey) {
        if (raw is! Map) return;
        final package = (raw['packageName'] ?? '').toString().trim();
        if (package.isEmpty || byPackage.containsKey(package)) return;
        final name = (raw[nameKey] ?? '').toString().trim();
        byPackage[package] = InstalledAppInfo(
          appName: name.isEmpty ? package : name,
          packageName: package,
        );
      }

      for (final child in children.docs) {
        final data = child.data();
        if (data['pairingStatus'] == 'unpaired') continue;
        final installed = data['installedApps'];
        if (installed is List) {
          for (final app in installed) {
            add(app, 'appName');
          }
        }
        final report = data['latestUsageReport'];
        final used = report is Map ? report['allApps'] : null;
        if (used is List) {
          for (final app in used) {
            add(app, 'displayName');
            if (app is Map) {
              final package = (app['packageName'] ?? '').toString();
              final icon = app['iconBase64'];
              if (package.isNotEmpty && icon is String && icon.isNotEmpty) {
                _iconByPackage[package] = icon;
              }
            }
          }
        }
      }
    }

    if (byPackage.isEmpty) {
      _usingLocalAppList = true;
      return _androidAppService.getInstalledApps();
    }

    _usingLocalAppList = false;
    final apps = byPackage.values.toList()
      ..sort(
        (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
      );
    return apps;
  }

  Future<void> _loadAppsAndRules() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final apps = await _loadChildApps();
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
      appBar: WellScreenAppBar.subPage(
        title: 'App Rules',
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _loadingWebsites || _savingWebsite
                ? null
                : () {
                    _loadAppsAndRules();
                    _loadWebsiteRules();
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.settings_outlined),
            onSelected: (value) {
              if (value == 'accessibility') {
                _androidAppService.openAccessibilitySettings();
              } else if (value == 'usage') {
                _androidAppService.openUsageAccessSettings();
              } else if (value == 'clear') {
                _clearRules();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'accessibility',
                child: Text('Accessibility settings'),
              ),
              PopupMenuItem(value: 'usage', child: Text('Usage access')),
              PopupMenuItem(value: 'clear', child: Text('Clear all rules')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: AppPillButton(
                  label: 'Save Rules',
                  expand: true,
                  loading: _saving,
                  onPressed: _saveAllRules,
                ),
              ),
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                    child: Column(
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            isDense: true,
                            filled: true,
                            fillColor: AppColors.surfaceMuted,
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: AppColors.textSecondary,
                            ),
                            hintText: 'Search apps',
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                          onChanged: (value) {
                            setState(() {
                              _searchText = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _SummaryTile(
                                count: monitoredRules.length,
                                label: 'Monitored',
                                icon: Icons.info_outline_rounded,
                                background: AppColors.primaryLight,
                                foreground: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _SummaryTile(
                                count: restrictedRules.length,
                                label: 'Restricted',
                                icon: Icons.lock_outline_rounded,
                                background: const Color(0xFFFECACA),
                                foreground: const Color(0xFF991B1B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        const SchedulesCard(),
                        const SizedBox(height: 14),
                        _websiteRulesCard(),
                        if (_usingLocalAppList) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Your child\'s phone has not sent its app list '
                            'yet, so these are the apps on this phone. Open '
                            'WellScreen on the child\'s phone to sync it.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
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
                            ? 'No apps have been reported by your child\'s phone yet.'
                            : 'No installed apps match "$_searchText".',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    sliver: DecoratedSliver(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.card),
                        border: Border.all(color: AppColors.border),
                      ),
                      sliver: SliverList.separated(
                        itemCount: filteredApps.length + 1,
                        separatorBuilder: (context, index) => index == 0
                            ? const SizedBox.shrink()
                            : const Divider(indent: 14, endIndent: 14),
                        itemBuilder: (context, index) {
                          if (index == 0) return const _PermissionsHeader();

                          final app = filteredApps[index - 1];
                          final rule = _rulesByPackage[app.packageName];

                          return _AppRuleRow(
                            app: app,
                            iconBase64: _iconByPackage[app.packageName],
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
                  ),
              ],
            ),
    );
  }
}

/// Tinted count tile ("12 Monitored", "3 Restricted").
class _SummaryTile extends StatelessWidget {
  final int count;
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  const _SummaryTile({
    required this.count,
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                    fontFeatures: kTabularFigures,
                  ),
                ),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(color: foreground, fontSize: 14)),
              ],
            ),
          ),
          Icon(icon, color: foreground, size: 18),
        ],
      ),
    );
  }
}

/// "App Permissions" title with the Monitor / Restrict column headers.
class _PermissionsHeader extends StatelessWidget {
  const _PermissionsHeader();

  @override
  Widget build(BuildContext context) {
    const columnStyle = TextStyle(
      color: AppColors.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );

    return const Padding(
      padding: EdgeInsets.fromLTRB(14, 14, 10, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'App Permissions',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Monitor',
              textAlign: TextAlign.center,
              style: columnStyle,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              'Restrict',
              textAlign: TextAlign.center,
              style: columnStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppRuleRow extends StatelessWidget {
  final InstalledAppInfo app;
  final String? iconBase64;
  final bool monitorEnabled;
  final bool restrictEnabled;
  final ValueChanged<bool> onMonitorChanged;
  final ValueChanged<bool> onRestrictChanged;

  const _AppRuleRow({
    required this.app,
    this.iconBase64,
    required this.monitorEnabled,
    required this.restrictEnabled,
    required this.onMonitorChanged,
    required this.onRestrictChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: Row(
        children: [
          BrandAppIcon(
            label: app.appName,
            packageName: app.packageName,
            iconBase64: iconBase64,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RuleSwitch(
            label: 'Monitor ${app.appName}',
            value: monitorEnabled,
            onChanged: onMonitorChanged,
          ),
          _RuleSwitch(
            label: 'Restrict ${app.appName}',
            value: restrictEnabled,
            onChanged: onRestrictChanged,
          ),
        ],
      ),
    );
  }
}

class _RuleSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _RuleSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      child: Semantics(
        label: label,
        child: Transform.scale(
          scale: 0.82,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
