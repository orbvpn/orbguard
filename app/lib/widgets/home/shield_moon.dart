/// A shield stationed on the orbit around the ring: a 40 glass disc inside a
/// 44 press target, drawn by its real state.
///
///   on       lime ink, lit rim
///   care     amber ink on an amber field: it found something
///   limited  muted ink: this device cannot run it
///   off      dim ink, dashed rim: an empty slot, waiting to be turned on
///
/// Until the guards have answered once it is drawn quiet (dim ink, plain rim),
/// because "not known yet" must not look like "turned off".
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/pressable.dart';
import '../../services/home/home_brief.dart';
import '../shields/shield_look.dart';

/// How a shield's state is said aloud, after its name.
String shieldStateWord(ShieldState state, String deviceNoun) => switch (state) {
      ShieldState.on => 'on',
      ShieldState.care => 'needs you',
      ShieldState.limited => 'limited on this $deviceNoun',
      ShieldState.off => 'off',
    };

class ShieldMoon extends StatelessWidget {
  const ShieldMoon({
    super.key,
    required this.shield,
    required this.state,
    required this.known,
    required this.deviceNoun,
    this.disc = designDisc,
    this.onTap,
  });

  /// Side of the press target. It never shrinks, whatever the disc does.
  static const double target = 44;

  /// Side of the disc at its design size.
  static const double designDisc = 40;

  /// Side of the disc drawn inside the target: smaller on a small orbit, so
  /// the shields keep their distance from the ring.
  final double disc;

  final Shield shield;
  final ShieldState state;

  /// False until the guards have answered once.
  final bool known;
  final String deviceNoun;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Brand tokens flip with the theme; depend on it so the moon repaints.
    Theme.of(context);

    final bool care = state == ShieldState.care;
    final bool dashed = known && state == ShieldState.off;
    final Color ink = !known
        ? Brand.text3
        : switch (state) {
            ShieldState.on => Brand.limeInk,
            ShieldState.care => Brand.amberInk,
            ShieldState.limited => Brand.text2,
            ShieldState.off => Brand.text3,
          };

    return Pressable(
      onTap: onTap,
      semanticLabel: known
          ? '${shield.name}, ${shieldStateWord(state, deviceNoun)}'
          : shield.name,
      child: SizedBox.square(
        dimension: target,
        child: Center(
          child: CustomPaint(
            painter: _DiscPainter(
              // An empty slot is hollow: the page colour, not a lit disc.
              fill: dashed
                  ? Brand.bg
                  : Color.alphaBlend(
                      care ? Brand.amberPill : Brand.glassFill, Brand.bg),
              line: care ? Brand.amberLine : Brand.glassBorder,
              dashed: dashed,
            ),
            foregroundPainter: dashed
                ? null
                : GlassTopEdgePainter(
                    radius: disc / 2,
                    color: Brand.topEdge,
                    bottomColor: Brand.bottomEdge,
                  ),
            child: SizedBox.square(
              dimension: disc,
              child: Center(
                child: DuotoneIcon(shield.icon,
                    size: disc * 19 / designDisc, color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A solid disc (so the orbit line does not show through) with a hairline
/// rim, dashed for a shield that is not turned on.
class _DiscPainter extends CustomPainter {
  const _DiscPainter({
    required this.fill,
    required this.line,
    required this.dashed,
  });

  final Color fill;
  final Color line;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = fill);

    final Paint rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line;
    if (!dashed) {
      canvas.drawCircle(c, r - 0.5, rim);
      return;
    }
    // 3 on, 3 off, evened out so the last dash meets the first cleanly.
    final Rect ring = Rect.fromCircle(center: c, radius: r - 0.5);
    final int dashes = (2 * math.pi * (r - 0.5) / 6).round();
    final double step = 2 * math.pi / dashes;
    for (int i = 0; i < dashes; i++) {
      canvas.drawArc(ring, i * step, step / 2, false, rim);
    }
  }

  @override
  bool shouldRepaint(_DiscPainter old) =>
      old.fill != fill || old.line != line || old.dashed != dashed;
}
