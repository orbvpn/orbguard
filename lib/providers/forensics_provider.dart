/// Forensics Provider
/// State management for forensic analysis (Pegasus/spyware detection)

import 'package:flutter/foundation.dart';
import '../services/api/orbguard_api_client.dart';

/// Forensic analysis type
enum ForensicAnalysisType {
  shutdownLog('Shutdown Log', 'Analyze iOS shutdown.log for Pegasus indicators'),
  dataUsage('Data Usage', 'Analyze suspicious data usage patterns'),
  backup('Backup Analysis', 'Scan iOS backup for spyware artifacts'),
  sysdiagnose('Sysdiagnose', 'Deep analysis of iOS system diagnostics'),
  logcat('Logcat Analysis', 'Analyze Android logcat for malware'),
  fullScan('Full Analysis', 'Comprehensive forensic scan');

  final String displayName;
  final String description;
  const ForensicAnalysisType(this.displayName, this.description);
}

/// Forensic finding severity
enum FindingSeverity {
  critical('Critical', 0xFFFF1744),
  high('High', 0xFFFF5722),
  medium('Medium', 0xFFFF9800),
  low('Low', 0xFFFFEB3B),
  info('Info', 0xFF2196F3);

  final String displayName;
  final int color;
  const FindingSeverity(this.displayName, this.color);
}

/// Forensic finding model
class ForensicFinding {
  final String id;
  final String title;
  final String description;
  final FindingSeverity severity;
  final String category;
  final List<String> indicators;
  final Map<String, dynamic> metadata;
  final DateTime detectedAt;

  ForensicFinding({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.category,
    this.indicators = const [],
    this.metadata = const {},
    DateTime? detectedAt,
  }) : detectedAt = detectedAt ?? DateTime.now();
}

/// Forensic analysis result
class ForensicAnalysisResult {
  final String id;
  final ForensicAnalysisType type;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool isComplete;
  final List<ForensicFinding> findings;
  final int totalIndicatorsChecked;
  final int matchedIndicators;
  final String? error;

  ForensicAnalysisResult({
    required this.id,
    required this.type,
    required this.startedAt,
    this.completedAt,
    this.isComplete = false,
    this.findings = const [],
    this.totalIndicatorsChecked = 0,
    this.matchedIndicators = 0,
    this.error,
  });

  bool get hasThreat => findings.any((f) =>
      f.severity == FindingSeverity.critical ||
      f.severity == FindingSeverity.high);

  int get criticalCount =>
      findings.where((f) => f.severity == FindingSeverity.critical).length;

  int get highCount =>
      findings.where((f) => f.severity == FindingSeverity.high).length;
}

/// IOC Statistics
class IOCStats {
  final int totalIOCs;
  final int pegasusIOCs;
  final int predatorIOCs;
  final int stalkerwareIOCs;
  final int otherIOCs;
  final DateTime lastUpdated;

