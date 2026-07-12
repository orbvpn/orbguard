/// Glass Bottom Navigation Bar - OrbX Style
///
/// A floating pill-shaped glass navigation bar matching OrbX design
/// Features: 60px height, borderRadius 30, accent highlight on selected tab
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/colors.dart';
import '../theme/glass_theme.dart';
import 'duotone_icon.dart';

/// Navigation item data
class NavItem {
  final String label;
  final String iconPath;
  final String? activeIconPath;

  const NavItem({
    required this.label,
    required this.iconPath,
    this.activeIconPath,
  });
}

/// Glass Bottom Navigation Bar - OrbX Style
///
/// Pill-shaped (60px height, 30px radius), glass blur, accent background on selected
class GlassBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavItem> items;

  const GlassBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  /// Default navigation items for OrbGuard
  static const List<NavItem> defaultItems = [
    NavItem(
      label: 'Dashboard',
      iconPath: AppIcons.dashboard,
    ),
    NavItem(
      label: 'Scan',
      iconPath: AppIcons.search,
    ),
    NavItem(
      label: 'Intel',
      iconPath: AppIcons.structure,
    ),
    NavItem(
      label: 'Settings',
      iconPath: AppIcons.settings,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: bottomPadding + 12,
      ),
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          color: GlassTheme.glassColor(isDark),
          border: Border.all(
            color: GlassTheme.glassBorderColor(isDark),
            width: GlassTheme.borderWidth,
          ),
          boxShadow: [GlassTheme.elevatedShadow(isDark)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: GlassTheme.blurFilter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: List.generate(items.length, (index) {
                  final isSelected = currentIndex == index;
                  final item = items[index];

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onTap(index);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          color: isSelected
                              ? (isDark
                                  ? AppColors.accent.withAlpha(35)
                                  : AppColors.accent.withAlpha(20))
                              : Colors.transparent,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DuotoneIcon(
                              item.iconPath,
                              size: 22,
                              color: isSelected
                                  ? AppColors.accent
                                  : (isDark
                                      ? Colors.white.withAlpha(150)
                                      : Colors.black.withAlpha(100)),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.label,
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? AppColors.accent
                                    : (isDark
                                        ? Colors.white.withAlpha(150)
                                        : Colors.black.withAlpha(100)),
                                letterSpacing: -0.2,
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
        ),
      ),
    );
  }
}

/// Floating action button style glass button
class GlassFloatingButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final Color? color;
  final double size;

  const GlassFloatingButton({
    super.key,
    required this.child,
    required this.onTap,
    this.color,
    this.size = 56,
  });

  @override
  State<GlassFloatingButton> createState() => _GlassFloatingButtonState();
}

class _GlassFloatingButtonState extends State<GlassFloatingButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final buttonColor = widget.color ?? AppColors.accent;

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: buttonColor,
            boxShadow: [
              BoxShadow(
                color: buttonColor.withAlpha(100),
                blurRadius: 16,
                spreadRadius: 2,
              ),
              GlassTheme.shadow(isDark),
            ],
          ),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}
