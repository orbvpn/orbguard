/// Glass Theme - iOS 26 Liquid Glass Design System
/// Centralized constants and helpers for glass UI effects

import 'dart:ui';
import 'package:flutter/material.dart';

/// iOS 26 Liquid Glass Theme Constants and Helpers
class GlassTheme {
  GlassTheme._();

  // ============== BLUR CONSTANTS ==============
  static const double blurSigma = 20.0;
  static const double blurSigmaLight = 15.0;
  static const double blurSigmaHeavy = 30.0;

  // ============== BORDER RADIUS ==============
  static const double radiusPill = 38.0;
  static const double radiusLarge = 24.0;
  static const double radiusMedium = 16.0;
  static const double radiusSmall = 12.0;
  static const double radiusXSmall = 8.0;

  // ============== BORDER WIDTH ==============
  static const double borderWidth = 0.5;
  static const double borderWidthThick = 1.0;

  // ============== COLORS - LIGHT MODE ==============
  static Color get glassColorLight => Colors.white.withAlpha(230);
  static Color get glassBorderColorLight => Colors.black.withAlpha(12);
  static Color get glassShadowColorLight => Colors.black.withAlpha(15);

  // ============== COLORS - DARK MODE ==============
  static Color get glassColorDark => Colors.white.withAlpha(22);
  static Color get glassBorderColorDark => Colors.white.withAlpha(30);
  static Color get glassShadowColorDark => Colors.black.withAlpha(40);

  // ============== ACCENT COLORS ==============
  static const Color primaryAccent = Color(0xFF00D9FF); // Cyan
  static const Color secondaryAccent = Color(0xFFFF006E); // Pink
  static const Color successColor = Color(0xFF00E676); // Green
  static const Color warningColor = Color(0xFFFFAB00); // Orange
  static const Color errorColor = Color(0xFFFF5252); // Red

  // ============== BACKGROUND GRADIENT COLORS ==============
  static const Color gradientTop = Color(0xFF1a1a2e);
  static const Color gradientBottom = Color(0xFF0a0a14);
  static const Color gradientTopLight = Color(0xFFf0f4f8);
  static const Color gradientBottomLight = Color(0xFFe0e5eb);

  // ============== HELPER METHODS ==============

  /// Get glass background color based on theme
  static Color glassColor(bool isDark) {
    return isDark ? glassColorDark : glassColorLight;
  }

  /// Get glass border color based on theme
  static Color glassBorderColor(bool isDark) {
    return isDark ? glassBorderColorDark : glassBorderColorLight;
  }

  /// Get glass shadow based on theme
  static BoxShadow shadow(bool isDark) {
    return BoxShadow(
      color: isDark ? glassShadowColorDark : glassShadowColorLight,
      blurRadius: 15,
      offset: const Offset(0, 3),
    );
  }

  /// Get list of shadows for glass effect
  static List<BoxShadow> shadows(bool isDark) {
    return [shadow(isDark)];
  }

  /// Standard blur filter for glass effect
  static ImageFilter get blurFilter {
    return ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma);
  }

  /// Light blur filter
  static ImageFilter get blurFilterLight {
    return ImageFilter.blur(sigmaX: blurSigmaLight, sigmaY: blurSigmaLight);
  }

  /// Heavy blur filter
  static ImageFilter get blurFilterHeavy {
    return ImageFilter.blur(sigmaX: blurSigmaHeavy, sigmaY: blurSigmaHeavy);
  }

  /// Complete glass decoration for containers
  static BoxDecoration glassDecoration({
    bool isDark = true,
    double radius = radiusMedium,
    bool withShadow = true,
    Color? customColor,
    Color? customBorderColor,
  }) {
    return BoxDecoration(
      color: customColor ?? glassColor(isDark),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: customBorderColor ?? glassBorderColor(isDark),
        width: borderWidth,
      ),
      boxShadow: withShadow ? shadows(isDark) : null,
    );
  }

  /// Pill-shaped glass decoration (for nav bars, buttons)
  static BoxDecoration pillGlassDecoration({
    bool isDark = true,
    bool withShadow = true,
  }) {
    return glassDecoration(
      isDark: isDark,
      radius: radiusPill,
      withShadow: withShadow,
    );
  }

  /// Circular glass decoration (for icon buttons)
  static BoxDecoration circularGlassDecoration({
    bool isDark = true,
    bool withShadow = true,
  }) {
    return BoxDecoration(
      color: glassColor(isDark),
      shape: BoxShape.circle,
      border: Border.all(
        color: glassBorderColor(isDark),
        width: borderWidth,
      ),
      boxShadow: withShadow ? shadows(isDark) : null,
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

  /// Get themed text style
  static TextStyle headingStyle({bool isDark = true}) {
    return TextStyle(
      color: isDark ? Colors.white : Colors.black87,
      fontWeight: FontWeight.bold,
      fontSize: 18,
    );
  }

  static TextStyle bodyStyle({bool isDark = true}) {
    return TextStyle(
      color: isDark ? Colors.white70 : Colors.black54,
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
