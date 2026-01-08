/// Intelligence Sources Screen
/// Threat intelligence source management interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/glass_widgets.dart';

class IntelligenceSourcesScreen extends StatefulWidget {
  const IntelligenceSourcesScreen({super.key});

  @override
  State<IntelligenceSourcesScreen> createState() => _IntelligenceSourcesScreenState();
}

class _IntelligenceSourcesScreenState extends State<IntelligenceSourcesScreen> {
  bool _isLoading = false;
  final List<IntelSource> _sources = [];

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  Future<void> _loadSources() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _sources.addAll(_getSampleSources());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'Intelligence Sources',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddSourceDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSources,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : _sources.isEmpty
              ? _buildEmptyState()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Stats
                    Row(
                      children: [
                        _buildStatCard('Active', _sources.where((s) => s.isEnabled).length.toString(), GlassTheme.successColor),
                        const SizedBox(width: 12),
                        _buildStatCard('Total IOCs', '45.2K', GlassTheme.primaryAccent),
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
    );
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
              GlassIconBox(
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
              _buildSourceStat(Icons.storage, '${source.indicatorCount} IOCs'),
              const SizedBox(width: 16),
              _buildSourceStat(Icons.access_time, 'Updated ${source.lastUpdated}'),
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

  Widget _buildSourceStat(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.white.withAlpha(128)),
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
          Icon(Icons.source, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
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
          ElevatedButton.icon(
            onPressed: () => _showAddSourceDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Source'),
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Colors.white,
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

  IconData _getSourceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'stix/taxii':
        return Icons.api;
      case 'misp':
        return Icons.hub;
      case 'csv':
        return Icons.table_chart;
      case 'json':
        return Icons.code;
      default:
        return Icons.source;
    }
  }

  List<IntelSource> _getSampleSources() {
    return [
      IntelSource(
        name: 'AlienVault OTX',
        type: 'STIX/TAXII',
        category: 'Open Source',
        format: 'STIX 2.1',
        updateFrequency: 'Hourly',
        indicatorCount: 15420,
        lastUpdated: '2h ago',
        description: 'Open Threat Exchange community-driven threat intelligence.',
        isEnabled: true,
      ),
      IntelSource(
        name: 'Abuse.ch',
        type: 'CSV',
        category: 'Open Source',
        format: 'CSV',
        updateFrequency: 'Every 5 min',
        indicatorCount: 8930,
        lastUpdated: '5m ago',
        description: 'Malware and botnet tracking feeds.',
        isEnabled: true,
      ),
      IntelSource(
        name: 'MISP Community',
        type: 'MISP',
        category: 'Community',
        format: 'MISP JSON',
        updateFrequency: 'Real-time',
        indicatorCount: 12500,
        lastUpdated: '1h ago',
        description: 'MISP community threat sharing platform.',
        isEnabled: true,
      ),
      IntelSource(
        name: 'Recorded Future',
        type: 'JSON',
        category: 'Commercial',
        format: 'JSON',
        updateFrequency: 'Real-time',
        indicatorCount: 5200,
        lastUpdated: '30m ago',
        description: 'Premium threat intelligence feed.',
        isEnabled: false,
      ),
      IntelSource(
        name: 'PhishTank',
        type: 'JSON',
        category: 'Open Source',
        format: 'JSON',
        updateFrequency: 'Hourly',
        indicatorCount: 3150,
        lastUpdated: '45m ago',
        description: 'Community-driven phishing URL database.',
        isEnabled: true,
      ),
    ];
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
}
