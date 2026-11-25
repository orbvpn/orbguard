/// The sheet behind the ring: how the privacy score adds up.
///
/// Seven rules from [PrivacyScoreEngine], in their fixed order, each with
/// the points it earned of the points it is worth. A rule short of its
/// ceiling is amber and opens the fix that earns the rest; a VPN or proxy
/// nobody has confirmed is one more row, the points it takes off. Points the
/// device cannot earn are given, and a note says why. Nothing here is
/// invented: every number is the engine's.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/pressable.dart';
import '../../services/home/privacy_score_engine.dart';
import '../../utils/host_platform.dart';

class ScoreSheet extends StatelessWidget {
  const ScoreSheet({
    super.key,
    required this.score,
    this.onFactorTap,
    this.platform,
  });

  final PrivacyScore score;

  /// Called with a factor's id after the sheet has closed.
  final void Function(String factorId)? onFactorTap;

  /// The device the notes are worded for. Defaults to the one this runs on.
  final TargetPlatform? platform;

  static Future<void> show(
    BuildContext context, {
    required PrivacyScore score,
    void Function(String factorId)? onFactorTap,
    TargetPlatform? platform,
  }) =>
      showAppSheet<void>(
        context,
        child: ScoreSheet(
            score: score, onFactorTap: onFactorTap, platform: platform),
      );

  /// The fix that earns the penalty back.
  static const String _vpnFix = 'review_vpn';

  /// The words on the lime button for a fix worth [points].
  static String actionFor(String factorId, int points) => switch (factorId) {
        'run_check' => 'Run a check, earn $points',
        'enable_guards' => 'Turn on shields, earn $points',
        'check_breaches' => 'Check your email, earn $points',
        'enable_alerts' => 'Turn on alerts, earn $points',
        _ => 'Close the gap, earn $points',
      };

