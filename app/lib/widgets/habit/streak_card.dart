/// "Days protected" streak card — Phase 3.3 habit loop.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_container.dart';
import '../../services/habit/protection_streak_controller.dart';

/// A calm, reward-only surface for the protection streak: it celebrates the
/// current streak, always keeps the best streak visible (even across a
/// gap), and — only when a checkup is due — adds one gentle nudge line.
/// There is no streak-loss framing anywhere: a broken streak simply reads as
/// an invitation to "start your streak" again, never as a loss.
///
/// Self-contained: the caller owns and provides the [controller] (see
/// [ProtectionStreakController]) — this widget only reads it and rebuilds
/// when it changes. Call `controller.recordCheckup(DateTime.now())` when a
/// scan/checkup completes elsewhere in the app.
class StreakCard extends StatelessWidget {
  /// The habit-loop controller providing streak state. Owned/loaded by the
  /// parent (e.g. a long-lived instance on the home screen) and disposed by
  /// it — this widget never mutates or disposes it.
  final ProtectionStreakController controller;

  /// The "current" instant used to evaluate the weekly-checkup nudge.
  /// Defaults to `DateTime.now()` at build time when omitted — pass a fixed
  /// value from tests/golden tests for determinism.
  final DateTime? now;

  const StreakCard({super.key, required this.controller, this.now});

  @override
  Widget build(BuildContext context) {
    // AnimatedBuilder re-runs the builder whenever [controller] notifies, so
    // the card stays in sync as checkups are recorded — without requiring
    // the parent to rebuild this widget itself.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildCard(context),
    );
  }

  Widget _buildCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveNow = now ?? DateTime.now();
    final current = controller.currentStreak;
    final best = controller.bestStreak;
    final started = current > 0;
    // The zero-state headline already reads as an invitation to check up —
    // stacking the nudge line under it would just repeat the same call to
    // action, so the nudge only ever appears once a streak exists.
    final showNudge = started && controller.isCheckupDueThisWeek(effectiveNow);

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DuotoneIcon(
                started ? AppIcons.shieldCheck : AppIcons.shield,
                size: 32,
                // Lime = the brand's "protected/live" signal once a streak
                // exists; neutral/muted for the inviting zero-state so it
                // never reads as a warning.
                color: started ? AppColors.accentInk : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      started
                          ? '$current ${_dayWord(current)} protected'
                          : 'Start your streak — run a checkup',
                      style: BrandText.heading(size: 20, color: cs.onSurface),
                    ),
                    if (best > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Best streak: $best ${_dayWord(best)}',
                        style: BrandText.mono(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (showNudge) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Pink only punctuates the small bell glyph (kit rule: pink
                // never fills, never colors the message itself) — the copy
                // stays a calm, neutral-toned nudge, never an alert.
                DuotoneIcon(AppIcons.bell, size: 16, color: AppColors.secondaryInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Time for your weekly checkup',
                    style: BrandText.body(size: 13, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _dayWord(int n) => n == 1 ? 'day' : 'days';
}
