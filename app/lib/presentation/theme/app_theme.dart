/// AppTheme — OrbGuard's world-class dual-mode design system.
///
/// Two carefully tuned [ThemeData]s (light + dark) sharing one brand language:
/// a single cyan accent, layered neutral surfaces, Inter typography, and
/// consistent component styling. The frosted-glass components in glass_theme
/// derive their mode from [Theme.of(context).brightness], so flipping
/// [MaterialApp.themeMode] re-skins the entire app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

class AppTheme {
  AppTheme._();

  // ---- Shared radii (mirrors GlassTheme) ----
  static const double rLg = 24;
  static const double rMd = 16;
  static const double rSm = 12;

  /// Build a complete Inter-based [TextTheme] tuned for a dense security UI.
  static TextTheme _textTheme(Color onSurface, Color muted) {
    final base = GoogleFonts.interTextTheme();
    TextStyle s(double size, FontWeight w, {double? h, double? ls, Color? c}) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: ls,
          color: c ?? onSurface,
        );
    return base.copyWith(
      // Display / hero numbers (e.g. the security score)
      displayLarge: s(44, FontWeight.w700, h: 1.05, ls: -1.0),
      displayMedium: s(36, FontWeight.w700, h: 1.08, ls: -0.8),
      displaySmall: s(30, FontWeight.w700, h: 1.1, ls: -0.5),
      // Screen titles
      headlineMedium: s(24, FontWeight.w700, h: 1.15, ls: -0.4),
      headlineSmall: s(20, FontWeight.w700, h: 1.2, ls: -0.2),
      // Card / section titles
      titleLarge: s(18, FontWeight.w600, h: 1.25, ls: -0.1),
      titleMedium: s(16, FontWeight.w600, h: 1.3),
      titleSmall: s(14, FontWeight.w600, h: 1.3),
      // Body
      bodyLarge: s(16, FontWeight.w400, h: 1.45, c: onSurface),
      bodyMedium: s(14, FontWeight.w400, h: 1.45, c: onSurface),
      bodySmall: s(12.5, FontWeight.w400, h: 1.4, c: muted),
      // Labels / buttons / chips
      labelLarge: s(14, FontWeight.w600, h: 1.2, ls: 0.1),
      labelMedium: s(12, FontWeight.w600, h: 1.2, ls: 0.2, c: muted),
      labelSmall: s(11, FontWeight.w600, h: 1.2, ls: 0.4, c: muted),
    );
  }

  static ThemeData _build({required bool dark}) {
    final brand = dark ? AppColors.brandDark : AppColors.brandLight;
    final bg = dark ? AppColors.bgDark : AppColors.bgLight;
    final surface = dark ? AppColors.surfaceDarkElevated : AppColors.surfaceLightElevated;
    final surfaceHigh = dark ? AppColors.surfaceDarkHigh : AppColors.surfaceLightHigh;
    final onSurface = dark ? AppColors.onDark : AppColors.onLight;
    final muted = dark ? AppColors.onDarkMuted : AppColors.onLightMuted;
    final outline = dark ? AppColors.outlineDark : AppColors.outlineLight;

    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: brand,
      onPrimary: dark ? const Color(0xFF04222A) : Colors.white,
      primaryContainer: brand.withValues(alpha: dark ? 0.18 : 0.12),
      onPrimaryContainer: brand,
      secondary: AppColors.secondary,
      onSecondary: Colors.white,
      tertiary: AppColors.warning,
      onTertiary: Colors.white,
      error: dark ? AppColors.errorLight : AppColors.errorDark,
      onError: Colors.white,
      errorContainer: AppColors.error.withValues(alpha: dark ? 0.18 : 0.12),
      onErrorContainer: dark ? AppColors.errorLight : AppColors.errorDark,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceHigh,
      onSurfaceVariant: muted,
      outline: outline,
      outlineVariant: outline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: onSurface,
      onInverseSurface: surface,
      inversePrimary: brand,
    );

    final text = _textTheme(onSurface, muted);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      primaryColor: brand,
      // Transparent so the ambient gradient background shows through glass.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: bg,
      splashFactory: InkRipple.splashFactory,
      textTheme: text,
      primaryTextTheme: text,
      iconTheme: IconThemeData(color: onSurface, size: 22),
      dividerTheme: DividerThemeData(color: outline, thickness: 0.6, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: onSurface,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        selectedColor: brand.withValues(alpha: dark ? 0.20 : 0.14),
        side: BorderSide(color: outline),
        labelStyle: text.labelMedium!.copyWith(color: onSurface),
        secondaryLabelStyle: text.labelMedium!.copyWith(color: brand),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(rSm)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          minimumSize: const Size(0, 50),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size(0, 50),
          side: BorderSide(color: outline),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(rMd)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: text.labelLarge,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : muted),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? brand
                : (dark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.10))),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        hintStyle: text.bodyMedium!.copyWith(color: muted),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: brand, width: 1.4),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rLg)),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(rLg)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? AppColors.surfaceDarkHigh
            : AppColors.onLight,
        contentTextStyle: text.bodyMedium!.copyWith(
            color: dark ? AppColors.onDark : Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? AppColors.surfaceDarkHigh : AppColors.onLight,
          borderRadius: BorderRadius.circular(rSm),
        ),
        textStyle: text.labelMedium!.copyWith(
            color: dark ? AppColors.onDark : Colors.white),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: brand),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      }),
    );
  }

  static final ThemeData dark = _build(dark: true);
  static final ThemeData light = _build(dark: false);

  /// Ambient full-screen gradient background for the given brightness.
  static BoxDecoration backgroundDecoration(bool dark) => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [AppColors.bgDarkTop, AppColors.bgDark, AppColors.bgDarkBottom]
              : const [
                  AppColors.bgLightTop,
                  AppColors.bgLight,
                  AppColors.bgLightBottom
                ],
        ),
      );
}

/// Ergonomic theme accessors on [BuildContext].
extension AppThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Primary readable text color (adapts to mode). Use instead of Colors.white.
  Color get onSurface => Theme.of(this).colorScheme.onSurface;

  /// Muted/secondary text color (adapts to mode). Use instead of Colors.white70.
  Color get onSurfaceMuted => Theme.of(this).colorScheme.onSurfaceVariant;
}
