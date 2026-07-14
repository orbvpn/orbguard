/// MITRE ATT&CK Widgets
/// Widgets for displaying MITRE ATT&CK techniques
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../providers/mitre_provider.dart';

/// Tactic column header
class TacticHeader extends StatelessWidget {
  final MitreTactic tactic;
  final int detectedCount;
  final bool isSelected;
  final VoidCallback? onTap;

  const TacticHeader({
    super.key,
    required this.tactic,
    this.detectedCount = 0,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.info.withAlpha(51)
              : cs.surfaceContainerHighest,
          border: Border(
            bottom: BorderSide(
              color: isSelected
                  ? AppColors.secondaryInk
                  : cs.outline,
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tactic.shortName,
              style: TextStyle(
                color: isSelected ? AppColors.secondaryInk : cs.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
            if (detectedCount > 0) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Text(
                  '$detectedCount',
                  style: TextStyle(
                    color: Brand.onDanger,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
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

/// Technique chip/card
class TechniqueChip extends StatelessWidget {
  final MitreTechnique technique;
  final bool isDetected;
  final bool isSelected;
  final VoidCallback? onTap;

  const TechniqueChip({
    super.key,
    required this.technique,
    this.isDetected = false,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDetected
              ? AppColors.error.withAlpha(51)
              : isSelected
                  ? AppColors.info.withAlpha(51)
                  : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
          border: Border.all(
            color: isDetected
                ? AppColors.error.withAlpha(128)
                : isSelected
                    ? AppColors.secondaryInk
                    : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDetected) ...[
              DuotoneIcon(
                AppIcons.dangerTriangle,
                color: AppColors.errorInk,
                size: 12,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                technique.id,
                style: TextStyle(
                  color: isDetected
                      ? AppColors.errorInk
                      : AppColors.secondaryInk,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                technique.name,
                style: TextStyle(
                  color: isDetected ? AppColors.errorInk : cs.onSurfaceVariant,
                  fontSize: 10,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tactic column with techniques
class TacticColumn extends StatelessWidget {
  final MitreTactic tactic;
  final List<MitreTechnique> techniques;
  final Set<String> detectedTechniqueIds;
  final String? selectedTechniqueId;
  final Function(MitreTechnique)? onTechniqueTap;

  const TacticColumn({
    super.key,
    required this.tactic,
    required this.techniques,
    this.detectedTechniqueIds = const {},
    this.selectedTechniqueId,
    this.onTechniqueTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tactic header
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(GlassTheme.radiusXSmall)),
              border: Border.all(color: AppColors.secondaryInk.withAlpha(77)),
            ),
            child: Column(
              children: [
                Text(
                  tactic.name,
                  style: TextStyle(
                    color: AppColors.secondaryInk,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  tactic.id,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
          // Techniques list
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.5),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(GlassTheme.radiusXSmall)),
                border: Border.all(
                  color: cs.outline,
                ),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(4),
                itemCount: techniques.length,
                itemBuilder: (context, index) {
                  final technique = techniques[index];
                  final isDetected = detectedTechniqueIds.contains(technique.id);
                  final isSelected = technique.id == selectedTechniqueId;

                  return TechniqueChip(
                    technique: technique,
                    isDetected: isDetected,
                    isSelected: isSelected,
                    onTap: () => onTechniqueTap?.call(technique),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Technique detail card
class TechniqueDetailCard extends StatelessWidget {
  final MitreTechnique technique;
  final DetectedTechnique? detection;
  final VoidCallback? onClose;

  const TechniqueDetailCard({
    super.key,
    required this.technique,
    this.detection,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
        border: detection != null
            ? Border.all(color: AppColors.error.withAlpha(128))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.info.withAlpha(51),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                ),
                child: Text(
                  technique.id,
                  style: TextStyle(
                    color: AppColors.secondaryInk,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  technique.name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onClose != null)
                IconButton(
                  icon: DuotoneIcon(AppIcons.closeCircle, color: cs.onSurfaceVariant, size: 20),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Detection badge
          if (detection != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(51),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.dangerTriangle, color: AppColors.errorInk, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Detected in your device',
                          style: TextStyle(
                            color: AppColors.errorInk,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Source: ${detection!.source}',
                          style: TextStyle(
                            color: AppColors.errorInk,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Description
          Text(
            technique.description,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),

          // Platforms
          Row(
            children: [
              Text(
                'Platforms: ',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              ...technique.platforms.map((p) => Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: p == 'Android'
                          ? AppColors.success.withAlpha(51)
                          : Brand.surface2,
                      borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(
                        color: p == 'Android'
                            ? AppColors.accentInk
                            : cs.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  )),
            ],
          ),

          // Mitigations
          if (technique.mitigations != null && technique.mitigations!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Mitigations: ${technique.mitigations!.join(", ")}',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],

          // Detection evidence
          if (detection != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: cs.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Evidence:',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detection!.evidence,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// MITRE stats summary card
class MitreStatsCard extends StatelessWidget {
  final int totalTechniques;
  final int detectedTechniques;
  final Map<String, int> detectedByTactic;

  const MitreStatsCard({
    super.key,
    required this.totalTechniques,
    required this.detectedTechniques,
    required this.detectedByTactic,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon(
                AppIcons.shieldCheck,
                color: AppColors.secondaryInk,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MITRE ATT&CK Coverage',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BrandText.title(color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              _buildStat(context, 'Total Techniques', '$totalTechniques',
                  AppColors.secondaryInk),
              const SizedBox(width: 16),
              _buildStat(
                context,
                'Detected',
                '$detectedTechniques',
                detectedTechniques > 0
                    ? AppColors.errorInk
                    : AppColors.accentInk,
              ),
            ],
          ),

          if (detectedByTactic.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Detected by Tactic:',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: detectedByTactic.entries.map((e) {
                final tactic = MitreTactic.mobileTactics.firstWhere(
                  (t) => t.id == e.key,
                  orElse: () => MitreTactic(
                    id: e.key,
                    name: e.key,
                    shortName: e.key,
                    description: '',
                    order: 0,
                  ),
                );
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(51),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                    border: Border.all(color: AppColors.error.withAlpha(77)),
                  ),
                  child: Text(
                    '${tactic.shortName}: ${e.value}',
                    style: TextStyle(
                      color: AppColors.errorInk,
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStat(
      BuildContext context, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: BrandText.heading(color: color, size: 24),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Legend for MITRE display
class MitreLegend extends StatelessWidget {
  const MitreLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem(context, 'Normal', cs.outline),
          const SizedBox(width: 16),
          _buildLegendItem(context, 'Selected', AppColors.info),
          const SizedBox(width: 16),
          _buildLegendItem(context, 'Detected', AppColors.error),
        ],
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withAlpha(128),
            borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
