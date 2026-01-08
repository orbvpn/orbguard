/// Campaigns Screen
/// Active threat campaign tracking and intelligence interface

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../services/api/orbguard_api_client.dart';
import '../../models/api/campaign.dart';

class CampaignsScreen extends StatefulWidget {
  const CampaignsScreen({super.key});

  @override
  State<CampaignsScreen> createState() => _CampaignsScreenState();
}

class _CampaignsScreenState extends State<CampaignsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _showActiveOnly = true;
  List<Campaign> _campaigns = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCampaigns();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Threat Campaigns',
        actions: [
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GlassTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Active'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCampaignsList(_campaigns.where((c) => c.isActive).toList()),
                _buildCampaignsList(_campaigns),
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
                icon: _getCampaignIcon(campaign.type),
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
                          campaign.type,
                          style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              GlassBadge(text: campaign.severity.toUpperCase(), color: severityColor, fontSize: 10),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            campaign.description,
            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCampaignStat(AppIcons.dangerTriangle, '${campaign.indicatorCount} IOCs'),
              const SizedBox(width: 16),
              _buildCampaignStat(AppIcons.clock, _formatDate(campaign.firstSeen)),
              const Spacer(),
              if (campaign.actorName != null)
                GlassBadge(text: campaign.actorName!, color: const Color(0xFF9C27B0), fontSize: 10),
            ],
          ),
          if (campaign.targetedRegions.isNotEmpty || campaign.targetedSectors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ...campaign.targetedRegions.take(2).map((region) =>
                    _buildTargetChip(AppIcons.global, region, const Color(0xFF2196F3))),
                ...campaign.targetedSectors.take(2).map((sector) =>
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
                    icon: _getCampaignIcon(campaign.type),
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
                campaign.description,
                style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 14),
              ),
              const SizedBox(height: 20),

              // Details
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Type', campaign.type),
                    _buildDetailRow('Severity', campaign.severity.toUpperCase()),
                    _buildDetailRow('First Seen', _formatDate(campaign.firstSeen)),
                    if (campaign.lastSeen != null)
                      _buildDetailRow('Last Seen', _formatDate(campaign.lastSeen!)),
                    _buildDetailRow('Indicators', '${campaign.indicatorCount} IOCs'),
                    if (campaign.actorName != null)
                      _buildDetailRow('Threat Actor', campaign.actorName!),
                  ],
                ),
              ),

              // Targets
              if (campaign.targetedRegions.isNotEmpty || campaign.targetedSectors.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Targets',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (campaign.targetedRegions.isNotEmpty) ...[
                  const GlassSectionHeader(title: 'Regions'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: campaign.targetedRegions.map((r) =>
                        GlassBadge(text: r, color: const Color(0xFF2196F3))).toList(),
                  ),
                ],
                if (campaign.targetedSectors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const GlassSectionHeader(title: 'Sectors'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: campaign.targetedSectors.map((s) =>
                        GlassBadge(text: s, color: const Color(0xFFFF9800))).toList(),
                  ),
                ],
              ],

              // TTPs
              if (campaign.ttps.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'MITRE ATT&CK TTPs',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: campaign.ttps.map((ttp) => Container(
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
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return GlassTheme.errorColor;
      case 'high':
        return const Color(0xFFFF5722);
      case 'medium':
        return GlassTheme.warningColor;
      case 'low':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  String _getCampaignIcon(String type) {
    switch (type.toLowerCase()) {
      case 'phishing':
        return AppIcons.letter;
      case 'ransomware':
        return AppIcons.lock;
      case 'apt':
        return AppIcons.shieldCheck;
      case 'malware':
        return AppIcons.bug;
      case 'ddos':
        return AppIcons.cloudStorage;
      case 'espionage':
        return AppIcons.eye;
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
    return [
      Campaign(
        id: '1',
        name: 'PhishHook 2025',
        type: 'Phishing',
        description: 'Large-scale phishing campaign targeting financial institutions with fake login pages.',
        severity: 'critical',
        isActive: true,
        firstSeen: DateTime.now().subtract(const Duration(days: 14)),
        lastSeen: DateTime.now().subtract(const Duration(hours: 2)),
        indicatorCount: 245,
        actorName: 'FIN7',
        targetedRegions: ['North America', 'Europe'],
        targetedSectors: ['Financial', 'Banking'],
        ttps: ['T1566.001', 'T1204', 'T1078'],
      ),
      Campaign(
        id: '2',
        name: 'RansomCloud',
        type: 'Ransomware',
        description: 'Cloud-targeting ransomware campaign exploiting misconfigured S3 buckets.',
        severity: 'high',
        isActive: true,
        firstSeen: DateTime.now().subtract(const Duration(days: 30)),
        indicatorCount: 89,
        targetedRegions: ['Global'],
        targetedSectors: ['Technology', 'Healthcare'],
        ttps: ['T1486', 'T1490', 'T1027'],
      ),
      Campaign(
        id: '3',
        name: 'MobileHunter',
        type: 'Malware',
        description: 'Android spyware distributed through fake app stores targeting mobile banking users.',
        severity: 'high',
        isActive: true,
        firstSeen: DateTime.now().subtract(const Duration(days: 45)),
        indicatorCount: 156,
        actorName: 'APT41',
        targetedRegions: ['Asia Pacific'],
        targetedSectors: ['Mobile Banking', 'Cryptocurrency'],
        ttps: ['T1437', 'T1533', 'T1417'],
      ),
      Campaign(
        id: '4',
        name: 'CredentialStorm',
        type: 'APT',
        description: 'Sophisticated credential harvesting campaign using supply chain compromise.',
        severity: 'critical',
        isActive: false,
        firstSeen: DateTime.now().subtract(const Duration(days: 90)),
        lastSeen: DateTime.now().subtract(const Duration(days: 15)),
        indicatorCount: 312,
        actorName: 'Lazarus Group',
        targetedRegions: ['South Korea', 'Japan', 'USA'],
        targetedSectors: ['Defense', 'Government'],
        ttps: ['T1195', 'T1078', 'T1003'],
      ),
    ];
  }
}
