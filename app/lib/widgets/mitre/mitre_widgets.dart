/// MITRE ATT&CK Widgets
/// Widgets for displaying MITRE ATT&CK techniques
library mitre_widgets;

import 'package:flutter/material.dart';

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF00D9FF).withAlpha(51)
              : const Color(0xFF1D1E33),
          border: Border(
            bottom: BorderSide(
              color: isSelected
                  ? const Color(0xFF00D9FF)
                  : Colors.grey.withAlpha(77),
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
                color: isSelected ? const Color(0xFF00D9FF) : Colors.white,
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
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$detectedCount',
                  style: const TextStyle(
                    color: Colors.white,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isDetected
              ? Colors.red.withAlpha(51)
              : isSelected
                  ? const Color(0xFF00D9FF).withAlpha(51)
                  : const Color(0xFF2A2D3E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isDetected
                ? Colors.red.withAlpha(128)
                : isSelected
                    ? const Color(0xFF00D9FF)
                    : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDetected) ...[
              const DuotoneIcon(
                AppIcons.dangerTriangle,
                color: Colors.red,
                size: 12,
              ),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                technique.id,
                style: TextStyle(
                  color: isDetected
                      ? Colors.red
                      : const Color(0xFF00D9FF),
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
                  color: isDetected ? Colors.red[100] : Colors.white70,
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
              color: const Color(0xFF1D1E33),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: const Color(0xFF00D9FF).withAlpha(77)),
            ),
            child: Column(
              children: [
                Text(
                  tactic.name,
                  style: const TextStyle(
                    color: Color(0xFF00D9FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                Text(
                  tactic.id,
                  style: TextStyle(
                    color: Colors.grey[500],
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
                color: const Color(0xFF0A0E21).withAlpha(128),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                border: Border.all(
                  color: const Color(0xFF1D1E33),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
        border: detection != null
            ? Border.all(color: Colors.red.withAlpha(128))
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
                  color: const Color(0xFF00D9FF).withAlpha(51),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  technique.id,
                  style: const TextStyle(
                    color: Color(0xFF00D9FF),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  technique.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              if (onClose != null)
                IconButton(
                  icon: const DuotoneIcon(AppIcons.closeCircle, color: Colors.white54, size: 20),
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
                color: Colors.red.withAlpha(51),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const DuotoneIcon(AppIcons.dangerTriangle, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detected in your device',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          'Source: ${detection!.source}',
                          style: TextStyle(
                            color: Colors.red[200],
                            fontSize: 10,
                          ),
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
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),

          // Platforms
          Row(
            children: [
              const Text(
                'Platforms: ',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
              ...technique.platforms.map((p) => Container(
                    margin: const EdgeInsets.only(right: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: p == 'Android'
                          ? Colors.green.withAlpha(51)
                          : Colors.grey.withAlpha(51),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p,
                      style: TextStyle(
                        color: p == 'Android' ? Colors.green : Colors.grey,
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
              style: const TextStyle(
                color: Colors.white54,
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
                color: const Color(0xFF0A0E21),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Evidence:',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detection!.evidence,
                    style: const TextStyle(
                      color: Colors.white70,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DuotoneIcon(
                AppIcons.shieldCheck,
                color: Color(0xFF00D9FF),
                size: 24,
              ),
              const SizedBox(width: 8),
              const Text(
                'MITRE ATT&CK Coverage',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              _buildStat('Total Techniques', '$totalTechniques', Colors.blue),
              const SizedBox(width: 16),
              _buildStat(
                'Detected',
                '$detectedTechniques',
                detectedTechniques > 0 ? Colors.red : Colors.green,
              ),
            ],
          ),

          if (detectedByTactic.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Detected by Tactic:',
              style: TextStyle(
                color: Colors.white54,
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
                    color: Colors.red.withAlpha(51),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.red.withAlpha(77)),
                  ),
                  child: Text(
                    '${tactic.shortName}: ${e.value}',
                    style: const TextStyle(
                      color: Colors.red,
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

  Widget _buildStat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildLegendItem('Normal', const Color(0xFF2A2D3E)),
          const SizedBox(width: 16),
          _buildLegendItem('Selected', const Color(0xFF00D9FF)),
          const SizedBox(width: 16),
          _buildLegendItem('Detected', Colors.red),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withAlpha(128),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
