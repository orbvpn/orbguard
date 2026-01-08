/// Glass Theme - iOS 26 Liquid Glass Design System
///
/// Centralized styling for all frosted glass UI elements.
/// Based on Apple's iOS 26 Liquid Glass design language.
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'colors.dart';

/// iOS 26 Liquid Glass design constants
class GlassTheme {
  GlassTheme._();

  // ============================================================================
  // BLUR SETTINGS
  // ============================================================================

  /// Standard blur for glass elements (iOS 26 style)
  static const double blurSigma = 20.0;

  /// Heavy blur for modals and sheets
  static const double blurSigmaHeavy = 30.0;

  /// Light blur for subtle effects
  static const double blurSigmaLight = 15.0;

  // ============================================================================
  // GLASS COLORS - iOS 26 LIQUID GLASS STYLE
  // ============================================================================

  /// Glass background color for light mode
  /// More opaque frosted white - matches Apple Music iOS 26 Beta 3
  static Color glassColorLight = Colors.white.withAlpha(230);

  /// Glass background color for dark mode
  /// Subtle white tint on dark
  static Color glassColorDark = Colors.white.withAlpha(22);

  /// Get glass color based on theme
  static Color glassColor(bool isDark) => isDark ? glassColorDark : glassColorLight;

  // ============================================================================
  // BORDER COLORS
  // ============================================================================

  /// Glass border color for light mode
  static Color glassBorderColorLight = Colors.black.withAlpha(12);

  /// Glass border color for dark mode
  static Color glassBorderColorDark = Colors.white.withAlpha(30);

  /// Get glass border color based on theme
  static Color glassBorderColor(bool isDark) =>
      isDark ? glassBorderColorDark : glassBorderColorLight;

  /// Standard border width
  static const double borderWidth = 0.5;

  // ============================================================================
  // ACCENT COLORS - Using AppColors
  // ============================================================================

  static const Color primaryAccent = AppColors.accent; // Cyan
  static const Color secondaryAccent = AppColors.secondary; // Tech Blue
  static const Color successColor = AppColors.success; // Green/Cyan
  static const Color warningColor = AppColors.warning; // Orange
  static const Color errorColor = AppColors.error; // Red

  // ============================================================================
  // SHADOWS - iOS 26 SOFT SHADOW STYLE
  // ============================================================================

  /// Shadow for light mode
  static Color glassShadowColorLight = Colors.black.withAlpha(15);

  /// Shadow for dark mode
  static Color glassShadowColorDark = Colors.black.withAlpha(40);

  /// Shadow for light mode
  static BoxShadow shadowLight = BoxShadow(
    color: glassShadowColorLight,
    blurRadius: 15,
    offset: const Offset(0, 3),
  );

  /// Shadow for dark mode
  static BoxShadow shadowDark = BoxShadow(
    color: glassShadowColorDark,
    blurRadius: 15,
    offset: const Offset(0, 3),
  );

  /// Get shadow based on theme
  static BoxShadow shadow(bool isDark) => isDark ? shadowDark : shadowLight;

  /// Get list of shadows for glass effect
  static List<BoxShadow> shadows(bool isDark) {
    return [shadow(isDark)];
  }

  /// Elevated shadow for floating elements
  static BoxShadow elevatedShadow(bool isDark) => BoxShadow(
        color: Colors.black.withAlpha(isDark ? 50 : 20),
        blurRadius: 20,
        offset: const Offset(0, 4),
      );

  // ============================================================================
  // BORDER RADIUS - iOS 26 STYLE
  // ============================================================================

  /// Pill shape radius (for nav bars, buttons)
  static const double radiusPill = 38.0;

  /// Large radius for cards and containers
  static const double radiusLarge = 24.0;

  /// Medium radius for smaller elements
  static const double radiusMedium = 16.0;

  /// Small radius for chips and badges
  static const double radiusSmall = 12.0;

  /// Extra small radius
  static const double radiusXSmall = 8.0;

  // ============================================================================
  // GRADIENT BACKGROUNDS FOR GLASS VISIBILITY
  // ============================================================================

  /// Background gradient colors - dark mode
  static const Color gradientTop = Color(0xFF1a1a2e);
  static const Color gradientBottom = Color(0xFF0a0a14);

  /// Background gradient colors - light mode
  static const Color gradientTopLight = Color(0xFFf0f4f8);
  static const Color gradientBottomLight = Color(0xFFe0e5eb);

