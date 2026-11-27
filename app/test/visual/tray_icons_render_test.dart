// Draws the tray icon for Windows and Linux in every state the ring can be
// in, for a dark and a light taskbar, into assets/tray/. Also draws a sheet
// to look at: every icon on both taskbars, magnified, and the tray menu for
// each of Home's moments.
//
// The ring is drawn the way the Mac's menu bar ring draws it at menu bar size
// (macos/Runner/GlanceRing.swift, GlanceRingPainter): Home's ring geometry
// (OrbGeometry in lib/widgets/home/orb_ring.dart), the brand's ring tokens,
// an amber spark at each gap, dots when never checked, the band without its
// colour when nothing is on watch, and the logo mark before any glance. As
// on the Mac, a tiny ring gets fewer, larger dots and sparks held at a size
// that still reads.
//
// Each size is drawn at its own pixels, not scaled from a bigger one:
// Windows gets 16, 20, 24 and 32 in one .ico (plain 32 bit bitmaps, which
// every Windows reads), Linux gets 22, 24 and 32 as PNGs.
//
// Skipped unless asked:
//
//   flutter test test/visual/tray_icons_render_test.dart \
//       --dart-define=TRAY_ASSETS=true \
//       --dart-define=RENDER_DIR=/absolute/folder
//
// TRAY_ASSETS writes the icons into assets/tray/. RENDER_DIR writes the
// sheets there.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/services/desktop/desktop_tray.dart';
import 'package:orbguard/services/home/glance.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';
import 'package:orbguard/widgets/home/orb_ring.dart';

import '../support/real_fonts.dart';

const bool _assets = bool.fromEnvironment('TRAY_ASSETS');
const String _dir = String.fromEnvironment('RENDER_DIR');

// ── The state a picture shows, read back from its name ─────────────────────

enum _Mode { logo, fresh, band }

class _State {
  const _State(this.mode, {this.gaps = const [], this.still = false});

  factory _State.of(String key) {
    if (key == 'logo') return const _State(_Mode.logo);
    if (key == 'fresh') return const _State(_Mode.fresh);
    final List<String> parts = key.split('-');
    return _State(
      _Mode.band,
      still: parts.first == 'still',
      gaps: [for (final String g in parts.skip(1)) double.parse(g)],
    );
  }

  final _Mode mode;
  final List<double> gaps;
  final bool still;
}

// ── The ring at tray size (GlanceRingPainter, ported) ──────────────────────

const double _r = OrbGeometry.centre;
const double _w = OrbGeometry.thickness;
const double _sparkR = 4.6;
const double _dotR = 1.6;

double _rad(double fromTop) => (fromTop - 90) * math.pi / 180;
Offset _at(double fromTop, double radius) =>
    Offset(radius * math.cos(_rad(fromTop)), radius * math.sin(_rad(fromTop)));

/// saturate(.12) then brightness(.82), as orb_ring.dart's still filter.
Color _stillColour(Color c) => Color.from(
      alpha: c.a,
      red: 0.2521 * c.r + 0.5159 * c.g + 0.0520 * c.b,
      green: 0.1537 * c.r + 0.6143 * c.g + 0.0520 * c.b,
      blue: 0.1537 * c.r + 0.5159 * c.g + 0.1504 * c.b,
    );

List<double> _even(int n) => [for (int i = 0; i < n; i++) i / (n - 1)];

