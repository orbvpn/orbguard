/// OrbGuard Brand System — single source of truth for the 2026 brand kit.
///
/// Shared with OrbVPN (orbx): Volt Lime + Cyber Pink on obsidian/cloud,
/// Apple-style liquid glass. Dark is the default; light flips when
/// [AppColors.uiBrightness] is `Brightness.light` (synced in
/// `MaterialApp.builder` in main.dart).
///
/// USAGE RULES (keep it premium — from the brand kit):
///  1. One lime action per screen — the single primary intent. Else glass/neutral.
///  2. Pink punctuates — alerts, live indicators, small accents. Never large fills.
///  3. Obsidian / cloud leads — generous background space is the trust signal.
///  4. Glass over color — glass needs a colorful/layered backdrop ([bedGradient]).
///  5. Lime is fill-only — always [onLime] text on lime; never lime text on white.
library;

import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'colors.dart';

/// Writing system driving the type tokens (fonts, tracking, line-height).
enum BrandScript { latin, arabic, persian }

/// Brand color + metric tokens. Theme-aware getters read [AppColors.uiBrightness].
class Brand {
  Brand._();

  static bool get _dark => AppColors.uiBrightness == Brightness.dark;

  /// True when the active theme is dark. Used e.g. to keep the glass rim a
  /// strict top-only inset highlight in dark (kit spec) vs the continuous
  /// full-perimeter wrap in light.
  static bool get darkMode => _dark;

  // ── Surfaces & text ──────────────────────────────────────────────────────
  static const Color _bgDark = Color(0xFF08080A);
  static const Color _bgLight = Color(0xFFF4F5F1);
  static Color get bg => _dark ? _bgDark : _bgLight;

  static const Color _surfaceDark = Color(0xFF131316);
  static const Color _surfaceLight = Color(0xFFFFFFFF);
  static Color get surface => _dark ? _surfaceDark : _surfaceLight;

  static const Color _surface2Dark = Color(0xFF1C1C21);
  static const Color _surface2Light = Color(0xFFECEDE7);
  static Color get surface2 => _dark ? _surface2Dark : _surface2Light;

  static const Color _textDark = Color(0xFFF5F6F8);
  static const Color _textLight = Color(0xFF0B0B0E);
  static Color get text => _dark ? _textDark : _textLight;

  static const Color _text2Dark = Color(0xFF9A9CA6);
  static const Color _text2Light = Color(0xFF5A5C66);
  static Color get text2 => _dark ? _text2Dark : _text2Light;

  static const Color _text3Dark = Color(0xFF6F717C);
  static const Color _text3Light = Color(0xFF8A8C96);
  static Color get text3 => _dark ? _text3Dark : _text3Light;

  /// Hairline border. dark rgba(255,255,255,.10) · light rgba(18,18,28,.10)
  static Color get border => _dark
      ? Colors.white.withValues(alpha: 0.10)
      : const Color(0xFF12121C).withValues(alpha: 0.10);

  // ── Brand accents (fills constant across themes) ──────────────────────────
  static const Color lime = Color(0xFFC6FF3D); // primary action / live state
  static const Color onLime = Color(0xFF08080A); // text/icons ON lime
  /// Primary (lime) button interaction states — kit-exact.
  static Color get limeHover => _dark ? const Color(0xFFB2E82F) : const Color(0xFFABE52B);
  static Color get limePressed => _dark ? const Color(0xFF9CCF26) : const Color(0xFF97CC22);

  static const Color pink = Color(0xFFFF3DA6); // accent fills, alerts
  static const Color onPinkDark = Color(0xFF08080A);
  static Color get onPink => _dark ? onPinkDark : Colors.white;
  /// Pink for TEXT (contrast-safe): dark #FF6CC0 · light #D81B86 (AA).
  static Color get pinkInk => _dark ? const Color(0xFFFF6CC0) : const Color(0xFFD81B86);

  /// Lime for TEXT/ICONS (contrast-safe): lime on dark, deep lime on light.
  static Color get limeInk => _dark ? lime : const Color(0xFF5C8A00);

  static Color get danger => _dark ? const Color(0xFFFF5C6C) : const Color(0xFFE0354A);
  /// Text/icon ON a destructive (danger) fill.
  static Color get onDanger => _dark ? const Color(0xFFF5F6F8) : Colors.white;
  static Color get focus => _dark ? lime : const Color(0xFF8FBF1E);

