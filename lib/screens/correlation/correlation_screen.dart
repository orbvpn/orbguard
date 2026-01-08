/// Correlation Engine Screen
/// Advanced threat correlation and analysis interface

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class CorrelationScreen extends StatefulWidget {
  const CorrelationScreen({super.key});

  @override
  State<CorrelationScreen> createState() => _CorrelationScreenState();
}

class _CorrelationScreenState extends State<CorrelationScreen> {
  bool _isLoading = false;
  bool _isCorrelating = false;
  final List<CorrelationResult> _results = [];
  String _selectedEngine = 'All';

  final List<String> _engines = ['All', 'IOC Matching', 'Behavior Analysis', 'MITRE Mapping', 'Campaign Attribution'];

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _results.addAll(_getSampleResults());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassPage(
      title: 'Correlation Engine',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : Column(
              children: [
                // Actions row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: DuotoneIcon(AppIcons.play, size: 22, color: Colors.white),
                        onPressed: _isCorrelating ? null : _runCorrelation,
                        tooltip: 'Run Correlation',
                      ),
                      IconButton(
                        icon: DuotoneIcon(AppIcons.refresh, size: 22, color: Colors.white),
                        onPressed: _isLoading ? null : _loadResults,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),
                ),
                // Engine filter
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: _engines.map((engine) {
                      final isSelected = engine == _selectedEngine;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(engine),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _selectedEngine = engine),
                          backgroundColor: GlassTheme.glassColorDark,
                          selectedColor: GlassTheme.primaryAccent.withAlpha(77),
                          labelStyle: TextStyle(
                            color: isSelected ? GlassTheme.primaryAccent : Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Stats
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildStatCard('Correlations', _results.length.toString(), GlassTheme.primaryAccent),
                      const SizedBox(width: 12),
                      _buildStatCard('High Confidence', _results.where((r) => r.confidence >= 0.8).length.toString(), GlassTheme.successColor),
                    ],
                  ),
                ),

