/// ML Analysis Screen
/// Machine learning anomaly detection and analysis interface
///
/// Wire format note: GET /ml/models returns the MLService stats object
/// (`models_loaded`, `models: [MLModelInfo]`, ...). Each MLModelInfo carries
/// `name`, `version`, `type`, `status` ("ready"/"not_trained"), `trained_at`,
/// `training_size`, optional `accuracy` (omitted when untrained) and
/// `feature_names`.
///
/// GET /ml/anomalies scores recent indicators with the trained isolation
/// forest and returns `{anomalies: [{indicator_id, score, is_anomaly,
/// threshold, confidence, contributors, method, computed_at, value?, type?,
/// severity?}], count, processed, statistics}`; while the anomaly model is
/// untrained it answers 409 code "models_not_trained", which this screen
/// surfaces as an informative state (not an error).
///
/// GET /ml/insights derives narrative insights from real indicator-store
/// statistics and model state: `{insights: [{id, title, description,
/// severity, generated_at, data?}], count}`. An empty store yields an empty
/// list — rendered as an honest empty state, never fabricated entries.
///
/// There is still no server endpoint for enabling/disabling individual
/// models, so that control remains disabled.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/app_theme.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_tab_page.dart';
import '../../presentation/widgets/glass_widgets.dart';
import '../../services/api/orbguard_api_client.dart';

class MLAnalysisScreen extends StatefulWidget {
  const MLAnalysisScreen({super.key});

  @override
  State<MLAnalysisScreen> createState() => _MLAnalysisScreenState();
}

class _MLAnalysisScreenState extends State<MLAnalysisScreen> {
  final GlobalKey<GlassTabPageState> _tabPageKey = GlobalKey<GlassTabPageState>();
  final OrbGuardApiClient _apiClient = OrbGuardApiClient.instance;
  bool _isLoading = false;
  String? _error;
  final List<MLModel> _models = [];
  final List<AnomalyDetection> _anomalies = [];
  final List<MLInsight> _insights = [];

  // True when GET /ml/anomalies answered 409 models_not_trained — the
  // anomaly model has not been trained yet. Rendered as an informative
  // state, distinct from a transport/server error.
  bool _modelsNotTrained = false;
  String? _modelsNotTrainedMessage;

  // True while a manually triggered anomaly analysis is running.
  bool _isRunningAnalysis = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final errors = <String>[];

    List<MLModel> models = [];
    try {
      final modelsData = await _apiClient.getMLModels();
      models = modelsData.map((json) => MLModel.fromJson(json)).toList();
    } catch (e) {
      errors.add('models: $e');
    }

    List<AnomalyDetection> anomalies = [];
    bool modelsNotTrained = false;
    String? modelsNotTrainedMessage;
    try {
      final anomaliesData = await _apiClient.getAnomalies();
      anomalies = anomaliesData
          .map((json) => AnomalyDetection.fromJson(json))
          .toList();
    } on MlModelsNotTrainedError catch (e) {
      modelsNotTrained = true;
      modelsNotTrainedMessage = e.message;
    } catch (e) {
      errors.add('anomalies: $e');
    }

    List<MLInsight> insights = [];
    try {
      final insightsData = await _apiClient.getMLInsights();
      insights = insightsData.map((json) => MLInsight.fromJson(json)).toList();
    } catch (e) {
      errors.add('insights: $e');
    }