  /// Top gradient for frosted glass visibility (light mode only)
  /// Smooth fade from edge - no visible line
  static BoxDecoration topGradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.black.withAlpha(35),
        Colors.black.withAlpha(30),
        Colors.black.withAlpha(22),
        Colors.black.withAlpha(12),
        Colors.black.withAlpha(5),
        Colors.transparent,
      ],
      stops: const [0.0, 0.15, 0.35, 0.55, 0.75, 1.0],
    ),
  );

  /// Bottom gradient for frosted glass visibility (light mode only)
  /// Smooth fade from edge - no visible line
  static BoxDecoration bottomGradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [
        Colors.black.withAlpha(38),
        Colors.black.withAlpha(32),
        Colors.black.withAlpha(22),
        Colors.black.withAlpha(12),
        Colors.black.withAlpha(5),
        Colors.transparent,
      ],
      stops: const [0.0, 0.15, 0.35, 0.55, 0.75, 1.0],
    ),
  );

  /// Height for top gradient
  static const double topGradientHeight = 280.0;

  /// Height for bottom gradient
  static const double bottomGradientHeight = 250.0;

  // ============================================================================
  // HELPER METHODS
  // ============================================================================

  /// Get complete glass decoration
  static BoxDecoration glassDecoration({
    bool isDark = true,
    double radius = radiusMedium,
    bool withShadow = true,
    Color? customColor,
    Color? customBorderColor,
    Color? tintColor,
    bool elevated = false,
  }) {
    Color bgColor = customColor ?? glassColor(isDark);

    // Apply tint if provided
    if (tintColor != null) {
      bgColor = Color.alphaBlend(tintColor.withAlpha(isDark ? 30 : 20), bgColor);
    }

    return BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: customBorderColor ?? glassBorderColor(isDark),
        width: borderWidth,
      ),
      boxShadow: withShadow
          ? [elevated ? elevatedShadow(isDark) : shadow(isDark)]
          : null,
    );
  }

  /// Get pill-shaped glass decoration (for nav bars)
  static BoxDecoration pillGlassDecoration({
    bool isDark = true,
    bool withShadow = true,
    bool elevated = false,
  }) {
    return glassDecoration(
      isDark: isDark,
      radius: radiusPill,
      withShadow: withShadow,
      elevated: elevated,
    );
  }

  /// Get circular glass decoration (for round buttons)
  static BoxDecoration circularGlassDecoration({
    bool isDark = true,
    bool withShadow = true,
    bool elevated = false,
  }) {
    return BoxDecoration(
      color: glassColor(isDark),
      shape: BoxShape.circle,
      border: Border.all(
        color: glassBorderColor(isDark),
        width: borderWidth,
      ),
      boxShadow: withShadow
          ? [elevated ? elevatedShadow(isDark) : shadow(isDark)]
          : null,
    );
  }

  /// Card-style glass decoration
  static BoxDecoration cardGlassDecoration({
    bool isDark = true,
    bool withShadow = true,
  }) {
    return glassDecoration(
      isDark: isDark,
      radius: radiusLarge,
      withShadow: withShadow,
    );
  }

  /// Badge/chip glass decoration
  static BoxDecoration badgeGlassDecoration({
    bool isDark = true,
    Color? tintColor,
  }) {
    return BoxDecoration(
      color: tintColor?.withAlpha(40) ?? glassColor(isDark),
      borderRadius: BorderRadius.circular(radiusXSmall),
      border: Border.all(
        color: tintColor?.withAlpha(80) ?? glassBorderColor(isDark),
        width: borderWidth,
      ),
    );
  }

  /// Tinted glass decoration (for colored cards)
  static BoxDecoration tintedGlassDecoration({
    required Color tintColor,
    bool isDark = true,
    double radius = radiusMedium,
    double opacity = 0.15,
  }) {
    return BoxDecoration(
      color: tintColor.withOpacity(opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: tintColor.withOpacity(0.3),
        width: borderWidth,
      ),
    );
  }

  /// Get background gradient for glass visibility
  static LinearGradient backgroundGradient({bool isDark = true}) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [gradientTop, gradientBottom]
          : [gradientTopLight, gradientBottomLight],
    );
  }

  /// Standard blur filter
  static ImageFilter get blurFilter => ImageFilter.blur(
        sigmaX: blurSigma,
        sigmaY: blurSigma,
      );

  /// Light blur filter
  static ImageFilter get blurFilterLight => ImageFilter.blur(
        sigmaX: blurSigmaLight,
        sigmaY: blurSigmaLight,
      );

  /// Heavy blur filter for modals
  static ImageFilter get blurFilterHeavy => ImageFilter.blur(
        sigmaX: blurSigmaHeavy,
        sigmaY: blurSigmaHeavy,
      );

  // ============================================================================
  // TEXT STYLES
  // ============================================================================

  /// Get themed text style
  static TextStyle headingStyle({bool isDark = true}) {
    return TextStyle(
      color: isDark ? Colors.white : AppColors.textPrimary,
      fontWeight: FontWeight.bold,
      fontSize: 18,
    );
  }

  static TextStyle bodyStyle({bool isDark = true}) {
    return TextStyle(
      color: isDark ? Colors.white70 : AppColors.textSecondary,
      fontSize: 14,
    );
  }

  static TextStyle captionStyle({bool isDark = true}) {
    return TextStyle(
      color: isDark ? Colors.white38 : Colors.black38,
      fontSize: 12,
    );
  }
}

