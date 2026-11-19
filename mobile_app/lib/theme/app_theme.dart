/// WellScreen's single source of visual truth.
///
/// WHY THIS EXISTS: before this file, every screen redeclared its own copy
/// of the same ~10 color constants (purple/darkText/grayText/etc.) as local
/// `static const` fields - drift was inevitable (rules_screen.dart had
/// already drifted onto a different background and different
/// blue/red than every other screen). One shared file means changing the
/// brand color, a card radius, or a spacing value happens once, not once
/// per screen, and it's what makes the "seamless, consistent" redesign
/// requested actually possible instead of aspirational.
///
/// Re-themed from the original brand purple (#5B2BBF) to a blue/teal
/// "Trust Blue" palette after a research pass on parental-control apps
/// specifically: blue is the color most consistently associated with
/// trust, calm, and safety across UX color-psychology research, and it's
/// what competitors in this exact category (Google Family Link
/// especially) lean on for that reason - purple reads more as
/// premium/creative, which fits a design tool better than a safety tool a
/// parent needs to feel confident in. Every value below changed together
/// so nothing drifts out of coordination; screens should still only ever
/// reference AppColors, never a new literal Color(0x...).
library;

import 'package:flutter/material.dart';

/// The full color palette. Semantic names (success/warning/danger/info),
/// not just raw brand colors - previously every screen invented its own
/// ad hoc green/orange/red for "healthy/moderate/high risk" style states,
/// which is exactly the kind of thing that drifts. Use these, not a new
/// literal Color(0x...) in a screen file.
class AppColors {
  AppColors._();

  // Brand - design D ("WellScreen Light", Nov 2026): the three colors of
  // the WellScreen logo. Indigo (left figure) is the primary, teal (right
  // figure) means healthy / OK, violet (end of the heart) marks highlights
  // and over-goal values. The heart's indigo-to-violet blend is
  // [heroGradient], used only on the main screen-time cards.
  static const Color primary = Color(0xFF3438B8);
  static const Color primaryDark = Color(0xFF262A8F);
  static const Color primaryLight = Color(0xFFE7E8F9);
  /// Logo violet - AI/ML accents and "over goal" highlights.
  static const Color accent = Color(0xFF7024B8);
  static const Color violet = Color(0xFF7024B8);
  static const Color violetBg = Color(0xFFF0E5FA);
  /// Logo teal as a fill (progress, chips). Text on it uses [onTeal].
  static const Color teal = Color(0xFF52B8A0);
  static const Color onTeal = Color(0xFF0B2E27);

  /// The logo heart's indigo-to-violet blend, for hero cards only.
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF3438B8), Color(0xFF5A2EBA), Color(0xFF7024B8)],
  );

  // Neutrals - an indigo-tinted ink and greys so text matches the brand.
  static const Color background = Color(0xFFF5F6FB);
  static const Color surface = Colors.white;
  static const Color border = Color(0xFFE3E5F2);
  static const Color textPrimary = Color(0xFF161A4A);
  static const Color textSecondary = Color(0xFF565B7D);
  static const Color textDisabled = Color(0xFF9A9DB8);

  // Semantic - consistent across every screen. Success is the logo teal,
  // darkened so it passes 4.5:1 as text on white.
  static const Color success = Color(0xFF1F7F6B);
  static const Color successBg = Color(0xFFDDF3EE);
  static const Color warning = Color(0xFF9A5B00);
  static const Color warningBg = Color(0xFFFDF0D9);
  static const Color danger = Color(0xFFC62F4B);
  static const Color dangerBg = Color(0xFFFBE4E9);
  static const Color info = primary;
  static const Color infoBg = primaryLight;

  // Detection-source tags (SiteCategoryService's three mechanisms) - one
  // fixed color per source everywhere it's shown.
  static const Color sourceLookup = primary;
  static const Color sourceKeyword = warning;
  static const Color sourceMl = accent;

  /// Filled inactive track (progress bars, switches off, chart bars).
  static const Color track = Color(0xFFD3D5EC);

  /// Primary call-to-action fill ("Approve", "Copy Code", "Export PDF").
  static const Color ink = primary;
  /// Inputs, incoming chat bubbles and soft secondary buttons.
  static const Color surfaceMuted = Color(0xFFEEF0FA);
  /// Outgoing chat bubble and chat composer actions.
  static const Color messenger = primary;
  /// Unread dot on the bottom bar.
  static const Color badge = Color(0xFFE0344F);

  /// Translucent primary for focus rings and soft shadows.
  static const Color primaryA20 = Color(0x333438B8);
  static const Color primaryA33 = Color(0x553438B8);
  /// Soft indigo-tinted shadow under cards.
  static const Color shadow = Color(0x0D161A4A);
}

/// Bundled fonts (pubspec.yaml): Inter for body text, Outfit for headings.
class AppFonts {
  AppFonts._();
  static const String body = 'Inter';
  static const String heading = 'Outfit';
}

