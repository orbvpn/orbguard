/// Victim-safe stalkerware UX — a small, trauma-informed moral + UX moat.
///
/// When OrbGuard surfaces something that looks like stalkerware / monitoring
/// software, *removing it can alert the person who installed it*. For someone
/// experiencing domestic abuse or coercive control, that alert can escalate
/// danger. Two calm affordances live here, modelled on Apple's Safety Check:
///
///  1. [VictimSafetyNotice] — a "before you remove this" card shown beside any
///     removal/disable action on a monitoring app. Never alarmist.
///  2. [QuickExitAction] / [VictimSafety.quickExit] — a duress "Quick Exit"
///     that immediately leaves the sensitive view for the neutral home screen,
///     so an onlooker never sees the finding.
///
/// Detection stays honest: [VictimSafety.mentionsSurveillance] keys off the
/// analyzer's OWN text (malware family, warnings, threat description) — it never
/// invents a label.
library;

import 'package:flutter/material.dart';

import '../theme/brand.dart';
import '../theme/colors.dart';
import '../theme/glass_theme.dart';
import 'brand_button.dart';
import 'duotone_icon.dart';

/// Stateless helpers for the victim-safety flow.
class VictimSafety {
  VictimSafety._();

  /// Vocabulary the analyzer uses for covert person-monitoring software. Kept
  /// deliberately specific (not generic ad "trackers") so the safety framing
  /// only appears when a finding really reads like stalkerware / spyware.
  static const List<String> _surveillanceTerms = <String>[
    'stalkerware',
    'stalker',
    'spyware',
    'spouseware',
    'surveillance',
    'monitoring',
    'monitor',
    'keylogger',
    'keylog',
    'eavesdrop',
    'wiretap',
    'covert',
    'hidden camera',
    'spy app',
    'track location',
    'location tracking',
    'parental control',
    'phone tracker',
  ];

  /// True when any of [signals] reads like monitoring / stalkerware. Feed it the
  /// analyzer's own text (app name, malware family, warnings, threat
  /// description) — never a guess. Callers gate on this to decide whether to
  /// show a [VictimSafetyNotice] before a removal / disable action.
  static bool mentionsSurveillance(Iterable<String?> signals) {
    for (final signal in signals) {
      if (signal == null || signal.isEmpty) continue;
      final lower = signal.toLowerCase();
      for (final term in _surveillanceTerms) {
        if (lower.contains(term)) return true;
      }
    }
    return false;
  }

  /// Duress "Quick Exit" — modelled on Apple Safety Check. Immediately pops back
  /// to the neutral home screen (the navigator's first route), so the sensitive
  /// stalkerware view is off-screen at once. Real navigation, nothing faked.
  static void quickExit(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

/// A calm "before you remove this" warning, shown next to a removal / disable
/// action on a detected monitoring or spyware app. Copy is trauma-informed —
/// it names the real risk without alarm and points to a support resource in
/// plain text (no link). When [showQuickExit] is true it embeds a [Quick Exit]
/// escape right where the victim is reading the warning.
class VictimSafetyNotice extends StatelessWidget {
  /// Override the escape action (defaults to [VictimSafety.quickExit]).
  final VoidCallback? onQuickExit;

  /// Whether to render the embedded "Quick Exit" button (default true).
  final bool showQuickExit;

  final EdgeInsetsGeometry margin;

  const VictimSafetyNotice({
    super.key,
    this.onQuickExit,
    this.showQuickExit = true,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      margin: margin,
      padding: const EdgeInsets.all(16),
      // Pink "punctuates" (kit rule 2): a soft alert tint, never a large fill.
      decoration: GlassTheme.tintedGlassDecoration(
        tintColor: AppColors.secondary,
        radius: GlassTheme.radiusMedium,
        opacity: 0.10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A protective shield-with-person, not an alarmist warning sign.
              DuotoneIcon('shield_user', size: 22, color: AppColors.secondaryInk),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Before you remove this',
                  style: BrandText.title(size: 15, weight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'If this is monitoring or spyware, removing it may alert the person '
            'who set it up — and that could put you at risk. There is no rush to '
            'act right now.',
            style: BrandText.body(size: 13, color: onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            'If you feel unsafe, consider reaching out to a domestic-violence '
            'support service or someone you trust before making changes. They '
            'can help you plan a safe next step.',
            style: BrandText.body(size: 13),
          ),
          if (showQuickExit) ...[
            const SizedBox(height: 14),
            BrandButton.secondary(
              label: 'Quick Exit',
              svgPath: 'assets/icons/exit.svg',
              onPressed: () => onQuickExit != null
                  ? onQuickExit!()
                  : VictimSafety.quickExit(context),
            ),
          ],
        ],
      ),
    );
  }
}

/// Discreet header affordance for the duress "Quick Exit". Drops into a
/// [GlassPage]/[GlassTabPage] `actions` list (matches the existing
/// GestureDetector + [DuotoneIcon] header actions). Labelled for screen
/// readers and long-press tooltip even though it renders as a small icon.
class QuickExitAction extends StatelessWidget {
  final VoidCallback? onExit;
  final double size;

  const QuickExitAction({super.key, this.onExit, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Quick Exit',
      child: Tooltip(
        message: 'Quick Exit',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onExit != null ? onExit!() : VictimSafety.quickExit(context),
          child: DuotoneIcon(
            'exit',
            size: size,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
