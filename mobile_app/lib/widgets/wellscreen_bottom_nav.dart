import 'package:flutter/material.dart';

class WellScreenNavItem {
  const WellScreenNavItem({
    required this.icon,
    required this.label,
    this.showBadge = false,
  });

  final IconData icon;
  final String label;

  /// Draws a small red unread dot on the icon's top-right corner.
  final bool showBadge;
}

/// Floating white pill navigation bar: icon with a text label underneath.
/// The active tab gets a soft blue pill highlight behind its icon.
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
  static const Color _activeColor = Color(0xFF1E40AF);
  static const Color _activePill = Color(0xFFDBEAFE);
  static const Color _inactiveColor = Color(0xFF64748B);
  static const Color _badgeColor = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: navBackground,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = index == currentIndex;
              final color = selected ? _activeColor : _inactiveColor;

              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.label,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(26),
                    onTap: () => onTap(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? _activePill : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(item.icon, color: color, size: 22),
                              if (item.showBadge)
                                Positioned(
                                  right: -3,
                                  top: -2,
                                  child: Container(
                                    width: 9,
                                    height: 9,
                                    decoration: BoxDecoration(
                                      color: _badgeColor,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        ExcludeSemantics(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
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
