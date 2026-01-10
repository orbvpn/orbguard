/// Intelligence Sources Screen
/// Threat intelligence source management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class IntelligenceSourcesScreen extends StatefulWidget {
  const IntelligenceSourcesScreen({super.key});

  @override
  State<IntelligenceSourcesScreen> createState() => _IntelligenceSourcesScreenState();
}

class _IntelligenceSourcesScreenState extends State<IntelligenceSourcesScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  final List<IntelSource> _sources = [];

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final api = OrbGuardApiClient.instance;
      final sourcesData = await api.getIntelSources();

      setState(() {
        _sources.clear();
        _sources.addAll(sourcesData.map((json) => IntelSource.fromJson(json)));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load intelligence sources: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Intelligence Sources',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : _errorMessage != null
              ? _buildErrorState()
              : _sources.isEmpty
                  ? _buildEmptyState()
                  : Column(
                  children: [
                    // Actions row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            icon: DuotoneIcon(AppIcons.addCircle, size: 22, color: Colors.white),
                            onPressed: () => _showAddSourceDialog(context),
                            tooltip: 'Add Source',
                          ),
                          IconButton(
                            icon: DuotoneIcon(AppIcons.refresh, size: 22, color: Colors.white),
                            onPressed: _isLoading ? null : _loadSources,
                            tooltip: 'Refresh',
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          // Stats
                          Row(
                            children: [
                              _buildStatCard('Active', _sources.where((s) => s.isEnabled).length.toString(), GlassTheme.successColor),
                              const SizedBox(width: 12),
                              _buildStatCard('Total IOCs', _formatIOCCount(_sources.fold(0, (sum, s) => sum + s.indicatorCount)), GlassTheme.primaryAccent),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // Source categories
                          const GlassSectionHeader(title: 'Open Source Feeds'),
                          ..._sources.where((s) => s.category == 'Open Source').map(_buildSourceCard),

                          const GlassSectionHeader(title: 'Commercial Feeds'),
                          ..._sources.where((s) => s.category == 'Commercial').map(_buildSourceCard),

                          const GlassSectionHeader(title: 'Community Feeds'),
                          ..._sources.where((s) => s.category == 'Community').map(_buildSourceCard),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  String _formatIOCCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceCard(IntelSource source) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getSourceIcon(source.type),
                color: source.isEnabled ? GlassTheme.successColor : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      source.type,
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Switch(
                value: source.isEnabled,
                onChanged: (v) => setState(() => source.isEnabled = v),
                activeColor: GlassTheme.successColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSourceStat(AppIcons.database, '${source.indicatorCount} IOCs'),
              const SizedBox(width: 16),
              _buildSourceStat(AppIcons.clock, 'Updated ${source.lastUpdated}'),
            ],
          ),
          if (source.description != null) ...[
            const SizedBox(height: 8),
            Text(
              source.description!,
              style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              GlassBadge(text: source.format, color: GlassTheme.primaryAccent, fontSize: 10),
              const SizedBox(width: 8),
              GlassBadge(
                text: '${source.updateFrequency}',
                color: const Color(0xFF9C27B0),
                fontSize: 10,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceStat(String icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: Colors.white.withAlpha(128)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(AppIcons.intelligence, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          const Text(
            'No Intelligence Sources',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Add threat intelligence feeds to enrich your data',
            style: TextStyle(color: Colors.white.withAlpha(153)),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _showAddSourceDialog(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuotoneIcon(AppIcons.addCircle, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                const Text('Add Source'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(AppIcons.dangerTriangle, size: 64, color: GlassTheme.errorColor.withAlpha(128)),
          const SizedBox(height: 16),
          const Text(
            'Failed to Load Sources',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              _errorMessage ?? 'An unexpected error occurred',
              style: TextStyle(color: Colors.white.withAlpha(153)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadSources,
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuotoneIcon(AppIcons.refresh, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                const Text('Retry'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAddSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GlassTheme.gradientTop,
        title: const Text('Add Intelligence Source', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Source Name',
                labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Feed URL',
                labelStyle: TextStyle(color: Colors.white.withAlpha(128)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Add', style: TextStyle(color: GlassTheme.primaryAccent)),
          ),
        ],
      ),
    );
  }

  String _getSourceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'stix/taxii':
        return AppIcons.stixTaxii;
      case 'misp':
        return AppIcons.structure;
      case 'csv':
        return AppIcons.fileText;
      case 'json':
        return AppIcons.code;
      default:
        return AppIcons.intelligence;
    }
  }
}

class IntelSource {
  final String name;
  final String type;
  final String category;
  final String format;
  final String updateFrequency;
  final int indicatorCount;
  final String lastUpdated;
  final String? description;
  bool isEnabled;

  IntelSource({
    required this.name,
    required this.type,
    required this.category,
    required this.format,
    required this.updateFrequency,
    required this.indicatorCount,
    required this.lastUpdated,
    this.description,
    this.isEnabled = true,
  });

  factory IntelSource.fromJson(Map<String, dynamic> json) {
    return IntelSource(
      name: json['name'] as String? ?? 'Unknown',
      type: json['type'] as String? ?? 'Unknown',
      category: json['category'] as String? ?? 'Other',
      format: json['format'] as String? ?? 'Unknown',
      updateFrequency: json['update_frequency'] as String? ?? 'Unknown',
      indicatorCount: json['indicator_count'] as int? ?? 0,
      lastUpdated: json['last_updated'] as String? ?? 'N/A',
      description: json['description'] as String?,
      isEnabled: json['is_enabled'] as bool? ?? json['enabled'] as bool? ?? true,
    );
  }
}
