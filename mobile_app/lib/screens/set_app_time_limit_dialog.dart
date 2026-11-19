import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/brand_app_icon.dart';

/// Returns the selected daily allowance in minutes, or null if dismissed.
/// This widget does not save a rule or enforce an app restriction by itself.
Future<int?> showSetAppTimeLimitDialog({
  required BuildContext context,
  required String appName,
  required int usageTodayMs,
  int? initialLimitMinutes,
  String? packageName,
  String? iconBase64,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _SetAppTimeLimitSheet(
      appName: appName,
      packageName: packageName,
      iconBase64: iconBase64,
      usageTodayMs: usageTodayMs,
      initialLimitMinutes: initialLimitMinutes,
    ),
  );
}

class _SetAppTimeLimitSheet extends StatefulWidget {
  const _SetAppTimeLimitSheet({
    required this.appName,
    required this.usageTodayMs,
    required this.initialLimitMinutes,
    this.packageName,
    this.iconBase64,
  });

  final String appName;
  final String? packageName;
  final String? iconBase64;
  final int usageTodayMs;
  final int? initialLimitMinutes;

  @override
  State<_SetAppTimeLimitSheet> createState() => _SetAppTimeLimitSheetState();
}

class _SetAppTimeLimitSheetState extends State<_SetAppTimeLimitSheet> {
  late final TextEditingController _hoursController;
  late final TextEditingController _minutesController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialLimitMinutes ?? 60).clamp(1, 1440).toInt();
    _hoursController = TextEditingController(text: '${initial ~/ 60}');
    _minutesController = TextEditingController(text: '${initial % 60}');
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  int? get _selectedMinutes {
    final hours = int.tryParse(_hoursController.text.trim());
    final minutes = int.tryParse(_minutesController.text.trim());
    if (hours == null || minutes == null || hours < 0 || minutes < 0 ||
        minutes > 59) {
      return null;
    }
    final total = hours * 60 + minutes;
    return total >= 1 && total <= 1440 ? total : null;
  }

  void _setPreset(int minutes) {
    _hoursController.text = '${minutes ~/ 60}';
    _minutesController.text = '${minutes % 60}';
    setState(() => _error = null);
  }

  void _save() {
    final minutes = _selectedMinutes;
    if (minutes == null) {
      setState(() => _error =
          'Enter a limit between 1 minute and 24 hours (0–59 minutes per hour).');
      return;
    }
    Navigator.of(context).pop(minutes);
  }

  String _durationText(int minutes) {
    if (minutes <= 0) return '0m';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '${rest}m';
    return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedMinutes;
    final usedMs = widget.usageTodayMs < 0 ? 0 : widget.usageTodayMs;
    final usedMinutes = Duration(milliseconds: usedMs).inMinutes;
    final int? remaining = selected == null
        ? null
        : (selected - usedMinutes).clamp(0, 1440).toInt();
    final double ratio = selected == null
        ? 0.0
        : (usedMs / (selected * 60000)).clamp(0.0, 1.0).toDouble();

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BrandAppIcon(
                      label: widget.appName,
                      packageName: widget.packageName,
                      iconBase64: widget.iconBase64,
                      size: 48,
                      radius: 14,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Set time limit',
                            style: TextStyle(
                              fontFamily: AppFonts.heading,
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.appName} · daily allowance',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Quick options',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final minutes in const [30, 60, 120, 180]) ...[
                      if (minutes != 30) const SizedBox(width: 8),
                      Expanded(
                        child: _presetButton(minutes, selected == minutes),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _numberField('Hours', _hoursController)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _numberField('Minutes', _minutesController),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.danger)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _statBox(
                        'Used today',
                        _durationText(usedMinutes),
                        AppColors.violetBg,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _statBox(
                        'Remaining',
                        remaining == null ? '—' : _durationText(remaining),
                        AppColors.successBg,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 6,
                    color: ratio >= 1 ? AppColors.danger : AppColors.primary,
                    backgroundColor: AppColors.track,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        child: const Text('Save limit'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _presetButton(int minutes, bool on) {
    return Semantics(
      selected: on,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _setPreset(minutes),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.primaryLight : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: on ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            _durationText(minutes),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          onChanged: (_) => setState(() => _error = null),
        ),
      ],
    );
  }

  Widget _statBox(String label, String value, Color background) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontFamily: AppFonts.heading,
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
