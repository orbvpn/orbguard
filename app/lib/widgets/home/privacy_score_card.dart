/// PrivacyScoreCard — the 0–1000 privacy score meter for the home control
/// panel (P4.2).
///
/// Renders a [PrivacyScore] that the caller computed with the pure
/// [PrivacyScoreEngine] from REAL signals. The card never invents data:
/// the factor list under the meter is exactly the engine's "fix this to earn
/// N points" output, and when it's empty the card says so plainly.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/home/privacy_score_engine.dart';

class PrivacyScoreCard extends StatefulWidget {
  final PrivacyScore score;

  /// Invoked with a [ScoreFactor.id] when the user taps a specific factor in
  /// the expanded "things to fix" list; the parent routes it to the right
  /// flow (scan, guards, breach check, …). Optional — the inline list still
  /// informs when unwired.
  final void Function(String factorId)? onFactorTap;

  const PrivacyScoreCard({super.key, required this.score, this.onFactorTap});

  @override
  State<PrivacyScoreCard> createState() => _PrivacyScoreCardState();
}

class _PrivacyScoreCardState extends State<PrivacyScoreCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final score = widget.score;

    // Band chip ink: lime ≥700 · amber 450–699 · pink <450 (contrast-safe inks).
    final Color bandInk = score.value >= 700
        ? AppColors.accentInk
        : score.value >= 450
            ? AppColors.amberInk
            : AppColors.secondaryInk;

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row: PRIVACY SCORE + band chip.
          Row(
            children: [
              Expanded(
                child: Text(
                  'PRIVACY SCORE',
                  style: BrandText.label(size: 11.5, color: cs.onSurfaceVariant),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: bandInk.withAlpha(26),
                  borderRadius: BorderRadius.circular(Brand.rPill),
                ),
                child: Text(
                  score.band,
                  style: BrandText.mono(
                      size: 11, color: bandInk, weight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Big value + / 1000.
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${score.value}',
                  style: BrandText.display(size: 44, color: cs.onSurface)),
              const SizedBox(width: 6),
              Text('/ 1000',
                  style:
                      BrandText.mono(size: 13, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),

          // Meter: lime fill fraction on a muted token-derived track.
          Container(
            height: 8,
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: cs.onSurface.withAlpha(20),
              borderRadius: BorderRadius.circular(Brand.rPill),
            ),
            child: FractionallySizedBox(
              widthFactor: (score.value / 1000).clamp(0.0, 1.0),
              heightFactor: 1.0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.accent, // lime is fill-only — this IS a fill
                  borderRadius: BorderRadius.circular(Brand.rPill),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          if (score.factors.isEmpty)
            Row(
              children: [
                DuotoneIcon(AppIcons.checkCircle,
                    size: 18, color: AppColors.accentInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Everything's on — nicely done",
                    style: BrandText.title(
                        size: 13.5, color: AppColors.accentInk),
                  ),
                ),
              ],
            )
          else ...[
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.dangerTriangle,
                      size: 18, color: AppColors.amberInk),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${score.factors.length} thing${score.factors.length == 1 ? '' : 's'} to fix — tap to see',
                      style: BrandText.title(
                          size: 13.5, color: AppColors.amberInk),
                    ),
                  ),
                  DuotoneIcon(
                    _expanded ? AppIcons.chevronUp : AppIcons.chevronDown,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              ...score.factors.map((f) => _FactorRow(
                    factor: f,
                    onTap: widget.onFactorTap == null
                        ? null
                        : () => widget.onFactorTap!(f.id),
                  )),
            ],
          ],
        ],
      ),
    );
  }
}

/// One "fix this to earn N points" row — label + a "+N pts" mono chip.
class _FactorRow extends StatelessWidget {
  final ScoreFactor factor;
  final VoidCallback? onTap;

  const _FactorRow({required this.factor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                factor.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: BrandText.body(size: 13.5, color: cs.onSurface),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accentPill,
                borderRadius: BorderRadius.circular(Brand.rPill),
              ),
              child: Text(
                '+${factor.points} pts',
                style: BrandText.mono(
                    size: 11, color: AppColors.accentInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
