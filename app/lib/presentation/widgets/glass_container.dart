/// Glass Container Widgets - iOS 26 Liquid Glass Design
/// Reusable glass-effect container widgets
///
/// Note: Core glass widgets (GlassContainer, GlassCircleButton, GlassPillContainer,
/// GlassGradientBackground) are defined in glass_theme.dart.
/// This file contains additional specialized glass widgets.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/glass_theme.dart';

// Re-export core glass widgets from glass_theme.dart for convenience
export '../theme/glass_theme.dart'
    show GlassContainer, GlassCircleButton, GlassPillContainer,
         GlassGradientBackground, GlassGradientPosition;

/// Glass card widget (replacement for Card)
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool isDark;
  final VoidCallback? onTap;
  final Color? tintColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.isDark = true,
    this.onTap,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    Widget card = GlassContainer(
      padding: padding ?? const EdgeInsets.all(16),
      margin: margin ?? const EdgeInsets.only(bottom: 12),
      borderRadius: GlassTheme.radiusLarge,
      tintColor: tintColor,
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }

    return card;
  }
}

/// Glass badge/chip widget
class GlassBadge extends StatelessWidget {
  final String text;
  final Color? color;
  final IconData? icon;
  final bool isDark;
  final double? fontSize;

  const GlassBadge({
    super.key,
    required this.text,
    this.color,
    this.icon,
    this.isDark = true,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final badgeColor = color ?? GlassTheme.primaryAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: GlassTheme.badgeGlassDecoration(
        isDark: isDark,
        tintColor: badgeColor,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: badgeColor),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              color: badgeColor,
              fontSize: fontSize ?? 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass icon container
class GlassIconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool isDark;

  const GlassIconBox({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 20,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
        border: Border.all(
          color: color.withAlpha(60),
          width: GlassTheme.borderWidth,
        ),
      ),
      child: Center(
        child: Icon(icon, color: color, size: iconSize),
      ),
    );
  }
}

/// Glass icon box using SVG duotone icons
class GlassSvgIconBox extends StatelessWidget {
  final String icon;
  final Color color;
  final double size;
  final double iconSize;
  final bool isDark;

  const GlassSvgIconBox({
    super.key,
    required this.icon,
    required this.color,
    this.size = 40,
    this.iconSize = 20,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
        border: Border.all(
          color: color.withAlpha(60),
          width: GlassTheme.borderWidth,
        ),
      ),
      child: Center(
        child: SvgPicture.asset(
          'assets/icons/$icon.svg',
          width: iconSize,
          height: iconSize,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// Glass list tile
class GlassListTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDark;
  final EdgeInsetsGeometry? padding;

  const GlassListTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDark = true,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    Widget tile = GlassContainer(
      padding: padding ?? const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      borderRadius: GlassTheme.radiusSmall,
      blur: false,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: actualIsDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: actualIsDark ? Colors.white54 : Colors.black45,
                      fontSize: 13,
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: tile);
    }

    return tile;
  }
}

/// Glass section header
class GlassSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool isDark;

  const GlassSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: actualIsDark ? Colors.white38 : Colors.black38,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Glass divider
class GlassDivider extends StatelessWidget {
  final bool isDark;
  final double height;

  const GlassDivider({
    super.key,
    this.isDark = true,
    this.height = 1,
  });

  @override
  Widget build(BuildContext context) {
    final actualIsDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: actualIsDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(10),
    );
  }
}
