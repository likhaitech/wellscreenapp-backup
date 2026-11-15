import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/admin_settings_api_service.dart';
import '../theme/app_theme.dart';

/// Manuscript "Manage System Settings -> Upload System Patch": the admin
/// supplies a configuration patch, the server validates it (unknown keys,
/// wrong types and out-of-range values are rejected with no change) and
/// only then applies it and writes an audit log entry.
class AdminPatchScreen extends StatefulWidget {
  const AdminPatchScreen({super.key});

  @override
  State<AdminPatchScreen> createState() => _AdminPatchScreenState();
}

class _AdminPatchScreenState extends State<AdminPatchScreen> {
  static const String _template = '''{
  "version": "1.0.1",
  "description": "Lower default daily limit",
  "settings": {
    "default_daily_limit_minutes": 120,
    "focus_mode_enabled": true
  }
}''';

  final AdminSettingsApiService _api = AdminSettingsApiService();
  final TextEditingController _controller =
      TextEditingController(text: _template);

  bool _busy = false;
  List<String> _errors = [];
  String? _success;
  Map<String, dynamic>? _validChanges;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _parse() {
    try {
      final decoded = jsonDecode(_controller.text);
      if (decoded is Map<String, dynamic>) return decoded;
      setState(() => _errors = ['Patch must be a JSON object.']);
    } catch (e) {
      setState(() => _errors = ['Invalid JSON: ${e.toString()}']);
    }
    return null;
  }

  Future<void> _run({required bool validateOnly}) async {
    setState(() {
      _errors = [];
      _success = null;
      _validChanges = null;
    });

    final patch = _parse();
    if (patch == null) return;

    setState(() => _busy = true);

    try {
      final result = await _api.applyPatch(patch, validateOnly: validateOnly);
      if (!mounted) return;

      final changes = Map<String, dynamic>.from(result['changes'] ?? {});

      setState(() {
        _validChanges = changes;
        _success = validateOnly
            ? 'Patch is valid. Nothing has been applied yet.'
            : 'Patch applied and logged.';
      });
    } on SystemPatchRejected catch (e) {
      if (!mounted) return;
      setState(() => _errors = e.errors);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errors = ['Request failed: $e']);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmApply() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apply system patch?'),
        content: const Text(
          'This updates the system-wide settings and is recorded in the '
          'system logs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (ok == true) await _run(validateOnly: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('System Patch')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionHeader(
                  icon: Icons.system_update_alt_rounded,
                  iconColor: AppColors.primary,
                  title: 'Configuration Patch',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Paste a patch as JSON. It is validated first; an invalid '
                  'patch is rejected and changes nothing.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _controller,
                  maxLines: 12,
                  minLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => _run(validateOnly: true),
                        child: const Text('Validate'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _confirmApply,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Apply patch'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppBadge(
                    label: 'PATCH REJECTED - NO CHANGES MADE',
                    color: AppColors.danger,
                    background: AppColors.dangerBg,
                    icon: Icons.error_rounded,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final err in _errors)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('- $err'),
                    ),
                ],
              ),
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppBadge(
                    label: _success!.toUpperCase(),
                    color: AppColors.success,
                    background: AppColors.successBg,
                    icon: Icons.check_circle_rounded,
                  ),
                  if (_validChanges != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    for (final e in _validChanges!.entries)
                      Text('${e.key}: ${e.value}'),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