/// Draws [state] filling a [side] pixel square, with the tokens of [shade].
void _paint(Canvas canvas, double side, _State state, Brightness shade) {
  final Brightness was = AppColors.uiBrightness;
  AppColors.uiBrightness = shade;
  try {
    canvas.save();
    canvas.translate(side / 2, side / 2);

    if (state.mode == _Mode.logo) {
      // orbguard_icon.svg: a circle of radius 34 and stroke 22 in a 100 box,
      // its ramp centred up and left. The logo's ramp is the light one, in
      // both themes.
      final double u = side / 100;
      canvas.scale(u);
      AppColors.uiBrightness = Brightness.light;
      final List<Color> logo = Brand.orbFill;
      canvas.drawCircle(
        Offset.zero,
        34,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..isAntiAlias = true
          ..shader = ui.Gradient.radial(
              const Offset(-12, -12), 62, logo, _even(logo.length)),
      );
      canvas.restore();
      return;
    }

    final double u = side / OrbGeometry.box;
    canvas.scale(u);

    // The track: the empty channel under everything.
    canvas.drawCircle(
      Offset.zero,
      _r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _w
        ..color = Brand.orbTrack,
    );

    switch (state.mode) {
      case _Mode.logo:
        break;

      case _Mode.fresh:
        // Never checked: a ring of dots, fewer and larger than Home's so
        // they still read as dots at 16 px.
        const int count = 12;
        final double dot = math.max(_dotR, 0.8 / u);
        final Paint paint = Paint()..color = Brand.text3.withValues(alpha: 0.9);
        for (int i = 0; i < count; i++) {
          canvas.drawCircle(_at(i * 360 / count, _r), dot, paint);
        }

      case _Mode.band:
        final List<Color> ramp = state.still
            ? [for (final Color c in Brand.orbFill) _stillColour(c)]
            : Brand.orbFill;
        final Shader body = ui.Gradient.radial(
            const Offset(-20, -22), 124, ramp, _even(ramp.length));
        final Shader sheen = ui.Gradient.linear(
          const Offset(-80, -80),
          const Offset(80, 80),
          [
            Brand.orbSheen.withValues(alpha: 0.18),
            Brand.orbSheen.withValues(alpha: 0),
            Brand.orbShade.withValues(alpha: 0.14),
          ],
          const [0, 0.42, 1],
        );
        for (final Shader shader in [body, sheen]) {
          final Paint paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _w
            ..strokeCap = StrokeCap.round
            ..shader = shader;
          for (final OrbArc arc in OrbGeometry.body(state.gaps)) {
            if (arc.isWhole) {
              canvas.drawCircle(Offset.zero, _r, paint);
            } else {
              canvas.drawArc(
                Rect.fromCircle(center: Offset.zero, radius: _r),
                _rad(arc.start),
                arc.sweep * math.pi / 180,
                false,
                paint,
              );
            }
          }
        }
        // Home's depth: both edges of the band shaded, kept inside the band.
        // The Mac's menu bar ring leaves it out; here it keeps the band's
        // edge on a light taskbar, where the ramp's palest part would
        // otherwise melt into the bar.
        final double depth = state.still ? 0.5 : 1;
        canvas.save();
        canvas.clipPath(_outline(OrbGeometry.body(state.gaps)));
        canvas.drawCircle(
          Offset.zero,
          OrbGeometry.inner + 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..color = Brand.orbDepth.withValues(alpha: 0.28 * depth)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
        );
        canvas.drawCircle(
          Offset.zero,
          OrbGeometry.outer - 1,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = Brand.orbDepth.withValues(alpha: 0.2 * depth)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2),
        );
        canvas.restore();

        // An amber spark where the circle is open, held at a visible size.
        final double spark = math.max(_sparkR, 0.95 / u);
        final Paint amber = Paint()..color = Brand.amber;
        for (final double g in state.gaps) {
          canvas.drawCircle(_at(g, _r), spark, amber);
        }
    }
    canvas.restore();
  } finally {
    AppColors.uiBrightness = was;
  }
}

/// The band as a filled shape, as orb_ring.dart draws it for its depth.
Path _outline(List<OrbArc> arcs) {
  const double ro = OrbGeometry.outer, ri = OrbGeometry.inner;
  final Rect outer = Rect.fromCircle(center: Offset.zero, radius: ro);
  final Rect inner = Rect.fromCircle(center: Offset.zero, radius: ri);
  const Radius cap = Radius.circular(_w / 2);
  final Path path = Path();
  for (final OrbArc a in arcs) {
    if (a.isWhole) {
      path
        ..fillType = PathFillType.evenOdd
        ..addOval(outer)
        ..addOval(inner);
      continue;
    }
    final double a0 = _rad(a.start);
    final double sweep = a.sweep * math.pi / 180;
    final double a1 = a0 + sweep;
    final Offset start = Offset(ro * math.cos(a0), ro * math.sin(a0));
    path
      ..moveTo(start.dx, start.dy)
      ..arcTo(outer, a0, sweep, false)
      ..arcToPoint(Offset(ri * math.cos(a1), ri * math.sin(a1)), radius: cap)
      ..arcTo(inner, a1, -sweep, false)
      ..arcToPoint(start, radius: cap)
      ..close();
  }
  return path;
}

