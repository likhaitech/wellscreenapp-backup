/// Shared WellScreen building blocks used by every screen:
/// [WellScreenAppBar], [BentoCard], [StatusPill] and [FloatingPillDock].
library;

import 'package:flutter/material.dart';

import '../services/password_policy.dart';
import '../theme/app_theme.dart';

/// Numerals that keep the same width, for timers, counters and KPIs.
const List<FontFeature> kTabularFigures = [FontFeature.tabularFigures()];

// ---------------------------------------------------------------- app bar

/// The one top bar.
///
/// * [WellScreenAppBar.primary] - tab screens: menu icon, shield + wordmark,
///   avatar on the right.
/// * [WellScreenAppBar.subPage] - pushed screens: back arrow, bold title and
///   optional trailing actions.
class WellScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WellScreenAppBar.primary({
    super.key,
    this.onMenu,
    this.onAvatar,
    this.avatar,
    this.title = 'WellScreen',
    this.onTitleLongPress,
    this.actions = const [],
  }) : isPrimary = true,
       onBack = null,
       showBack = false;

  const WellScreenAppBar.subPage({
    super.key,
    required this.title,
    this.onBack,
    this.showBack = true,
    this.actions = const [],
  }) : isPrimary = false,
       onMenu = null,
       onAvatar = null,
       avatar = null,
       onTitleLongPress = null;

  final bool isPrimary;
  final String title;
  final VoidCallback? onMenu;
  final VoidCallback? onAvatar;
  final Widget? avatar;
  final VoidCallback? onTitleLongPress;
  final VoidCallback? onBack;
  final bool showBack;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: isPrimary ? _primary(context) : _subPage(context),
        ),
      ),
    );
  }

  Widget _primary(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Menu',
          onPressed: onMenu,
          icon: const _TwoLineMenuIcon(),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onTitleLongPress,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The real WellScreen logo, not a stand-in icon.
                Image.asset(
                  'assets/icons/wellscreen_icon.png',
                  width: 28,
                  height: 28,
                  semanticLabel: 'WellScreen',
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.heading,
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ...actions,
        Padding(
          padding: const EdgeInsets.only(left: 4, right: 6),
          child: InkResponse(
            onTap: onAvatar,
            radius: 24,
            child: SizedBox(
              width: 36,
              height: 36,
              child: ClipOval(
                child:
                    avatar ??
                    const ColoredBox(
                      color: AppColors.primaryLight,
                      child: Icon(
                        Icons.person_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _subPage(BuildContext context) {
    return Row(
      children: [
        if (showBack)
          IconButton(
            tooltip: 'Back',
            onPressed: onBack ?? () => Navigator.maybePop(context),
            icon: const Icon(
              Icons.arrow_back_rounded,
              color: AppColors.textPrimary,
            ),
          )
        else
          const SizedBox(width: 12),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppFonts.heading,
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        ...actions,
        const SizedBox(width: 4),
      ],
    );
  }
}

class _TwoLineMenuIcon extends StatelessWidget {
  const _TwoLineMenuIcon();

  @override
  Widget build(BuildContext context) {
    Widget line(double width) => Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    return SizedBox(
      width: 24,
      height: 24,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [line(20), const SizedBox(height: 6), line(14)],
      ),
    );
  }
}

// ------------------------------------------------------------------- card

/// White 20px-radius card with a 1px border and a very soft shadow.
/// [color] and [borderColor] allow the tinted variants (amber request
/// banner, blue/coral summary tiles).
class BentoCard extends StatelessWidget {
  const BentoCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- pill

enum StatusTone { success, warning, danger, info, neutral }

/// Small rounded status label ("Online", "Pending", "Restricted").
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.dot = false,
  });

  final String label;
  final StatusTone tone;
  final IconData? icon;

  /// Show a small filled dot before the label (for "Online" style states).
  final bool dot;

  static Color foregroundFor(StatusTone tone) {
    switch (tone) {
      case StatusTone.success:
        return AppColors.success;
      case StatusTone.warning:
        return AppColors.warning;
      case StatusTone.danger:
        return AppColors.danger;
      case StatusTone.info:
        return AppColors.primary;
      case StatusTone.neutral:
        return AppColors.textSecondary;
    }
  }

  static Color backgroundFor(StatusTone tone) {
    switch (tone) {
      case StatusTone.success:
        return AppColors.successBg;
      case StatusTone.warning:
        return AppColors.warningBg;
      case StatusTone.danger:
        return AppColors.dangerBg;
      case StatusTone.info:
        return AppColors.primaryLight;
      case StatusTone.neutral:
        return AppColors.surfaceMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final foreground = foregroundFor(tone);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundFor(tone),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- dock

class DockItem {
  const DockItem({
    required this.icon,
    required this.label,
    this.showBadge = false,
  });

  final IconData icon;

  /// Never drawn. Screen-reader name and long-press tooltip only.
  final String label;

  /// Red unread dot on the icon's top-right corner.
  final bool showBadge;
}

/// The only bottom navigation in the app: a floating white full-pill dock
/// with icon-only tabs. The active tab is a solid blue circle with a white
/// icon.
class FloatingPillDock extends StatelessWidget {
  const FloatingPillDock({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<DockItem> items;
  final ValueChanged<int> onTap;

  static const Color _inactive = AppColors.textSecondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A161A4A),
                blurRadius: 20,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = index == currentIndex;

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.label,
                  child: Tooltip(
                    message: item.label,
                    excludeFromSemantics: true,
                    child: InkResponse(
                      onTap: () => onTap(index),
                      radius: 30,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.primary
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                item.icon,
                                color: selected ? Colors.white : _inactive,
                                size: 24,
                              ),
                              if (item.showBadge)
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: AppColors.badge,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: selected
                                            ? AppColors.primary
                                            : Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ auth pieces

/// Centered shield + wordmark + tagline shown at the top of the sign-in and
/// create-account screens.
class WellScreenBrandHeader extends StatelessWidget {
  const WellScreenBrandHeader({
    super.key,
    this.title = 'WellScreen',
    this.tagline = 'Build healthy digital habits together',
  });

  final String title;
  final String tagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/icons/wellscreen_icon.png',
          width: 84,
          height: 84,
          semanticLabel: 'WellScreen',
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppFonts.heading,
            color: AppColors.textPrimary,
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tagline,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

/// A form field with its label above a soft, borderless pill input.
class WellScreenField extends StatelessWidget {
  const WellScreenField({
    super.key,
    required this.label,
    required this.controller,
    this.hintText,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.prefixIcon,
    this.enabled = true,
    this.maxLength,
    this.textInputAction,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final bool enabled;
  final int? maxLength;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    // Design D: rounded rectangle with a hairline border on white.
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

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
          enabled: enabled,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLength: maxLength,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hintText,
            counterText: '',
            isDense: true,
            filled: true,
            fillColor: AppColors.surface,
            prefixIcon: prefixIcon,
            prefixIconColor: AppColors.textSecondary,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            border: border(AppColors.border),
            enabledBorder: border(AppColors.border),
            disabledBorder: border(AppColors.border),
            focusedBorder: border(AppColors.primary, 1.5),
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------- password rules

/// Error dialog listing every password requirement, with a check for the
/// ones already met and a cross for the ones still missing.
Future<void> showPasswordRequirementsDialog(
  BuildContext context,
  String password,
) {
  final rules = PasswordPolicy.evaluate(password);

  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      icon: const Icon(
        Icons.lock_outline_rounded,
        color: AppColors.danger,
        size: 32,
      ),
      title: const Text(
        'Password is too weak',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your password must have:',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 10),
          for (final rule in rules)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    rule.met
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 18,
                    color: rule.met ? AppColors.success : AppColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rule.label,
                      style: TextStyle(
                        color: rule.met
                            ? AppColors.textSecondary
                            : AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: rule.met
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        AppPillButton(
          label: 'OK',
          expand: true,
          onPressed: () => Navigator.pop(dialogContext),
        ),
      ],
    ),
  );
}

/// Segmented pill tabs from the design D mockups (Manage users, System
/// logs). The selected tab is a white pill on the primaryLight track.
/// With more than four labels the row scrolls instead of squeezing.
class WellScreenPillTabs extends StatelessWidget {
  const WellScreenPillTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scrolls = labels.length > 4;
    Widget tab(int i) {
      final on = selected == i;
      return Semantics(
        selected: on,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 38,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: scrolls ? 14 : 4),
            decoration: BoxDecoration(
              color: on ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: on
                  ? const [
                      BoxShadow(
                        color: AppColors.shadow,
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              labels[i],
              maxLines: 1,
              style: TextStyle(
                color: on ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: on ? FontWeight.w700 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    final track = BoxDecoration(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    );
    if (scrolls) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: track,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [for (var i = 0; i < labels.length; i++) tab(i)],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: track,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) Expanded(child: tab(i)),
        ],
      ),
    );
  }
}