                // Running indicator
                if (_isCorrelating)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GlassCard(
                      tintColor: GlassTheme.primaryAccent,
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: GlassTheme.primaryAccent),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Running correlation...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                                Text('Analyzing threat patterns', style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Results
                Expanded(
                  child: _results.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredResults.length,
                          itemBuilder: (context, index) {
                            return _buildResultCard(_filteredResults[index]);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  List<CorrelationResult> get _filteredResults {
    if (_selectedEngine == 'All') return _results;
    return _results.where((r) => r.engine == _selectedEngine).toList();
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

  Widget _buildResultCard(CorrelationResult result) {
    final confidenceColor = result.confidence >= 0.8
        ? GlassTheme.successColor
        : result.confidence >= 0.5
            ? GlassTheme.warningColor
            : Colors.grey;

    return GlassCard(
      onTap: () => _showResultDetails(context, result),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getEngineIcon(result.engine),
                color: _getEngineColor(result.engine),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      result.engine,
                      style: TextStyle(color: _getEngineColor(result.engine), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(result.confidence * 100).toInt()}%',
                    style: TextStyle(color: confidenceColor, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text('confidence', style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.description,
            style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCorrelationStat(AppIcons.urlProtection, '${result.linkedEntities} entities'),
              const SizedBox(width: 16),
              _buildCorrelationStat(AppIcons.clock, _formatTime(result.timestamp)),
            ],
          ),
          if (result.relatedIndicators.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: result.relatedIndicators.take(3).map((indicator) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: GlassTheme.errorColor.withAlpha(40),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      indicator,
                      style: const TextStyle(color: GlassTheme.errorColor, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCorrelationStat(String icon, String text) {
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
          DuotoneIcon(AppIcons.correlation, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          const Text(
            'No Correlations',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Run correlation to find threat relationships',
            style: TextStyle(color: Colors.white.withAlpha(153)),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _runCorrelation,
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuotoneIcon(AppIcons.play, size: 18, color: Colors.white),
                const SizedBox(width: 8),
                const Text('Run Correlation'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _runCorrelation() {
    setState(() => _isCorrelating = true);

    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        _isCorrelating = false;
        _results.insert(0, CorrelationResult(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'New Correlation Found',
          description: 'Detected relationship between recent phishing campaign and known threat actor.',
          engine: 'Campaign Attribution',
          confidence: 0.87,
          linkedEntities: 5,
          timestamp: DateTime.now(),
          relatedIndicators: ['185.192.69.x', 'fake-login.com', 'APT41'],
        ));
      });
    });
  }

  void _showResultDetails(BuildContext context, CorrelationResult result) {
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
              Text(result.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GlassBadge(text: result.engine, color: _getEngineColor(result.engine)),
              const SizedBox(height: 16),
              Text(result.description, style: TextStyle(color: Colors.white.withAlpha(204))),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Confidence', '${(result.confidence * 100).toInt()}%'),
                    _buildDetailRow('Linked Entities', '${result.linkedEntities}'),
                    _buildDetailRow('Timestamp', _formatTime(result.timestamp)),
                  ],
                ),
              ),
              if (result.relatedIndicators.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Related Indicators', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...result.relatedIndicators.map((indicator) => GlassCard(
                      child: Row(
                        children: [
                          const GlassSvgIconBox(icon: AppIcons.dangerTriangle, color: GlassTheme.errorColor, size: 36),
                          const SizedBox(width: 12),
                          Text(indicator, style: const TextStyle(color: Colors.white, fontFamily: 'monospace')),
                        ],
                      ),
                    )),
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

  Color _getEngineColor(String engine) {
    switch (engine) {
      case 'IOC Matching':
        return GlassTheme.errorColor;
      case 'Behavior Analysis':
        return const Color(0xFF9C27B0);
      case 'MITRE Mapping':
        return GlassTheme.primaryAccent;
      case 'Campaign Attribution':
        return GlassTheme.warningColor;
      default:
        return Colors.grey;
    }
  }

  String _getEngineIcon(String engine) {
    switch (engine) {
      case 'IOC Matching':
        return AppIcons.objectScan;
      case 'Behavior Analysis':
        return AppIcons.mlAnalysis;
      case 'MITRE Mapping':
        return AppIcons.mitre;
      case 'Campaign Attribution':
        return AppIcons.campaign;
      default:
        return AppIcons.correlation;
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  List<CorrelationResult> _getSampleResults() {
    return [
      CorrelationResult(
        id: '1',
        title: 'APT41 Campaign Link',
        description: 'Multiple indicators from recent scan match known APT41 infrastructure.',
        engine: 'Campaign Attribution',
        confidence: 0.92,
        linkedEntities: 8,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        relatedIndicators: ['185.192.69.44', 'cobaltstrike.com', 'mimikatz.exe'],
      ),
      CorrelationResult(
        id: '2',
        title: 'Credential Theft Pattern',
        description: 'Behavior pattern matches known credential theft techniques (T1003).',
        engine: 'MITRE Mapping',
        confidence: 0.85,
        linkedEntities: 5,
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        relatedIndicators: ['T1003', 'lsass.exe', 'procdump.exe'],
      ),
      CorrelationResult(
        id: '3',
        title: 'Phishing Infrastructure',
        description: 'Domain registration patterns indicate coordinated phishing campaign.',
        engine: 'IOC Matching',
        confidence: 0.78,
        linkedEntities: 12,
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        relatedIndicators: ['fake-login*.com', '192.168.x.x', 'phishing-kit.zip'],
      ),
    ];
  }
}

class CorrelationResult {
  final String id;
  final String title;
  final String description;
  final String engine;
  final double confidence;
  final int linkedEntities;
  final DateTime timestamp;
  final List<String> relatedIndicators;

  CorrelationResult({
    required this.id,
    required this.title,
    required this.description,
    required this.engine,
    required this.confidence,
    required this.linkedEntities,
    required this.timestamp,
    required this.relatedIndicators,
  });
}