Future<ui.Image> _draw(String key, int side, Brightness shade) {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  _paint(canvas, side.toDouble(), _State.of(key), shade);
  return recorder.endRecording().toImage(side, side);
}

Future<Uint8List> _png(ui.Image image) async =>
    (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();

/// One 32 bit bitmap entry of a .ico: the header, the colours bottom row
/// first in BGRA with straight alpha, then the 1 bit mask (set where the
/// pixel is clear) for anything that ignores alpha.
Future<Uint8List> _icoBitmap(ui.Image image) async {
  final int w = image.width, h = image.height;
  final Uint8List rgba =
      (await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba))!
          .buffer
          .asUint8List();
  final int maskRow = ((w + 31) ~/ 32) * 4;
  final BytesBuilder out = BytesBuilder();
  final ByteData header = ByteData(40)
    ..setUint32(0, 40, Endian.little)
    ..setInt32(4, w, Endian.little)
    ..setInt32(8, h * 2, Endian.little)
    ..setUint16(12, 1, Endian.little)
    ..setUint16(14, 32, Endian.little)
    ..setUint32(16, 0, Endian.little)
    ..setUint32(20, w * h * 4 + maskRow * h, Endian.little);
  out.add(header.buffer.asUint8List());
  for (int y = h - 1; y >= 0; y--) {
    for (int x = 0; x < w; x++) {
      final int i = (y * w + x) * 4;
      out.add([rgba[i + 2], rgba[i + 1], rgba[i], rgba[i + 3]]);
    }
  }
  for (int y = h - 1; y >= 0; y--) {
    final Uint8List row = Uint8List(maskRow);
    for (int x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] == 0) row[x >> 3] |= 0x80 >> (x & 7);
    }
    out.add(row);
  }
  return out.toBytes();
}

/// A .ico holding [images], smallest first.
Future<Uint8List> _ico(List<ui.Image> images) async {
  final List<Uint8List> bodies = [
    for (final ui.Image i in images) await _icoBitmap(i),
  ];
  final ByteData dir = ByteData(6 + 16 * images.length)
    ..setUint16(0, 0, Endian.little)
    ..setUint16(2, 1, Endian.little)
    ..setUint16(4, images.length, Endian.little);
  int offset = 6 + 16 * images.length;
  for (int n = 0; n < images.length; n++) {
    final int e = 6 + 16 * n;
    dir
      ..setUint8(e, images[n].width)
      ..setUint8(e + 1, images[n].height)
      ..setUint8(e + 2, 0)
      ..setUint8(e + 3, 0)
      ..setUint16(e + 4, 1, Endian.little)
      ..setUint16(e + 6, 32, Endian.little)
      ..setUint32(e + 8, bodies[n].length, Endian.little)
      ..setUint32(e + 12, offset, Endian.little);
    offset += bodies[n].length;
  }
  return (BytesBuilder()
        ..add(dir.buffer.asUint8List())
        ..add([for (final Uint8List b in bodies) ...b]))
      .toBytes();
}

// ── The sheets ─────────────────────────────────────────────────────────────

/// The taskbars the icons sit on: Windows 11's dark and light taskbar, and a
/// GNOME top bar.
const Map<String, Color> _bars = {
  'dark taskbar': Color(0xFF202020), // vendor identity
  'light taskbar': Color(0xFFF3F3F3), // vendor identity
  'GNOME bar': Color(0xFF000000), // vendor identity
};