// ============================================================================
// REUSABLE GLASS WIDGETS
// ============================================================================

/// Gradient background for glass visibility
/// Place at the edges of screens with floating glass elements
class GlassGradientBackground extends StatelessWidget {
  final GlassGradientPosition? position;
  final bool isDark;
  final Widget? child;

  const GlassGradientBackground({
    super.key,
    this.position,
    required this.isDark,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    // Full screen gradient background
    if (child != null) {
      return Container(
        decoration: BoxDecoration(
          gradient: GlassTheme.backgroundGradient(isDark: isDark),
        ),
        child: Stack(
          children: [
            // Top gradient overlay (light mode only)
            if (!isDark)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: GlassTheme.topGradientHeight,
                child: Container(decoration: GlassTheme.topGradient),
              ),
            // Bottom gradient overlay (light mode only)
            if (!isDark)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: GlassTheme.bottomGradientHeight,
                child: Container(decoration: GlassTheme.bottomGradient),
              ),
            // Main content
            child!,
          ],
        ),
      );
    }

    // Position-based gradient (for positioned use)
    if (position == null) return const SizedBox.shrink();

    // Only show position gradients in light mode
    if (isDark) return const SizedBox.shrink();

    final isTop = position == GlassGradientPosition.top;

    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: 0,
      right: 0,
      height: isTop
          ? GlassTheme.topGradientHeight
          : GlassTheme.bottomGradientHeight,
      child: Container(
        decoration: isTop ? GlassTheme.topGradient : GlassTheme.bottomGradient,
      ),
    );
  }
}

/// Position for glass gradient background
enum GlassGradientPosition { top, bottom }

/// A glass container with iOS 26 Liquid Glass styling
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? tintColor;
  final bool elevated;
  final bool blur;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.tintColor,
    this.elevated = false,
    this.blur = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? GlassTheme.radiusLarge;

    Widget content = Container(
      padding: padding,
      decoration: GlassTheme.glassDecoration(
        isDark: isDark,
        radius: radius,
        tintColor: tintColor,
        elevated: elevated,
      ),
      child: child,
    );

    if (blur) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: content,
        ),
      );
    }

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: content);
    }

    return content;
  }
}

/// A circular glass button with iOS 26 styling
class GlassCircleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final bool elevated;
  final Color? tintColor;

  const GlassCircleButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 50,
    this.elevated = false,
    this.tintColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget button = Container(
      width: size,
      height: size,
      decoration: tintColor != null
          ? BoxDecoration(
              shape: BoxShape.circle,
              color: tintColor!.withAlpha(isDark ? 40 : 30),
              border: Border.all(
                color: tintColor!.withAlpha(isDark ? 80 : 60),
                width: GlassTheme.borderWidth,
              ),
              boxShadow: [
                if (elevated) GlassTheme.elevatedShadow(isDark),
              ],
            )
          : GlassTheme.circularGlassDecoration(
              isDark: isDark,
              elevated: elevated,
            ),
      child: ClipOval(
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: Center(child: child),
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: button);
    }
    return button;
  }
}

/// A pill-shaped glass container (for navigation bars)
class GlassPillContainer extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final bool elevated;

  const GlassPillContainer({
    super.key,
    required this.child,
    this.height = 76,
    this.padding,
    this.margin,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget content = Container(
      height: height,
      padding: padding,
      decoration: GlassTheme.pillGlassDecoration(
        isDark: isDark,
        elevated: elevated,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTheme.radiusPill),
        child: BackdropFilter(
          filter: GlassTheme.blurFilter,
          child: child,
        ),
      ),
    );

    if (margin != null) {
      content = Padding(padding: margin!, child: content);
    }

    return content;
  }
}

/// Extension for easy theme access from BuildContext
extension GlassThemeExtension on BuildContext {
  bool get isDarkMode {
    return Theme.of(this).brightness == Brightness.dark;
  }

  Color get glassColor => GlassTheme.glassColor(isDarkMode);
  Color get glassBorderColor => GlassTheme.glassBorderColor(isDarkMode);
  BoxShadow get glassShadow => GlassTheme.shadow(isDarkMode);

  BoxDecoration glassDecoration({double radius = GlassTheme.radiusMedium}) {
    return GlassTheme.glassDecoration(isDark: isDarkMode, radius: radius);
  }
}
