/// Integrations Screen
/// Third-party integrations management interface

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_app_bar.dart';
import '../../presentation/widgets/glass_widgets.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  bool _isLoading = false;
  final List<Integration> _integrations = [];

  @override
  void initState() {
    super.initState();
    _loadIntegrations();
  }

  Future<void> _loadIntegrations() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _integrations.addAll(_getSampleIntegrations());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Integrations',
        actions: [
          GlassAppBarAction(
            svgIcon: AppIcons.refresh,
            onTap: _isLoading ? null : _loadIntegrations,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Stats
                Row(
                  children: [
                    _buildStatCard('Connected', _integrations.where((i) => i.isConnected).length.toString(), GlassTheme.successColor),
                    const SizedBox(width: 12),
                    _buildStatCard('Available', _integrations.length.toString(), GlassTheme.primaryAccent),
                  ],
                ),
                const SizedBox(height: 24),

                // Connected integrations
                if (_integrations.any((i) => i.isConnected)) ...[
                  const GlassSectionHeader(title: 'Connected'),
                  ..._integrations.where((i) => i.isConnected).map((i) => _buildIntegrationCard(i)),
                ],

                // Available integrations
                const GlassSectionHeader(title: 'Available Integrations'),
                ..._integrations.where((i) => !i.isConnected).map((i) => _buildIntegrationCard(i)),
              ],
            ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildIntegrationCard(Integration integration) {
    return GlassCard(
      onTap: () => _showIntegrationDetails(context, integration),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: integration.color.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: DuotoneIcon(
                _getIntegrationIcon(integration.type),
                color: integration.color,
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
                  integration.name,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  integration.description,
                  style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          integration.isConnected
              ? const GlassBadge(text: 'Connected', color: GlassTheme.successColor, fontSize: 10)
              : OutlinedButton(
                  onPressed: () => _connectIntegration(integration),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: GlassTheme.primaryAccent,
                    side: const BorderSide(color: GlassTheme.primaryAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero,
                  ),
                  child: const Text('Connect', style: TextStyle(fontSize: 12)),
                ),
        ],
      ),
    );
  }

  void _showIntegrationDetails(BuildContext context, Integration integration) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
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
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: integration.color.withAlpha(40),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: DuotoneIcon(
                        _getIntegrationIcon(integration.type),
                        color: integration.color,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          integration.name,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        integration.isConnected
                            ? const GlassBadge(text: 'Connected', color: GlassTheme.successColor)
                            : const GlassBadge(text: 'Not Connected', color: Colors.grey),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(integration.description, style: TextStyle(color: Colors.white.withAlpha(204))),
              const SizedBox(height: 24),

              const Text('Features', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...integration.features.map((feature) => _buildFeatureRow(feature)),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: integration.isConnected
                    ? OutlinedButton(
                        onPressed: () {
                          setState(() => integration.isConnected = false);
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: GlassTheme.errorColor,
                          side: const BorderSide(color: GlassTheme.errorColor),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DuotoneIcon(AppIcons.urlProtection, size: 18, color: GlassTheme.errorColor),
                            const SizedBox(width: 8),
                            const Text('Disconnect'),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        onPressed: () {
                          _connectIntegration(integration);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: GlassTheme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DuotoneIcon(AppIcons.urlProtection, size: 18, color: Colors.white),
                            const SizedBox(width: 8),
                            const Text('Connect'),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow(String feature) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          DuotoneIcon(AppIcons.checkCircle, size: 18, color: GlassTheme.successColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(feature, style: TextStyle(color: Colors.white.withAlpha(204))),
          ),
        ],
      ),
    );
  }

  void _connectIntegration(Integration integration) {
    setState(() => integration.isConnected = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${integration.name} connected successfully'),
        backgroundColor: GlassTheme.successColor,
      ),
    );
  }

  String _getIntegrationIcon(String type) {
    switch (type.toLowerCase()) {
      case 'messaging':
        return AppIcons.chatLine;
      case 'siem':
        return AppIcons.shieldCheck;
      case 'ticketing':
        return AppIcons.ticket;
      case 'cloud':
        return AppIcons.cloudStorage;
      case 'email':
        return AppIcons.letter;
      case 'analytics':
        return AppIcons.chartSquare;
      default:
        return AppIcons.integrations;
    }
  }

  List<Integration> _getSampleIntegrations() {
    return [
      Integration(
        id: '1',
        name: 'Slack',
        type: 'Messaging',
        description: 'Send alerts and notifications to Slack channels.',
        color: const Color(0xFF4A154B),
        features: [
          'Real-time threat alerts',
          'Daily summary reports',
          'Interactive incident response',
          'Custom channel routing',
        ],
        isConnected: true,
      ),
      Integration(
        id: '2',
        name: 'Microsoft Teams',
        type: 'Messaging',
        description: 'Integrate with Microsoft Teams for collaboration.',
        color: const Color(0xFF5558AF),
        features: [
          'Threat notifications',
          'Team collaboration',
          'Adaptive cards support',
          'Bot interactions',
        ],
        isConnected: true,
      ),
      Integration(
        id: '3',
        name: 'Splunk',
        type: 'SIEM',
        description: 'Send events to Splunk for advanced analysis.',
        color: const Color(0xFF65A637),
        features: [
          'Event forwarding',
          'Custom dashboards',
          'Correlation rules',
          'Historical analysis',
        ],
        isConnected: false,
      ),
      Integration(
        id: '4',
        name: 'ServiceNow',
        type: 'Ticketing',
        description: 'Create and manage security incidents.',
        color: const Color(0xFF81B5A1),
        features: [
          'Auto ticket creation',
          'Incident management',
          'SLA tracking',
          'Workflow automation',
        ],
        isConnected: false,
      ),
      Integration(
        id: '5',
        name: 'AWS Security Hub',
        type: 'Cloud',
        description: 'Integrate with AWS Security Hub findings.',
        color: const Color(0xFFFF9900),
        features: [
          'Finding export',
          'Compliance checks',
          'Multi-account support',
          'Resource monitoring',
        ],
        isConnected: false,
      ),
      Integration(
        id: '6',
        name: 'PagerDuty',
        type: 'Ticketing',
        description: 'Alert on-call teams for critical threats.',
        color: const Color(0xFF06AC38),
        features: [
          'Critical alerts',
          'On-call scheduling',
          'Escalation policies',
          'Incident response',
        ],
        isConnected: false,
      ),
      Integration(
        id: '7',
        name: 'Jira',
        type: 'Ticketing',
        description: 'Create Jira issues for security incidents.',
        color: const Color(0xFF0052CC),
        features: [
          'Issue creation',
          'Custom fields',
          'Project mapping',
          'Status sync',
        ],
        isConnected: false,
      ),
    ];
  }
}

class Integration {
  final String id;
  final String name;
  final String type;
  final String description;
  final Color color;
  final List<String> features;
  bool isConnected;

  Integration({
    required this.id,
    required this.name,
    required this.type,
    required this.description,
    required this.color,
    required this.features,
    this.isConnected = false,
  });
}
