// lib/screens/scan/findings_screen.dart
// Results of the privacy check, stated plainly.
//
// Honesty contract:
// - The headline count is exactly threats.length as handed over by the
//   caller; checksRun is the number of checks that genuinely ran
//   (ScanResult.itemsScanned) — neither is ever embellished here.
// - Checks that couldn't run are reported separately and are NEVER counted
//   as passed.
// - Severity colors are used as ink and faint tints, not alarm fills; no
//   fear copy — each finding is stated plainly with a fix path.

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/theme/spacing.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/glass_container.dart';

class FindingsScreen extends StatelessWidget {
  /// Threat maps straight from the scan (`ScanResult.threats`), with the
  /// engine's plain-language 'name', 'description' and 'severity' fields.
  final List<Map<String, dynamic>> threats;

  /// Number of checks that genuinely ran (`ScanResult.itemsScanned`).
  final int checksRun;

  /// Checks that couldn't run on this device — shown honestly, never
  /// counted as passed. Omit (null) or 0 to hide the line.
  final int? checksUnavailable;

  /// "Fix these" CTA (threats present). When null, the CTA becomes a
  /// plain "Done" that pops.
  final VoidCallback? onFixAll;

  /// Called when a finding card is tapped.
  final void Function(Map<String, dynamic> threat)? onOpenThreat;

  const FindingsScreen({
    super.key,
    required this.threats,
    required this.checksRun,
    this.checksUnavailable,
    this.onFixAll,
    this.onOpenThreat,
  });

  static String _severityOf(Map<String, dynamic> threat) =>
      '${threat['severity'] ?? ''}'.toUpperCase();

  static int _severityRank(String severity) => switch (severity) {
        'CRITICAL' => 0,
        'HIGH' => 1,
        'MEDIUM' => 2,
        'LOW' => 3,
        'INFO' => 4,
        _ => 5,
      };

  /// Severity ramp tint (AppColors severity tokens); rendered as INK via
  /// [AppColors.glyphInk] and a faint tint box — never an alarm fill.
  static Color _severityTint(String severity) => switch (severity) {
        'CRITICAL' => AppColors.severityCritical,
        'HIGH' => AppColors.severityHigh,
        'MEDIUM' => AppColors.severityMedium,
        'LOW' => AppColors.severityLow,
        _ => AppColors.severityInfo,
      };

  static String _severityIcon(String severity) => switch (severity) {
        'CRITICAL' || 'HIGH' => 'danger_triangle',
        'MEDIUM' => 'danger_circle',
        _ => 'info_circle',
      };

  /// Stable severity ordering (critical first) without trusting Dart's
  /// unstable List.sort for equal ranks.
  List<Map<String, dynamic>> get _ordered {
    final indexed = threats.asMap().entries.toList()
      ..sort((a, b) {
        final byRank = _severityRank(_severityOf(a.value)) -
            _severityRank(_severityOf(b.value));
        return byRank != 0 ? byRank : a.key - b.key;
      });
    return [for (final entry in indexed) entry.value];
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Your results',
      body: threats.isEmpty ? _buildAllClear(context) : _buildFindings(context),
    );
  }

  // ---------------------------------------------------------------------
  // Findings
  // ---------------------------------------------------------------------

  Widget _buildFindings(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final count = threats.length;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              AppSpacing.lg,
            ),
            children: [
              Text(
                'Your check found $count ${count == 1 ? 'thing' : 'things'}',
                style: BrandText.h2(size: 26, color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                "— and here's how to fix each",
                style: BrandText.body(
                  size: 15,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              for (final threat in _ordered) _buildThreatCard(context, threat),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.sm,
            AppSpacing.screenHorizontal,
            AppSpacing.xl,
          ),
          // The screen's single lime action.
          child: onFixAll != null
              ? BrandButton(label: 'Fix these', onPressed: onFixAll)
              : BrandButton(
                  label: 'Done',
                  onPressed: () => Navigator.pop(context),
                ),
        ),
      ],
    );
  }

  Widget _buildThreatCard(BuildContext context, Map<String, dynamic> threat) {
    final scheme = Theme.of(context).colorScheme;
    final severity = _severityOf(threat);
    final tint = _severityTint(severity);
    final ink = AppColors.glyphInk(tint);

    final rawName = '${threat['name'] ?? ''}';
    final name = rawName.isEmpty ? 'Unnamed finding' : rawName;
    final description = '${threat['description'] ?? ''}';

    return GlassCard(
      onTap: onOpenThreat == null ? null : () => onOpenThreat!(threat),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
            ),
            child: Center(
              child: DuotoneIcon(_severityIcon(severity), size: 22, color: ink),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.title(size: 15, color: scheme.onSurface),
                ),
                if (description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: BrandText.body(
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (onOpenThreat != null) ...[
            const SizedBox(width: AppSpacing.sm),
            DuotoneIcon(
              'alt_arrow_right',
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // All clear — honest proof of what actually ran
  // ---------------------------------------------------------------------

  Widget _buildAllClear(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unavailable = checksUnavailable ?? 0;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentPill,
              ),
              child: Center(
                child: DuotoneIcon(
                  'shield_check',
                  size: 48,
                  color: AppColors.accentInk,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'All clear',
              style: BrandText.h2(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.sm),
            // The honest proof line: exactly the checks that ran.
            Text(
              '$checksRun ${checksRun == 1 ? 'check' : 'checks'} ran clean',
              textAlign: TextAlign.center,
              style: BrandText.body(
                size: 15,
                weight: FontWeight.w500,
                color: scheme.onSurface,
              ),
            ),
            if (unavailable > 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  "$unavailable ${unavailable == 1 ? "check isn't" : "checks aren't"} available on this device",
                  textAlign: TextAlign.center,
                  style: BrandText.body(
                    size: 13.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xxxl),
            // The screen's single lime action.
            BrandButton(
              label: 'Done',
              expand: false,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xxl * 2,
                vertical: AppSpacing.lg - 1,
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