  /// Amber/gold ink for medium-tier signals (severity, latency).
  static Color get amberInk => _dark ? const Color(0xFFFFB800) : const Color(0xFF8A6500);

  // ── Disabled controls (kit): fill = surface2, text/icon = text3 ────────────
  static Color get disabledFill => _dark ? _surface2Dark : _surface2Light;
  static Color get onDisabled => _dark ? _text3Dark : _text3Light;

  // ── Bottom navigation (glass bar; only the ACTIVE item takes lime) ─────────
  /// Active icon + label. Light uses DEEP lime — raw #C6FF3D is a fill color and
  /// fails contrast as an icon tint on white (kit note).
  static Color get navActive => _dark ? lime : const Color(0xFF5C8A00);
  /// Active pill behind the item: dark lime@.14 · light #96C414@.20.
  static Color get navActivePill => _dark
      ? lime.withValues(alpha: 0.14)
      : const Color(0xFF96C414).withValues(alpha: 0.20);
  /// Inactive icon + label = secondary text.
  static Color get navInactive => text2;

  /// ORB currency identity (product token — NOT a brand accent).
  static const Color orbGold = Color(0xFFFFB800);
  static const Color orbGoldLight = Color(0xFFFFD54F);

  // ── Liquid glass ──────────────────────────────────────────────────────────
  static Color get glassFill =>
      _dark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.55);
  /// Hairline — the exact kit border.
  static Color get glassBorder =>
      _dark ? Colors.white.withValues(alpha: 0.18) : const Color(0xFF12121C).withValues(alpha: 0.08);
  /// Top-edge sheen for the corner fades / fill gradient.
  static Color get glassHi =>
      _dark ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.45);

  /// Kit `inset 0 1px 0 rgba(255,255,255,.90)` crisp white top edge — dark .35 ·
  /// light .90. Drawn by [GlassTopEdgePainter] as a 1px stroke that FOLLOWS the
  /// rounded corners.
  static Color get topEdge =>
      _dark ? Colors.white.withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.90);

  /// Bottom end of the continuous perimeter rim (light only; dark fades out).
  static Color get bottomEdge =>
      _dark ? Colors.transparent : Colors.white.withValues(alpha: 0.55);
  static double get glassBlur => _dark ? 24.0 : 22.0;

  // ── Elevation ─────────────────────────────────────────────────────────────
  /// dark 0 24px 50px rgba(0,0,0,.45) · light 0 18px 40px rgba(20,20,45,.12)
  static List<BoxShadow> get shadow => _dark
      ? const [BoxShadow(color: Color(0x73000000), blurRadius: 50, offset: Offset(0, 24))]
      : const [BoxShadow(color: Color(0x1F14142D), blurRadius: 40, offset: Offset(0, 18))];

  // ── Radius ────────────────────────────────────────────────────────────────
  static const double rSm = 11;
  static const double rMd = 14;
  static const double rLg = 22;
  static const double rPill = 999;

  // ── Spacing scale (px): 4 8 12 16 24 32 48 64 96 ──────────────────────────
  static const double s1 = 4, s2 = 8, s3 = 12, s4 = 16, s5 = 24, s6 = 32, s7 = 48, s8 = 64, s9 = 96;

  // ── Type families (script-aware; OrbGuard ships EN today, gates kept for
  //    parity with orbx so future locales inherit the kit RTL rules) ─────────

  /// Active script, driven by the app locale (fa → persian, ar → arabic).
  static BrandScript script = BrandScript.latin;

  static bool get _rtlScript => script != BrandScript.latin;

  /// Display & headings — Archivo · Vazirmatn (fa) · IBM Plex Sans Arabic (ar).
  static String get fontDisplay => switch (script) {
        BrandScript.persian => 'Vazirmatn',
        BrandScript.arabic => 'IBM Plex Sans Arabic',
        BrandScript.latin => 'Archivo',
      };

  /// Body & UI — IBM Plex Sans · Vazirmatn (fa) · IBM Plex Sans Arabic (ar).
  static String get fontSans => switch (script) {
        BrandScript.persian => 'Vazirmatn',
        BrandScript.arabic => 'IBM Plex Sans Arabic',
        BrandScript.latin => 'IBM Plex Sans',
      };

  /// Labels & data — IBM Plex Mono for Latin.
  static String get fontMono => switch (script) {
        BrandScript.persian => 'Vazirmatn',
        BrandScript.arabic => 'IBM Plex Sans Arabic',
        BrandScript.latin => 'IBM Plex Mono',
      };

  /// Letter-spacing gate — NEVER letter-space Arabic script.
  static double track(double latinValue) => _rtlScript ? 0.0 : latinValue;

  /// Real-weights gate — clamp Arabic to ≤700 (no fake bold).
  static FontWeight weight(FontWeight w) {
    if (script == BrandScript.arabic && w.value > FontWeight.w700.value) {
      return FontWeight.w700;
    }
    return w;
  }

  /// Body line-height — kit demands ≥1.8 for Arabic-script body text.
  static double bodyHeight(double latinValue) =>
      _rtlScript ? (latinValue < 1.8 ? 1.8 : latinValue) : latinValue;

  /// Explicit line box for SINGLE-LINE UI text under RTL.
  static double? get uiLineHeight => _rtlScript ? 1.35 : null;

  /// Display/heading line-height under RTL.
  static double displayHeight(double latinValue) =>
      _rtlScript ? (latinValue < 1.35 ? 1.35 : latinValue) : latinValue;

  // ── Liquid-glass material (kit `.glass` / `.glass-sm`) ────────────────────
  /// Luminance-preserving saturation color matrix (CSS `saturate(s)`).
  static List<double> _saturate(double s) {
    const double lr = 0.213, lg = 0.715, lb = 0.072;
    final double r = (1 - s) * lr, g = (1 - s) * lg, b = (1 - s) * lb;
    return <double>[
      r + s, g, b, 0, 0, //
      r, g + s, b, 0, 0, //
      r, g, b + s, 0, 0, //
      0, 0, 0, 1, 0,
    ];
  }

  /// Kit backdrop-filter: `blur(--glass-blur) saturate(155%/150%)` — blur THEN
  /// boost saturation of whatever's behind the glass (so the bed colors pop).
  static ImageFilter get blur => ImageFilter.compose(
        outer: ColorFilter.matrix(_saturate(_dark ? 1.55 : 1.50)),
        inner: ImageFilter.blur(sigmaX: glassBlur, sigmaY: glassBlur),
      );
  static ImageFilter get blurSm => ImageFilter.compose(
        outer: ColorFilter.matrix(_saturate(_dark ? 1.55 : 1.50)),
        inner: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      );

  /// Kit `.glass` decoration. Optional [tint] alpha-blends a state color
  /// (e.g. lime when protected) into fill + border.
  static BoxDecoration glass({double radius = rLg, Color? tint, bool elevated = true}) {
    final fill = tint == null ? glassFill : Color.alphaBlend(tint, glassFill);
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color.alphaBlend(glassHi, fill), fill, fill],
        stops: const [0.0, 0.06, 1.0],
      ),
      border: Border.all(
        color: tint == null ? glassBorder : Color.alphaBlend(tint, glassBorder),
        width: 1,
      ),
      boxShadow: elevated ? shadow : null,
    );
  }

  /// Lighter glass for inline controls (kit `.glass-sm`): blur 12, radius md.
  static BoxDecoration glassSm({double radius = rMd, Color? tint}) =>
      glass(radius: radius, tint: tint, elevated: false);

  /// Kit `.card` — solid `--surface` with `--border` hairline.
  static BoxDecoration card({double radius = rLg}) => BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border, width: 1),
      );

  /// Brand **Spectrum** (kit "Logo / hero only") — lime → mint → cyan →
  /// periwinkle → light-purple. For hero-card gradient borders and the orb.
  static const LinearGradient spectrum = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFC6FF3D),
      Color(0xFF7FE6A8),
      Color(0xFF53D2D8),
      Color(0xFF9FB1E6),
      Color(0xFFC79BD6),
    ],
  );

  /// A colorful bed so glass has something to refract (brand `.glass-bed`).
  static Gradient bedGradient() => RadialGradient(
        center: const Alignment(-0.56, -0.44), // ~22% 28%
        radius: 1.1,
        colors: [lime.withValues(alpha: 0.22), Colors.transparent],
        stops: const [0.0, 0.55],
      );
}