/// Spacing scale - use multiples of this instead of literal EdgeInsets
/// numbers, so padding/gaps are consistent instead of "whatever felt
/// right in this one screen" (previous screens mixed 12/14/18/20/22/24
/// with no evident system).
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double xxl = 40;
}

class AppRadius {
  AppRadius._();
  static const double card = 20;
  static const double button = 16;
  static const double input = 16;
  static const double pill = 999;
  static const double sheet = 28;
}

/// The MaterialApp-level theme. Wire this into main.dart's
/// `MaterialApp(theme: AppTheme.light())` instead of the inline ThemeData
/// that was there before.
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: AppFonts.body,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontFamily: AppFonts.heading,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          fontFamily: AppFonts.heading,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontFamily: AppFonts.heading,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.45,
        ),
        labelSmall: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppFonts.heading,
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textDisabled,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 48),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          minimumSize: const Size(0, 48),
          side: const BorderSide(color: AppColors.border),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.track,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        // Light indigo, not solid: the label stays dark and readable.
        selectedColor: AppColors.primaryLight,
        checkmarkColor: AppColors.primary,
        side: BorderSide.none,
        shape: const StadiumBorder(),
        labelStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
    );
  }
}

/// One card shape, used everywhere - replaces the two competing styles
/// found across the app (a custom 26px `_whiteCard()` helper vs. Material
/// `Card` at elevation 2 / radius 18, used inconsistently screen to
/// screen). Every redesigned screen should build sections with this, not
/// a hand-rolled Container.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A111827),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: card,
    );
  }
}

/// A small colored pill, used for status/severity/source labels
/// ("High Risk", "gambling", "(AI-detected)") - one consistent visual
/// treatment instead of ad hoc Text-with-color scattered through screens.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    required this.color,
    required this.background,
    this.icon,
  });

  final String label;
  final Color color;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// A standard section header used at the top of every AppCard - icon,
/// title, optional trailing widget. Kills the copy-pasted Row(Icon +
/// SizedBox + Expanded(Text(...))) block that was hand-rewritten (with
/// small inconsistencies) in nearly every card across the app.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 22),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    );
  }
}

/// A single empty/placeholder state - replaces the many hand-written
/// "No X synced yet" AlertReportCard-style widgets that each screen
/// re-implemented slightly differently.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: icon,
            iconColor: AppColors.textDisabled,
            title: title,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A single error state, styled to match AppEmptyState but in the danger
/// palette with an optional retry action - previously every screen that
/// bothered to handle a stream/future error at all (not all did - see
/// git history / the UI audit that added this) wrote its own ad hoc
/// Center(Text(...)) for it, so a real backend failure looked different
/// on every screen instead of being instantly recognizable as "this is an
/// error state" the way a parent or admin only has to learn once.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    this.title = 'Something Went Wrong',
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(
            icon: Icons.error_outline_rounded,
            iconColor: AppColors.danger,
            title: title,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Retry',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Which of the three button looks from the design spec to draw.
enum AppPillStyle {
  /// Solid obsidian - the main action ("Approve", "Copy Code", "Export PDF").
  primary,

  /// Solid brand blue ("App Rules", "Verify & Continue").
  brand,

  /// Soft neutral or tinted fill - secondary actions ("Deny", "Share GPS").
  soft,
}

/// The one full-pill button used on every redesigned screen, so heights,
/// radius and weights stay identical instead of being restyled per screen.
class AppPillButton extends StatelessWidget {
  const AppPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = AppPillStyle.primary,
    this.icon,
    this.expand = false,
    this.compact = false,
    this.softTint = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppPillStyle style;
  final IconData? icon;

  /// Fill the available width (for full-width form actions).
  final bool expand;

  /// 36px tall instead of 48px - for buttons inside a card header row.
  final bool compact;

  /// For [AppPillStyle.soft] only: blue-tinted fill instead of neutral gray.
  final bool softTint;

  /// Show a spinner instead of the label and ignore taps.
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    switch (style) {
      case AppPillStyle.primary:
        background = AppColors.ink;
        foreground = Colors.white;
      case AppPillStyle.brand:
        background = AppColors.primary;
        foreground = Colors.white;
      case AppPillStyle.soft:
        background = softTint ? AppColors.primaryLight : AppColors.surfaceMuted;
        foreground = softTint ? AppColors.primaryDark : AppColors.textPrimary;
    }

    final height = compact ? 36.0 : 48.0;
    final button = ElevatedButton(
      onPressed: loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: loading ? background : AppColors.border,
        disabledForegroundColor: loading
            ? foreground
            : AppColors.textDisabled,
        elevation: 0,
        minimumSize: Size(0, height),
        padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
        shape: const StadiumBorder(),
        textStyle: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: compact ? 13 : 15,
        ),
      ),
      child: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: foreground,
              ),
            )
          : Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 16 : 18),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );

    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
