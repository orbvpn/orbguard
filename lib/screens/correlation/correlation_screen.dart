/// Correlation Engine Screen
/// Advanced threat correlation and analysis interface.
///
/// Wire format: GET /correlation returns {results: [CorrelationEvent...],
/// count} where a CorrelationEvent is {id, type (temporal|infrastructure|
/// ttp|behavioral|network|campaign), strength (weak|moderate|strong|
/// very_strong), confidence, description, indicators: [uuid...],
/// campaign_id?, threat_actor_id?, evidence, created_at}. POST
/// /correlation/run executes a server-scoped correlation over recent
/// indicators and returns {run, correlations, statistics}.

import 'package:flutter/material.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class CorrelationScreen extends StatefulWidget {
  const CorrelationScreen({super.key});

  @override
  State<CorrelationScreen> createState() => _CorrelationScreenState();
}

class _CorrelationScreenState extends State<CorrelationScreen> {
  final OrbGuardApiClient _apiClient = OrbGuardApiClient.instance;
  bool _isLoading = false;
  bool _isCorrelating = false;
  String? _error;
  final List<CorrelationResult> _results = [];
  String _selectedEngine = 'All';

  // Mirrors the backend CorrelationType enum (models/correlation.go).
  final List<String> _engines = [
    'All',
    'Temporal',
    'Infrastructure',
    'TTP',
    'Behavioral',
    'Network',
    'Campaign',
  ];

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await _apiClient.getCorrelationResults();

      setState(() {
        _results.clear();
        _results.addAll(data.map((json) => CorrelationResult.fromJson(json)));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load correlation results: $e';
        _isLoading = false;
      });
    }
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

                // Error state (real load failures are shown, not hidden)
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: GlassCard(
                      tintColor: GlassTheme.errorColor,
                      child: Row(
                        children: [
                          const DuotoneIcon('danger_circle',
                              color: GlassTheme.errorColor, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(
                                  color: Colors.white.withAlpha(204),
                                  fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: const DuotoneIcon('refresh',
                                color: Colors.white, size: 20),
                            onPressed: _loadResults,
                            tooltip: 'Retry',
                          ),
                        ],
                      ),
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

  /// Runs a server-scoped correlation (POST /correlation/run), then
  /// refreshes the persisted results list so the screen reflects exactly
  /// what the backend stored.
  Future<void> _runCorrelation() async {
    setState(() => _isCorrelating = true);

    try {
      final result = await _apiClient.runCorrelation();

      final found = (result['correlations'] is List)
          ? (result['correlations'] as List).length
          : 0;

      if (!mounted) return;
      setState(() => _isCorrelating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            found == 0
                ? 'Correlation run complete — no new correlations found'
                : 'Correlation run complete — $found correlation'
                    '${found == 1 ? '' : 's'} found',
          ),
          backgroundColor: GlassTheme.gradientTop,
        ),
      );

      // Refresh from the persisted list (GET /correlation) after the run.
      await _loadResults();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCorrelating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Correlation failed: $e'), backgroundColor: GlassTheme.errorColor),
      );
    }
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
                    if (result.strength.isNotEmpty)
                      _buildDetailRow('Strength',
                          CorrelationResult._humanStrength(result.strength)),
                    _buildDetailRow('Correlated Indicators', '${result.linkedEntities}'),
                    _buildDetailRow('Created', _formatTime(result.timestamp)),
                  ],
                ),
              ),
              if (result.relatedIndicators.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text('Correlated Indicators (IDs)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...result.relatedIndicators.map((indicator) => GlassCard(
                      child: Row(
                        children: [
                          const GlassSvgIconBox(icon: AppIcons.dangerTriangle, color: GlassTheme.errorColor, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              indicator,
                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                            ),
                          ),
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
      case 'Temporal':
        return const Color(0xFF2196F3);
      case 'Infrastructure':
        return GlassTheme.errorColor;
      case 'TTP':
        return GlassTheme.primaryAccent;
      case 'Behavioral':
        return const Color(0xFF9C27B0);
      case 'Network':
        return const Color(0xFF4CAF50);
      case 'Campaign':
        return GlassTheme.warningColor;
      default:
        return Colors.grey;
    }
  }

  String _getEngineIcon(String engine) {
    switch (engine) {
      case 'Temporal':
        return AppIcons.clock;
      case 'Infrastructure':
        return AppIcons.objectScan;
      case 'TTP':
        return AppIcons.mitre;
      case 'Behavioral':
        return AppIcons.mlAnalysis;
      case 'Network':
        return AppIcons.urlProtection;
      case 'Campaign':
        return AppIcons.campaign;
      default:
        return AppIcons.correlation;
    }
  }

  String _formatTime(DateTime time) {
    if (time.millisecondsSinceEpoch == 0) return 'unknown';
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

}

/// Parsed view of a backend CorrelationEvent
/// (orbguard.lab internal/domain/models/correlation.go).
class CorrelationResult {
  final String id;
  final String title;
  final String description;
  final String engine; // humanized CorrelationType
  final String strength; // weak | moderate | strong | very_strong
  final double confidence;
  final int linkedEntities;
  final DateTime timestamp;

  /// Correlated indicator UUIDs (the backend links events to indicators
  /// by id, not by raw value).
  final List<String> relatedIndicators;

  CorrelationResult({
    required this.id,
    required this.title,
    required this.description,
    required this.engine,
    required this.strength,
    required this.confidence,
    required this.linkedEntities,
    required this.timestamp,
    required this.relatedIndicators,
  });

  /// Maps a backend CorrelationType to the engine display name used by the
  /// filter chips.
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

  static String _humanStrength(String strength) =>
      strength.replaceAll('_', ' ');

  factory CorrelationResult.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    final engine = _engineFromType(type);
    final strength = json['strength'] as String? ?? '';
    final indicators = (json['indicators'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];
    final createdRaw = json['created_at'] as String?;

    return CorrelationResult(
      id: json['id'] as String? ?? '',
      title: strength.isEmpty
          ? '$engine correlation'
          : '$engine correlation (${_humanStrength(strength)})',
      description: json['description'] as String? ?? '',
      engine: engine,
      strength: strength,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      linkedEntities: indicators.length,
      timestamp: (createdRaw != null ? DateTime.tryParse(createdRaw) : null) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      relatedIndicators: indicators,
    );
  }
}