  /// Why a waived rule's points are given, worded for the device.
  static String? noteFor(ScoreRule rule, TargetPlatform? platform) {
    if (!rule.waived) return null;
    final String noun = deviceNounFor(platform);
    switch (rule.id) {
      case 'audit':
        if (platform == TargetPlatform.iOS) {
          return 'iPhone cannot audit other apps, so those last ${rule.max} '
              'points are yours. You are never marked down for something the '
              'system forbids.';
        }
        return 'OrbGuard does not audit other apps on a $noun yet, so those '
            'last ${rule.max} points are yours.';
      case 'alerts':
        return 'Alerts are not available on this $noun yet, so those '
            '${rule.max} points are yours.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TargetPlatform? on = platform ?? hostPlatform();
    final bool good = score.value >= 700;

    void close(String id) {
      Navigator.of(context).pop();
      onFactorTap?.call(id);
    }

    final List<Widget> rows = [
      for (int i = 0; i < score.rules.length; i++)
        _ScoreRow(
          label: score.rules[i].label,
          points: '${score.rules[i].earned} of ${score.rules[i].max}',
          short: !score.rules[i].full,
          divided: i > 0,
          onTap: (!score.rules[i].full && score.rules[i].factorId != null)
              ? () => close(score.rules[i].factorId!)
              : null,
        ),
      if (score.penalty > 0)
        _ScoreRow(
          label: 'A VPN or proxy is not confirmed',
          points: '${score.penalty} off',
          short: true,
          divided: score.rules.isNotEmpty,
          onTap: () => close(_vpnFix),
        ),
    ];
    final List<String> notes = [
      for (final ScoreRule rule in score.rules)
        if (noteFor(rule, on) case final String note) note,
    ];
    final ScoreFactor? top = score.factors.isEmpty ? null : score.factors.first;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('How your score adds up',
                style: BrandText.h2(color: cs.onSurface, size: 23)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text('${score.value}',
                        style: BrandText.numeral(
                            size: 44, color: cs.onSurface, tabular: true)),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('of 1000',
                          style: BrandText.body(size: 15, color: Brand.text2)
                              .copyWith(height: 1)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: good ? AppColors.accentPill : Brand.amberPill,
                  borderRadius: BorderRadius.circular(Brand.rPill),
                ),
                child: Text(score.band,
                    style: BrandText.title(
                        size: 12,
                        color: good ? Brand.limeInk : Brand.amberInk)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _ScoreBar(score: score),
          const SizedBox(height: 6),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...rows,
                  for (final String note in notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(note,
                          style: BrandText.body(size: 13.5, color: Brand.text2)
                              .copyWith(height: Brand.bodyHeight(1.45))),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (top == null)
            BrandButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(),
            )
          else ...[
            // The one lime action: the fix worth the most.
            BrandButton(
              label: actionFor(top.id, top.points),
              onPressed: () => close(top.id),
            ),
            const SizedBox(height: 6),
            _QuietButton(
              label: 'Done',
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ],
      ),
    );
  }
}

/// Seven segments in rule order, each as wide as its rule is worth. The
/// earned share is filled; the missing share is an amber outline.
class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.score});

  final PrivacyScore score;

  @override
  Widget build(BuildContext context) {
    final List<ScoreRule> rules = score.rules;
    return Semantics(
      container: true,
      label: '${score.value} of 1000 points',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (int i = 0; i < rules.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: rules[i].max,
                child: SizedBox(
                  key: ValueKey('score_segment_$i'),
                  height: 8,
                  child: CustomPaint(
                    painter: _SegmentPainter(
                      share: rules[i].max == 0
                          ? 1
                          : rules[i].earned / rules[i].max,
                      fill: Brand.limeInk,
                      miss: Brand.amberInk,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SegmentPainter extends CustomPainter {
  const _SegmentPainter({
    required this.share,
    required this.fill,
    required this.miss,
  });

  final double share;
  final Color fill;
  final Color miss;

  static const double _radius = 4;
  static const double _stroke = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = share.clamp(0.0, 1.0);
    final RRect whole = RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(_radius));
    final double split = size.width * s;

    if (s > 0) {
      canvas.save();
      canvas.clipRRect(whole);
      canvas.drawRect(
          Rect.fromLTWH(0, 0, split, size.height), Paint()..color = fill);
      canvas.restore();
    }
    if (s < 1) {
      const double half = _stroke / 2;
      const Radius r = Radius.circular(_radius - half);
      final Rect rest = Rect.fromLTRB(
          split + half, half, size.width - half, size.height - half);
      final RRect outline = s > 0
          ? RRect.fromRectAndCorners(rest, topRight: r, bottomRight: r)
          : RRect.fromRectAndRadius(rest, r);
      canvas.drawRRect(
        outline,
        Paint()
          ..color = miss
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_SegmentPainter old) =>
      old.share != share || old.fill != fill || old.miss != miss;
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.points,
    required this.short,
    required this.divided,
    required this.onTap,
  });

  final String label;
  final String points;

  /// Short of its ceiling: amber numbers, and a chevron when it opens a fix.
  final bool short;
  final bool divided;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color ink = short ? Brand.amberInk : Brand.text2;
    return Pressable(
      onTap: onTap,
      radius: BorderRadius.circular(Brand.rSm),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border:
              divided ? Border(top: BorderSide(color: Brand.hairline)) : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: BrandText.body(size: 15, color: Brand.text)
                      .copyWith(height: Brand.bodyHeight(1.3))),
            ),
            const SizedBox(width: 10),
            Text(points, style: BrandText.mono(size: 13.5, color: ink)),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              DuotoneIcon(AppIcons.chevronRight,
                  key: const ValueKey('rule_chevron'), size: 17, color: ink),
            ],
          ],
        ),
      ),
    );
  }
}

/// The kit's text button: no fill, quiet ink, a full press target.
class _QuietButton extends StatelessWidget {
  const _QuietButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      radius: BorderRadius.circular(Brand.rMd),
      child: SizedBox(
        height: 44,
        child: Center(
          child: Text(label,
              style: BrandText.title(
                  size: 15, weight: FontWeight.w500, color: Brand.text2)),
        ),
      ),
    );
  }
}
