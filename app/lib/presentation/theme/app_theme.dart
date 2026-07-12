/// AppTheme — OrbGuard on the 2026 OrbVPN brand kit.
///
/// Two [ThemeData]s (light + dark) sharing one brand language: Volt Lime as
/// the single action accent (fill-only; deep-lime ink on light), Cyber Pink
/// punctuation, obsidian/cloud surfaces, liquid glass, and the bundled
/// Archivo / IBM Plex Sans / IBM Plex Mono type stack. The frosted-glass
/// components in glass_theme derive their mode from
/// [Theme.of(context).brightness]; flipping [MaterialApp.themeMode] re-skins
/// the entire app. `AppColors.uiBrightness` is synced in MaterialApp.builder.
library;

// Cupertino import: CupertinoPageTransitionsBuilder moved from the material
// library to cupertino in newer Flutter — importing both resolves it on every
// SDK the app targets (CI pins 3.41.5; dev machines run newer).
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand.dart';
import 'colors.dart';

class AppTheme {
  AppTheme._();

  // ---- Shared radii (mirrors GlassTheme) ----
  static const double rLg = 24;
  static const double rMd = 16;
  static const double rSm = 12;

  // ---- Kit token shorthands (per-brightness; theme build is explicit) ----
  static const Color _lime = Color(0xFFC6FF3D);
  static const Color _onLime = Color(0xFF08080A);
  static Color _limeHover(bool dark) =>
      dark ? const Color(0xFFB2E82F) : const Color(0xFFABE52B);
  static Color _limePressed(bool dark) =>
      dark ? const Color(0xFF9CCF26) : const Color(0xFF97CC22);
  static Color _disabledFill(bool dark) =>
      dark ? const Color(0xFF1C1C21) : const Color(0xFFECEDE7);
  static Color _onDisabled(bool dark) =>
      dark ? const Color(0xFF6F717C) : const Color(0xFF8A8C96);
  static Color _pinkInk(bool dark) =>
      dark ? const Color(0xFFFF6CC0) : const Color(0xFFD81B86);
  // Active accent as INK (icons/labels/indicators): raw lime fails contrast on
  // white, so light uses deep lime.
  static Color _activeInk(bool dark) => dark ? _lime : const Color(0xFF5C8A00);
  static Color _activePill(bool dark) => dark
      ? _lime.withValues(alpha: 0.14)
      : const Color(0xFF96C414).withValues(alpha: 0.20);

  /// Brand type stack (bundled — no runtime font fetch).
  /// Display/headlines = Archivo; body/UI = IBM Plex Sans; data labels = Mono.
  static TextTheme _textTheme(Color onSurface, Color muted) {
    TextStyle d(double size, FontWeight w, {double? h, Color? c}) => TextStyle(
          fontFamily: Brand.fontDisplay,
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: size * -0.02,
          color: c ?? onSurface,
        );
    TextStyle s(double size, FontWeight w, {double? h, double? ls, Color? c}) =>
        TextStyle(
          fontFamily: Brand.fontSans,
          fontSize: size,
          fontWeight: w,
          height: h,
          letterSpacing: ls,
          color: c ?? onSurface,
        );
    return TextTheme(
      // Display / hero numbers (e.g. the security score) — Archivo 800/700
      displayLarge: d(44, FontWeight.w800, h: 1.05),
      displayMedium: d(36, FontWeight.w800, h: 1.08),
      displaySmall: d(30, FontWeight.w700, h: 1.1),
      // Screen titles — Archivo 700
      headlineLarge: d(28, FontWeight.w700, h: 1.15),
      headlineMedium: d(24, FontWeight.w700, h: 1.15),
      headlineSmall: d(20, FontWeight.w700, h: 1.2),
      // Card / section titles — IBM Plex Sans 600
      titleLarge: s(18, FontWeight.w600, h: 1.25, ls: -0.2),
      titleMedium: s(16, FontWeight.w600, h: 1.3, ls: -0.2),
      titleSmall: s(14, FontWeight.w600, h: 1.3),
      // Body — IBM Plex Sans 400
      bodyLarge: s(16, FontWeight.w400, h: 1.5),
      bodyMedium: s(14, FontWeight.w400, h: 1.45),
      bodySmall: s(12.5, FontWeight.w400, h: 1.4, c: muted),
      // Labels / buttons — Plex Sans 600; small data labels lean mono-ish
      labelLarge: s(14, FontWeight.w600, h: 1.2, ls: 0.1),
      labelMedium: s(12, FontWeight.w600, h: 1.2, ls: 0.2, c: muted),
      labelSmall: s(11, FontWeight.w600, h: 1.2, ls: 0.4, c: muted),
    );
  }

