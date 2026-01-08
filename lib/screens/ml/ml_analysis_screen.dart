/// ML Analysis Screen
/// Machine learning anomaly detection and analysis interface

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_widgets.dart';

class MLAnalysisScreen extends StatefulWidget {
  const MLAnalysisScreen({super.key});

  @override
  State<MLAnalysisScreen> createState() => _MLAnalysisScreenState();
}

class _MLAnalysisScreenState extends State<MLAnalysisScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  bool _isAnalyzing = false;
  final List<MLModel> _models = [];
  final List<AnomalyDetection> _anomalies = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {
      _models.addAll(_getSampleModels());
      _anomalies.addAll(_getSampleAnomalies());
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(
        title: 'ML Analysis',
        actions: [
          IconButton(
            icon: DuotoneIcon(AppIcons.play, size: 24, color: Colors.white),
            onPressed: _isAnalyzing ? null : _runAnalysis,
          ),
          IconButton(
            icon: DuotoneIcon(AppIcons.refresh, size: 24, color: Colors.white),
            onPressed: _isLoading ? null : _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: GlassTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Models'),
            Tab(text: 'Anomalies'),
            Tab(text: 'Insights'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: GlassTheme.primaryAccent))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildModelsTab(),
                _buildAnomaliesTab(),
                _buildInsightsTab(),
              ],
            ),
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

          _buildInsightCard(
            icon: AppIcons.graphUp,
            title: 'Threat Trend Analysis',
            insight: 'Phishing attempts increased 23% this week compared to last week.',
            color: GlassTheme.errorColor,
          ),
          _buildInsightCard(
            icon: AppIcons.clock,
            title: 'Attack Pattern',
            insight: 'Most threats detected between 9 AM - 11 AM local time.',
            color: GlassTheme.warningColor,
          ),
          _buildInsightCard(
            icon: AppIcons.global,
            title: 'Geographic Analysis',
            insight: '45% of threat origins from Eastern European IP ranges.',
            color: GlassTheme.primaryAccent,
          ),
          _buildInsightCard(
            icon: AppIcons.shieldWarning,
            title: 'Vulnerability Prediction',
            insight: 'High probability of credential-based attacks in next 24 hours.',
            color: const Color(0xFF9C27B0),
          ),

          const SizedBox(height: 24),
          const Text('Model Performance', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          GlassCard(
            child: Column(
              children: [
                _buildPerformanceBar('URL Classifier', 0.94),
                _buildPerformanceBar('SMS Analyzer', 0.91),
                _buildPerformanceBar('Behavior Model', 0.87),
                _buildPerformanceBar('Anomaly Detector', 0.82),
              ],
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

  void _runAnalysis() {
    setState(() => _isAnalyzing = true);
    _tabController.animateTo(1);

    Future.delayed(const Duration(seconds: 3), () {
      setState(() {
        _isAnalyzing = false;
        _anomalies.insert(0, AnomalyDetection(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: 'Unusual Network Traffic',
          description: 'Detected abnormal data exfiltration pattern from device.',
          model: 'Behavior Model',
          severity: 'high',
          anomalyScore: 0.89,
          detectedAt: DateTime.now(),
        ));
      });
    });
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

  List<MLModel> _getSampleModels() {
    return [
      MLModel(name: 'URL Threat Classifier', type: 'Classifier', description: 'Classifies URLs as malicious, suspicious, or safe.', accuracy: 0.94, precision: 0.92, recall: 0.89),
      MLModel(name: 'SMS Phishing Detector', type: 'NLP', description: 'Detects smishing attempts using NLP analysis.', accuracy: 0.91, precision: 0.88, recall: 0.93),
      MLModel(name: 'Network Anomaly Detector', type: 'Anomaly Detection', description: 'Detects unusual network behavior patterns.', accuracy: 0.87, precision: 0.85, recall: 0.82),
      MLModel(name: 'App Behavior Analyzer', type: 'Behavior Analysis', description: 'Analyzes app behavior for malicious activity.', accuracy: 0.82, precision: 0.79, recall: 0.84),
    ];
  }

  List<AnomalyDetection> _getSampleAnomalies() {
    return [
      AnomalyDetection(
        id: '1',
        title: 'Unusual Login Pattern',
        description: 'Multiple failed login attempts detected from new location.',
        model: 'Behavior Model',
        severity: 'high',
        anomalyScore: 0.92,
        detectedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      AnomalyDetection(
        id: '2',
        title: 'Suspicious DNS Query',
        description: 'DNS query to known malicious domain detected.',
        model: 'Network Anomaly Detector',
        severity: 'critical',
        anomalyScore: 0.95,
        detectedAt: DateTime.now().subtract(const Duration(hours: 5)),
      ),
    ];
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
}