TextPainter _text(String s, double size, Color colour,
    {String family = 'IBM Plex Sans', FontWeight weight = FontWeight.w500}) {
  return TextPainter(
    text: TextSpan(
      text: s,
      style: TextStyle(
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          color: colour),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

/// Every icon at every size on each taskbar, magnified with hard pixels.
Future<ui.Image> _iconSheet(Map<String, Map<int, ui.Image>> icons,
    {required List<int> sizes}) async {
  const double zoom = 4, cell = 32 * zoom + 24, label = 300;
  final List<String> keys = icons.keys.toList();
  final double width = label + _bars.length * sizes.length * cell + 24;
  final double height = 60 + keys.length * cell;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas c = Canvas(recorder);
  c.drawRect(Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFF2B2B30)); // vendor identity
  double x = label;
  for (final MapEntry<String, Color> bar in _bars.entries) {
    for (final int s in sizes) {
      _text('${bar.key} $s', 18, const Color(0xFFDDDDDD)) // vendor identity
          .paint(c, Offset(x, 18));
      x += cell;
    }
  }
  for (int row = 0; row < keys.length; row++) {
    final double y = 60 + row * cell;
    _text(keys[row], 22, const Color(0xFFFFFFFF), // vendor identity
            family: 'IBM Plex Mono')
        .paint(c, Offset(16, y + cell / 2 - 14));
    double x = label;
    for (final Color bg in _bars.values) {
      for (final int s in sizes) {
        final ui.Image img = icons[keys[row]]![s]!;
        final double box = s * zoom + 16;
        c.drawRect(Rect.fromLTWH(x, y, box, box), Paint()..color = bg);
        c.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, s.toDouble(), s.toDouble()),
          Rect.fromLTWH(x + 8, y + 8, s * zoom, s * zoom),
          Paint()..filterQuality = FilterQuality.none,
        );
        x += cell;
      }
    }
  }
  return recorder.endRecording().toImage(width.ceil(), height.ceil());
}

/// The tray menu for each of Home's moments, drawn plainly the way Windows
/// draws a menu (the real one is the system's own).
Future<ui.Image> _menuSheet(List<(String, Glance?)> moments, DateTime now,
    {required bool dark}) async {
  const double rowH = 36, menuW = 460, gap = 28, pad = 8;
  final Color bg = dark
      ? const Color(0xFF2C2C2C)
      : const Color(0xFFF9F9F9); // vendor identity
  final Color ink = dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF1B1B1B); // vendor identity
  final Color grey = dark
      ? const Color(0xFF8A8A8A)
      : const Color(0xFF9A9A9A); // vendor identity
  final Color rule = dark
      ? const Color(0xFF454545)
      : const Color(0xFFE0E0E0); // vendor identity
  final List<List<TrayItem>> menus = [
    for (final (String, Glance?) m in moments)
      TrayMenu.of(m.$2, now: now, use24h: true),
  ];
  double height(List<TrayItem> items) => [
        for (final TrayItem i in items) i.isSeparator ? 9.0 : rowH
      ].fold(2 * pad, (a, b) => a + b);
  final double tallest = menus.map(height).reduce(math.max);
  final double width = moments.length * (menuW + gap) + gap;
  final double sheetH = 70 + tallest + gap;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas c = Canvas(recorder);
  c.drawRect(
      Rect.fromLTWH(0, 0, width, sheetH),
      Paint()
        ..color = dark
            ? const Color(0xFF1A1A1A)
            : const Color(0xFFE6E6E6)); // vendor identity
  for (int n = 0; n < moments.length; n++) {
    final double x = gap + n * (menuW + gap);
    _text(moments[n].$1, 18, grey).paint(c, Offset(x, 24));
    final RRect box = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 70, menuW, height(menus[n])),
        const Radius.circular(8));
    c.drawRRect(box, Paint()..color = bg);
    c.drawRRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = rule);
    double y = 70 + pad;
    for (final TrayItem item in menus[n]) {
      if (item.isSeparator) {
        c.drawLine(Offset(x + 12, y + 4.5), Offset(x + menuW - 12, y + 4.5),
            Paint()..color = rule);
        y += 9;
        continue;
      }
      _text(item.label!, 16, item.enabled ? ink : grey, weight: FontWeight.w400)
          .paint(c, Offset(x + 40, y + 8));
      y += rowH;
    }
  }
  return recorder.endRecording().toImage(width.ceil(), sheetH.ceil());
}