/// Kit `inset 0 1px 0` glass rim as a 1px stroke that follows the rounded
/// corners (never a straight-line "shelf").
///
///  • [topOnly] = false (LIGHT): strokes the WHOLE perimeter with a vertical
///    gradient — brightest at top ([color]) fading to [bottomColor].
///  • [topOnly] = true (DARK): strokes ONLY the top edge + top corner arcs.
class GlassTopEdgePainter extends CustomPainter {
  final double radius;
  final Color color;
  final Color? bottomColor;
  final bool topOnly;
  const GlassTopEdgePainter({
    required this.radius,
    required this.color,
    this.bottomColor,
    this.topOnly = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 1.0;
    final inset = stroke / 2 + 0.5; // sit just inside the 1px hairline border
    final r = (radius - inset).clamp(0.0, size.shortestSide / 2 - inset);

    if (topOnly) {
      if (color.a == 0) return;
      final path = Path()
        ..moveTo(inset, inset + r)
        ..arcToPoint(Offset(inset + r, inset), radius: Radius.circular(r))
        ..lineTo(size.width - inset - r, inset)
        ..arcToPoint(Offset(size.width - inset, inset + r), radius: Radius.circular(r));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
      return;
    }

    final top = color;
    final bottom = bottomColor ?? color;
    if (top.a == 0 && bottom.a == 0) return;
    final rect = Rect.fromLTWH(inset, inset, size.width - 2 * inset, size.height - 2 * inset);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, bottom],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(GlassTopEdgePainter old) =>
      old.radius != radius ||
      old.color != color ||
      old.bottomColor != bottomColor ||
      old.topOnly != topOnly;
}

/// Full-bleed brand bed — the kit's signature lime (top-left) → pink
/// (bottom-right) wash, so liquid-glass surfaces have color to refract
/// (kit rule 4). Drop as the first child of a screen's Stack, behind content.
class BrandBed extends StatelessWidget {
  const BrandBed({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            // Volt-lime, top-left — large/soft so the wash reaches the middle.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.7, -0.95),
                    radius: 1.7,
                    colors: [Brand.lime.withValues(alpha: dark ? 0.15 : 0.30), Colors.transparent],
                    stops: const [0.0, 0.95],
                  ),
                ),
              ),
            ),
            // Cyber-pink, bottom-right
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.9, 0.95),
                    radius: 1.7,
                    colors: [Brand.pink.withValues(alpha: dark ? 0.16 : 0.26), Colors.transparent],
                    stops: const [0.0, 0.95],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kit `.glass` surface rendered faithfully:
///   • uniform `--glass-fill` body
///   • crisp 1px `--glass-hi` top rim following the corner radius
///   • 1px `--glass-border` hairline
///   • the deep ambient `--shadow` on an OUTER box so it is NOT clipped away
class BrandGlass extends StatelessWidget {
  final Widget child;
  final double radius;
  final Color? tint;
  final EdgeInsetsGeometry? padding;
  final bool elevated;
  final List<BoxShadow>? extraShadow;
  /// Draw a [Brand.spectrum] gradient border (kit "logo / hero only") instead
  /// of the plain hairline — for hero/featured cards.
  final bool spectrumBorder;

  const BrandGlass({
    super.key,
    required this.child,
    this.radius = Brand.rLg,
    this.tint,
    this.padding,
    this.elevated = true,
    this.extraShadow,
    this.spectrumBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final fill = tint == null ? Brand.glassFill : Color.alphaBlend(tint!, Brand.glassFill);
    final brd = tint == null ? Brand.glassBorder : Color.alphaBlend(tint!, Brand.glassBorder);
    final r = BorderRadius.circular(radius);
    final shadows = [
      if (elevated) ...Brand.shadow,
      if (extraShadow != null) ...extraShadow!,
    ];

    final glass = Container(
      decoration: BoxDecoration(borderRadius: r, boxShadow: shadows),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: Brand.blur,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Container(
                padding: padding,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: r,
                  border: spectrumBorder ? null : Border.all(color: brd, width: 1),
                ),
                child: child,
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: GlassTopEdgePainter(
                      radius: radius,
                      color: Brand.topEdge,
                      bottomColor: Brand.bottomEdge,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!spectrumBorder) return glass;

    return Stack(
      children: [
        glass,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _SpectrumBorderPainter(radius: radius, strokeWidth: 1.5)),
          ),
        ),
      ],
    );
  }
}

