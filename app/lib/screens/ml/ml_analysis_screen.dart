/// ML Analysis Screen
/// Machine learning anomaly detection and analysis interface

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
  bool _isAnalyzing = false;
  String? _error;
  final List<MLModel> _models = [];
  final List<AnomalyDetection> _anomalies = [];
  final List<MLInsight> _insights = [];

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

    try {
      // Load ML models, anomalies, and insights from API
      final results = await Future.wait([
        _apiClient.getMLModels(),
        _apiClient.getAnomalies(),
        _apiClient.getMLInsights(),
      ]);

      final modelsData = results[0];
      final anomaliesData = results[1];
      final insightsData = results[2];

      setState(() {
        _models.clear();
        _models.addAll(modelsData.map((json) => MLModel.fromJson(json)));

        _anomalies.clear();
        _anomalies.addAll(anomaliesData.map((json) => AnomalyDetection.fromJson(json)));

        _insights.clear();
        _insights.addAll(insightsData.map((json) => MLInsight.fromJson(json)));

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load ML data: $e';
        _isLoading = false;
      });
    }
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
        IconButton(
          icon: DuotoneIcon(AppIcons.play, size: 22, color: Colors.white),
          onPressed: _isAnalyzing ? null : _runAnalysis,
          tooltip: 'Run Analysis',
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
        // Stats
        Row(
          children: [
            _buildStatCard('Models', _models.length.toString(), GlassTheme.primaryAccent),
            const SizedBox(width: 12),
            _buildStatCard('Active', _models.where((m) => m.isEnabled).length.toString(), GlassTheme.successColor),
          ],
        ),
        const SizedBox(height: 24),

        const GlassSectionHeader(title: 'Detection Models'),
        ..._models.map((model) => _buildModelCard(model)),
      ],
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
    final accuracyColor = model.accuracy >= 0.9
        ? GlassTheme.successColor
        : model.accuracy >= 0.7
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
                color: model.isEnabled ? GlassTheme.primaryAccent : Colors.grey,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(model.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    Text(model.type, style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 11)),
                  ],
                ),
              ),
              Switch(
                value: model.isEnabled,
                onChanged: (v) => setState(() => model.isEnabled = v),
                activeColor: GlassTheme.successColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildModelMetric('Accuracy', '${(model.accuracy * 100).toInt()}%', accuracyColor),
              const SizedBox(width: 16),
              _buildModelMetric('Precision', '${(model.precision * 100).toInt()}%', Colors.white54),
              const SizedBox(width: 16),
              _buildModelMetric('Recall', '${(model.recall * 100).toInt()}%', Colors.white54),
            ],
          ),
          const SizedBox(height: 8),
          Text(model.description, style: TextStyle(color: Colors.white.withAlpha(153), fontSize: 12)),
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
    if (_anomalies.isEmpty) {
      return _buildEmptyState(
        icon: AppIcons.mlAnalysis,
        title: 'No Anomalies',
        subtitle: 'Run analysis to detect anomalies',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_isAnalyzing)
          GlassCard(
            tintColor: GlassTheme.primaryAccent,
            child: Row(
              children: [
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: GlassTheme.primaryAccent)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Analyzing patterns...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                      Text('Running ML models', style: TextStyle(color: Colors.white.withAlpha(128), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
              _buildAnomalyStat(AppIcons.graphUp, 'Score: ${(anomaly.anomalyScore * 100).toInt()}%'),
              const SizedBox(width: 16),
              _buildAnomalyStat(AppIcons.clock, _formatTime(anomaly.detectedAt)),
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

          if (_insights.isEmpty)
            GlassCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No insights available yet',
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

  Widget _buildPerformanceBar(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(color: Colors.white.withAlpha(179), fontSize: 13)),
              Text('${(value * 100).toInt()}%', style: const TextStyle(color: GlassTheme.primaryAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: value,
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
          Text(subtitle, style: TextStyle(color: Colors.white.withAlpha(153))),
        ],
      ),
    );
  }

  Future<void> _runAnalysis() async {
    setState(() => _isAnalyzing = true);
    _tabPageKey.currentState?.animateToTab(1);

    try {
      // Run ML analysis via API
      final result = await _apiClient.runMLAnalysis();

      setState(() {
        _isAnalyzing = false;
        // Add any new anomalies detected
        if (result['anomalies'] != null) {
          final newAnomalies = (result['anomalies'] as List)
              .map((json) => AnomalyDetection.fromJson(json as Map<String, dynamic>))
              .toList();
          for (final anomaly in newAnomalies) {
            if (!_anomalies.any((a) => a.id == anomaly.id)) {
              _anomalies.insert(0, anomaly);
            }
          }
        }
      });
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Analysis failed: $e'), backgroundColor: GlassTheme.errorColor),
        );
      }
    }
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
                    _buildDetailRow('Anomaly Score', '${(anomaly.anomalyScore * 100).toInt()}%'),
                    _buildDetailRow('Detected', _formatTime(anomaly.detectedAt)),
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
      case 'classifier':
        return AppIcons.filter;
      case 'anomaly detection':
        return AppIcons.dangerTriangle;
      case 'nlp':
        return AppIcons.fileText;
      case 'behavior analysis':
        return AppIcons.mlAnalysis;
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

class MLModel {
  final String name;
  final String type;
  final String description;
  final double accuracy;
  final double precision;
  final double recall;
  bool isEnabled;

  MLModel({
    required this.name,
    required this.type,
    required this.description,
    required this.accuracy,
    required this.precision,
    required this.recall,
    this.isEnabled = true,
  });

  factory MLModel.fromJson(Map<String, dynamic> json) {
    return MLModel(
      name: json['name'] as String? ?? 'Unknown Model',
      type: json['type'] as String? ?? 'Unknown',
      description: json['description'] as String? ?? '',
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0.0,
      precision: (json['precision'] as num?)?.toDouble() ?? 0.0,
      recall: (json['recall'] as num?)?.toDouble() ?? 0.0,
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }
}

class AnomalyDetection {
  final String id;
  final String title;
  final String description;
  final String model;
  final String severity;
  final double anomalyScore;
  final DateTime detectedAt;

  AnomalyDetection({
    required this.id,
    required this.title,
    required this.description,
    required this.model,
    required this.severity,
    required this.anomalyScore,
    required this.detectedAt,
  });

  factory AnomalyDetection.fromJson(Map<String, dynamic> json) {
    return AnomalyDetection(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Anomaly Detected',
      description: json['description'] as String? ?? '',
      model: json['model'] as String? ?? 'Unknown',
      severity: json['severity'] as String? ?? 'medium',
      anomalyScore: (json['anomaly_score'] as num?)?.toDouble() ?? 0.0,
      detectedAt: json['detected_at'] != null
          ? DateTime.parse(json['detected_at'] as String)
          : DateTime.now(),
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
