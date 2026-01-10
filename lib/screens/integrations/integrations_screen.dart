// Integrations Screen
// Third-party integrations management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class IntegrationsScreen extends StatefulWidget {
  const IntegrationsScreen({super.key});

  @override
  State<IntegrationsScreen> createState() => _IntegrationsScreenState();
}

class _IntegrationsScreenState extends State<IntegrationsScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  final List<Integration> _integrations = [];

  @override
  void initState() {
    super.initState();
    _loadIntegrations();
  }

  Future<void> _loadIntegrations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiData = await OrbGuardApiClient.instance.getIntegrations();
      final integrations = apiData.map((json) => Integration.fromJson(json)).toList();

      setState(() {
        _integrations.clear();
        _integrations.addAll(integrations);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load integrations: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Integrations',
      body: Column(
        children: [
          // Actions row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: DuotoneIcon(AppIcons.refresh, size: 22, color: Colors.white),
                  onPressed: _isLoading ? null : _loadIntegrations,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
                : _errorMessage != null
                    ? _buildErrorState()
                    : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
          ),
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
                          Navigator.pop(context);
                          _disconnectIntegration(integration);
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
                          Navigator.pop(context);
                          _connectIntegration(integration);
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

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DuotoneIcon(AppIcons.shieldWarning, size: 48, color: GlassTheme.errorColor),
            const SizedBox(height: 16),
            Text(
              'Error Loading Integrations',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadIntegrations,
              icon: DuotoneIcon(AppIcons.refresh, size: 18, color: GlassTheme.primaryAccent),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: GlassTheme.primaryAccent,
                side: const BorderSide(color: GlassTheme.primaryAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectIntegration(Integration integration) async {
    try {
      await OrbGuardApiClient.instance.updateIntegration(
        integration.id,
        {'is_connected': true},
      );
      setState(() => integration.isConnected = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${integration.name} connected successfully'),
            backgroundColor: GlassTheme.successColor,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect ${integration.name}: ${e.toString()}'),
            backgroundColor: GlassTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _disconnectIntegration(Integration integration) async {
    try {
      await OrbGuardApiClient.instance.updateIntegration(
        integration.id,
        {'is_connected': false},
      );
      setState(() => integration.isConnected = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${integration.name} disconnected'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to disconnect ${integration.name}: ${e.toString()}'),
            backgroundColor: GlassTheme.errorColor,
          ),
        );
      }
    }
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

  factory Integration.fromJson(Map<String, dynamic> json) {
    return Integration(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'other',
      description: json['description'] as String? ?? '',
      color: _parseColor(json['color']),
      features: (json['features'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isConnected: json['is_connected'] as bool? ?? false,
    );
  }

  static Color _parseColor(dynamic colorValue) {
    if (colorValue == null) return const Color(0xFF6B7280);
    if (colorValue is int) return Color(colorValue);
    if (colorValue is String) {
      // Handle hex color strings like "#FF5500" or "0xFFFF5500"
      String hex = colorValue.replaceAll('#', '').replaceAll('0x', '');
      if (hex.length == 6) hex = 'FF$hex'; // Add alpha if missing
      return Color(int.parse(hex, radix: 16));
    }
    return const Color(0xFF6B7280);
  }
}