    if (!mounted) return;
    setState(() {
      _models
        ..clear()
        ..addAll(models);
      _anomalies
        ..clear()
        ..addAll(anomalies);
      _insights
        ..clear()
        ..addAll(insights);
      _modelsNotTrained = modelsNotTrained;
      _modelsNotTrainedMessage = modelsNotTrainedMessage;
      _error = errors.isEmpty ? null : 'Failed to load ML data — ${errors.join('; ')}';
      _isLoading = false;
    });
  }

  /// Runs the real anomaly analysis (GET /ml/anomalies scores recent
  /// indicators server-side) and switches to the Anomalies tab.
  Future<void> _runAnalysis() async {
    if (_isRunningAnalysis) return;
    setState(() => _isRunningAnalysis = true);

    try {
      final anomaliesData = await _apiClient.getAnomalies();
      if (!mounted) return;
      setState(() {
        _anomalies
          ..clear()
          ..addAll(anomaliesData.map((json) => AnomalyDetection.fromJson(json)));
        _modelsNotTrained = false;
        _modelsNotTrainedMessage = null;
        _isRunningAnalysis = false;
      });
      _tabPageKey.currentState?.animateToTab(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _anomalies.isEmpty
                ? 'Analysis complete — no anomalies detected'
                : 'Analysis complete — ${_anomalies.length} '
                    'anomal${_anomalies.length == 1 ? 'y' : 'ies'} detected',
          ),
        ),
      );
    } on MlModelsNotTrainedError catch (e) {
      if (!mounted) return;
      setState(() {
        _modelsNotTrained = true;
        _modelsNotTrainedMessage = e.message;
        _isRunningAnalysis = false;
      });
      _tabPageKey.currentState?.animateToTab(1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRunningAnalysis = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Analysis failed: $e'),
          backgroundColor: GlassTheme.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_isLoading) {
      return GlassPage(
        title: 'ML Analysis',
        body: const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent)),
      );
    }

    return GlassTabPage(
      key: _tabPageKey,
      title: 'ML Analysis',
      hasSearch: true,
      searchHint: 'Search anomalies...',
      actions: [
        _isRunningAnalysis
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: GlassTheme.primaryAccent,
                  ),
                ),
              )
            : IconButton(
                icon: DuotoneIcon(AppIcons.play, size: 22, color: cs.onSurface),
                onPressed: _runAnalysis,
                tooltip: 'Run Analysis',
              ),
        IconButton(
          icon: DuotoneIcon(AppIcons.refresh, size: 22, color: cs.onSurface),
          onPressed: _isLoading ? null : _loadData,
          tooltip: 'Refresh',
        ),
      ],
      tabs: [
        GlassTab(
          label: 'Models',
          iconPath: 'settings',
          content: _buildModelsTab(context),
        ),
        GlassTab(
          label: 'Anomalies',
          iconPath: 'danger_triangle',
          content: _buildAnomaliesTab(context),
        ),
        GlassTab(
          label: 'Insights',
          iconPath: 'chart',
          content: _buildInsightsTab(context),
        ),
      ],
    );
  }

  Widget _buildModelsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_error != null) ...[
          _buildErrorCard(context, _error!),
          const SizedBox(height: 24),
        ],

        // Stats
        Row(
          children: [
            _buildStatCard(context, 'Models', _models.length.toString(), GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard(context, 'Trained', _models.where((m) => m.isReady).length.toString(), GlassTheme.successColor),
          ],
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'Detection Models'),
        if (_models.isEmpty && _error == null)
          _buildEmptyState(
            context,
            icon: AppIcons.mlAnalysis,
            title: 'No Models Reported',
            subtitle: 'The server did not return any ML models',
          )
        else
          ..._models.map((model) => _buildModelCard(context, model)),
      ],
    );
  }

  Widget _buildErrorCard(BuildContext context, String message) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      tintColor: GlassTheme.errorColor,
      child: Row(
        children: [
          const DuotoneIcon('danger_circle', color: GlassTheme.errorColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: cs.onSurface, fontSize: 12)),
          ),
          IconButton(
            icon: DuotoneIcon('refresh', color: cs.onSurface, size: 20),
            onPressed: _loadData,
            tooltip: 'Retry',
          ),
        ],
      ),
    );
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

  Widget _buildModelCard(BuildContext context, MLModel model) {
    final cs = Theme.of(context).colorScheme;
    final accuracy = model.accuracy;
    final accuracyColor = accuracy == null
        ? cs.onSurfaceVariant
        : accuracy >= 0.9
            ? GlassTheme.successColor
            : accuracy >= 0.7
                ? GlassTheme.warningColor
                : GlassTheme.errorColor;

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(
                icon: _getModelIcon(model.type),
                color: model.isReady ? GlassTheme.primaryAccent : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
                    Text(
                      model.version.isEmpty ? model.type : '${model.type} • v${model.version}', maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ),
              GlassBadge(
                text: model.isReady ? 'READY' : 'NOT TRAINED',
                color: model.isReady ? GlassTheme.successColor : GlassTheme.warningColor,
                fontSize: 10,
              ),
              const SizedBox(width: 8),
              // The server has no endpoint to enable/disable individual
              // models, so this control is intentionally disabled instead of
              // pretending to toggle anything.
              Tooltip(
                message: 'Model enable/disable is not supported by the server yet',
                child: Switch(
                  value: model.isReady,
                  onChanged: null,
                  activeThumbColor: GlassTheme.successColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildModelMetric(
                context,
                'Accuracy',
                accuracy != null ? '${(accuracy * 100).toInt()}%' : 'n/a',
                accuracyColor,
              ),
              const SizedBox(width: 16),
              _buildModelMetric(context, 'Training Size', model.trainingSize.toString(), cs.onSurfaceVariant),
              const SizedBox(width: 16),
              _buildModelMetric(context, 'Features', model.featureNames.length.toString(), cs.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            model.trainedAt != null
                ? 'Last trained ${_formatTime(model.trainedAt!)}'
                : 'Never trained',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildModelMetric(BuildContext context, String label, String value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.7), fontSize: 10)),
      ],
    );
  }

  Widget _buildAnomaliesTab(BuildContext context) {
    if (_modelsNotTrained) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [_buildModelsNotTrainedCard(context)],
      );
    }

    if (_anomalies.isEmpty) {
      return _buildEmptyState(
        context,
        icon: AppIcons.mlAnalysis,
        title: 'No Anomalies Detected',
        subtitle: 'The anomaly model scored recent indicators and found '
            'nothing anomalous. Use Run Analysis to re-score.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        ..._anomalies.map((anomaly) => _buildAnomalyCard(context, anomaly)),
      ],
    );
  }

  /// Informative card for the 409 models_not_trained state: anomaly
  /// detection exists but its model has not been trained yet on this
  /// deployment, so there is honestly nothing to score with.
  Widget _buildModelsNotTrainedCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      tintColor: GlassTheme.warningColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const GlassSvgIconBox(
                icon: AppIcons.mlAnalysis,
                color: GlassTheme.warningColor,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Anomaly Model Not Trained',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _modelsNotTrainedMessage ??
                'The server-side anomaly detection model has not been '
                    'trained yet.',
            style: TextStyle(color: cs.onSurface, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            'Anomaly detection becomes available once the backend trains the '
            'isolation forest on collected indicators. No fabricated results '
            'are shown in the meantime.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _isRunningAnalysis ? null : _runAnalysis,
              icon: DuotoneIcon(AppIcons.refresh, size: 16,
                  color: GlassTheme.primaryAccent),
              label: const Text(
                'Check Again',
                style: TextStyle(color: GlassTheme.primaryAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnomalyCard(BuildContext context, AnomalyDetection anomaly) {
    final cs = Theme.of(context).colorScheme;
    final severityColor = _getSeverityColor(anomaly.severity);

    return GlassCard(
      tintColor: severityColor,
      onTap: () => _showAnomalyDetails(context, anomaly),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassSvgIconBox(icon: AppIcons.dangerTriangle, color: severityColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(anomaly.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
                    Text(anomaly.model, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              GlassBadge(text: anomaly.severity.toUpperCase(), color: severityColor, fontSize: 10),
            ],
          ),
          const SizedBox(height: 12),
          Text(anomaly.description, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildAnomalyStat(
                context,
                AppIcons.graphUp,
                anomaly.anomalyScore != null
                    ? 'Score: ${(anomaly.anomalyScore! * 100).toInt()}%'
                    : 'Score: n/a',
              ),
              const SizedBox(width: 16),
              _buildAnomalyStat(
                context,
                AppIcons.clock,
                anomaly.detectedAt != null ? _formatTime(anomaly.detectedAt!) : 'Time unknown',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnomalyStat(BuildContext context, String icon, String text) {
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

  Widget _buildInsightsTab(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Insights', style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          if (_insights.isEmpty)
            GlassCard(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No insights yet — insights are derived from collected '
                    'indicators and model state, and the store is empty',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            )
          else
            ..._insights.map((insight) => _buildInsightCard(
              context,
              icon: insight.icon,
              title: insight.title,
              insight: insight.description,
              color: insight.color,
            )),

          const SizedBox(height: 24),
          Text('Model Performance', style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          GlassCard(
            child: Column(
              children: _models.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No model data available',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ]
                  : _models.map((model) => _buildPerformanceBar(context, model.name, model.accuracy)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard(
    BuildContext context, {
    required String icon,
    required String title,
    required String insight,
    required Color color,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GlassCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlassSvgIconBox(icon: icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(insight, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceBar(BuildContext context, String label, double? value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ),
              Text(
                value != null ? '${(value * 100).toInt()}%' : 'n/a',
                style: TextStyle(
                  color: value != null ? GlassTheme.primaryAccent : cs.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value ?? 0,
              backgroundColor: cs.onSurface.withValues(alpha: 0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(GlassTheme.primaryAccent),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required String icon,
    required String title,
    required String subtitle,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DuotoneIcon(icon, size: 64, color: GlassTheme.primaryAccent.withAlpha(128)),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: cs.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showAnomalyDetails(BuildContext context, AnomalyDetection anomaly) {
    final severityColor = _getSeverityColor(anomaly.severity);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            gradient: GlassTheme.backgroundGradient(isDark: context.isDark),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  GlassSvgIconBox(icon: AppIcons.dangerTriangle, color: severityColor, size: 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(anomaly.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.onSurface, fontSize: 18, fontWeight: FontWeight.bold)),
                        GlassBadge(text: anomaly.severity.toUpperCase(), color: severityColor),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(anomaly.description, style: TextStyle(color: context.onSurfaceMuted)),
              const SizedBox(height: 20),
              GlassContainer(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Model', anomaly.model),
                    _buildDetailRow(
                      'Anomaly Score',
                      anomaly.anomalyScore != null
                          ? '${(anomaly.anomalyScore! * 100).toInt()}%'
                          : 'n/a',
                    ),
                    _buildDetailRow(
                      'Threshold',
                      anomaly.threshold != null
                          ? '${(anomaly.threshold! * 100).toInt()}%'
                          : 'n/a',
                    ),
                    _buildDetailRow(
                      'Confidence',
                      anomaly.confidence != null
                          ? '${(anomaly.confidence! * 100).toInt()}%'
                          : 'n/a',
                    ),
                    _buildDetailRow(
                      'Detected',
                      anomaly.detectedAt != null ? _formatTime(anomaly.detectedAt!) : 'n/a',
                    ),
                  ],
                ),
              ),
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
          Text(value,
              style: TextStyle(
                  color: context.onSurface, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _getModelIcon(String type) {
    switch (type.toLowerCase()) {
      case 'classification':
        return AppIcons.filter;
      case 'anomaly_detection':
        return AppIcons.dangerTriangle;
      case 'clustering':
        return AppIcons.mlAnalysis;
      case 'nlp':
        return AppIcons.fileText;
      default:
        return AppIcons.cpu;
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return GlassTheme.errorColor;
      case 'high':
        return const Color(0xFFFF5722);
      case 'medium':
        return GlassTheme.warningColor;
      default:
        return const Color(0xFF4CAF50);
    }
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

}

/// Mirrors the live MLModelInfo JSON emitted by the backend
/// (orbguard-lab internal/domain/models/ml.go): name, version, type,
/// trained_at, training_size, accuracy (omitempty), feature_names, status.
class MLModel {
  final String name;
  final String type;
  final String version;
  final String status; // "ready" or "not_trained"
  final double? accuracy; // omitted by the server when not meaningful
  final int trainingSize;
  final DateTime? trainedAt;
  final List<String> featureNames;

  MLModel({
    required this.name,
    required this.type,
    required this.version,
    required this.status,
    required this.trainingSize,
    required this.featureNames,
    this.accuracy,
    this.trainedAt,
  });

  bool get isReady => status == 'ready';

  factory MLModel.fromJson(Map<String, dynamic> json) {
    // Go encodes an untrained model's zero time as "0001-01-01T00:00:00Z";
    // treat that as "never trained" rather than a real timestamp.
    DateTime? trainedAt;
    final rawTrainedAt = json['trained_at'] as String?;
    if (rawTrainedAt != null) {
      final parsed = DateTime.tryParse(rawTrainedAt);
      if (parsed != null && parsed.year > 1970) {
        trainedAt = parsed;
      }
    }

    return MLModel(
      name: json['name'] as String? ?? 'Unknown Model',
      type: json['type'] as String? ?? 'unknown',
      version: json['version'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      trainingSize: (json['training_size'] as num?)?.toInt() ?? 0,
      trainedAt: trainedAt,
      featureNames:
          (json['feature_names'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }
}

/// Mirrors a GET /ml/anomalies entry: the backend AnomalyScore
/// (indicator_id, score, is_anomaly, threshold, confidence, contributors,
/// method, computed_at — see orbguard-lab models/ml.go) enriched with the
/// scored indicator's value/type/severity when the indicator is known.
/// Absent fields stay null and render as "n/a" — never fake values.
class AnomalyDetection {
  final String id;
  final String title;
  final String description;
  final String model;
  final String severity;
  final double? anomalyScore;
  final double? threshold;
  final double? confidence;
  final List<String> contributors;
  final DateTime? detectedAt;

  AnomalyDetection({
    required this.id,
    required this.title,
    required this.description,
    required this.model,
    required this.severity,
    this.anomalyScore,
    this.threshold,
    this.confidence,
    this.contributors = const [],
    this.detectedAt,
  });

  factory AnomalyDetection.fromJson(Map<String, dynamic> json) {
    final score = (json['score'] as num?)?.toDouble() ??
        (json['anomaly_score'] as num?)?.toDouble();
    final timestampRaw =
        (json['computed_at'] as String?) ?? (json['detected_at'] as String?);
    final value = json['value'] as String?;
    final type = json['type'] as String?;
    final contributors =
        (json['contributors'] as List?)?.whereType<String>().toList() ??
            const <String>[];

    return AnomalyDetection(
      id: json['indicator_id'] as String? ?? json['id'] as String? ?? '',
      title: value ?? 'Anomalous Indicator',
      description: contributors.isNotEmpty
          ? 'Contributing features: ${contributors.join(', ')}'
          : (type != null
              ? 'Anomalous $type indicator flagged by the model'
              : 'Indicator flagged as anomalous by the model'),
      model: json['method'] as String? ?? json['model'] as String? ?? 'unknown',
      severity: json['severity'] as String? ?? 'unknown',
      anomalyScore: score,
      threshold: (json['threshold'] as num?)?.toDouble(),
      confidence: (json['confidence'] as num?)?.toDouble(),
      contributors: contributors,
      detectedAt: timestampRaw != null ? DateTime.tryParse(timestampRaw) : null,
    );
  }
}

/// Mirrors a GET /ml/insights entry emitted by the backend MLService:
/// {id, title, description, severity ("info"/"warning"/"high"/"critical"),
/// generated_at, data?}. Icon and color are derived from severity.
class MLInsight {
  final String id;
  final String title;
  final String description;
  final String severity;
  final DateTime? generatedAt;

  MLInsight({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    this.generatedAt,
  });

  factory MLInsight.fromJson(Map<String, dynamic> json) {
    final generatedRaw = json['generated_at'] as String?;
    return MLInsight(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Insight',
      description: json['description'] as String? ?? '',
      severity: json['severity'] as String? ?? 'info',
      generatedAt:
          generatedRaw != null ? DateTime.tryParse(generatedRaw) : null,
    );
  }

  Color get color {
    switch (severity.toLowerCase()) {
      case 'critical':
        return GlassTheme.errorColor;
      case 'high':
        return const Color(0xFFFF5722);
      case 'warning':
        return GlassTheme.warningColor;
      default:
        return const Color(0xFF2196F3);
    }
  }

  String get icon {
    switch (severity.toLowerCase()) {
      case 'critical':
      case 'high':
        return AppIcons.dangerTriangle;
      case 'warning':
        return AppIcons.graphUp;
      default:
        return AppIcons.chart;
    }
  }
}