  static ThemeData _build({required bool dark}) {
    // Lime is the scheme primary (fills); ink variants applied per-component.
    final bg = dark ? AppColors.bgDark : AppColors.bgLight;
    final surface = dark ? AppColors.surfaceDarkElevated : AppColors.surfaceLightElevated;
    final surfaceHigh = dark ? AppColors.surfaceDarkHigh : AppColors.surfaceLightHigh;
    final onSurface = dark ? AppColors.onDark : AppColors.onLight;
    final muted = dark ? AppColors.onDarkMuted : AppColors.onLightMuted;
    final outline = dark ? AppColors.outlineDark : AppColors.outlineLight;
    final errorInk = dark ? const Color(0xFFFF5C6C) : const Color(0xFFE0354A);

    final scheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: _lime,
      onPrimary: _onLime, // dark text on Volt Lime — kit rule 5
      primaryContainer: _activePill(dark),
      onPrimaryContainer: _activeInk(dark),
      secondary: AppColors.secondary, // Cyber Pink
      onSecondary: dark ? _onLime : Colors.white,
      tertiary: AppColors.orbGold,
      onTertiary: _onLime,
      error: errorInk,
      onError: dark ? const Color(0xFFF5F6F8) : Colors.white,
      errorContainer: AppColors.error.withValues(alpha: dark ? 0.18 : 0.12),
      onErrorContainer: errorInk,
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
      inversePrimary: _activeInk(!dark),
    );

