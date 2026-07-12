/// App Color Palette — OrbGuard on the 2026 OrbVPN brand kit.
///
/// SINGLE SOURCE OF TRUTH for every color in the app (with `brand.dart` for
/// theme-aware glass/metric/typography tokens that build on these).
/// Volt Lime + Cyber Pink on obsidian/cloud, Apple-style liquid glass.
///
/// USAGE RULES (from the brand kit):
///  1. One lime action per screen — the single primary intent. Else glass/neutral.
///  2. Pink punctuates — alerts, live indicators, small accents. Never large fills.
///  3. Obsidian / cloud leads — generous background space is the trust signal.
///  4. Glass over color — glass needs a colorful bed behind it (BrandBed).
///  5. Lime is fill-only — always dark [Brand.onLime] text on lime; never lime
///     text on white (use [accentInk]).
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._(); // Private constructor

  // ==========================================
  // Primary Brand Colors
  // ==========================================

  /// Primary brand action — Volt Lime (fill-only; use dark onLime text on it).
  static const Color primary = Color(0xFFC6FF3D);
  static const Color primaryDark = Color(0xFFB2E82F);
  static const Color primaryLight = Color(0xFFD6FF6E);

  /// Secondary brand accent — Cyber Pink.
  static const Color secondary = Color(0xFFFF3DA6);
  static const Color secondaryDark = Color(0xFFD81B86);
  static const Color secondaryLight = Color(0xFFFF6CC0);

  /// Accent — Volt Lime (the kit uses one accent family).
  static const Color accent = Color(0xFFC6FF3D);
  static const Color accentDark = Color(0xFFB2E82F);
  static const Color accentLight = Color(0xFFD6FF6E);

  // ==========================================
  // Status Colors
  // ==========================================

  /// Success / protected / live — Volt Lime.
  static const Color success = Color(0xFFC6FF3D);
  static const Color successLight = Color(0xFFD6FF6E);
  static const Color successDark = Color(0xFFB2E82F);

  /// Warning — Cyber Pink (the kit has no amber; pink is the alert accent).
  static const Color warning = Color(0xFFFF3DA6);
  static const Color warningLight = Color(0xFFFF6CC0);
  static const Color warningDark = Color(0xFFD81B86);

  /// Error / danger.
  static const Color error = Color(0xFFFF5C6C);
  static const Color errorLight = Color(0xFFFF8A8A);
  static const Color errorDark = Color(0xFFE0354A);

  /// Info — Cyber Pink accent.
  static const Color info = Color(0xFFFF3DA6);
  static const Color infoLight = Color(0xFFFF6CC0);
  static const Color infoDark = Color(0xFFD81B86);

  // ==========================================
  // Threat Status Colors
  // ==========================================

  /// Protected / safe — Volt Lime (the brand "live" state).
  static const Color protected = Color(0xFFC6FF3D);

  /// Scanning / working — neutral grey (kit: motion conveys progress, not color).
  static const Color scanning = Color(0xFF9A9CA6);

  /// Threat detected — danger red.
  static const Color threatDetected = Color(0xFFFF5C6C);

  /// Idle (soft grey) — brand text-2.
  static const Color idle = Color(0xFF9A9CA6);

  /// Critical threat — deep danger red.
  static const Color critical = Color(0xFFE0354A);

  // ==========================================
  // Light Theme Colors
  // ==========================================

  /// Background — brand kit "cloud" (`--bg` light).
  static const Color backgroundLight = Color(0xFFF4F5F1);

  /// Surface (cards, dialogs) — brand kit `--surface` light.
  static const Color surfaceLight = Color(0xFFFFFFFF);

  /// Text colors — brand `--text` / `--text-2` / `--text-3` (light).
  static const Color textPrimary = Color(0xFF0B0B0E);
  static const Color textSecondary = Color(0xFF5A5C66);
  static const Color textDisabled = Color(0xFF8A8C96);

  /// Divider — brand hairline (light).
  static const Color divider = Color(0xFFDCDDE1);

  // ==========================================
  // Dark Theme Colors
  // ==========================================

  /// Background — brand kit "obsidian" (`--bg` dark).
  static const Color backgroundDark = Color(0xFF08080A);

  /// Surface (cards, dialogs) — brand kit `--surface` dark.
  static const Color surfaceDark = Color(0xFF131316);

  /// Text colors — brand `--text` / `--text-2` / `--text-3` (dark).
  static const Color textPrimaryDark = Color(0xFFF5F6F8);
  static const Color textSecondaryDark = Color(0xFF9A9CA6);
  static const Color textDisabledDark = Color(0xFF6F717C);

  /// Divider — brand hairline (dark).
  static const Color dividerDark = Color(0xFF2A2A30);

  /// Dark theme gradient colors — brand obsidian / surface.
  static const Color gradientDarkStart = Color(0xFF08080A);
  static const Color gradientDarkMid = Color(0xFF131316);
  static const Color gradientDarkEnd = Color(0xFF08080A);

  // ==========================================
  // Theme-aware brightness + INK tokens
  // ==========================================

  /// Synced in MaterialApp.builder (main.dart). Defaults to dark — unchanged
  /// until set. Powers every theme-aware getter here and in `brand.dart`.
  static Brightness uiBrightness = Brightness.dark;

  static bool get _dark => uiBrightness == Brightness.dark;

  /// Theme-aware secondary text (brand --text-2). NOT const.
  static Color get text2 => _dark ? textSecondaryDark : textSecondary;

  // Kit rule: raw lime (#C6FF3D) is a FILL color — as ink it fails contrast on
  // light. Use these for any lime/pink/red-colored text, icon or indicator;
  // they resolve to the vivid hue on dark and the contrast-safe deep variant
  // on light. NOT const — do not use inside const expressions.

  /// Lime-family ink (accent/primary/success as text/icon): lime on dark,
  /// deep lime #5C8A00 on light.
  static Color get accentInk => _dark ? accent : const Color(0xFF5C8A00);

  /// Pink-family ink (secondary/warning/info as text/icon): #FF6CC0 on dark,
  /// #D81B86 on light (AA).
  static Color get secondaryInk =>
      _dark ? const Color(0xFFFF6CC0) : const Color(0xFFD81B86);

  /// Danger/error ink (error as text/icon): #FF5C6C dark · #E0354A light (AA).
  static Color get errorInk =>
      _dark ? const Color(0xFFFF5C6C) : const Color(0xFFE0354A);

  /// Amber/gold ink (medium-tier signals): gold on dark · deep amber on light.
  static Color get amberInk =>
      _dark ? const Color(0xFFFFB800) : const Color(0xFF8A6500);

  /// Selected-pill tint for chips/tags/segments (kit: "only the active item
  /// takes lime"): lime@.14 on dark · #96C414@.20 on light. Pair with
  /// [accentInk] for the label/icon — never a solid lime fill + white text.
  static Color get accentPill =>
      _dark ? const Color(0x24C6FF3D) : const Color(0x3396C414);

  // ==========================================
  // On-light foreground tokens (WCAG AA)
  // ==========================================

  static const Color accentOnLight = Color(0xFF5C8A00); // deep lime ink
  static const Color successOnLight = Color(0xFF2E7D32); // 5.13:1
  static const Color warningOnLight = Color(0xFFD81B86); // pink alert on light
  static const Color infoOnLight = Color(0xFFD81B86);
  static const Color errorOnLight = Color(0xFFD32F2F); // 4.98:1
  static const Color amberOnLight = Color(0xFF8A6500); // 5.10:1

  /// ORB currency identity (product token — NOT a brand accent).
  static const Color orbGold = Color(0xFFFFB800);

  // ==========================================
  // Gradient Colors
  // ==========================================

  /// Primary gradient — lime.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Secondary gradient — pink.
  static const LinearGradient secondaryGradient = LinearGradient(
    colors: [secondary, secondaryDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Accent gradient — lime.
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accent, accentDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Success gradient — lime.
  static const LinearGradient successGradient = LinearGradient(
    colors: [success, successDark],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Background gradient (for splash, onboarding) — lime → pink.
  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ==========================================
  // Severity Colors (brand-disciplined ramp)
  // ==========================================
  // critical = deep danger · high = danger · medium = pink (the kit's alert
  // accent) · low = gold · info = neutral text-2. Use as badge/tint FILLS;
  // for text/icons prefer the *Ink getters.

  static const Color severityCritical = Color(0xFFE0354A);
  static const Color severityHigh = Color(0xFFFF5C6C);
  static const Color severityMedium = Color(0xFFFF3DA6);
  static const Color severityLow = Color(0xFFFFB800);
  static const Color severityInfo = Color(0xFF9A9CA6);

  // ==========================================
  // Chart Colors (statistics) — brand spectrum family
  // ==========================================

  static const List<Color> chartColors = [
    Color(0xFFC6FF3D), // Volt Lime
    Color(0xFFFF3DA6), // Cyber Pink
    Color(0xFF53D2D8), // Spectrum cyan
    Color(0xFF9FB1E6), // Spectrum periwinkle
    Color(0xFFC79BD6), // Spectrum light-purple
    Color(0xFFFFB800), // ORB gold
    Color(0xFF7FE6A8), // Spectrum mint
    Color(0xFFFF5C6C), // Danger red
  ];

  // ==========================================
  // Glass UI Colors — brand `--glass-fill` / `--glass-border`
  // ==========================================

  /// Glass fill for light mode — white .55.
  static Color get glassLight => Colors.white.withValues(alpha: 0.55);

  /// Glass fill for dark mode — white .08.
  static Color get glassDark => Colors.white.withValues(alpha: 0.08);

  /// Glass border for light mode — rgba(18,18,28,.08).
  static Color get glassBorderLight =>
      const Color(0xFF12121C).withValues(alpha: 0.08);

  /// Glass border for dark mode — white .18.
  static Color get glassBorderDark => Colors.white.withValues(alpha: 0.18);

  // ==========================================
  // Opacity Variants
  // ==========================================

  /// Get color with opacity
  static Color withOpacity(Color color, double opacity) {
    return color.withValues(alpha: opacity);
  }

  /// Semi-transparent overlay
  static Color get overlay => Colors.black.withValues(alpha: 0.5);

  /// Light overlay
  static Color get overlayLight => Colors.black.withValues(alpha: 0.2);

  /// Dark overlay
  static Color get overlayDark => Colors.black.withValues(alpha: 0.7);

  // ==========================================
  // Refined Design-System Tokens (v2 — dual mode)
  // Same names as before (AppTheme/ColorScheme consume these) — values now
  // resolve to the 2026 brand kit.
  // ==========================================

  // Brand accent, mode-tuned for contrast/vibrancy
  /// Volt Lime for dark surfaces (fill + ink on dark).
  static const Color brandDark = Color(0xFFC6FF3D);
  /// Deep lime for legibility on light surfaces (ink; lime stays fill-only).
  static const Color brandLight = Color(0xFF5C8A00);

  // ---- Dark scheme (obsidian, layered) ----
  /// App background base — obsidian.
  static const Color bgDark = Color(0xFF08080A);
  /// Gradient ends for the ambient background.
  static const Color bgDarkTop = Color(0xFF111114);
  static const Color bgDarkBottom = Color(0xFF08080A);
  /// Elevated card/sheet surface.
  static const Color surfaceDarkElevated = Color(0xFF131316);
  static const Color surfaceDarkHigh = Color(0xFF1C1C21);
  /// Text on dark.
  static const Color onDark = Color(0xFFF5F6F8);
  static const Color onDarkMuted = Color(0xFF9A9CA6);
  static const Color onDarkFaint = Color(0xFF6F717C);
  static const Color outlineDark = Color(0x1AFFFFFF); // white @ .10

  // ---- Light scheme (cloud, frosted glass) ----
  /// App background base — cloud.
  static const Color bgLight = Color(0xFFF4F5F1);
  static const Color bgLightTop = Color(0xFFFAFBF7);
  static const Color bgLightBottom = Color(0xFFECEDE7);
  /// Elevated card/sheet surface (white).
  static const Color surfaceLightElevated = Color(0xFFFFFFFF);
  static const Color surfaceLightHigh = Color(0xFFECEDE7);
  /// Text on light.
  static const Color onLight = Color(0xFF0B0B0E);
  static const Color onLightMuted = Color(0xFF5A5C66);
  static const Color onLightFaint = Color(0xFF8A8C96);
  static const Color outlineLight = Color(0x1A12121C); // #12121C @ .10
}
