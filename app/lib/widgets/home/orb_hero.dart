/// Home's hero: the ring with its six shields stationed on an orbit around it.
///
/// The ring is drawn from the brief's real state: dotted until a check has
/// run, open toward each shield that found something, grey when nothing is on
/// watch, and breathing only while something is.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../services/home/home_brief.dart';
import 'orb_ring.dart';
import 'shield_moon.dart';

class OrbHero extends StatelessWidget {
  const OrbHero({
    super.key,
    required this.brief,
    required this.orbit,
    required this.deviceNoun,
    required this.ringLabel,
    this.checking,
    this.onRingTap,
    this.onShieldTap,
  });

  final HomeBrief brief;

  /// Radius of the circle the shields sit on. The ring and the shields take
  /// their sizes from it. See [orbitForWidth].
  final double orbit;
  final String deviceNoun;

  /// What pressing the ring does, said aloud.
  final String ringLabel;

  /// The check running right now, one segment per check, or null when no
  /// check runs. While it runs the ring counts the checks instead of showing
  /// the score, which is about to change.
  final List<OrbSegment>? checking;
  final VoidCallback? onRingTap;
  final void Function(Shield shield)? onShieldTap;

  /// The orbit's radius at its design size, where the ring is 224 across.
  static const double designOrbit = 150;
  static const double _designRing = 224;

  /// Below this the shields would crowd the ring.
  static const double minOrbit = 96;

  /// The widest orbit a screen of [width] holds without a shield leaving it:
  /// half a press target each side, plus 4 of air.
  static double orbitForWidth(double width) => math.max(
      minOrbit, math.min(designOrbit, (width - ShieldMoon.target - 8) / 2));

  /// Height the hero takes for a given orbit.
  static double heightFor(double orbit) => orbit * 2 + 8;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // repaint with the theme
    final double ring = orbit * _designRing / designOrbit;
    // On a small orbit the shields are drawn a little smaller (never the
    // target), so they keep their distance from the ring.
    final double disc = ShieldMoon.designDisc -
        6 *
            ((designOrbit - 20 - orbit) / (designOrbit - 20 - minOrbit))
                .clamp(0.0, 1.0);
    final int? score = brief.score;

    final List<OrbSegment>? checking = this.checking;
    final OrbStatus status = checking != null
        ? OrbStatus.checking(checking)
        : !brief.checked
            ? const OrbStatus.fresh()
            : OrbStatus.open(
                [for (final gap in brief.gaps) gap.shield.angle],
                live: brief.live,
                still: brief.still,
              );

    // The caption follows the ring down, but not past a size that reads.
    final double captionSize = math.max(10.5, ring * 0.053);
    final TextStyle caption = BrandText.body(
      size: captionSize,
      weight: FontWeight.w500,
      color: Brand.text2,
    ).copyWith(height: 1.2, letterSpacing: Brand.track(captionSize * 0.01));

    return SizedBox(
      height: heightFor(orbit),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: Container(
              width: orbit * 2,
              height: orbit * 2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Brand.border),
              ),
            ),
          ),
          OrbRing(
            status: status,
            size: ring,
            onTap: onRingTap,
            semanticLabel: ringLabel,
            child: checking != null
                ? _Count(
                    // A check that has finished, whichever way it went. What
                    // each one found is for the results to say.
                    done: checking
                        .where((s) =>
                            s == OrbSegment.done || s == OrbSegment.unavailable)
                        .length,
                    total: checking.length,
                    ring: ring,
                    caption: caption,
                  )
                : score == null
                    ? Text('Not checked yet',
                        textAlign: TextAlign.center, style: caption)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('$score',
                                maxLines: 1,
                                style: BrandText.numeral(size: ring * 0.158)),
                          ),
                          SizedBox(height: ring * 0.012),
                          Text('privacy score', maxLines: 1, style: caption),
                        ],
                      ),
          ),
          for (final Shield shield in Shield.values)
            Transform.translate(
              offset: Offset(
                orbit * math.sin(shield.angle * math.pi / 180),
                -orbit * math.cos(shield.angle * math.pi / 180),
              ),
              child: ShieldMoon(
                shield: shield,
                state: brief.shields[shield]!,
                known: brief.shieldsKnown,
                deviceNoun: deviceNoun,
                disc: disc,
                onTap: onShieldTap == null ? null : () => onShieldTap!(shield),
              ),
            ),
        ],
      ),
    );
  }
}

/// The ring's hole while a check runs: how many checks are done, of how many.
class _Count extends StatelessWidget {
  const _Count({
    required this.done,
    required this.total,
    required this.ring,
    required this.caption,
  });

  final int done;
  final int total;
  final double ring;
  final TextStyle caption;

  @override
  Widget build(BuildContext context) {
    final double size = ring * 0.158;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              text: '$done',
              children: [
                TextSpan(
                  text: '/$total',
                  style: BrandText.numeral(
                      size: size * 0.5, color: Brand.text2, tabular: true),
                ),
              ],
            ),
            maxLines: 1,
            style: BrandText.numeral(size: size, tabular: true),
          ),
        ),
        SizedBox(height: ring * 0.012),
        Text('checks', maxLines: 1, style: caption),
      ],
    );
  }
}
