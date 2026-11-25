/// OrbRing — the brand ring as the app's whole status system.
///
/// One drawing says five things, and each is backed by a real state:
///   whole     nothing found, the circle is closed
///   open      something needs the user; the ring opens toward the shield
///             that found it, and closes again when it is dealt with
///   segments  a check is running, one segment per check that can really run
///   dotted    never checked
///   still     nothing is on watch, so the ring loses its colour
///
/// It is painted with arcs and gradients only (no image, no shader asset), from
/// the proportions and colours of `assets/branding/orbguard_icon.svg`. Motion
/// runs only while something real runs ([OrbStatus.live] or a running check),
/// and never when the platform asks for reduced motion.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../presentation/theme/brand.dart';

/// One arc of the ring, in degrees clockwise from twelve o'clock.
@immutable
class OrbArc {
  const OrbArc(this.start, this.sweep);

  final double start;
  final double sweep;

  bool get isWhole => sweep >= 360;

  @override
  bool operator ==(Object other) =>
      other is OrbArc && other.start == start && other.sweep == sweep;

  @override
  int get hashCode => Object.hash(start, sweep);

  @override
  String toString() => 'OrbArc($start, $sweep)';
}

/// The ring's arithmetic, on a 200 unit box. Pure, so it can be tested without
/// a canvas.
abstract final class OrbGeometry {
  /// Side of the design box every other number is measured in.
  static const double box = 200;

  /// Outer and inner edge of the band.
  static const double outer = 96;
  static const double inner = 52;

  /// Radius of the band's centre line, and its thickness.
  static const double centre = (outer + inner) / 2;
  static const double thickness = outer - inner;

  /// Degrees a round end reaches past the arc it caps.
  static final double capDegrees = (thickness / 2) / centre * 180 / math.pi;

  /// Daylight a gap shows between its two round ends, in degrees.
  static const double gapOpening = 15;

  /// How far either side of its centre a gap is cut on the centre line.
  static final double gapHalf = gapOpening / 2 + capDegrees;

  /// The band, broken where the gaps are.
  ///
  /// [gaps] are cut at [openness] of their full width: 1 is fully open, 0 is
  /// closed, and the values between are a gap healing. [held] gaps stay fully
  /// open whatever [openness] says, so one gap can close while another waits.
  static List<OrbArc> body(
    List<double> gaps, {
    double openness = 1,
    List<double> held = const [],
  }) {
    final double closing = gapHalf * openness.clamp(0.0, 1.0);
    final Map<double, double> halves = {
      if (closing >= 0.4)
        for (final g in gaps) _onDial(g): closing,
      for (final g in held) _onDial(g): gapHalf,
    };
    if (halves.isEmpty) return const [OrbArc(0, 360)];

    // One arc from the far side of each gap to the near side of the next.
    final List<double> at = halves.keys.toList()..sort();
    final List<OrbArc> arcs = [];
    for (int i = 0; i < at.length; i++) {
      final bool last = i == at.length - 1;
      final double next = last ? at.first : at[i + 1];
      final double from = at[i] + halves[at[i]]!;
      final double to = next + (last ? 360 : 0) - halves[next]!;
      arcs.add(OrbArc(from, to - from));
    }
    return arcs;
  }

  /// One arc per check, with a little air between them.
  static List<OrbArc> segments(int count) {
    if (count <= 0) return const [];
    final double pad = count > 7 ? 2.2 : 3;
    final double step = 360 / count;
    return [
      for (int i = 0; i < count; i++) OrbArc(i * step + pad, step - 2 * pad),
    ];
  }

  static double _onDial(double degrees) => (degrees % 360 + 360) % 360;
}

/// One check in a running check.
enum OrbSegment {
  /// Not reached yet.
  pending,

  /// Running now.
  running,

  /// Ran.
  done,

  /// Cannot run on this device. Drawn hatched, never as done.
  unavailable,
}

enum _OrbMode { ring, checking, fresh }

/// What the ring is showing. Build it from real state only.
@immutable
class OrbStatus {
  /// A closed circle. [live] when something is verified on watch (the ring
  /// breathes); [still] when checked but nothing is on watch (it loses its
  /// colour). Neither: coloured and at rest.
  const OrbStatus.whole({this.live = false, this.still = false})
      : assert(!(live && still), 'a ring cannot be live and still at once'),
        _mode = _OrbMode.ring,
        gaps = const [],
        segments = const [];

