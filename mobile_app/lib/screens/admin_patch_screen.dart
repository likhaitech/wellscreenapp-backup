import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/admin_settings_api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/wellscreen_ui.dart';

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
    final changeKeys = _validChanges?.keys.toList() ?? const <String>[];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const WellScreenAppBar.subPage(title: 'System patch'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          const Text(
            'Paste a JSON configuration patch. It is checked first; a '
            'rejected patch changes nothing.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          const Text(
            'Configuration patch',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            maxLines: 12,
            minLines: 10,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.all(14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            _resultCard(
              icon: Icons.error_outline_rounded,
              color: AppColors.danger,
              tint: AppColors.dangerBg,
              title: 'Patch rejected - no changes made',
              lines: _errors,
            ),
          ],
          if (_success != null) ...[
            const SizedBox(height: 12),
            _resultCard(
              icon: Icons.check_rounded,
              color: AppColors.success,
              tint: AppColors.successBg,
              title: _success!,
              lines: [
                if (changeKeys.isNotEmpty)
                  '${changeKeys.length} key${changeKeys.length == 1 ? '' : 's'}'
                      ' will change: ${changeKeys.join(', ')}',
                for (final e in _validChanges!.entries)
                  '${e.key}: ${e.value}',
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryLight,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(50),
                  ),
                  onPressed: _busy ? null : () => _run(validateOnly: true),
                  child: const Text('Validate'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
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
    );
  }

  Widget _resultCard({
    required IconData icon,
    required Color color,
    required Color tint,
    required String title,
    required List<String> lines,
  }) {
    return BentoCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final line in lines)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