    final text = _textTheme(onSurface, muted);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      primaryColor: _lime,
      fontFamily: Brand.fontSans,
      // Transparent so the ambient brand background shows through glass.
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
      // Chips/tags: surface2 base, hairline; selected takes the active pill
      // tint with active-ink label (only the active item takes lime — kit).
      chipTheme: ChipThemeData(
        backgroundColor: _disabledFill(dark),
        selectedColor: _activePill(dark),
        disabledColor: _disabledFill(dark).withValues(alpha: 0.5),
        side: BorderSide(color: outline),
        labelStyle: text.labelMedium!.copyWith(color: onSurface),
        secondaryLabelStyle: text.labelMedium!.copyWith(color: _activeInk(dark)),
        checkmarkColor: _activeInk(dark),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      // Primary buttons = lime fill with kit hover/pressed/disabled states.
      filledButtonTheme: FilledButtonThemeData(style: _elevatedStyle(dark, text)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: _elevatedStyle(dark, text)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: _outlinedStyle(dark, text, onSurface, outline)),
      textButtonTheme: TextButtonThemeData(style: _textBtnStyle(dark, text)),
      // Switch: lime track + onLime thumb when ON (lime is a FILL here).
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return _onDisabled(dark);
          if (s.contains(WidgetState.selected)) return _onLime;
          return muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? _lime : _disabledFill(dark)),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? Colors.transparent : outline),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return _disabledFill(dark);
          if (s.contains(WidgetState.selected)) return _lime;
          return Colors.transparent;
        }),
        checkColor: const WidgetStatePropertyAll(_onLime),
        side: BorderSide(color: muted, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return _onDisabled(dark);
          if (s.contains(WidgetState.selected)) return _activeInk(dark);
          return muted;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: _lime,
        inactiveTrackColor: _disabledFill(dark),
        thumbColor: _lime,
        overlayColor: _lime.withValues(alpha: 0.12),
        valueIndicatorColor: surface,
        valueIndicatorTextStyle: text.labelLarge!.copyWith(color: onSurface),
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
          // Kit focus token — lime on dark, deep lime tint on light.
          borderSide: BorderSide(
              color: dark ? _lime : const Color(0xFF8FBF1E), width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: errorInk, width: 1.6),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(rMd),
          borderSide: BorderSide(color: errorInk, width: 1.6),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        // Dialog titles carry the display face (kit).
        titleTextStyle: TextStyle(
          fontFamily: Brand.fontDisplay,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        contentTextStyle: text.bodyMedium!.copyWith(color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            dark ? AppColors.surfaceDarkHigh : AppColors.surfaceDark,
        contentTextStyle:
            text.bodyMedium!.copyWith(color: AppColors.onDark),
        actionTextColor: _lime,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(rMd)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? AppColors.surfaceDarkHigh : AppColors.onLight,
          borderRadius: BorderRadius.circular(rSm),
        ),
        textStyle: text.labelMedium!.copyWith(color: AppColors.onDark),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: _activeInk(dark),
        unselectedLabelColor: muted,
        indicatorColor: _activeInk(dark),
        dividerColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall!.copyWith(fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: _activeInk(dark),
        linearTrackColor: _disabledFill(dark),
        circularTrackColor: Colors.transparent,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _lime,
        foregroundColor: _onLime,
        elevation: 4,
      ),
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        TargetPlatform.android: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: const CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: const FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.linux: const FadeUpwardsPageTransitionsBuilder(),
      }),
    );
  }

  /// ElevatedButton / FilledButton = primary lime with kit states.
  static ButtonStyle _elevatedStyle(bool dark, TextTheme text) {
    return ButtonStyle(
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      textStyle: WidgetStatePropertyAll(text.labelLarge!.copyWith(fontSize: 16)),
      backgroundColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return _disabledFill(dark);
        if (s.contains(WidgetState.pressed)) return _limePressed(dark);
        if (s.contains(WidgetState.hovered)) return _limeHover(dark);
        return _lime;
      }),
      foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? _onDisabled(dark) : _onLime),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }

  /// OutlinedButton = secondary/ghost; neutral text + hairline, glass-like.
  static ButtonStyle _outlinedStyle(
      bool dark, TextTheme text, Color onSurface, Color outline) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 14)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      textStyle: WidgetStatePropertyAll(text.labelLarge!.copyWith(fontSize: 16)),
      foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? _onDisabled(dark) : onSurface),
      side: WidgetStateProperty.resolveWith((s) => BorderSide(
            color: s.contains(WidgetState.disabled)
                ? outline.withValues(alpha: 0.5)
                : outline,
          )),
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) return onSurface.withValues(alpha: 0.10);
        if (s.contains(WidgetState.hovered)) return onSurface.withValues(alpha: 0.05);
        return Colors.transparent;
      }),
    );
  }

  /// TextButton = ghost; pink-ink label, subtle overlay on hover/press.
  static ButtonStyle _textBtnStyle(bool dark, TextTheme text) {
    return ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? _onDisabled(dark) : _pinkInk(dark)),
      overlayColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.pressed)) {
          return _pinkInk(dark).withValues(alpha: 0.14);
        }
        if (s.contains(WidgetState.hovered)) {
          return _pinkInk(dark).withValues(alpha: 0.08);
        }
        return Colors.transparent;
      }),
    );
  }

  static final ThemeData dark = _build(dark: true);
  static final ThemeData light = _build(dark: false);

  /// Ambient full-screen gradient background for the given brightness —
  /// obsidian/cloud (the BrandBed radial washes layer on top of this in
  /// GlassGradientBackground).
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