  /// A circle open at each of [gaps], in degrees clockwise from twelve.
  const OrbStatus.open(this.gaps, {this.live = false, this.still = false})
      : assert(!(live && still), 'a ring cannot be live and still at once'),
        _mode = _OrbMode.ring,
        segments = const [];

  /// A check in progress, one entry per check in the order they run.
  const OrbStatus.checking(this.segments)
      : _mode = _OrbMode.checking,
        gaps = const [],
        live = false,
        still = false;

  /// Never checked.
  const OrbStatus.fresh()
      : _mode = _OrbMode.fresh,
        gaps = const [],
        segments = const [],
        live = false,
        still = false;

  final _OrbMode _mode;
  final List<double> gaps;
  final List<OrbSegment> segments;
  final bool live;
  final bool still;

  bool get isRing => _mode == _OrbMode.ring;
  bool get isChecking => _mode == _OrbMode.checking;
  bool get isFresh => _mode == _OrbMode.fresh;

  @override
  bool operator ==(Object other) =>
      other is OrbStatus &&
      other._mode == _mode &&
      other.live == live &&
      other.still == still &&
      listEquals(other.gaps, gaps) &&
      listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(
      _mode, live, still, Object.hashAll(gaps), Object.hashAll(segments));
}

/// The ring. Give it [onTap] and a [semanticLabel] to make it one button;
/// [child] sits in the hole.
class OrbRing extends StatefulWidget {
  const OrbRing({
    super.key,
    required this.status,
    this.size = 224,
    this.onTap,
    this.semanticLabel,
    this.child,
  }) : assert(onTap == null || semanticLabel != null,
            'a ring that can be pressed needs a name');

  final OrbStatus status;

  /// Outer diameter of the band's box. The glow reaches a little past it.
  final double size;
  final VoidCallback? onTap;

  /// Read in place of whatever [child] shows.
  final String? semanticLabel;
  final Widget? child;

  @override
  State<OrbRing> createState() => _OrbRingState();
}

class _OrbRingState extends State<OrbRing> with TickerProviderStateMixin {
  /// Canvas overhang as a share of the ring's size: the bloom reaches 0.7 of
  /// the size from the centre and swells by 22% when the circle closes.
  static const double _bleed = 0.375;

  /// Seconds of ambient motion so far. Only advances while something real runs.
  final ValueNotifier<double> _seconds = ValueNotifier<double>(0);
  late final Ticker _clock;
  late final AnimationController _closing;
  late final AnimationController _flash;

  double _clockBase = 0;
  List<double> _closingGaps = const [];
  bool _reduceMotion = false;
  bool _pressed = false;
  bool _focusRing = false;

