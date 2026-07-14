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
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
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
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassPage(
      title: 'Correlation Engine',
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppColors.accentInk))
          : Column(
              children: [
                // Actions row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: DuotoneIcon(AppIcons.play, size: 22, color: cs.onSurface),
                        onPressed: _isCorrelating ? null : _runCorrelation,
                        tooltip: 'Run Correlation',
                      ),
                      IconButton(
                        icon: DuotoneIcon(AppIcons.refresh, size: 22, color: cs.onSurface),
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
                          backgroundColor: GlassTheme.glassColor(isDark),
                          selectedColor: GlassTheme.primaryAccent.withAlpha(77),
                          labelStyle: TextStyle(
                            color: isSelected ? AppColors.accentInk : cs.onSurfaceVariant,
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
                      _buildStatCard(context, 'Correlations', _results.length.toString(), AppColors.accentInk),
                      const SizedBox(width: 12),
                      _buildStatCard(context, 'High Confidence', _results.where((r) => r.confidence >= 0.8).length.toString(), AppColors.accentInk),
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
                                  color: cs.onSurface,
                                  fontSize: 12),
                            ),
                          ),
                          IconButton(
                            icon: DuotoneIcon('refresh',
                                color: cs.onSurface, size: 20),
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
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentInk),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Running correlation...', style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500)),
                                Text('Analyzing threat patterns', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
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
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          itemCount: _filteredResults.length,
                          itemBuilder: (context, index) {
                            return _buildResultCard(context, _filteredResults[index]);
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

  Widget _buildStatCard(BuildContext context, String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: GlassContainer(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(BuildContext context, CorrelationResult result) {
    final cs = Theme.of(context).colorScheme;
    final confidenceColor = result.confidence >= 0.8
        ? AppColors.accentInk
        : result.confidence >= 0.5
            ? GlassTheme.warningColor
            : cs.onSurfaceVariant;

    return GlassCard(
      onTap: () => _showResultDetails(context, result),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getEngineIcon(result.engine),
                color: _getEngineColor(context, result.engine),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      result.engine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _getEngineColor(context, result.engine), fontSize: 11),
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
                  Text('confidence', style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 10)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            result.description,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCorrelationStat(context, AppIcons.urlProtection, '${result.linkedEntities} entities'),
              const SizedBox(width: 16),
              _buildCorrelationStat(context, AppIcons.clock, _formatTime(result.timestamp)),
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
                      borderRadius: BorderRadius.circular(GlassTheme.radiusXSmall),
                    ),
                    child: Text(
                      indicator,
                      style: TextStyle(color: AppColors.errorInk, fontSize: 10, fontFamily: Brand.fontMono),
                    ),
                  )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCorrelationStat(BuildContext context, String icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(AppIcons.correlation, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          Text(
            'No Correlations',
            style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Run correlation to find threat relationships',
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _runCorrelation,
            style: ElevatedButton.styleFrom(
              backgroundColor: GlassTheme.primaryAccent,
              foregroundColor: Brand.onLime,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DuotoneIcon(AppIcons.play, size: 18, color: Brand.onLime),
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
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(GlassTheme.radiusLarge)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Text(result.title, style: TextStyle(color: context.onSurface, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              GlassBadge(text: result.engine, color: _getEngineColor(context, result.engine)),
              const SizedBox(height: 16),
              Text(result.description, style: TextStyle(color: context.onSurfaceMuted)),
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
                Text('Correlated Indicators (IDs)', style: TextStyle(color: context.onSurface, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ...result.relatedIndicators.map((indicator) => GlassCard(
                      child: Row(
                        children: [
                          const GlassSvgIconBox(icon: AppIcons.dangerTriangle, color: GlassTheme.errorColor, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              indicator,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: context.onSurface, fontFamily: Brand.fontMono, fontSize: 12),
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
          Text(label, style: TextStyle(color: context.onSurfaceMuted)),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: context.onSurface, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Color _getEngineColor(BuildContext context, String engine) {
    switch (engine) {
      case 'Temporal':
        return AppColors.chartColors[2];
      case 'Infrastructure':
        return GlassTheme.errorColor;
      case 'TTP':
        return GlassTheme.primaryAccent;
      case 'Behavioral':
        return AppColors.chartColors[4];
      case 'Network':
        return AppColors.chartColors[6];
      case 'Campaign':
        return GlassTheme.warningColor;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
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
