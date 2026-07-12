// Threat Hunting Screen
// Proactive threat detection and investigation dashboard

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../providers/threat_hunting_provider.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../services/security/threat_hunting_service.dart';

class ThreatHuntingScreen extends StatefulWidget {
  const ThreatHuntingScreen({super.key});

  @override
  State<ThreatHuntingScreen> createState() => _ThreatHuntingScreenState();
}

class _ThreatHuntingScreenState extends State<ThreatHuntingScreen> {
  /// Transform for the graph viewport; the fit button resets it.
  final TransformationController _graphTransform = TransformationController();

  /// True while POST /correlation/run is in flight.
  bool _isRunningCorrelation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ThreatHuntingProvider>();
      provider.initialize();
      provider.loadGraphData();
      provider.loadCorrelationRules();
      provider.loadMLModels();
    });
  }

  @override
  void dispose() {
    _graphTransform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThreatHuntingProvider>(
      builder: (context, provider, _) {
        return GlassTabPage(
          title: 'Threat Hunting',
          hasSearch: true,
          searchHint: 'Search hunts...',
          tabs: [
            GlassTab(
              label: 'Hunts',
              iconPath: 'magnifer',
              content: _buildHuntsContent(provider),
            ),
            GlassTab(
              label: 'Findings',
              iconPath: 'shield',
              content: _buildFindingsContent(provider),
            ),
            GlassTab(
              label: 'Cases',
              iconPath: 'file',
              content: _buildCasesContent(provider),
            ),
            GlassTab(
              label: 'MITRE',
              iconPath: 'chart',
              content: _buildMitreContent(provider),
            ),
            GlassTab(
              label: 'Graph',
              iconPath: 'server',
              content: _buildGraphContent(provider),
            ),
            GlassTab(
              label: 'Correlate',
              iconPath: 'lock',
              content: _buildCorrelationContent(provider),
            ),
            GlassTab(
              label: 'ML',
              iconPath: 'cloud_storage',
              content: _buildMLContent(provider),
            ),
          ],
          headerContent: _buildHeaderContent(provider),
          actions: [
            if (provider.isHunting)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: GlassTheme.primaryAccent,
                  ),
                ),
              )
            else
              IconButton(
                icon: DuotoneIcon('play', size: 22, color: context.onSurface),
                tooltip: 'Run All Critical Hunts',
                onPressed: () => provider.executeAllCriticalHunts(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHeaderContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) return const SizedBox.shrink();

    return Column(
      children: [
        // Hunt Progress
        if (provider.isHunting && provider.currentProgress != null)
          _buildHuntProgress(provider),
        // Stats
        if (!provider.isHunting) _buildStats(provider),
      ],
    );
  }

  Widget _buildHuntsContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    return _buildHuntsTab(provider);
  }

  Widget _buildFindingsContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    return _buildFindingsTab(provider);
  }

  Widget _buildCasesContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    return _buildCasesTab(provider);
  }

  Widget _buildMitreContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    return _buildMitreTab(provider);
  }

  Widget _buildGraphContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    return _buildGraphTab(provider);
  }

  Widget _buildCorrelationContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    return _buildCorrelationTab(provider);
  }

  Widget _buildMLContent(ThreatHuntingProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: GlassTheme.primaryAccent),
      );
    }
    return _buildMLTab(provider);
  }

  Widget _buildHuntProgress(ThreatHuntingProvider provider) {
    final progress = provider.currentProgress!;
    final hunt = provider.getHunt(progress.huntId);

    return GlassContainer(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GlassTheme.primaryAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hunt?.name ?? 'Running Hunt', maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      progress.phase, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress.progress * 100).toInt()}%',
                style: const TextStyle(
                  color: GlassTheme.primaryAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.progress,
              backgroundColor: context.onSurface.withValues(alpha: 0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(
                GlassTheme.primaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(ThreatHuntingProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          _buildStatItem(
            'Hunts',
            provider.availableHunts.length.toString(),
            GlassTheme.primaryAccent,
          ),
          _buildStatItem(
            'Findings',
            provider.totalFindings.toString(),
            GlassTheme.warningColor,
          ),
          _buildStatItem(
            'Critical',
            provider.criticalFindingsCount.toString(),
            GlassTheme.errorColor,
          ),
          _buildStatItem(
            'Cases',
            provider.openCases.length.toString(),
            AppColors.chartColors[4],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
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
              style: TextStyle(
                color: context.onSurfaceMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHuntsTab(ThreatHuntingProvider provider) {
    if (provider.availableHunts.isEmpty) {
      return _buildEmptyState(
        icon: 'magnifer',
        title: 'No Hunts Available',
        subtitle: 'Threat hunts are loading...',
      );
    }

    final groupedHunts = <HuntPriority, List<ThreatHunt>>{};
    for (final hunt in provider.availableHunts) {
      groupedHunts.putIfAbsent(hunt.priority, () => []).add(hunt);
    }

    // Sort by priority
    final sortedEntries = groupedHunts.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: sortedEntries.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8, top: 8),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(ThreatHuntingProvider.getPriorityColor(entry.key)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.key.name.toUpperCase()} PRIORITY',
                    style: TextStyle(
                      color: Color(ThreatHuntingProvider.getPriorityColor(entry.key)),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ...entry.value.map((hunt) => _buildHuntCard(hunt, provider)),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildHuntCard(ThreatHunt hunt, ThreatHuntingProvider provider) {
    final typeColor = Color(ThreatHuntingProvider.getHuntTypeColor(hunt.type));
    final result = provider.getHuntResult(hunt.id);
    final isRunning = provider.activeHuntId == hunt.id;

    // Result badge: a hunt with no findings but unevaluated rules is
    // "Inconclusive", which is explicitly distinguished from "Clean".
    String? badgeText;
    Color badgeColor = GlassTheme.successColor;
    if (result != null) {
      if (result.findings.isNotEmpty) {
        badgeText = '${result.findings.length} findings';
        badgeColor = result.hasCriticalFindings
            ? GlassTheme.errorColor
            : GlassTheme.warningColor;
      } else if (result.unavailableRules.isNotEmpty) {
        badgeText = 'Inconclusive';
        badgeColor = GlassTheme.warningColor;
      } else {
        badgeText = 'Clean';
        badgeColor = GlassTheme.successColor;
      }
    }

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isRunning ? null : () => _showHuntDetails(context, hunt, provider),
        borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                    ),
                    child: Center(
                      child: DuotoneIcon(
                        _getHuntTypeIcon(hunt.type),
                        color: typeColor,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hunt.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hunt.type.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (badgeText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                hunt.description,
                style: TextStyle(
                  color: context.onSurfaceMuted,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // MITRE ATT&CK tags
                  ...hunt.mitreAttackIds.take(3).map((id) => Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                        ),
                        child: Text(
                          id,
                          style: TextStyle(
                            color: context.onSurfaceMuted,
                            fontSize: 10,
                            fontFamily: Brand.fontMono,
                          ),
                        ),
                      )),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: isRunning || provider.isHunting
                        ? null
                        : () => provider.executeHunt(hunt.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: GlassTheme.primaryAccent,
                      foregroundColor: Brand.onLime,
                      disabledBackgroundColor: context.onSurface.withValues(alpha: 0.06),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: Text(isRunning ? 'Running...' : 'Run Hunt'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFindingsTab(ThreatHuntingProvider provider) {
    final allFindings = <HuntFinding>[];
    for (final result in provider.huntResults.values) {
      allFindings.addAll(result.findings);
    }

    if (allFindings.isEmpty) {
      return _buildEmptyState(
        icon: 'check_circle',
        title: 'No Findings',
        subtitle: 'Run threat hunts to detect security issues',
        color: GlassTheme.successColor,
      );
    }

    // Sort by severity
    allFindings.sort((a, b) => b.severity.compareTo(a.severity));

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: allFindings.length,
      itemBuilder: (context, index) {
        return _buildFindingCard(allFindings[index], provider);
      },
    );
  }

  Widget _buildFindingCard(HuntFinding finding, ThreatHuntingProvider provider) {
    final severityColor =
        Color(ThreatHuntingProvider.getSeverityColor(finding.severity));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: severityColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      _getFindingIcon(finding.type),
                      color: severityColor,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        finding.ruleName, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        finding.type.name.replaceAll(RegExp(r'(?=[A-Z])'), ' ').trim(), maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.onSurfaceMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                  child: Text(
                    finding.severityLevel.toUpperCase(),
                    style: TextStyle(
                      color: Brand.text,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              finding.description,
              style: TextStyle(
                color: context.onSurface.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            GlassContainer(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  DuotoneIcon(
                    'code',
                    size: 14,
                    color: context.onSurfaceMuted.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      finding.evidence,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.onSurfaceMuted,
                        fontSize: 11,
                        fontFamily: Brand.fontMono,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (finding.mitreAttackIds.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: finding.mitreAttackIds.map((id) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: GlassTheme.primaryAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                      ),
                      child: Text(
                        id,
                        style: TextStyle(
                          color: AppColors.accentInk,
                          fontSize: 10,
                          fontFamily: Brand.fontMono,
                        ),
                      ),
                    )).toList(),
              ),
            ],
            if (finding.recommendations.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...finding.recommendations.take(2).map((r) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const DuotoneIcon(
                          'arrow_right',
                          size: 16,
                          color: GlassTheme.primaryAccent,
                        ),
                        Expanded(
                          child: Text(
                            r,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.onSurfaceMuted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCasesTab(ThreatHuntingProvider provider) {
    if (provider.cases.isEmpty) {
      return _buildEmptyState(
        icon: 'folder_open',
        title: 'No Investigation Cases',
        subtitle: 'Create cases from findings to track investigations',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: provider.cases.length,
      itemBuilder: (context, index) {
        return _buildCaseCard(provider.cases[index]);
      },
    );
  }

  Widget _buildCaseCard(InvestigationCase caseItem) {
    final statusColor =
        Color(ThreatHuntingProvider.getCaseStatusColor(caseItem.status));

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  ),
                  child: Center(
                    child: DuotoneIcon(
                      'folder',
                      color: statusColor,
                      size: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caseItem.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${caseItem.relatedFindings.length} related findings', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.onSurfaceMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                  child: Text(
                    caseItem.status.displayName,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              caseItem.description,
              style: TextStyle(
                color: context.onSurfaceMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                DuotoneIcon(
                  'clock_circle',
                  size: 14,
                  color: context.onSurfaceMuted,
                ),
                const SizedBox(width: 4),
                Text(
                  'Opened ${_formatDate(caseItem.createdAt)}',
                  style: TextStyle(
                    color: context.onSurfaceMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMitreTab(ThreatHuntingProvider provider) {
    // Collect all MITRE ATT&CK IDs from hunts and findings
    final mitreMap = <String, List<ThreatHunt>>{};
    for (final hunt in provider.availableHunts) {
      for (final id in hunt.mitreAttackIds) {
        mitreMap.putIfAbsent(id, () => []).add(hunt);
      }
    }

    if (mitreMap.isEmpty) {
      return _buildEmptyState(
        icon: 'structure',
        title: 'MITRE ATT&CK Coverage',
        subtitle: 'Attack techniques covered by threat hunts',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'MITRE ATT&CK techniques covered by available hunts',
            style: TextStyle(
              color: context.onSurfaceMuted,
              fontSize: 14,
            ),
          ),
        ),
        ...mitreMap.entries.map((entry) => _buildMitreCard(entry.key, entry.value)),
      ],
    );
  }

  Widget _buildMitreCard(String techniqueId, List<ThreatHunt> hunts) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: GlassTheme.primaryAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                  ),
                  child: Text(
                    techniqueId,
                    style: TextStyle(
                      color: AppColors.accentInk,
                      fontWeight: FontWeight.bold,
                      fontFamily: Brand.fontMono,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${hunts.length} hunt(s)',
                  style: TextStyle(
                    color: context.onSurfaceMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _getMitreDescription(techniqueId),
              style: TextStyle(
                color: context.onSurfaceMuted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: hunts.map((hunt) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.onSurface.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                    ),
                    child: Text(
                      hunt.name,
                      style: TextStyle(
                        color: context.onSurfaceMuted,
                        fontSize: 11,
                      ),
                    ),
                  )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
    Color color = GlassTheme.primaryAccent,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DuotoneIcon(icon, size: 64, color: color.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: context.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: context.onSurfaceMuted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getHuntTypeIcon(HuntType type) {
    switch (type) {
      case HuntType.iocSweep:
        return 'magnifer';
      case HuntType.behaviorAnalysis:
        return 'cpu';
      case HuntType.anomalyDetection:
        return 'graph_up';
      case HuntType.attackPattern:
        return 'structure';
      case HuntType.dataExfiltration:
        return 'arrow_up';
      case HuntType.persistenceMechanism:
        return 'refresh';
      case HuntType.lateralMovement:
        return 'transfer_horizontal';
      case HuntType.privilegeEscalation:
        return 'arrow_up';
    }
  }

  String _getFindingIcon(FindingType type) {
    switch (type) {
      case FindingType.malwareIndicator:
        return 'bug';
      case FindingType.suspiciousApp:
        return 'smartphone';
      case FindingType.networkAnomaly:
        return 'wi_fi_router';
      case FindingType.dataExfiltration:
        return 'arrow_up';
      case FindingType.persistenceMechanism:
        return 'refresh';
      case FindingType.privilegeAbuse:
        return 'crown';
      case FindingType.configurationRisk:
        return 'settings';
      case FindingType.vulnerableComponent:
        return 'danger_triangle';
    }
  }

  String _getMitreDescription(String techniqueId) {
    // Simplified MITRE descriptions
    final descriptions = {
      'T1204': 'User Execution - Adversary relies on user action',
      'T1566': 'Phishing - Attempt to obtain sensitive information',
      'T1417': 'Input Capture - Capture user input via keylogging',
      'T1429': 'Audio Capture - Record audio from device',
      'T1512': 'Video Capture - Record video from device cameras',
      'T1533': 'Data from Local System - Collect data from device',
      'T1636': 'Contact List Access - Access contacts database',
      'T1537': 'Transfer Data to Cloud - Exfiltrate to cloud storage',
      'T1398': 'Boot/Logon Initialization Scripts - Establish persistence',
      'T1624': 'Event Triggered Execution - Execute on system events',
      'T1571': 'Non-Standard Port - Use unusual ports for C2',
      'T1573': 'Encrypted Channel - Encrypted C2 communication',
      'T1071': 'Application Layer Protocol - Use standard protocols',
      'T1404': 'Exploitation for Privilege Escalation',
      'T1428': 'Exploitation of Remote Services',
    };
    return descriptions[techniqueId] ?? 'Mobile attack technique';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  void _showHuntDetails(
    BuildContext context,
    ThreatHunt hunt,
    ThreatHuntingProvider provider,
  ) {
    final result = provider.getHuntResult(hunt.id);
    final typeColor = Color(ThreatHuntingProvider.getHuntTypeColor(hunt.type));

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.5,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius:
                const BorderRadius.vertical(
                    top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
                    ),
                    child: Center(
                      child: DuotoneIcon(
                        _getHuntTypeIcon(hunt.type),
                        color: typeColor,
                        size: 28,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hunt.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          hunt.type.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: typeColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                hunt.description,
                style: TextStyle(
                  color: context.onSurface.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hypothesis',
                      style: TextStyle(
                        color: context.onSurfaceMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hunt.hypothesis,
                      style: TextStyle(
                        color: context.onSurface,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Detection Rules',
                style: TextStyle(
                  color: context.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...hunt.rules.map((rule) => GlassContainer(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        DuotoneIcon(
                          'clipboard_text',
                          size: 18,
                          color: Color(ThreatHuntingProvider.getSeverityColor(rule.severity)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rule.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Type: ${rule.type.name}', maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.onSurfaceMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(rule.severity * 100).toInt()}%',
                          style: TextStyle(
                            color: Color(ThreatHuntingProvider.getSeverityColor(rule.severity)),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )),
              if (result != null) ...[
                const SizedBox(height: 20),
                Text(
                  'Last Result',
                  style: TextStyle(
                    color: context.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                GlassContainer(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildResultRow('Status', result.status.name),
                      _buildResultRow('Items Scanned', result.itemsScanned.toString()),
                      _buildResultRow('Rules Matched', result.rulesMatched.toString()),
                      _buildResultRow('Findings', result.findings.length.toString()),
                      if (result.unavailableRules.isNotEmpty)
                        _buildResultRow('Rules Not Evaluated',
                            result.unavailableRules.length.toString()),
                      _buildResultRow('Duration', '${result.duration.inSeconds}s'),
                    ],
                  ),
                ),
                // Rules that could not be evaluated on this platform/build,
                // shown explicitly so an inconclusive hunt is never mistaken
                // for a clean one.
                if (result.unavailableRules.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Rules Not Evaluated',
                    style: TextStyle(
                      color: context.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...result.unavailableRules.entries.map((entry) {
                    final rule = hunt.rules
                        .where((r) => r.id == entry.key)
                        .firstOrNull;
                    return GlassContainer(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const DuotoneIcon(
                            'danger_triangle',
                            size: 18,
                            color: GlassTheme.warningColor,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rule?.name ?? entry.key, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.onSurface,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  entry.value, maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.onSurfaceMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: provider.isHunting
                      ? null
                      : () {
                          Navigator.pop(context);
                          provider.executeHunt(hunt.id);
                        },
                  icon: const DuotoneIcon('play', size: 18),
                  label: const Text('Run Hunt'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.primaryAccent,
                    foregroundColor: Brand.onLime,
                    disabledBackgroundColor: context.onSurface.withValues(alpha: 0.06),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: context.onSurfaceMuted),
          ),
          Text(
            value,
            style: TextStyle(
              color: context.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Maximum nodes rendered in the inline mini-graph (full exploration
  /// lives in the dedicated Threat Graph screen).
  static const int _graphRenderCap = 12;

  Widget _buildGraphTab(ThreatHuntingProvider provider) {
    // Show loading state if fetching
    if (provider.isLoadingGraph) {
      return const Center(child: CircularProgressIndicator());
    }

    // Surface real load failures (e.g. 503 when Neo4j is unavailable)
    // instead of rendering them as an empty graph.
    if (provider.graphError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DuotoneIcon('danger_triangle',
                  color: GlassTheme.errorColor, size: 56),
              const SizedBox(height: 16),
              Text(
                'Graph Unavailable',
                style: TextStyle(
                    color: context.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                provider.graphError!,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: context.onSurfaceMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => provider.loadGraphData(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTheme.primaryAccent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Parse backend NodeView objects ({id, label, type, properties}); the
    // human-readable name lives in properties.value/name.
    final allNodes =
        provider.graphNodes.map(_HuntGraphNode.fromJson).where((n) => n.id.isNotEmpty).toList();

    // Show empty state if no nodes
    if (allNodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('structure', color: context.onSurfaceMuted, size: 64),
            const SizedBox(height: 16),
            Text('No threat graph data available', style: TextStyle(color: context.onSurfaceMuted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => provider.loadGraphData(),
              icon: const Icon(Icons.refresh),
              label: const Text('Load Graph Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: GlassTheme.primaryAccent,
              ),
            ),
          ],
        ),
      );
    }

    // Layout the rendered subset on a grid; edges come from the real
    // relations ({from, to}) between rendered node ids.
    final nodes = allNodes.take(_graphRenderCap).toList();
    final positions = <String, Offset>{};
    for (var i = 0; i < nodes.length; i++) {
      final row = i ~/ 3;
      final col = i % 3;
      positions[nodes[i].id] = Offset(150.0 + (col * 150), 80.0 + (row * 100));
    }

    final edges = <(Offset, Offset)>[];
    for (final rel in provider.graphRelations) {
      final a = positions[rel['from']?.toString()];
      final b = positions[rel['to']?.toString()];
      if (a != null && b != null && a != b) {
        edges.add((a, b));
      }
    }

    final canvasWidth = 480.0;
    final canvasHeight = 80.0 + ((nodes.length - 1) ~/ 3) * 100.0 + 80.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Graph visualization
        GlassCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const DuotoneIcon('structure', color: GlassTheme.primaryAccent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Threat Relationship Graph',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: DuotoneIcon('target', color: context.onSurfaceMuted, size: 24),
                    tooltip: 'Fit graph',
                    // Reset the viewport transform (pan/zoom) to identity.
                    onPressed: () => _graphTransform.value = Matrix4.identity(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: context.isDark
                      ? AppColors.overlayLight
                      : Brand.surface2,
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                  child: InteractiveViewer(
                    transformationController: _graphTransform,
                    constrained: false,
                    boundaryMargin: const EdgeInsets.all(200),
                    minScale: 0.4,
                    maxScale: 4,
                    child: SizedBox(
                      width: canvasWidth,
                      height: canvasHeight < 300 ? 300 : canvasHeight,
                      child: Stack(
                        children: [
                          // Draw real edges between rendered nodes
                          CustomPaint(
                            size: Size(canvasWidth,
                                canvasHeight < 300 ? 300 : canvasHeight),
                            painter: _GraphEdgePainter(
                                edges, context.colors.outline),
                          ),
                          // Draw nodes
                          ...nodes.map((node) {
                            final pos = positions[node.id]!;
                            return Positioned(
                              left: pos.dx - 35,
                              top: pos.dy - 25,
                              child: GestureDetector(
                                onTap: () => _showGraphNodeDetails(
                                    context, node, provider),
                                child: Container(
                                  width: 70,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _getNodeColor(node.type).withAlpha(50),
                                    borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                                    border: Border.all(color: _getNodeColor(node.type)),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      DuotoneIcon(_getNodeIcon(node.type), size: 16, color: _getNodeColor(node.type)),
                                      const SizedBox(height: 2),
                                      Text(
                                        node.label,
                                        style: TextStyle(color: context.onSurface, fontSize: 9),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (allNodes.length > nodes.length) ...[
                const SizedBox(height: 8),
                Text(
                  'Showing ${nodes.length} of ${allNodes.length} entities — '
                  'open the Threat Graph screen for the full graph',
                  style: TextStyle(
                      color: context.onSurfaceMuted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Legend (only node types actually present)
        GlassCard(
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Legend', style: TextStyle(color: context.onSurface, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: allNodes
                    .map((n) => n.type.toLowerCase())
                    .toSet()
                    .map((t) =>
                        _buildLegendItem(_displayNodeType(t), _getNodeColor(t)))
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Graph stats
        Row(
          children: [
            Expanded(
              child: GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('${allNodes.length}', style: const TextStyle(color: GlassTheme.primaryAccent, fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('Nodes', style: TextStyle(color: context.onSurfaceMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('${provider.graphRelations.length}', style: const TextStyle(color: GlassTheme.warningColor, fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('Edges', style: TextStyle(color: context.onSurfaceMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('${allNodes.map((n) => n.type.toLowerCase()).toSet().length}', style: const TextStyle(color: GlassTheme.errorColor, fontSize: 24, fontWeight: FontWeight.bold)),
                    Text('Types', style: TextStyle(color: context.onSurfaceMuted, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: context.onSurfaceMuted, fontSize: 12)),
      ],
    );
  }

  void _showGraphNodeDetails(BuildContext context, _HuntGraphNode node,
      ThreatHuntingProvider provider) {
    // Real relation count for this node from the loaded relations.
    final relationCount = provider.graphRelations
        .where((rel) =>
            rel['from']?.toString() == node.id ||
            rel['to']?.toString() == node.id)
        .length;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
        decoration: BoxDecoration(
          gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(GlassTheme.radiusLarge)),
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Row(
              children: [
                DuotoneIcon(_getNodeIcon(node.type), color: _getNodeColor(node.type), size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(node.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: context.onSurface,
                          fontSize: 20,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: GlassBadge(
                  text: _displayNodeType(node.type).toUpperCase(),
                  color: _getNodeColor(node.type)),
            ),
            const SizedBox(height: 16),
            Text(
              relationCount == 1
                  ? 'Connected to 1 other entity'
                  : 'Connected to $relationCount other entities',
              style: TextStyle(color: context.onSurfaceMuted),
            ),
            // Raw graph properties (real data from the graph database)
            if (node.properties.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Properties',
                  style: TextStyle(
                      color: context.onSurface, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: node.properties.entries
                      .take(12)
                      .map((e) => _buildResultRow(e.key, '${e.value}'))
                      .toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Maps a graph node label (e.g. "Indicator", "ThreatActor") to a
  /// human-friendly display name.
  String _displayNodeType(String type) {
    switch (type.toLowerCase()) {
      case 'threatactor':
      case 'threat-actor':
        return 'Threat Actor';
      case 'indicator':
        return 'Indicator';
      case 'campaign':
        return 'Campaign';
      case 'malware':
        return 'Malware';
      case 'tool':
        return 'Tool';
      default:
        return type;
    }
  }

  Color _getNodeColor(String type) {
    switch (type.toLowerCase()) {
      case 'threatactor':
      case 'threat-actor':
        return GlassTheme.errorColor;
      case 'malware':
        return AppColors.severityCritical;
      case 'campaign':
        return GlassTheme.warningColor;
      case 'indicator':
        return GlassTheme.primaryAccent;
      case 'tool':
        return AppColors.chartColors[4];
      default:
        return context.onSurfaceMuted;
    }
  }

  String _getNodeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'threatactor':
      case 'threat-actor':
        return 'user';
      case 'malware':
        return 'bug';
      case 'campaign':
        return 'structure';
      case 'indicator':
        return 'danger_triangle';
      case 'tool':
        return 'server_square';
      default:
        return 'help';
    }
  }

  /// Runs a server-scoped correlation (POST /correlation/run) and then
  /// reloads the persisted correlation events.
  Future<void> _runCorrelation(ThreatHuntingProvider provider) async {
    if (_isRunningCorrelation) return;
    setState(() => _isRunningCorrelation = true);

    try {
      final result = await OrbGuardApiClient.instance.runCorrelation();
      final found = (result['correlations'] is List)
          ? (result['correlations'] as List).length
          : 0;

      if (!mounted) return;
      setState(() => _isRunningCorrelation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            found == 0
                ? 'Correlation run complete — no new correlations found'
                : 'Correlation run complete — $found correlation'
                    '${found == 1 ? '' : 's'} found',
          ),
        ),
      );
      await provider.loadCorrelationRules();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRunningCorrelation = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Correlation failed: $e'),
            backgroundColor: GlassTheme.errorColor),
      );
    }
  }

  Widget _buildCorrelationTab(ThreatHuntingProvider provider) {
    // Show loading state
    if (provider.isLoadingCorrelation) {
      return const Center(child: CircularProgressIndicator());
    }

    // Surface real load failures instead of an empty list.
    if (provider.correlationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const DuotoneIcon('danger_triangle',
                  color: GlassTheme.errorColor, size: 56),
              const SizedBox(height: 16),
              Text(
                'Correlations Unavailable',
                style: TextStyle(
                    color: context.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                provider.correlationError!,
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: context.onSurfaceMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => provider.loadCorrelationRules(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: GlassTheme.primaryAccent),
              ),
            ],
          ),
        ),
      );
    }

    // Parse backend CorrelationEvent objects ({id, type, strength,
    // confidence, description, indicators, created_at}).
    final events =
        provider.correlationRules.map(_CorrelationEvent.fromJson).toList();

    // Show empty state if no correlations recorded yet
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('link', color: context.onSurfaceMuted, size: 64),
            const SizedBox(height: 16),
            Text('No correlations recorded yet', style: TextStyle(color: context.onSurfaceMuted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isRunningCorrelation
                  ? null
                  : () => _runCorrelation(provider),
              icon: const Icon(Icons.play_arrow),
              label: Text(
                  _isRunningCorrelation ? 'Running...' : 'Run Correlation'),
              style: ElevatedButton.styleFrom(backgroundColor: GlassTheme.primaryAccent),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Stats
        Row(
          children: [
            _buildCorrelationStat('Correlations', '${events.length}', GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildCorrelationStat('High Confidence', '${events.where((e) => e.confidence >= 0.8).length}', GlassTheme.successColor),
            const SizedBox(width: 12),
            _buildCorrelationStat('Strong', '${events.where((e) => e.strength == 'strong' || e.strength == 'very_strong').length}', GlassTheme.warningColor),
          ],
        ),
        const SizedBox(height: 24),

        // Run correlation (POST /correlation/run on the live backend)
        GlassCard(
          margin: EdgeInsets.zero,
          onTap: _isRunningCorrelation ? null : () => _runCorrelation(provider),
          child: Row(
            children: [
              if (_isRunningCorrelation)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: GlassTheme.primaryAccent),
                )
              else
                const DuotoneIcon('play', color: GlassTheme.primaryAccent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        _isRunningCorrelation
                            ? 'Running Correlation...'
                            : 'Run Correlation', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.onSurface,
                            fontWeight: FontWeight.bold)),
                    Text('Correlate recent indicators across engines', maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.onSurfaceMuted, fontSize: 12)),
                  ],
                ),
              ),
              DuotoneIcon('alt_arrow_right',
                  color: context.onSurfaceMuted.withValues(alpha: 0.7),
                  size: 24),
            ],
          ),
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'Correlation Events'),
        ...events.map(_buildCorrelationEventCard),
      ],
    );
  }

  Widget _buildCorrelationStat(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.onSurfaceMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Color _getCorrelationEngineColor(String engine) {
    switch (engine) {
      case 'Temporal':
        return AppColors.chartColors[2];
      case 'Infrastructure':
        return GlassTheme.errorColor;
      case 'TTP':
        return GlassTheme.primaryAccent;
      case 'Behavioral':
        return AppColors.chartColors[4];
      case 'Network':
        return AppColors.chartColors[6];
      case 'Campaign':
        return GlassTheme.warningColor;
      default:
        return context.onSurfaceMuted;
    }
  }

  Widget _buildCorrelationEventCard(_CorrelationEvent event) {
    final engineColor = _getCorrelationEngineColor(event.engine);
    final confidenceColor = event.confidence >= 0.8
        ? GlassTheme.successColor
        : event.confidence >= 0.5
            ? GlassTheme.warningColor
            : context.onSurfaceMuted;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DuotoneIcon('link', color: engineColor, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${event.engine} correlation', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: context.onSurface,
                            fontWeight: FontWeight.bold)),
                    if (event.description.isNotEmpty)
                      Text(event.description,
                          style: TextStyle(
                              color: context.onSurfaceMuted, fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${(event.confidence * 100).toInt()}%',
                      style: TextStyle(
                          color: confidenceColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  Text('confidence',
                      style: TextStyle(
                          color: context.onSurfaceMuted.withValues(alpha: 0.7), fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (event.strength.isNotEmpty)
                GlassBadge(
                    text: event.strength.replaceAll('_', ' '),
                    color: engineColor,
                    fontSize: 10),
              const SizedBox(width: 8),
              Text('${event.indicators.length} indicators',
                  style: TextStyle(
                      color: context.onSurfaceMuted, fontSize: 11)),
              const Spacer(),
              Text(
                  event.createdAt != null
                      ? _formatDate(event.createdAt!)
                      : 'unknown',
                  style: TextStyle(
                      color: context.onSurfaceMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMLTab(ThreatHuntingProvider provider) {
    // Convert API data to _MLModel objects
    final models = provider.mlModels.map((data) {
      return _MLModel(
        id: data['id']?.toString() ?? '',
        name: data['name']?.toString() ?? 'Unknown Model',
        description: data['description']?.toString() ?? '',
        type: data['type']?.toString() ?? 'Unknown',
        accuracy: (data['accuracy'] as num?)?.toDouble() ?? 0.0,
        isActive: data['is_active'] as bool? ?? false,
        lastTrained: data['last_trained'] != null
            ? DateTime.tryParse(data['last_trained'] as String) ?? DateTime.now()
            : DateTime.now(),
        anomaliesDetected: data['anomalies_detected'] as int? ?? 0,
      );
    }).toList();

    // Show loading state
    if (provider.isLoadingModels) {
      return const Center(child: CircularProgressIndicator());
    }

    // Show empty state if no models
    if (models.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon('cpu', color: context.onSurfaceMuted, size: 64),
            const SizedBox(height: 16),
            Text('No ML models available', style: TextStyle(color: context.onSurfaceMuted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => provider.loadMLModels(),
              icon: const Icon(Icons.refresh),
              label: const Text('Load Models'),
              style: ElevatedButton.styleFrom(backgroundColor: GlassTheme.primaryAccent),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // Overall ML stats
        GlassCard(
          margin: EdgeInsets.zero,
          child: Row(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: GlassTheme.primaryAccent.withAlpha(40),
                ),
                child: const Center(
                  child: DuotoneIcon('cpu', size: 40, color: GlassTheme.primaryAccent),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ML Engine', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${models.where((m) => m.isActive).length} active models', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.onSurfaceMuted)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const DuotoneIcon('check_circle', size: 14, color: GlassTheme.successColor),
                        const SizedBox(width: 4),
                        const Text('Healthy', style: TextStyle(color: GlassTheme.successColor, fontSize: 12)),
                        const SizedBox(width: 16),
                        Text(
                          '${models.fold(0, (sum, m) => sum + m.anomaliesDetected)} anomalies today',
                          style: TextStyle(color: context.onSurfaceMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Model stats
        Row(
          children: [
            _buildMLStat('Models', '${models.length}', GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildMLStat('Avg Accuracy', models.isEmpty ? 'N/A' : '${(models.fold(0.0, (sum, m) => sum + m.accuracy) / models.length * 100).toStringAsFixed(1)}%', GlassTheme.successColor),
            const SizedBox(width: 12),
            _buildMLStat('Anomalies', '${models.fold(0, (sum, m) => sum + m.anomaliesDetected)}', GlassTheme.warningColor),
          ],
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'ML Models'),
        ...models.map((model) => _buildMLModelCard(model)),
      ],
    );
  }

  Widget _buildMLStat(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.onSurfaceMuted, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildMLModelCard(_MLModel model) {
    return GlassCard(
      onTap: () => _showMLModelDetails(context, model),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (model.isActive
                          ? GlassTheme.primaryAccent
                          : context.onSurfaceMuted)
                      .withAlpha(40),
                  borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
                ),
                child: Center(
                  child: DuotoneIcon(
                    'cpu',
                    size: 24,
                    color: model.isActive
                        ? GlassTheme.primaryAccent
                        : context.onSurfaceMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.onSurface, fontWeight: FontWeight.bold)),
                    Text(model.description, style: TextStyle(color: context.onSurfaceMuted, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${model.accuracy}%', style: TextStyle(color: GlassTheme.successColor, fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('accuracy', style: TextStyle(color: context.onSurfaceMuted.withValues(alpha: 0.7), fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GlassBadge(text: model.type, color: GlassTheme.primaryAccent, fontSize: 10),
              const SizedBox(width: 8),
              GlassBadge(text: model.isActive ? 'Active' : 'Inactive', color: model.isActive ? GlassTheme.successColor : context.onSurfaceMuted, fontSize: 10),
              const Spacer(),
              DuotoneIcon('danger_triangle', size: 14, color: GlassTheme.warningColor.withAlpha(179)),
              const SizedBox(width: 4),
              Text('${model.anomaliesDetected} anomalies', style: TextStyle(color: context.onSurfaceMuted, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  void _showMLModelDetails(BuildContext context, _MLModel model) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius:
                const BorderRadius.vertical(
                    top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: GlassTheme.primaryAccent.withAlpha(40),
                      borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
                    ),
                    child: const DuotoneIcon('cpu', color: GlassTheme.primaryAccent, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
                        GlassBadge(text: model.type, color: GlassTheme.primaryAccent),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(model.description, style: TextStyle(color: context.onSurface.withValues(alpha: 0.8))),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildResultRow('Accuracy', '${model.accuracy}%'),
                    _buildResultRow('Status', model.isActive ? 'Active' : 'Inactive'),
                    _buildResultRow('Anomalies Detected', '${model.anomaliesDetected}'),
                    _buildResultRow('Last Trained', _formatModelDate(model.lastTrained)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatModelDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }
}

/// Parsed view of a backend NodeView ({id, label, type, properties}) as
/// served by GET /graph/nodes.
class _HuntGraphNode {
  final String id;
  final String label;
  final String type;
  final Map<String, dynamic> properties;

  _HuntGraphNode({
    required this.id,
    required this.label,
    required this.type,
    required this.properties,
  });

  factory _HuntGraphNode.fromJson(Map<String, dynamic> json) {
    final properties = (json['properties'] is Map)
        ? Map<String, dynamic>.from(json['properties'] as Map)
        : <String, dynamic>{};
    final id = json['id']?.toString() ?? '';
    final label = (properties['value'] as String?) ??
        (properties['name'] as String?) ??
        json['label']?.toString() ??
        id;
    return _HuntGraphNode(
      id: id,
      label: label,
      type: json['type']?.toString() ?? json['label']?.toString() ?? 'unknown',
      properties: properties,
    );
  }
}

/// Paints the real relationship edges between rendered node positions.
class _GraphEdgePainter extends CustomPainter {
  final List<(Offset, Offset)> edges;
  final Color edgeColor;

  _GraphEdgePainter(this.edges, this.edgeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = edgeColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final (a, b) in edges) {
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgePainter oldDelegate) =>
      oldDelegate.edges != edges || oldDelegate.edgeColor != edgeColor;
}

/// Parsed view of a backend CorrelationEvent ({id, type, strength,
/// confidence, description, indicators, created_at}) as served by
/// GET /correlation.
class _CorrelationEvent {
  final String id;
  final String engine; // humanized CorrelationType
  final String strength; // weak | moderate | strong | very_strong
  final double confidence;
  final String description;
  final List<String> indicators;
  final DateTime? createdAt;

  _CorrelationEvent({
    required this.id,
    required this.engine,
    required this.strength,
    required this.confidence,
    required this.description,
    required this.indicators,
    this.createdAt,
  });

  static String _engineFromType(String? type) {
    switch (type) {
      case 'temporal':
        return 'Temporal';
      case 'infrastructure':
        return 'Infrastructure';
      case 'ttp':
        return 'TTP';
      case 'behavioral':
        return 'Behavioral';
      case 'network':
        return 'Network';
      case 'campaign':
        return 'Campaign';
      default:
        return type ?? 'Unknown';
    }
  }

  factory _CorrelationEvent.fromJson(Map<String, dynamic> json) {
    final createdRaw = json['created_at'] as String?;
    return _CorrelationEvent(
      id: json['id']?.toString() ?? '',
      engine: _engineFromType(json['type'] as String?),
      strength: json['strength'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      indicators: (json['indicators'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      createdAt: createdRaw != null ? DateTime.tryParse(createdRaw) : null,
    );
  }
}

class _MLModel {
  final String id;
  final String name;
  final String description;
  final String type;
  final double accuracy;
  final bool isActive;
  final DateTime lastTrained;
  final int anomaliesDetected;

  _MLModel({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.accuracy,
    required this.isActive,
    required this.lastTrained,
    required this.anomaliesDetected,
  });
}
