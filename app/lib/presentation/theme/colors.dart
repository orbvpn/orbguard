/// App Color Palette
///
/// Defines all colors used throughout the application for consistency.
/// Based on the OrbGuard brand color palette, aligned with OrbX design system.
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // Private constructor

  // ==========================================
  // Primary Brand Colors
  // ==========================================

  /// Main brand color (Deep Blue / Navy Blue) - Security & Reliability
  static const Color primary = Color(0xFF1E4A8F);
  static const Color primaryDark = Color(0xFF153668);
  static const Color primaryLight = Color(0xFF2A5BA8);

  /// Secondary brand color (Tech Blue) - Modern & Fresh
  static const Color secondary = Color(0xFF4A90E2);
  static const Color secondaryDark = Color(0xFF3A7AC8);
  static const Color secondaryLight = Color(0xFF6AAAF0);

  /// Alternative Accent (Turquoise/Cyan) - Clarity & Calm
  static const Color accent = Color(0xFF00C1D4);
  static const Color accentDark = Color(0xFF009AAA);
  static const Color accentLight = Color(0xFF33D4E5);

  // ==========================================
  // Status Colors
  // ==========================================

  /// Success color (Connected/Protected state) - using accent turquoise
  static const Color success = Color(0xFF00C1D4);
  static const Color successLight = Color(0xFF33D4E5);
  static const Color successDark = Color(0xFF009AAA);

  /// Warning color (soft orange)
  static const Color warning = Color(0xFFFF9500);
  static const Color warningLight = Color(0xFFFFAD33);
  static const Color warningDark = Color(0xFFE68600);

  /// Error color (soft red)
  static const Color error = Color(0xFFFF6B6B);
  static const Color errorLight = Color(0xFFFF8A8A);
  static const Color errorDark = Color(0xFFE85555);

  /// Info color (tech blue)
  static const Color info = Color(0xFF4A90E2);
  static const Color infoLight = Color(0xFF6AAAF0);
  static const Color infoDark = Color(0xFF3A7AC8);

  // ==========================================
  // Threat Status Colors
  // ==========================================

  /// Protected (turquoise/cyan) - evokes security & calm
  static const Color protected = Color(0xFF00C1D4);

  /// Scanning (orange)
  static const Color scanning = Color(0xFFFF9500);

  /// Threat Detected (soft red)
  static const Color threatDetected = Color(0xFFFF6B6B);

  /// Idle (soft grey)
  static const Color idle = Color(0xFF9CA3AF);

  /// Critical threat (darker red)
  static const Color critical = Color(0xFFE53E3E);

  // ==========================================
  // Light Theme Colors
  // ==========================================

  /// Background - soft blue-grey (Apple Music iOS 26 style)
  /// Provides better contrast for frosted glass visibility
  static const Color backgroundLight = Color(0xFFE9EDF4);

  /// Surface (cards, dialogs) - white
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Text colors
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFBDBDBD);

  /// Divider
  static const Color divider = Color(0xFFE5E7EB);

  // ==========================================
  // Dark Theme Colors
  // ==========================================

  /// Background - dark grey
  static const Color backgroundDark = Color(0xFF121212);

  /// Surface (cards, dialogs) - slightly lighter
  static const Color surfaceDark = Color(0xFF1E1E1E);

  /// Text colors
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);
  static const Color textDisabledDark = Color(0xFF6B7280);

  /// Divider
  static const Color dividerDark = Color(0xFF2C2C2C);

  /// Dark theme gradient colors
  static const Color gradientDarkStart = Color(0xFF121212);
  static const Color gradientDarkMid = Color(0xFF1E1E1E);
  static const Color gradientDarkEnd = Color(0xFF121212);

  // ==========================================
  // Gradient Colors
  // ==========================================

  /// Primary gradient
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Secondary gradient
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Accent gradient (turquoise)
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Success gradient
  static const LinearGradient successGradient = LinearGradient(
    colors: [success, successDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background gradient (for splash, onboarding)
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ==========================================
  // Severity Colors
  // ==========================================

  /// For threat severity levels
  static const Color severityCritical = Color(0xFFE53E3E);
  static const Color severityHigh = Color(0xFFFF6B6B);
  static const Color severityMedium = Color(0xFFFF9500);
  static const Color severityLow = Color(0xFFFFD93D);
  static const Color severityInfo = Color(0xFF4A90E2);

  // ==========================================
  // Chart Colors (for statistics)
  // ==========================================

  static const List<Color> chartColors = [
    Color(0xFF1E4A8F), // Primary blue
    Color(0xFF4A90E2), // Secondary blue
    Color(0xFF00C1D4), // Accent cyan
    Color(0xFFFF9500), // Warning orange
    Color(0xFFFF6B6B), // Error red
    Color(0xFF9C27B0), // Purple
    Color(0xFF00897B), // Teal
    Color(0xFF795548), // Brown
  ];

  // ==========================================
  // Glass UI Colors
  // ==========================================

  /// Glass overlay for light mode
  static Color get glassLight => Colors.white.withAlpha(230);

  /// Glass overlay for dark mode
  static Color get glassDark => Colors.white.withAlpha(22);

  /// Glass border for light mode
  static Color get glassBorderLight => Colors.black.withAlpha(12);

  /// Glass border for dark mode
  static Color get glassBorderDark => Colors.white.withAlpha(30);

  // ==========================================
  // Opacity Variants
  // ==========================================

  /// Get color with opacity
  static Color withOpacity(Color color, double opacity) {
    return color.withOpacity(opacity);
  }

  /// Semi-transparent overlay
  static Color get overlay => Colors.black.withOpacity(0.5);

  /// Light overlay
  static Color get overlayLight => Colors.black.withOpacity(0.2);

  /// Dark overlay
  static Color get overlayDark => Colors.black.withOpacity(0.7);
}
