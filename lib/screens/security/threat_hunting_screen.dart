/// Threat Hunting Screen
/// Proactive threat detection and investigation dashboard

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../providers/threat_hunting_provider.dart';
import '../../services/security/threat_hunting_service.dart';

class ThreatHuntingScreen extends StatefulWidget {
  const ThreatHuntingScreen({super.key});

  @override
  State<ThreatHuntingScreen> createState() => _ThreatHuntingScreenState();
}

class _ThreatHuntingScreenState extends State<ThreatHuntingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ThreatHuntingProvider>().initialize();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThreatHuntingProvider>(
      builder: (context, provider, _) {
        return GlassScaffold(
          appBar: GlassAppBar(
            title: 'Threat Hunting',
            actions: [
              if (provider.isHunting)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(GlassTheme.primaryAccent),
                    ),
                  ),
                )
              else
                IconButton(
                  icon: const Icon(Icons.play_arrow),
                  tooltip: 'Run All Critical Hunts',
                  onPressed: () => provider.executeAllCriticalHunts(),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              indicatorColor: const Color(GlassTheme.primaryAccent),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(text: 'Hunts'),
                Tab(text: 'Findings'),
                Tab(text: 'Cases'),
                Tab(text: 'MITRE'),
              ],
            ),
          ),
          body: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: Color(GlassTheme.primaryAccent),
                  ),
                )
              : Column(
                  children: [
                    // Hunt Progress
                    if (provider.isHunting && provider.currentProgress != null)
                      _buildHuntProgress(provider),
                    // Stats
                    if (!provider.isHunting) _buildStats(provider),
                    // Tab content
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildHuntsTab(provider),
                          _buildFindingsTab(provider),
                          _buildCasesTab(provider),
                          _buildMitreTab(provider),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
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
                  color: Color(GlassTheme.primaryAccent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hunt?.name ?? 'Running Hunt',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      progress.phase,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${(progress.progress * 100).toInt()}%',
                style: const TextStyle(
                  color: Color(GlassTheme.primaryAccent),
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
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(GlassTheme.primaryAccent),
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
            const Color(GlassTheme.primaryAccent),
          ),
          _buildStatItem(
            'Findings',
            provider.totalFindings.toString(),
            const Color(GlassTheme.warningColor),
          ),
          _buildStatItem(
            'Critical',
            provider.criticalFindingsCount.toString(),
            const Color(GlassTheme.errorColor),
          ),
          _buildStatItem(
            'Cases',
            provider.openCases.length.toString(),
            const Color(0xFF9C27B0),
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
                color: Colors.white.withOpacity(0.6),
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
        icon: Icons.search,
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
      padding: const EdgeInsets.all(16),
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

    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: isRunning ? null : () => _showHuntDetails(context, hunt, provider),
        borderRadius: BorderRadius.circular(16),
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
                      color: typeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getHuntTypeIcon(hunt.type),
                      color: typeColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hunt.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hunt.type.displayName,
                          style: TextStyle(
                            color: typeColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (result != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: result.hasCriticalFindings
                            ? const Color(GlassTheme.errorColor).withOpacity(0.2)
                            : const Color(GlassTheme.successColor).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        result.hasCriticalFindings
                            ? '${result.findings.length} findings'
                            : 'Clean',
                        style: TextStyle(
                          color: result.hasCriticalFindings
                              ? const Color(GlassTheme.errorColor)
                              : const Color(GlassTheme.successColor),
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
                  color: Colors.white.withOpacity(0.7),
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
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          id,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: isRunning || provider.isHunting
                        ? null
                        : () => provider.executeHunt(hunt.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(GlassTheme.primaryAccent),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white12,
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
        icon: Icons.check_circle,
        title: 'No Findings',
        subtitle: 'Run threat hunts to detect security issues',
        color: const Color(GlassTheme.successColor),
      );
    }

    // Sort by severity
    allFindings.sort((a, b) => b.severity.compareTo(a.severity));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
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
                    color: severityColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getFindingIcon(finding.type),
                    color: severityColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        finding.ruleName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        finding.type.name.replaceAll(RegExp(r'(?=[A-Z])'), ' ').trim(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
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
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    finding.severityLevel.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
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
                color: Colors.white.withOpacity(0.8),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            GlassContainer(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  const Icon(
                    Icons.code,
                    size: 14,
                    color: Colors.white38,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      finding.evidence,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'monospace',
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
                        color: const Color(GlassTheme.primaryAccent).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        id,
                        style: const TextStyle(
                          color: Color(GlassTheme.primaryAccent),
                          fontSize: 10,
                          fontFamily: 'monospace',
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
                        const Icon(
                          Icons.arrow_right,
                          size: 16,
                          color: Color(GlassTheme.primaryAccent),
                        ),
                        Expanded(
                          child: Text(
                            r,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
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
        icon: Icons.folder_open,
        title: 'No Investigation Cases',
        subtitle: 'Create cases from findings to track investigations',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
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
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caseItem.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${caseItem.relatedFindings.length} related findings',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
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
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
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
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  'Opened ${_formatDate(caseItem.createdAt)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
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
        icon: Icons.grid_view,
        title: 'MITRE ATT&CK Coverage',
        subtitle: 'Attack techniques covered by threat hunts',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            'MITRE ATT&CK techniques covered by available hunts',
            style: TextStyle(
              color: Colors.white70,
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
                    color: const Color(GlassTheme.primaryAccent).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    techniqueId,
                    style: const TextStyle(
                      color: Color(GlassTheme.primaryAccent),
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${hunts.length} hunt(s)',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _getMitreDescription(techniqueId),
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
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
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      hunt.name,
                      style: const TextStyle(
                        color: Colors.white54,
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
    required IconData icon,
    required String title,
    required String subtitle,
    Color color = const Color(GlassTheme.primaryAccent),
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: color.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  IconData _getHuntTypeIcon(HuntType type) {
    switch (type) {
      case HuntType.iocSweep:
        return Icons.search;
      case HuntType.behaviorAnalysis:
        return Icons.psychology;
      case HuntType.anomalyDetection:
        return Icons.trending_up;
      case HuntType.attackPattern:
        return Icons.pattern;
      case HuntType.dataExfiltration:
        return Icons.upload;
      case HuntType.persistenceMechanism:
        return Icons.repeat;
      case HuntType.lateral:
        return Icons.swap_horiz;
      case HuntType.privilegeEscalation:
        return Icons.arrow_upward;
    }
  }

  IconData _getFindingIcon(FindingType type) {
    switch (type) {
      case FindingType.malwareIndicator:
        return Icons.bug_report;
      case FindingType.suspiciousApp:
        return Icons.apps;
      case FindingType.networkAnomaly:
        return Icons.wifi;
      case FindingType.dataExfiltration:
        return Icons.upload;
      case FindingType.persistenceMechanism:
        return Icons.repeat;
      case FindingType.privilegeAbuse:
        return Icons.admin_panel_settings;
      case FindingType.configurationRisk:
        return Icons.settings;
      case FindingType.vulnerableComponent:
        return Icons.warning;
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
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(GlassTheme.gradientTop),
                Color(GlassTheme.gradientBottom),
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                      color: typeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _getHuntTypeIcon(hunt.type),
                      color: typeColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hunt.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          hunt.type.displayName,
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
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              GlassContainer(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hypothesis',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hunt.hypothesis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Detection Rules',
                style: TextStyle(
                  color: Colors.white,
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
                        Icon(
                          Icons.rule,
                          size: 18,
                          color: Color(ThreatHuntingProvider.getSeverityColor(rule.severity)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rule.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Type: ${rule.type.name}',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
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
                const Text(
                  'Last Result',
                  style: TextStyle(
                    color: Colors.white,
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
                      _buildResultRow('Duration', '${result.duration.inSeconds}s'),
                    ],
                  ),
                ),
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
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Run Hunt'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(GlassTheme.primaryAccent),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
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
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
