import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'brand_app_icon.dart';

/// Renders the icon retrieved from the CHILD's actual installed package.
/// When the report has no icon for it (older report, app not used today),
/// [label] / [packageName] let [BrandAppIcon] show the app's real website
/// icon instead of a generic symbol.
class AppUsageIcon extends StatelessWidget {
  const AppUsageIcon({
    super.key,
    required this.encoded,
    this.fallback = Icons.apps_rounded,
    this.fallbackColor = AppColors.primary,
    this.size = 48,
    this.label,
    this.packageName,
  });

  final String? encoded;
  final IconData fallback;
  final Color fallbackColor;
  final double size;
  final String? label;
  final String? packageName;

  @override
  Widget build(BuildContext context) {
    final name = label;
    if (name != null && name.isNotEmpty) {
      return BrandAppIcon(
        label: name,
        packageName: packageName,
        iconBase64: encoded,
        size: size,
      );
    }
    final encodedIcon = encoded;
    Widget child = Icon(fallback, color: Colors.white, size: size * 0.58);
    if (encodedIcon != null && encodedIcon.isNotEmpty) {
      try {
        final bytes = base64Decode(encodedIcon);
        child = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Icon(
            fallback,
            color: Colors.white,
            size: size * 0.58,
          ),
        );
      } on FormatException {
        // Old reports or malformed icon data: show a neutral fallback.
      }
    }
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: fallbackColor,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Center(child: child),
    );
  }
}
