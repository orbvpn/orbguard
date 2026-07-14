/// Glass Theme — 2026 brand-kit Liquid Glass design system.
///
/// Centralized styling for all frosted glass UI elements. Values are the
/// OrbVPN brand kit's `.glass` recipe: fill white .08 (dark) / .55 (light),
/// 1px hairline, blur + saturate backdrop, deep ambient shadow, and a crisp
/// top rim. Mirrors `brand.dart` (Brand.*) — same tokens, `isDark`-parameter
/// API kept for the existing widget fleet.
library;

import 'dart:ui';
import 'package:flutter/material.dart';
import 'brand.dart';
import 'colors.dart';

/// Brand-kit liquid glass design constants
class GlassTheme {
  GlassTheme._();

  // ============================================================================
  // BLUR SETTINGS
  // ============================================================================

  /// Standard blur for glass elements
  static const double blurSigma = 20.0;

  /// Heavy blur for modals and sheets
  static const double blurSigmaHeavy = 30.0;

  /// Light blur for subtle effects
  static const double blurSigmaLight = 12.0;

  // ============================================================================
  // GLASS COLORS — brand `--glass-fill`
  // ============================================================================

  /// Glass fill for light mode — white .55.
  static Color glassColorLight = Colors.white.withValues(alpha: 0.55);

  /// Glass fill for dark mode — white .08.
  static Color glassColorDark = Colors.white.withValues(alpha: 0.08);

  /// Get glass color based on theme
  static Color glassColor(bool isDark) => isDark ? glassColorDark : glassColorLight;

  // ============================================================================
  // BORDER COLORS — brand `--glass-border`
  // ============================================================================

  /// Glass border color for light mode — rgba(18,18,28,.08).
  static Color glassBorderColorLight =
      const Color(0xFF12121C).withValues(alpha: 0.08);

  /// Glass border color for dark mode — white .18.
  static Color glassBorderColorDark = Colors.white.withValues(alpha: 0.18);

  /// Get glass border color based on theme
  static Color glassBorderColor(bool isDark) =>
      isDark ? glassBorderColorDark : glassBorderColorLight;

  /// Standard border width — kit hairline is 1px.
  static const double borderWidth = 1.0;

  // ============================================================================
  // ACCENT COLORS - Using AppColors
  // ============================================================================

  static const Color primaryAccent = AppColors.accent; // Volt Lime
  static const Color secondaryAccent = AppColors.secondary; // Cyber Pink
  static const Color successColor = AppColors.success; // Lime
  static const Color warningColor = AppColors.warning; // Pink
  static const Color errorColor = AppColors.error; // Danger red

  // ============================================================================
  // SHADOWS — the kit's deep ambient shadow
  // ============================================================================

  /// Shadow color for light mode — rgba(20,20,45,.12).
  static Color glassShadowColorLight = const Color(0x1F14142D);

  /// Shadow color for dark mode — rgba(0,0,0,.45).
  static Color glassShadowColorDark = const Color(0x73000000);

  /// Shadow for light mode — `0 18px 40px rgba(20,20,45,.12)`.
  static BoxShadow shadowLight = const BoxShadow(
    color: Color(0x1F14142D),
    blurRadius: 40,
    offset: Offset(0, 18),
  );

  /// Shadow for dark mode — `0 24px 50px rgba(0,0,0,.45)`.
  static BoxShadow shadowDark = const BoxShadow(
    color: Color(0x73000000),
    blurRadius: 50,
    offset: Offset(0, 24),
  );

  /// Get shadow based on theme
  static BoxShadow shadow(bool isDark) => isDark ? shadowDark : shadowLight;

  /// Get list of shadows for glass effect
  static List<BoxShadow> shadows(bool isDark) {
    return [shadow(isDark)];
  }

  /// Elevated shadow for floating elements — same kit ambient shadow.
  static BoxShadow elevatedShadow(bool isDark) => shadow(isDark);

  // ============================================================================
  // LAYOUT
  // ============================================================================

  /// Max content width on wide screens (tablet/desktop).
  static const double contentMaxWidth = 760.0;

  /// Vertical space reserved for the floating pill nav (60 height + 12 margin).
  static const double bottomNavClearance = 72.0;

  // ============================================================================
  // BORDER RADIUS
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

  /// Background gradient colors - dark mode (obsidian)
  static const Color gradientTop = AppColors.bgDarkTop;
  static const Color gradientBottom = AppColors.bgDarkBottom;

  /// Background gradient colors - light mode (cloud)
  static const Color gradientTopLight = AppColors.bgLightTop;
  static const Color gradientBottomLight = AppColors.bgLightBottom;

  /// Top gradient for frosted glass visibility (light mode only)
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

  /// Get complete glass decoration — kit `.glass`: fill with a subtle top
  /// sheen, 1px hairline, ambient shadow.
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

