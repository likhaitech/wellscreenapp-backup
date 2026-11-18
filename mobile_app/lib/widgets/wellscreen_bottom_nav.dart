import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WellScreenNavItem {
  const WellScreenNavItem({
    required this.icon,
    required this.label,
    this.showBadge = false,
  });

  final IconData icon;

  /// Not drawn. Used for the screen-reader name and the long-press tooltip.
  final String label;

  /// Draws a small red unread dot on the icon's top-right corner.
  final bool showBadge;
}

/// Floating white pill dock with icon-only tabs. The active tab sits inside
/// a solid blue circle with a white icon; the others are plain gray icons.
class WellScreenBottomNav extends StatelessWidget {
  const WellScreenBottomNav({
    super.key,
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<WellScreenNavItem> items;
  final ValueChanged<int> onTap;

  static const Color navBackground = Colors.white;
  static const Color _inactiveColor = Color(0xFF4B5563);

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
            color: navBackground,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: AppColors.border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A111827),
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
                                color: selected ? Colors.white : _inactiveColor,
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