GuardStatus _guard(String id, GuardState state) =>
    GuardStatus(id: id, name: id, state: state, detail: '');

Glance _glance(DateTime now,
    {bool checked = true,
    int openThreats = 0,
    int breaches = 0,
    bool watching = true}) {
  final DateTime? at = checked ? now.subtract(const Duration(hours: 2)) : null;
  final HomeBrief brief = HomeBrief.from(
    hasScanned: checked,
    verdictScore: checked ? 92 : -1,
    lastScanAt: at,
    checksRun: checked ? 6 : null,
    openThreats: openThreats,
    breachedAccounts: breaches,
    score: const PrivacyScoreEngine().compute(PrivacySignals(
      lastScanScore: 92,
      daysSinceScan: 0,
      openThreats: openThreats,
      guardsActive: 3,
      guardsAvailable: 3,
      breachedAccounts: breaches,
      riskyPermissionApps: 0,
      unknownVpnActive: false,
      notificationsGranted: true,
    )),
    guards: [
      _guard('spyware_watch',
          watching ? GuardState.active : GuardState.actionNeeded),
      _guard('breach', watching ? GuardState.active : GuardState.actionNeeded),
      _guard('alerts', GuardState.active),
    ],
    guardsResolved: true,
    now: now,
    deviceNoun: 'computer',
  );
  return Glance.from(brief: brief, lastScanAt: at);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadRealFonts);

  test('draws the tray icons', () async {
    final Map<Brightness, Map<String, Map<int, ui.Image>>> drawn = {};
    final List<int> sizes = {
      ...TrayIcon.windowsSizes,
      ...TrayIcon.linuxSizes,
    }.toList()
      ..sort();
    for (final Brightness shade in Brightness.values) {
      final Map<String, Map<int, ui.Image>> byKey = drawn[shade] = {};
      for (final String key in TrayIcon.keys) {
        final Map<int, ui.Image> bySize = byKey[key] = {};
        for (final int s in sizes) {
          bySize[s] = await _draw(key, s, shade);
        }
        if (!_assets) continue;
        final String ico =
            TrayIcon.asset(key, platform: TargetPlatform.windows, shade: shade);
        File(ico).writeAsBytesSync(await _ico(
            [for (final int s in TrayIcon.windowsSizes) bySize[s]!]));
        for (final int s in TrayIcon.linuxSizes) {
          final String png = TrayIcon.asset(key,
              platform: TargetPlatform.linux, shade: shade, scale: s / 22);
          File(png).writeAsBytesSync(await _png(bySize[s]!));
        }
      }
    }

    if (_dir.isEmpty) return;
    Directory(_dir).createSync(recursive: true);
    // Nine states to a page, so each page can be looked at whole.
    for (final Brightness shade in Brightness.values) {
      final List<String> keys = drawn[shade]!.keys.toList();
      for (int page = 0; page * 9 < keys.length; page++) {
        final ui.Image sheet = await _iconSheet({
          for (final String k in keys.skip(page * 9).take(9))
            k: drawn[shade]![k]!,
        }, sizes: sizes);
        File('$_dir/tray_icons_${shade.name}_${page + 1}.png')
            .writeAsBytesSync(await _png(sheet));
      }
    }

    final DateTime now = DateTime(2026, 11, 25, 9, 41);
    final List<(String, Glance?)> moments = [
      ('before any glance', null),
      ('never checked', _glance(now, checked: false)),
      ('all clear', _glance(now)),
      ('found', _glance(now, openThreats: 1)),
      ('found two', _glance(now, openThreats: 1, breaches: 1)),
      ('nothing on watch', _glance(now, watching: false)),
    ];
    for (final bool dark in const [true, false]) {
      final ui.Image sheet = await _menuSheet(moments, now, dark: dark);
      File('$_dir/tray_menu_${dark ? 'dark' : 'light'}.png')
          .writeAsBytesSync(await _png(sheet));
    }
  }, skip: !_assets && _dir.isEmpty);
}