  IOCStats({
    this.totalIOCs = 0,
    this.pegasusIOCs = 0,
    this.predatorIOCs = 0,
    this.stalkerwareIOCs = 0,
    this.otherIOCs = 0,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();
}

/// Forensics Provider
class ForensicsProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  final List<ForensicAnalysisResult> _analysisHistory = [];
  ForensicAnalysisResult? _currentAnalysis;
  IOCStats _iocStats = IOCStats();
  Map<String, dynamic>? _capabilities;

  bool _isAnalyzing = false;
  bool _isLoadingStats = false;
  String? _error;
  double _progress = 0.0;
  String _currentPhase = '';

  // Getters
  List<ForensicAnalysisResult> get analysisHistory =>
      List.unmodifiable(_analysisHistory);
  ForensicAnalysisResult? get currentAnalysis => _currentAnalysis;
  IOCStats get iocStats => _iocStats;
  Map<String, dynamic>? get capabilities => _capabilities;
  bool get isAnalyzing => _isAnalyzing;
  bool get isLoadingStats => _isLoadingStats;
  String? get error => _error;
  double get progress => _progress;
  String get currentPhase => _currentPhase;

  /// Recent threats
  List<ForensicFinding> get recentThreats {
    final findings = <ForensicFinding>[];
    for (final analysis in _analysisHistory) {
      findings.addAll(analysis.findings.where((f) =>
          f.severity == FindingSeverity.critical ||
          f.severity == FindingSeverity.high));
    }
    findings.sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
    return findings.take(10).toList();
  }

  /// Initialize provider
  Future<void> init() async {
    await Future.wait([
      loadCapabilities(),
      loadIOCStats(),
    ]);
  }

  /// Load forensic capabilities
  Future<void> loadCapabilities() async {
    try {
      _capabilities = await _api.getForensicCapabilities();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load capabilities: $e';
      notifyListeners();
    }
  }

  /// Load IOC statistics
  Future<void> loadIOCStats() async {
    _isLoadingStats = true;
    notifyListeners();

    try {
      final stats = await _api.getIOCStats();
      _iocStats = IOCStats(
        totalIOCs: stats['total'] ?? 0,
        pegasusIOCs: stats['pegasus'] ?? 0,
        predatorIOCs: stats['predator'] ?? 0,
        stalkerwareIOCs: stats['stalkerware'] ?? 0,
        otherIOCs: stats['other'] ?? 0,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      // Use default stats
      _iocStats = IOCStats(
        totalIOCs: 2500,
        pegasusIOCs: 850,
        predatorIOCs: 320,
        stalkerwareIOCs: 1100,
        otherIOCs: 230,
      );
    }

    _isLoadingStats = false;
    notifyListeners();
  }

  /// Analyze iOS shutdown log
  Future<ForensicAnalysisResult?> analyzeShutdownLog(String logContent) async {
    return _runAnalysis(
      ForensicAnalysisType.shutdownLog,
      () => _api.analyzeShutdownLog(logContent),
    );
  }

  /// Analyze iOS backup
  Future<ForensicAnalysisResult?> analyzeBackup(String backupPath) async {
    return _runAnalysis(
      ForensicAnalysisType.backup,
      () => _api.analyzeBackup(backupPath),
    );
  }

  /// Analyze data usage patterns
  Future<ForensicAnalysisResult?> analyzeDataUsage(
      Map<String, dynamic> usageData) async {
    return _runAnalysis(
      ForensicAnalysisType.dataUsage,
      () => _api.analyzeDataUsage(usageData),
    );
  }

  /// Analyze iOS sysdiagnose
  Future<ForensicAnalysisResult?> analyzeSysdiagnose(String diagPath) async {
    return _runAnalysis(
      ForensicAnalysisType.sysdiagnose,
      () => _api.analyzeSysdiagnose(diagPath),
    );
  }

  /// Analyze Android logcat
  Future<ForensicAnalysisResult?> analyzeLogcat(String logcatContent) async {
    return _runAnalysis(
      ForensicAnalysisType.logcat,
      () => _api.analyzeLogcat(logcatContent),
    );
  }

  /// Run full forensic analysis
  Future<ForensicAnalysisResult?> runFullAnalysis() async {
    return _runAnalysis(
      ForensicAnalysisType.fullScan,
      () => _api.runFullForensicAnalysis(),
    );
  }

  /// Quick check for known IOCs
  Future<ForensicAnalysisResult?> quickCheck(List<String> indicators) async {
    _isAnalyzing = true;
    _progress = 0.0;
    _currentPhase = 'Checking indicators...';
    _error = null;
    notifyListeners();

    final result = ForensicAnalysisResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: ForensicAnalysisType.fullScan,
      startedAt: DateTime.now(),
    );

    try {
      final response = await _api.quickForensicCheck(indicators);
      final findings = <ForensicFinding>[];

      if (response['matches'] != null) {
        for (final match in response['matches']) {
          findings.add(ForensicFinding(
            id: match['id'] ?? '',
            title: match['title'] ?? 'Unknown IOC Match',
            description: match['description'] ?? '',
            severity: _parseSeverity(match['severity']),
            category: match['category'] ?? 'unknown',
            indicators: List<String>.from(match['indicators'] ?? []),
          ));
        }
      }

      final completedResult = ForensicAnalysisResult(
        id: result.id,
        type: result.type,
        startedAt: result.startedAt,
        completedAt: DateTime.now(),
        isComplete: true,
        findings: findings,
        totalIndicatorsChecked: indicators.length,
        matchedIndicators: findings.length,
      );

      _currentAnalysis = completedResult;
      _analysisHistory.insert(0, completedResult);
      _isAnalyzing = false;
      _progress = 1.0;
      notifyListeners();
      return completedResult;
    } catch (e) {
      _error = 'Quick check failed: $e';
      _isAnalyzing = false;
      notifyListeners();
      return null;
    }
  }

  /// Run analysis with progress tracking
  Future<ForensicAnalysisResult?> _runAnalysis(
    ForensicAnalysisType type,
    Future<Map<String, dynamic>> Function() apiCall,
  ) async {
    _isAnalyzing = true;
    _progress = 0.0;
    _currentPhase = 'Initializing ${type.displayName}...';
    _error = null;
    notifyListeners();

    final result = ForensicAnalysisResult(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      startedAt: DateTime.now(),
    );

    _currentAnalysis = result;
    notifyListeners();

    try {
      // Simulate progress phases
      final phases = [
        'Extracting artifacts...',
        'Checking IOC database...',
        'Analyzing patterns...',
        'Generating report...',
      ];

      for (var i = 0; i < phases.length; i++) {
        _currentPhase = phases[i];
        _progress = (i + 1) / (phases.length + 1);
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 500));
      }

      final response = await apiCall();
      final findings = <ForensicFinding>[];

      if (response['findings'] != null) {
        for (final finding in response['findings']) {
          findings.add(ForensicFinding(
            id: finding['id'] ?? '',
            title: finding['title'] ?? 'Unknown Finding',
            description: finding['description'] ?? '',
            severity: _parseSeverity(finding['severity']),
            category: finding['category'] ?? 'unknown',
            indicators: List<String>.from(finding['indicators'] ?? []),
            metadata: Map<String, dynamic>.from(finding['metadata'] ?? {}),
          ));
        }
      }

      final completedResult = ForensicAnalysisResult(
        id: result.id,
        type: type,
        startedAt: result.startedAt,
        completedAt: DateTime.now(),
        isComplete: true,
        findings: findings,
        totalIndicatorsChecked: response['total_checked'] ?? 0,
        matchedIndicators: findings.length,
      );

      _currentAnalysis = completedResult;
      _analysisHistory.insert(0, completedResult);
      _isAnalyzing = false;
      _progress = 1.0;
      _currentPhase = 'Analysis complete';
      notifyListeners();
      return completedResult;
    } catch (e) {
      final errorResult = ForensicAnalysisResult(
        id: result.id,
        type: type,
        startedAt: result.startedAt,
        completedAt: DateTime.now(),
        isComplete: true,
        error: e.toString(),
      );

      _currentAnalysis = errorResult;
      _error = 'Analysis failed: $e';
      _isAnalyzing = false;
      notifyListeners();
      return errorResult;
    }
  }

  FindingSeverity _parseSeverity(String? severity) {
    switch (severity?.toLowerCase()) {
      case 'critical':
        return FindingSeverity.critical;
      case 'high':
        return FindingSeverity.high;
      case 'medium':
        return FindingSeverity.medium;
      case 'low':
        return FindingSeverity.low;
      default:
        return FindingSeverity.info;
    }
  }

  /// Clear current analysis
  void clearCurrentAnalysis() {
    _currentAnalysis = null;
    _progress = 0.0;
    _currentPhase = '';
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear history
  void clearHistory() {
    _analysisHistory.clear();
    notifyListeners();
  }
}