class _SpectrumBorderPainter extends CustomPainter {
  final double radius;
  final double strokeWidth;
  _SpectrumBorderPainter({required this.radius, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = strokeWidth / 2;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(inset, inset, size.width - strokeWidth, size.height - strokeWidth),
      Radius.circular(radius - inset),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = Brand.spectrum.createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_SpectrumBorderPainter old) =>
      old.radius != radius || old.strokeWidth != strokeWidth;
}

/// Circular kit glass (icon buttons) — same crisp rim + hairline + un-clipped
/// ambient shadow as [BrandGlass].
class BrandGlassCircle extends StatelessWidget {
  final Widget child;
  final double size;
  const BrandGlassCircle({super.key, required this.child, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: Brand.shadow),
      child: ClipOval(
        child: BackdropFilter(
          filter: Brand.blur,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.glassFill,
                  border: Border.all(color: Brand.glassBorder, width: 1),
                ),
                child: Center(child: child),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: GlassTopEdgePainter(
                      radius: size / 2,
                      color: Brand.topEdge,
                      bottomColor: Brand.bottomEdge,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Brand typography. Defaults follow the kit's `.t-*` recipes; pass [color] to
/// override (defaults to [Brand.text] / [Brand.text2]).
class BrandText {
  BrandText._();

  /// `.t-display` — Archivo 800, -3% tracking. [size] defaults to 40.
  static TextStyle display({Color? color, double size = 40, FontWeight weight = FontWeight.w800}) =>
      TextStyle(
        fontFamily: Brand.fontDisplay,
        fontWeight: Brand.weight(weight),
        fontSize: size,
        letterSpacing: Brand.track(size * -0.03),
        height: Brand.displayHeight(1.04),
        color: color ?? Brand.text,
      );

  /// `.t-h2` — Archivo 700, -2% tracking.
  static TextStyle h2({Color? color, double size = 30}) => TextStyle(
        fontFamily: Brand.fontDisplay,
        fontWeight: FontWeight.w700,
        fontSize: size,
        letterSpacing: Brand.track(size * -0.02),
        height: Brand.displayHeight(1.2),
        color: color ?? Brand.text,
      );

  /// Heading/value in Archivo at an arbitrary size (e.g. score numerals).
  static TextStyle heading({Color? color, double size = 21, FontWeight weight = FontWeight.w700}) =>
      TextStyle(
        fontFamily: Brand.fontDisplay,
        fontWeight: Brand.weight(weight),
        fontSize: size,
        letterSpacing: Brand.track(size * -0.02),
        height: Brand.uiLineHeight,
        color: color ?? Brand.text,
      );

  /// Title row label — IBM Plex Sans 600.
  static TextStyle title({Color? color, double size = 16, FontWeight weight = FontWeight.w600}) =>
      TextStyle(
        fontFamily: Brand.fontSans,
        fontWeight: Brand.weight(weight),
        fontSize: size,
        letterSpacing: Brand.track(-0.2),
        height: Brand.uiLineHeight,
        color: color ?? Brand.text,
      );

  /// `.t-body` — IBM Plex Sans 400.
  static TextStyle body({Color? color, double size = 16, FontWeight weight = FontWeight.w400}) =>
      TextStyle(
        fontFamily: Brand.fontSans,
        fontWeight: Brand.weight(weight),
        fontSize: size,
        height: Brand.bodyHeight(1.5),
        color: color ?? Brand.text2,
      );

  /// `.t-label` — IBM Plex Mono 500, +16% tracking, UPPERCASE (caller uppercases).
  static TextStyle label({Color? color, double size = 13, FontWeight weight = FontWeight.w500}) =>
      TextStyle(
        fontFamily: Brand.fontMono,
        fontWeight: Brand.weight(weight),
        fontSize: size,
        letterSpacing: Brand.track(size * 0.16),
        height: Brand.uiLineHeight,
        color: color ?? Brand.text2,
      );

  /// Mono data (latency, IP, durations) — tabular figures, mild tracking.
  static TextStyle mono({Color? color, double size = 13, FontWeight weight = FontWeight.w500}) =>
      TextStyle(
        fontFamily: Brand.fontMono,
        fontWeight: Brand.weight(weight),
        fontSize: size,
        letterSpacing: Brand.track(0.2),
        height: Brand.uiLineHeight,
        color: color ?? Brand.text2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