  @override
  void initState() {
    super.initState();
    _clock = createTicker((elapsed) {
      _seconds.value =
          _clockBase + elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    _closing = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 820))
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        setState(() => _closingGaps = const []);
        if (widget.status.isRing && widget.status.gaps.isEmpty) {
          _flash.forward(from: 0);
        }
      });
    _flash = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) _settle();
    _syncClock();
  }

  @override
  void didUpdateWidget(OrbRing old) {
    super.didUpdateWidget(old);
    final OrbStatus was = old.status, now = widget.status;
    if (was == now) return;

    if (_reduceMotion || !now.isRing) {
      _settle();
    } else {
      final List<double> closed = was.isRing
          ? [
              for (final g in was.gaps)
                if (!now.gaps.contains(g)) g
            ]
          : const [];
      if (closed.isNotEmpty) {
        // The two ends travel toward each other until the circle is whole.
        _closingGaps = closed;
        _flash.value = 0;
        _closing.forward(from: 0);
      } else if (was.isChecking && now.gaps.isEmpty) {
        _flash.forward(from: 0);
      }
    }
    _syncClock();
  }

  /// Drop any one-shot animation and show the end state.
  void _settle() {
    _closing.stop();
    _flash.stop();
    _flash.value = 0;
    _closingGaps = const [];
  }

  bool get _wantsClock {
    if (_reduceMotion) return false;
    final OrbStatus s = widget.status;
    return s.live || (s.isChecking && s.segments.contains(OrbSegment.running));
  }

  void _syncClock() {
    if (_wantsClock) {
      if (!_clock.isActive) _clock.start();
    } else if (_clock.isActive) {
      _clockBase = _seconds.value;
      _clock.stop();
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _closing.dispose();
    _flash.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _press(bool down) {
    if (_pressed != down) setState(() => _pressed = down);
  }

  @override
  Widget build(BuildContext context) {
    // Brand tokens flip with the theme; depend on it so the ring repaints.
    final Brightness brightness = Theme.of(context).brightness;
    final double size = widget.size;
    final VoidCallback? onTap = widget.onTap;

    // The bloom, and its swell when the circle closes, reach past the band.
    // The canvas is laid out that much larger, so no layer ever clips them.
    final double bleed = size * _bleed;
    Widget ring = SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -bleed,
            top: -bleed,
            right: -bleed,
            bottom: -bleed,
            child: AnimatedScale(
              scale: _pressed ? 0.965 : 1,
              duration: Duration(milliseconds: _reduceMotion ? 0 : 120),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _OrbPainter(
                    diameter: size,
                    bleed: bleed,
                    status: widget.status,
                    closingGaps: _closingGaps,
                    closing: _closing,
                    flash: _flash,
                    seconds: _seconds,
                    moving: _wantsClock,
                    focusRing: _focusRing,
                    palette: _OrbPalette.of(brightness),
                  ),
                ),
              ),
            ),
          ),
          if (widget.child != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(size * 0.25),
                  child: Center(child: widget.child),
                ),
              ),
            ),
        ],
      ),
    );

    if (widget.semanticLabel != null) ring = ExcludeSemantics(child: ring);

    if (onTap != null) {
      ring = FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (show) => setState(() => _focusRing = show),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          excludeFromSemantics: true,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: ring,
        ),
      );
    }

    if (widget.semanticLabel == null) return ring;
    return Semantics(
      container: true,
      button: onTap != null,
      label: widget.semanticLabel,
      onTap: onTap,
      child: ring,
    );
  }
}

/// The ring's colours, read once per build from the kit tokens.
@immutable
class _OrbPalette {
  _OrbPalette.of(this.brightness)
      : fill = Brand.orbFill,
        glow = Brand.orbGlow,
        shadow = Brand.orbShadow,
        track = Brand.orbTrack,
        segmentIdle = Brand.orbSegmentIdle,
        dots = Brand.text3,
        focus = Brand.focus;

  final Brightness brightness;
  final List<Color> fill;
  final Color glow;
  final Color shadow;
  final Color track;
  final Color segmentIdle;
  final Color dots;
  final Color focus;

  @override
  bool operator ==(Object other) =>
      other is _OrbPalette && other.brightness == brightness;

