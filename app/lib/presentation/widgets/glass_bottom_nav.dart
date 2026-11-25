/// The floating tab bar: a glass pill over the page, where only the current
/// tab takes lime.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';
import '../theme/colors.dart';
import '../theme/glass_theme.dart';
import 'duotone_icon.dart';
import 'pressable.dart';

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

/// The floating tab bar.
///
/// Each tab is one button that says its name and whether it is the current
/// one, can be reached and pressed from a keyboard, and keeps its label on one
/// line at any text size.
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

  /// Height of the glass pill. With the 12 it floats above the bottom inset,
  /// this is what [GlassTheme.bottomNavClearance] reserves under a page.
  static const double height = 66;

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

  /// How far the pill floats above the bottom edge of the screen.
  ///
  /// An iPhone reserves 34 for a home indicator that uses the lowest 13, so
  /// the pill sits inside the rest, the way the system's own floating bars do.
  /// Everywhere else the inset is the system's controls themselves (Android's
  /// navigation buttons), and the pill stays clear of all of it.
  static double _lift(BuildContext context) {
    final double inset = MediaQuery.paddingOf(context).bottom;
    return Theme.of(context).platform == TargetPlatform.iOS
        ? math.max(12, inset - 10)
        : inset + 12;
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Padding(
      padding: EdgeInsets.only(left: 14, right: 14, bottom: _lift(context)),
      // Translucent pill fill + border + blur: the page scrolls behind it and
      // shows through, frosted.
      child: Container(
        height: height,
        decoration: GlassTheme.pillGlassDecoration(
            isDark: Theme.of(context).brightness == Brightness.dark),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GlassTheme.radiusPill),
          child: BackdropFilter(
            filter: GlassTheme.blurFilter,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int index = 0; index < items.length; index++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: _Tab(
                          item: items[index],
                          selected: currentIndex == index,
                          reduceMotion: reduceMotion,
                          onTap: () => onTap(index),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.item,
    required this.selected,
    required this.reduceMotion,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final bool reduceMotion;
  final VoidCallback onTap;

  static const BorderRadius _radius = BorderRadius.all(Radius.circular(32));

  @override
  Widget build(BuildContext context) {
    // Kit: only the ACTIVE item takes lime, as a pill tint with ink-safe
    // icon and label (deep lime on light).
    final Color ink = selected ? Brand.navActive : Brand.navInactive;

    return Pressable(
      onTap: onTap,
      semanticLabel: item.label,
      selected: selected,
      radius: _radius,
      child: AnimatedContainer(
        duration: Duration(milliseconds: reduceMotion ? 0 : 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: _radius,
          color: selected ? Brand.navActivePill : Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(
              selected ? item.activeIconPath ?? item.iconPath : item.iconPath,
              size: 23,
              color: ink,
            ),
            const SizedBox(height: 3),
            // A tab label is a fixed piece of chrome: it grows a little with
            // the reader's text size, then holds, so it never leaves the bar.
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandText.body(
                  size: 11,
                  weight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: ink,
                ).copyWith(height: 1.15),
              ),
            ),
          ],
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
    // Lime is a FILL color — pair with Brand.onLime content (kit rule 5).
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
