/// Campaigns Screen
/// Active threat campaign tracking and intelligence interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../models/api/campaign.dart';
import '../../models/api/threat_indicator.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen> {
  bool _isLoading = true;
  bool _showActiveOnly = true;
  List<Campaign> _campaigns = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCampaigns();
  }

  Future<void> _loadCampaigns() async {
    setState(() => _isLoading = true);

    try {
      final response = await OrbGuardApiClient.instance.listCampaigns(active: _showActiveOnly);
      setState(() {
        _campaigns = response.items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load campaigns';
        _isLoading = false;
        // Load sample data
        _campaigns = _getSampleCampaigns();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassTabPage(
      title: 'Threat Campaigns',
      headerContent: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              icon: DuotoneIcon(
                _showActiveOnly ? AppIcons.filter : AppIcons.closeCircle,
                size: 24,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() => _showActiveOnly = !_showActiveOnly);
                _loadCampaigns();
              },
            ),
            IconButton(
              icon: const DuotoneIcon(AppIcons.refresh, size: 24, color: Colors.white),
              onPressed: _isLoading ? null : _loadCampaigns,
            ),
          ],
        ),
      ),
      tabs: [
        GlassTab(
          label: 'Active',
          iconPath: 'shield',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _buildCampaignsList(_campaigns.where((c) => c.isActive).toList()),
        ),
        GlassTab(
          label: 'Critical',
          iconPath: 'danger_triangle',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _buildCampaignsList(_campaigns.where((c) => c.severity == SeverityLevel.critical).toList()),
        ),
        GlassTab(
          label: 'Stats',
          iconPath: 'chart',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _buildStatsView(),
        ),
        GlassTab(
          label: 'History',
          iconPath: 'history',
          content: _isLoading
              ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
              : _buildCampaignsList(_campaigns),
        ),
      ],
    );
  }

  Widget _buildStatsView() {
    final activeCampaigns = _campaigns.where((c) => c.isActive).length;
    final criticalCount = _campaigns.where((c) => c.severity == SeverityLevel.critical).length;
    final highCount = _campaigns.where((c) => c.severity == SeverityLevel.high).length;
    final totalIOCs = _campaigns.fold<int>(0, (sum, c) => sum + c.indicatorCount);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Campaign Overview',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildStatRow('Total Campaigns', '${_campaigns.length}', AppIcons.campaign),
              _buildStatRow('Active Campaigns', '$activeCampaigns', AppIcons.shieldCheck),
              _buildStatRow('Critical Severity', '$criticalCount', AppIcons.dangerTriangle),
              _buildStatRow('High Severity', '$highCount', AppIcons.dangerTriangle),
              _buildStatRow('Total IOCs', '$totalIOCs', AppIcons.hook),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value, String icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 20, color: GlassTheme.primaryAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withAlpha(179)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCampaignsList(List<Campaign> campaigns) {
    if (campaigns.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.campaign,
        title: 'No Campaigns',
        subtitle: 'Active threat campaigns will appear here',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: campaigns.length,
      itemBuilder: (context, index) {
        return _buildCampaignCard(campaigns[index]);
      },
    );
  }

  Widget _buildCampaignCard(Campaign campaign) {
    final severityColor = _getSeverityColor(campaign.severity);

    return GlassCard(
      onTap: () => _showCampaignDetails(context, campaign),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getCampaignIcon(campaign.objective ?? 'unknown'),
                color: severityColor,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      campaign.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Row(
                      children: [
                        if (campaign.isActive)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: GlassTheme.successColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(
                          campaign.objective ?? 'Unknown',
                          style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GlassBadge(text: campaign.severity.value.toUpperCase(), color: severityColor, fontSize: 10),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            campaign.description ?? 'No description available',
            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCampaignStat(AppIcons.dangerTriangle, '${campaign.indicatorCount} IOCs'),
              const SizedBox(width: 16),
              if (campaign.firstSeen != null)
                _buildCampaignStat(AppIcons.clock, _formatDate(campaign.firstSeen!)),
              const Spacer(),
              if (campaign.associatedActors.isNotEmpty)
                GlassBadge(text: campaign.associatedActors.first, color: const Color(0xFF9C27B0), fontSize: 10),
            ],
          ),
          if (campaign.targetedCountries.isNotEmpty || campaign.targetedIndustries.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...campaign.targetedCountries.take(2).map((region) =>
                    _buildTargetChip(AppIcons.global, region, const Color(0xFF2196F3))),
                ...campaign.targetedIndustries.take(2).map((sector) =>
                    _buildTargetChip(AppIcons.enterprise, sector, const Color(0xFFFF9800))),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCampaignStat(String icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: Colors.white.withAlpha(128)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
      ],
    );
  }

  Widget _buildTargetChip(String icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required String icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: Colors.white.withAlpha(153)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showCampaignDetails(BuildContext context, Campaign campaign) {
    final severityColor = _getSeverityColor(campaign.severity);

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
              colors: [GlassTheme.gradientTop, GlassTheme.gradientBottom],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              // Header
              Row(
                children: [
                  GlassSvgIconBox(
                    icon: _getCampaignIcon(campaign.objective ?? 'unknown'),
                    color: severityColor,
                    size: 56,
                    iconSize: 28,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          campaign.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          children: [
                            if (campaign.isActive)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: const BoxDecoration(
                                  color: GlassTheme.successColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Text(
                              campaign.isActive ? 'Active Campaign' : 'Inactive',
                              style: TextStyle(
                                color: campaign.isActive ? GlassTheme.successColor : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Description
              Text(
                campaign.description ?? 'No description available',
                style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Details
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (campaign.objective != null)
                      _buildDetailRow('Objective', campaign.objective!),
                    _buildDetailRow('Severity', campaign.severity.value.toUpperCase()),
                    if (campaign.firstSeen != null)
                      _buildDetailRow('First Seen', _formatDate(campaign.firstSeen!)),
                    if (campaign.lastSeen != null)
                      _buildDetailRow('Last Seen', _formatDate(campaign.lastSeen!)),
                    _buildDetailRow('Indicators', '${campaign.indicatorCount} IOCs'),
                    if (campaign.associatedActors.isNotEmpty)
                      _buildDetailRow('Threat Actors', campaign.associatedActors.join(', ')),
                  ],
                ),
              ),

              // Targets
              if (campaign.targetedCountries.isNotEmpty || campaign.targetedIndustries.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Targets',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (campaign.targetedCountries.isNotEmpty) ...[
                  const GlassSectionHeader(title: 'Countries'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: campaign.targetedCountries.map((r) =>
                        GlassBadge(text: r, color: const Color(0xFF2196F3))).toList(),
                  ),
                ],
                if (campaign.targetedIndustries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const GlassSectionHeader(title: 'Industries'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: campaign.targetedIndustries.map((s) =>
                        GlassBadge(text: s, color: const Color(0xFFFF9800))).toList(),
                  ),
                ],
              ],

              // TTPs
              if (campaign.mitreTechniques.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'MITRE ATT&CK TTPs',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: campaign.mitreTechniques.map((ttp) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: GlassTheme.primaryAccent.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          ttp,
                          style: const TextStyle(
                            color: GlassTheme.primaryAccent,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                      )).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
        return GlassTheme.errorColor;
      case SeverityLevel.high:
        return const Color(0xFFFF5722);
      case SeverityLevel.medium:
        return GlassTheme.warningColor;
      case SeverityLevel.low:
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  String _getCampaignIcon(String objective) {
    switch (objective.toLowerCase()) {
      case 'phishing':
        return AppIcons.letter;
      case 'ransomware':
        return AppIcons.lock;
      case 'espionage':
        return AppIcons.eye;
      case 'financial':
        return AppIcons.wallet;
      case 'sabotage':
        return AppIcons.dangerTriangle;
      default:
        return AppIcons.campaign;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  List<Campaign> _getSampleCampaigns() {
    final now = DateTime.now();
    return [
      Campaign(
        id: '1',
        name: 'PhishHook 2025',
        objective: 'phishing',
        description: 'Large-scale phishing campaign targeting financial institutions with fake login pages.',
        severity: SeverityLevel.critical,
        isActive: true,
        firstSeen: now.subtract(const Duration(days: 14)),
        lastSeen: now.subtract(const Duration(hours: 2)),
        indicatorCount: 245,
        associatedActors: ['FIN7'],
        targetedCountries: ['North America', 'Europe'],
        targetedIndustries: ['Financial', 'Banking'],
        mitreTechniques: ['T1566.001', 'T1204', 'T1078'],
        aliases: [],
        targetedPlatforms: [],
        createdAt: now,
        updatedAt: now,
      ),
      Campaign(
        id: '2',
        name: 'RansomCloud',
        objective: 'ransomware',
        description: 'Cloud-targeting ransomware campaign exploiting misconfigured S3 buckets.',
        severity: SeverityLevel.high,
        isActive: true,
        firstSeen: now.subtract(const Duration(days: 30)),
        indicatorCount: 89,
        targetedCountries: ['Global'],
        targetedIndustries: ['Technology', 'Healthcare'],
        mitreTechniques: ['T1486', 'T1490', 'T1027'],
        aliases: [],
        associatedActors: [],
        targetedPlatforms: [],
        createdAt: now,
        updatedAt: now,
      ),
      Campaign(
        id: '3',
        name: 'MobileHunter',
        objective: 'espionage',
        description: 'Android spyware distributed through fake app stores targeting mobile banking users.',
        severity: SeverityLevel.high,
        isActive: true,
        firstSeen: now.subtract(const Duration(days: 45)),
        indicatorCount: 156,
        associatedActors: ['APT41'],
        targetedCountries: ['Asia Pacific'],
        targetedIndustries: ['Mobile Banking', 'Cryptocurrency'],
        mitreTechniques: ['T1437', 'T1533', 'T1417'],
        aliases: [],
        targetedPlatforms: ['android'],
        createdAt: now,
        updatedAt: now,
      ),
      Campaign(
        id: '4',
        name: 'CredentialStorm',
        objective: 'financial',
        description: 'Sophisticated credential harvesting campaign using supply chain compromise.',
        severity: SeverityLevel.critical,
        isActive: false,
        firstSeen: now.subtract(const Duration(days: 90)),
        lastSeen: now.subtract(const Duration(days: 15)),
        indicatorCount: 312,
        associatedActors: ['Lazarus Group'],
        targetedCountries: ['South Korea', 'Japan', 'USA'],
        targetedIndustries: ['Defense', 'Government'],
        mitreTechniques: ['T1195', 'T1078', 'T1003'],
        aliases: [],
        targetedPlatforms: [],
        createdAt: now,
        updatedAt: now,
      ),
    ];
  }
}
