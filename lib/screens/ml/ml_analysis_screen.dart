/// ML Analysis Screen
/// Machine learning anomaly detection and analysis interface
///
/// Wire format note: GET /ml/models returns the MLService stats object
/// (`models_loaded`, `models: [MLModelInfo]`, ...). Each MLModelInfo carries
/// `name`, `version`, `type`, `status` ("ready"/"not_trained"), `trained_at`,
/// `training_size`, optional `accuracy` (omitted when untrained) and
/// `feature_names`. There is currently no server endpoint for enabling or
/// disabling individual models, no stored anomaly history endpoint
/// (/ml/anomalies is an alias of the stats endpoint) and no insights endpoint
/// (/ml/insights is the same alias), so those sections render explicit
/// "unavailable" states instead of fabricated data.
library;

import 'package:flutter/material.dart';

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

  // The server does not yet expose stored anomaly history or insight feeds:
  // /ml/anomalies and /ml/insights are currently aliases of the ML stats
  // endpoint and never carry `anomalies`/`insights` arrays. These flags become
  // true only when the server actually returns entries, so the tabs can show
  // an honest "unavailable" state instead of pretending the system is clean.
  bool _anomalyHistoryAvailable = false;
  bool _insightsAvailable = false;

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
    bool anomaliesAvailable = false;
    try {
      final anomaliesData = await _apiClient.getAnomalies();
      anomalies = anomaliesData
          .map((json) => AnomalyDetection.fromJson(json))
          .toList();
      anomaliesAvailable = anomalies.isNotEmpty;
    } catch (e) {
      errors.add('anomalies: $e');
    }

    List<MLInsight> insights = [];
    bool insightsAvailable = false;
    try {
      final insightsData = await _apiClient.getMLInsights();
      insights = insightsData.map((json) => MLInsight.fromJson(json)).toList();
      insightsAvailable = insights.isNotEmpty;
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
      _anomalyHistoryAvailable = anomaliesAvailable;
      _insightsAvailable = insightsAvailable;
      _error = errors.isEmpty ? null : 'Failed to load ML data — ${errors.join('; ')}';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
        // Batch anomaly analysis (POST /ml/anomalies/detect) is not exposed
        // through the app's API layer yet; the only analysis call available to
        // the client analyzes a single raw value and cannot run a batch scan.
        // The control stays visible but disabled rather than firing a request
        // that the server is guaranteed to reject.
        Tooltip(
          message: 'Batch ML analysis is not available from the server yet',
          child: IconButton(
            icon: DuotoneIcon(AppIcons.play, size: 22, color: Colors.white.withAlpha(96)),
            onPressed: null,
            tooltip: 'Run Analysis (unavailable)',
          ),
        ),
        IconButton(
          icon: DuotoneIcon(AppIcons.refresh, size: 22, color: Colors.white),
          onPressed: _isLoading ? null : _loadData,
          tooltip: 'Refresh',
        ),
      ],
      tabs: [
        GlassTab(
          label: 'Models',
          iconPath: 'settings',
          content: _buildModelsTab(),
        ),
        GlassTab(
          label: 'Anomalies',
          iconPath: 'danger_triangle',
          content: _buildAnomaliesTab(),
        ),
        GlassTab(
          label: 'Insights',
          iconPath: 'chart',
          content: _buildInsightsTab(),
        ),
      ],
    );
  }

  Widget _buildModelsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[
          _buildErrorCard(_error!),
          const SizedBox(height: 16),
        ],

        // Stats
        Row(
          children: [
            _buildStatCard('Models', _models.length.toString(), GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Trained', _models.where((m) => m.isReady).length.toString(), GlassTheme.successColor),
          ],
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'Detection Models'),
        if (_models.isEmpty && _error == null)
          _buildEmptyState(
            icon: AppIcons.mlAnalysis,
            title: 'No Models Reported',
            subtitle: 'The server did not return any ML models',
          )
        else
          ..._models.map((model) => _buildModelCard(model)),
      ],
    );
  }

  Widget _buildErrorCard(String message) {
    return GlassCard(
      tintColor: GlassTheme.errorColor,
      child: Row(
        children: [
          const DuotoneIcon('danger_circle', color: GlassTheme.errorColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: Colors.white.withAlpha(204), fontSize: 12)),
          ),
          IconButton(
            icon: const DuotoneIcon('refresh', color: Colors.white, size: 20),
            onPressed: _loadData,
            tooltip: 'Retry',
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

  Widget _buildModelCard(MLModel model) {
    final accuracy = model.accuracy;
    final accuracyColor = accuracy == null
        ? Colors.white54
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
                color: model.isReady ? GlassTheme.primaryAccent : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(
                      model.version.isEmpty ? model.type : '${model.type} • v${model.version}',
                      style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11),
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
                'Accuracy',
                accuracy != null ? '${(accuracy * 100).toInt()}%' : 'n/a',
                accuracyColor,
              ),
              const SizedBox(width: 16),
              _buildModelMetric('Training Size', model.trainingSize.toString(), Colors.white54),
              const SizedBox(width: 16),
              _buildModelMetric('Features', model.featureNames.length.toString(), Colors.white54),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            model.trainedAt != null
                ? 'Last trained ${_formatTime(model.trainedAt!)}'
                : 'Never trained',
            style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildModelMetric(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(color: Colors.white.withAlpha(102), fontSize: 10)),
      ],
    );
  }

  Widget _buildAnomaliesTab() {
    if (!_anomalyHistoryAvailable) {
      return _buildEmptyState(
        icon: AppIcons.mlAnalysis,
        title: 'Anomaly History Unavailable',
        subtitle: 'The server does not provide stored anomaly detections yet',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ..._anomalies.map((anomaly) => _buildAnomalyCard(anomaly)),
      ],
    );
  }

  Widget _buildAnomalyCard(AnomalyDetection anomaly) {
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
                    Text(anomaly.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(anomaly.model, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11)),
                  ],
                ),
              ),
              GlassBadge(text: anomaly.severity.toUpperCase(), color: severityColor, fontSize: 10),
            ],
          ),
          const SizedBox(height: 12),
          Text(anomaly.description, style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildAnomalyStat(
                AppIcons.graphUp,
                anomaly.anomalyScore != null
                    ? 'Score: ${(anomaly.anomalyScore! * 100).toInt()}%'
                    : 'Score: n/a',
              ),
              const SizedBox(width: 16),
              _buildAnomalyStat(
                AppIcons.clock,
                anomaly.detectedAt != null ? _formatTime(anomaly.detectedAt!) : 'Time unknown',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnomalyStat(String icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DuotoneIcon(icon, size: 14, color: Colors.white.withAlpha(128)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
      ],
    );
  }

  Widget _buildInsightsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI Insights', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          if (!_insightsAvailable)
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'AI insights are not available from the server yet',
                    style: TextStyle(color: Colors.white.withAlpha(153)),
                  ),
                ),
              ),
            )
          else
            ..._insights.map((insight) => _buildInsightCard(
              icon: insight.icon,
              title: insight.title,
              insight: insight.insight,
              color: insight.color,
            )),

          const SizedBox(height: 24),
          const Text('Model Performance', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          GlassCard(
            child: Column(
              children: _models.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No model data available',
                          style: TextStyle(color: Colors.white.withAlpha(153)),
                        ),
                      ),
                    ]
                  : _models.map((model) => _buildPerformanceBar(model.name, model.accuracy)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightCard({
    required String icon,
    required String title,
    required String insight,
    required Color color,
  }) {
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
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(insight, style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceBar(String label, double? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13)),
              Text(
                value != null ? '${(value * 100).toInt()}%' : 'n/a',
                style: TextStyle(
                  color: value != null ? GlassTheme.primaryAccent : Colors.white54,
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
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(GlassTheme.primaryAccent),
              minHeight: 6,
            ),
          ),
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
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                  GlassSvgIconBox(icon: AppIcons.dangerTriangle, color: severityColor, size: 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(anomaly.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        GlassBadge(text: anomaly.severity.toUpperCase(), color: severityColor),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(anomaly.description, style: TextStyle(color: Colors.white.withAlpha(204))),
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
          Text(label, style: TextStyle(color: Colors.white.withAlpha(153))),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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

/// Stored anomaly detections are not served by the backend yet
/// (/ml/anomalies aliases the stats endpoint); this model parses entries
/// defensively if/when the server starts returning them. Absent fields stay
/// null and are rendered as "n/a" — never substituted with fake values.
class AnomalyDetection {
  final String id;
  final String title;
  final String description;
  final String model;
  final String severity;
  final double? anomalyScore;
  final DateTime? detectedAt;

  AnomalyDetection({
    required this.id,
    required this.title,
    required this.description,
    required this.model,
    required this.severity,
    this.anomalyScore,
    this.detectedAt,
  });

  factory AnomalyDetection.fromJson(Map<String, dynamic> json) {
    // Accept both a server-side AnomalyScore shape (score/method/computed_at,
    // see orbguard-lab models/ml.go) and a flattened history entry shape.
    final score = (json['anomaly_score'] as num?)?.toDouble() ??
        (json['score'] as num?)?.toDouble();
    final timestampRaw =
        (json['detected_at'] as String?) ?? (json['computed_at'] as String?);

    return AnomalyDetection(
      id: json['id'] as String? ?? json['indicator_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Anomaly Detected',
      description: json['description'] as String? ?? '',
      model: json['model'] as String? ?? json['method'] as String? ?? 'unknown',
      severity: json['severity'] as String? ?? 'unknown',
      anomalyScore: score,
      detectedAt: timestampRaw != null ? DateTime.tryParse(timestampRaw) : null,
    );
  }
}

class MLInsight {
  final String id;
  final String icon;
  final String title;
  final String insight;
  final String colorHex;

  MLInsight({
    required this.id,
    required this.icon,
    required this.title,
    required this.insight,
    required this.colorHex,
  });

  factory MLInsight.fromJson(Map<String, dynamic> json) {
    return MLInsight(
      id: json['id'] as String? ?? '',
      icon: json['icon'] as String? ?? 'chart_line',
      title: json['title'] as String? ?? 'Insight',
      insight: json['insight'] as String? ?? '',
      colorHex: json['color'] as String? ?? '#2196F3',
    );
  }

  Color get color {
    try {
      return Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF2196F3);
    }
  }
}