    final hi = isDark
        ? Colors.white.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.45);

    return BoxDecoration(
      // Kit fill gradient: hi-blend at the very top, then uniform fill.
      gradient: customColor != null
          ? null
          : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color.alphaBlend(hi, bgColor), bgColor, bgColor],
              stops: const [0.0, 0.06, 1.0],
            ),
      color: customColor != null ? bgColor : null,
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
      color: tintColor.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: tintColor.withValues(alpha: 0.3),
        width: borderWidth,
      ),
    );
  }

  /// Get background gradient for glass visibility — obsidian/cloud.
  static LinearGradient backgroundGradient({bool isDark = true}) {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: isDark
          ? [gradientTop, AppColors.bgDark, gradientBottom]
          : [gradientTopLight, AppColors.bgLight, gradientBottomLight],
    );
  }

  /// Luminance-preserving saturation matrix (CSS `saturate(s)`).
  static List<double> _saturate(double sat) {
    const double lr = 0.213, lg = 0.715, lb = 0.072;
    final double r = (1 - sat) * lr, g = (1 - sat) * lg, b = (1 - sat) * lb;
    return <double>[
      r + sat, g, b, 0, 0, //
      r, g + sat, b, 0, 0, //
      r, g, b + sat, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  static double get _sat =>
      AppColors.uiBrightness == Brightness.dark ? 1.55 : 1.50;

  /// Standard blur filter — kit backdrop-filter: blur THEN saturate(155%/150%)
  /// so the colorful bed pops through every glass surface.
  static ImageFilter get blurFilter => ImageFilter.compose(
        outer: ColorFilter.matrix(_saturate(_sat)),
        inner: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      );

  /// Light blur filter (inline controls)
  static ImageFilter get blurFilterLight => ImageFilter.compose(
        outer: ColorFilter.matrix(_saturate(_sat)),
        inner: ImageFilter.blur(sigmaX: blurSigmaLight, sigmaY: blurSigmaLight),
      );

  /// Heavy blur filter for modals
  static ImageFilter get blurFilterHeavy => ImageFilter.compose(
        outer: ColorFilter.matrix(_saturate(_sat)),
        inner: ImageFilter.blur(sigmaX: blurSigmaHeavy, sigmaY: blurSigmaHeavy),
      );

  // ============================================================================
  // TEXT STYLES — brand type stack (Archivo / IBM Plex Sans)
  // ============================================================================

  /// Section/card heading — display face.
  static TextStyle headingStyle({bool isDark = true}) {
    return TextStyle(
      fontFamily: Brand.fontDisplay,
      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimary,
      fontWeight: FontWeight.w700,
      fontSize: 18,
    );
  }

  static TextStyle bodyStyle({bool isDark = true}) {
    return TextStyle(
      fontFamily: Brand.fontSans,
      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondary,
      fontSize: 14,
      height: 1.45,
    );
  }

  static TextStyle captionStyle({bool isDark = true}) {
    return TextStyle(
      fontFamily: Brand.fontSans,
      color: isDark ? AppColors.textDisabledDark : AppColors.textDisabled,
      fontSize: 12,
    );
  }
}

// ============================================================================
// REUSABLE GLASS WIDGETS
// ============================================================================

/// Ambient brand background: obsidian/cloud base + the kit's signature
/// lime/pink radial bed (so glass has color to refract), plus the light-mode
/// edge fades. Wraps every route via MaterialApp.builder.
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
    // Full screen brand background
    if (child != null) {
      return Container(
        color: isDark ? AppColors.bgDark : AppColors.bgLight,
        child: Stack(
          children: [
            // Brand bed — lime top-left, pink bottom-right radial washes.
            const BrandBed(),
            // Edge fades for glass visibility (light mode only)
            if (!isDark)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: GlassTheme.topGradientHeight,
                child: Container(decoration: GlassTheme.topGradient),
              ),
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

/// A glass container with brand-kit liquid glass styling: saturated blur,
/// hairline, ambient shadow (un-clipped, on an outer box) and the crisp
/// 1px top rim.
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
    final r = BorderRadius.circular(radius);

    Widget inner = Container(
      padding: padding,
      decoration: GlassTheme.glassDecoration(
        isDark: isDark,
        radius: radius,
        tintColor: tintColor,
        elevated: elevated,
        // Shadow moves to the OUTER box so ClipRRect can't clip it away.
        withShadow: !blur,
      ),
      child: child,
    );

    Widget content;
    if (blur) {
      content = Container(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: [
            elevated
                ? GlassTheme.elevatedShadow(isDark)
                : GlassTheme.shadow(isDark)
          ],
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: GlassTheme.blurFilter,
            child: Stack(
              fit: StackFit.passthrough,
              children: [
                inner,
                // Kit crisp top rim following the corner radius.
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: GlassTopEdgePainter(
                        radius: radius,
                        color: Brand.topEdge,
                        bottomColor: Brand.bottomEdge,
                        topOnly: isDark,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      content = inner;
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

/// A circular glass button with brand-kit styling
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
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Center(child: child),
              // Kit crisp top rim following the circle's top arc.
              if (tintColor == null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: GlassTopEdgePainter(
                        radius: size / 2,
                        color: Brand.topEdge,
                        bottomColor: Brand.bottomEdge,
                        topOnly: isDark,
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
