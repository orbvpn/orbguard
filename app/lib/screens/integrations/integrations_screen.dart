// Integrations Screen
// Third-party integrations management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/api_interceptors.dart' show ApiError;
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
      // Integrations is an optional enterprise feature — when the backend does
      // not expose it the endpoint 404s. Treat that as an empty state (the
      // normal "Available Integrations" list, just empty) rather than a scary
      // error. Non-404 errors are real and still surface.
      final gone = e is ApiError && e.statusCode == 404;
      setState(() {
        if (gone) _integrations.clear();
        _errorMessage =
            gone ? null : 'Failed to load integrations: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Integrations',
      actions: [
        GestureDetector(
          onTap: () {
            if (!_isLoading) _loadIntegrations();
          },
          child: DuotoneIcon(AppIcons.refresh, size: 22, color: context.colors.onSurface),
        ),
      ],
      body: Column(
        children: [
          // Content
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
                : _errorMessage != null
                    ? _buildErrorState()
                    : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      // Stats
                      Row(
                        children: [
                          _buildStatCard('Connected', _integrations.where((i) => i.isConnected).length.toString(), AppColors.accentInk),
                          const SizedBox(width: 12),
                          _buildStatCard('Available', _integrations.length.toString(), AppColors.accentInk),
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
            Text(value, style: BrandText.heading(color: color, size: 28)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12)),
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
              borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
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
                  style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  integration.description,
                  style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 12),
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
                    foregroundColor: AppColors.accentInk,
                    side: BorderSide(color: AppColors.accentInk),
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: context.isDark
                  ? const [GlassTheme.gradientTop, GlassTheme.gradientBottom]
                  : const [GlassTheme.gradientTopLight, GlassTheme.gradientBottomLight],
            ),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
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
                      borderRadius: BorderRadius.circular(GlassTheme.radiusMedium),
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
                          style: TextStyle(color: context.colors.onSurface, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        integration.isConnected
                            ? const GlassBadge(text: 'Connected', color: GlassTheme.successColor)
                            : GlassBadge(text: 'Not Connected', color: context.colors.onSurfaceVariant),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(integration.description, style: TextStyle(color: context.colors.onSurface.withValues(alpha: 0.8))),
              const SizedBox(height: 24),

              Text('Features', style: TextStyle(color: context.colors.onSurface, fontWeight: FontWeight.bold)),
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
                          foregroundColor: AppColors.errorInk,
                          side: BorderSide(color: AppColors.errorInk),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DuotoneIcon(AppIcons.urlProtection, size: 18, color: AppColors.errorInk),
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
                          foregroundColor: Brand.onLime,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            DuotoneIcon(AppIcons.urlProtection, size: 18, color: Brand.onLime),
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
          DuotoneIcon(AppIcons.checkCircle, size: 18, color: AppColors.accentInk),
          const SizedBox(width: 12),
          Expanded(
            child: Text(feature, style: TextStyle(color: context.colors.onSurface.withValues(alpha: 0.8))),
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
            DuotoneIcon(AppIcons.shieldWarning, size: 48, color: AppColors.errorInk),
            const SizedBox(height: 16),
            Text(
              'Error Loading Integrations',
              style: TextStyle(color: context.colors.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage ?? 'An unknown error occurred',
              style: TextStyle(color: context.colors.onSurfaceVariant, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _loadIntegrations,
              icon: DuotoneIcon(AppIcons.refresh, size: 18, color: AppColors.accentInk),
              label: const Text('Retry'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentInk,
                side: BorderSide(color: AppColors.accentInk),
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
            backgroundColor: Brand.surface2,
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
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isConnected: json['is_connected'] as bool? ?? false,
    );
  }

  static Color _parseColor(dynamic colorValue) {
    if (colorValue == null) return AppColors.severityInfo;
    if (colorValue is int) return Color(colorValue);
    if (colorValue is String) {
      // Handle hex color strings like "#FF5500" or "0xFFFF5500"
      String hex = colorValue.replaceAll('#', '').replaceAll('0x', '');
      if (hex.length == 6) hex = 'FF$hex'; // Add alpha if missing
      // Tolerate a non-hex color string (e.g. a named color) instead of
      // throwing and failing the whole integrations parse.
      final parsed = int.tryParse(hex, radix: 16);
      if (parsed != null) return Color(parsed);
    }
    return AppColors.severityInfo;
  }
}