  @override
  int get hashCode => brightness.hashCode;
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.diameter,
    required this.bleed,
    required this.status,
    required this.closingGaps,
    required this.closing,
    required this.flash,
    required this.seconds,
    required this.moving,
    required this.focusRing,
    required this.palette,
  }) : super(repaint: Listenable.merge([seconds, closing, flash]));

  final double diameter;

  /// How far the canvas reaches past the band's box on every side.
  final double bleed;
  final OrbStatus status;
  final List<double> closingGaps;
  final Animation<double> closing;
  final Animation<double> flash;
  final ValueListenable<double> seconds;

  /// False under reduced motion and whenever nothing real is running.
  final bool moving;
  final bool focusRing;
  final _OrbPalette palette;

  static const double _r = OrbGeometry.centre;
  static const double _w = OrbGeometry.thickness;
  static const List<double> _rampStops = [0, 0.2, 0.4, 0.6, 0.8, 1];

  /// The kit's Spectrum as a soft light that patrols the ring: a white head
  /// with a tail through mint, cyan and periwinkle to lilac. Stops are turns
  /// of a sweep whose zero sits 110 degrees behind the head.
  static final List<Color> _glint = () {
    final List<Color> s = Brand.spectrum.colors;
    final Color mint = s[1], cyan = s[2], periwinkle = s[3], lilac = s[4];
    const Color head = Brand.orbSheen;
    return [
      lilac.withValues(alpha: 0),
      lilac.withValues(alpha: 0),
      lilac.withValues(alpha: 0.22),
      periwinkle.withValues(alpha: 0.32),
      cyan.withValues(alpha: 0.40),
      mint.withValues(alpha: 0.46),
      head.withValues(alpha: 0.46),
      head.withValues(alpha: 0.20),
      head.withValues(alpha: 0),
      head.withValues(alpha: 0),
    ];
  }();
  static const List<double> _glintStops = [
    0, 0.0444, 0.1069, 0.1528, 0.1972, 0.2417, 0.2847, 0.3181, 0.35, 1, //
  ];

  /// saturate(.12) then brightness(.82): a ring with nothing on watch.
  static const ColorFilter _stillFilter = ColorFilter.matrix(<double>[
    0.2521, 0.5159, 0.0520, 0, 0, //
    0.1537, 0.6143, 0.0520, 0, 0, //
    0.1537, 0.5159, 0.1504, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  static double _rad(double degreesFromTop) =>
      (degreesFromTop - 90) * math.pi / 180;

  static Offset _at(double degreesFromTop, double radius) {
    final double a = _rad(degreesFromTop);
    return Offset(radius * math.cos(a), radius * math.sin(a));
  }

  /// 0 to 1 and back over [period] seconds, eased at both ends.
  static double _wave(double t, double period) =>
      0.5 - 0.5 * math.cos(2 * math.pi * t / period);

  Paint _band({StrokeCap cap = StrokeCap.round}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = _w
    ..strokeCap = cap;

  ui.Shader get _ramp =>
      ui.Gradient.radial(const Offset(-20, -22), 124, palette.fill, _rampStops);

  @override
  void paint(Canvas canvas, Size size) {
    final double side = diameter;
    final Offset c = size.center(Offset.zero);
    final double t = seconds.value;
    final bool live = moving && status.live;
    final double breath = live ? _wave(t, 7) : 0;
    final double f = flash.value;
    final bool flashing = f > 0 && f < 1;

    // The bloom behind the ring. It swells once when the circle closes.
    final double bloom = flashing
        ? 1
        : (status.isFresh || status.still)
            ? 0.25
            : live
                ? 0.72 + 0.28 * breath
                : 0.86;
    final double swell =
        flashing ? 1 + 0.22 * (f < 0.35 ? f / 0.35 : (1 - f) / 0.65) : 1;
    final double bloomRadius = side * 0.7 * swell;
    canvas.drawCircle(
      c,
      bloomRadius,
      Paint()
        ..shader = ui.Gradient.radial(c, bloomRadius, [
          palette.glow.withValues(alpha: palette.glow.a * bloom),
          palette.glow.withValues(alpha: 0),
        ], const [
          0,
          0.74
        ]),
    );

    // From here on: the ring's own 200 unit box, centred on the origin.
    final double pop = flashing
        ? 0.97 +
            0.03 * Curves.easeOutBack.transform((f * 9 / 7).clamp(0.0, 1.0))
        : 1;
    final double unit = side / OrbGeometry.box;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(unit * (1 + 0.018 * breath) * pop);

    canvas.drawCircle(Offset.zero, _r, _band()..color = palette.track);

    if (status.isFresh) {
      _paintDots(canvas);
    } else if (status.isChecking) {
      _paintSegments(canvas, t);
    } else {
      _paintBody(canvas, t, live);
    }

    if (focusRing) {
      canvas.drawCircle(
        Offset.zero,
        OrbGeometry.outer + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 / unit
          ..color = palette.focus,
      );
    }
    canvas.restore();
  }

  void _paintBody(Canvas canvas, double t, bool live) {
    final Rect ring = Rect.fromCircle(center: Offset.zero, radius: _r);
    final List<OrbArc> arcs = OrbGeometry.body(
      closingGaps,
      openness: 1 - Curves.easeInOut.transform(closing.value),
      held: status.gaps,
    );
    final Path path = Path();
    for (final OrbArc a in arcs) {
      if (a.isWhole) {
        path.addOval(ring);
      } else {
        path.addArc(ring, _rad(a.start), a.sweep * math.pi / 180);
      }
    }
    final ColorFilter? grey = status.still ? _stillFilter : null;

    // Contact shadow, then the band in the logo's ramp, then a sheen from the
    // top left that falls to shade at the bottom right.
    canvas.drawPath(
      path.shift(const Offset(0, 2.5)),
      _band()
        ..color = palette.shadow
        ..colorFilter = grey
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(
        path,
        _band()
          ..shader = _ramp
          ..colorFilter = grey);
    canvas.drawPath(
      path,
      _band()
        ..shader = ui.Gradient.linear(
          const Offset(-80, -80),
          const Offset(80, 80),
          [
            Brand.orbSheen.withValues(alpha: 0.18),
            Brand.orbSheen.withValues(alpha: 0),
            Brand.orbShade.withValues(alpha: 0.14),
          ],
          const [0, 0.42, 1],
        ),
    );

    // Depth: both edges of the band shaded, and a highlight along the upper
    // outer edge. Kept inside the band, so a gap's round ends stay clean.
    final double depth = status.still ? 0.5 : 1;
    canvas.save();
    canvas.clipPath(_outline(arcs));
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
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: OrbGeometry.outer - 9),
      _rad(-62),
      76 * math.pi / 180,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = Brand.orbSheen.withValues(alpha: 0.62 * depth)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.7),
    );
    canvas.restore();

    // The patrol light. It only travels while the ring is live.
    if (!status.still) {
      final double turn = live ? (t / 13) % 1 : 0;
      canvas.drawPath(
        path,
        _band()
          ..blendMode = palette.brightness == Brightness.dark
              ? BlendMode.screen
              : BlendMode.softLight
          ..shader = SweepGradient(
            colors: _glint,
            stops: _glintStops,
            transform: GradientRotation((turn * 360 - 200) * math.pi / 180),
          ).createShader(Rect.fromCircle(
              center: Offset.zero, radius: OrbGeometry.box / 2)),
      );
    }

    // A calm amber spark where the circle is open.
    for (final double gap in status.gaps) {
      final double pulse = live ? _wave(t, 2.2) : 0.57;
      canvas.drawCircle(
        _at(gap, _r),
        4.6 * (0.8 + 0.35 * pulse),
        Paint()
          ..color = Brand.amber.withValues(alpha: live ? 0.7 + 0.3 * pulse : 1),
      );
    }
  }

  /// The band as a filled shape: outer edge, round end, inner edge, round end.
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

  void _paintSegments(Canvas canvas, double t) {
    final Rect ring = Rect.fromCircle(center: Offset.zero, radius: _r);
    final List<OrbArc> arcs = OrbGeometry.segments(status.segments.length);
    final Color idle = palette.segmentIdle;
    final ui.Shader ramp = _ramp;
    for (int i = 0; i < arcs.length; i++) {
      final double start = _rad(arcs[i].start);
      final double sweep = arcs[i].sweep * math.pi / 180;
      final Paint paint = _band(cap: StrokeCap.butt);
      switch (status.segments[i]) {
        case OrbSegment.done:
          paint.shader = ramp;
        case OrbSegment.pending:
          paint.color = idle;
        case OrbSegment.running:
          final double glow = moving ? 0.35 + 0.65 * _wave(t, 0.9) : 1;
          paint.color = idle.withValues(alpha: idle.a * glow);
        case OrbSegment.unavailable:
          // Hatched: 2 unit ticks every 7 units along the centre line.
          paint.color = idle.withValues(alpha: idle.a * 0.55);
          final double tick = 2 / _r, pitch = 7 / _r;
          for (double a = 0; a + tick <= sweep; a += pitch) {
            canvas.drawArc(ring, start + a, tick, false, paint);
          }
          continue;
      }
      canvas.drawArc(ring, start, sweep, false, paint);
    }
  }

  /// Never checked: the centre line as a ring of dots.
  void _paintDots(Canvas canvas) {
    final int count = (2 * math.pi * _r / 9.1).round();
    final Paint dot = Paint()..color = palette.dots.withValues(alpha: 0.9);
    for (int i = 0; i < count; i++) {
      canvas.drawCircle(_at(i * 360 / count, _r), 1.6, dot);
    }
  }

  /// Only the disc is the button, so the corners of its box stay free for
  /// whatever is stationed around the ring.
  @override
  bool hitTest(Offset position) =>
      (position - Offset(bleed + diameter / 2, bleed + diameter / 2))
          .distance <=
      diameter / 2;

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.diameter != diameter ||
      old.bleed != bleed ||
      old.status != status ||
      old.moving != moving ||
      old.focusRing != focusRing ||
      old.palette != palette ||
      !listEquals(old.closingGaps, closingGaps);
}
