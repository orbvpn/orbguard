// Forensics Provider
// State management for forensic analysis (Pegasus/spyware detection)
//
// Request/response shapes mirror the live backend handlers in
// orbguard.lab/internal/api/handlers/forensics.go and the
// ForensicResult / QuickCheckResult models.

import '../utils/platform_info.dart';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/api/orbguard_api_client.dart';

/// Forensic analysis type
enum ForensicAnalysisType {
  shutdownLog('Shutdown Log', 'Analyze iOS shutdown.log for Pegasus indicators'),
  backup('Backup Analysis', 'Scan iOS backup for spyware artifacts'),
  sysdiagnose('Sysdiagnose', 'Deep analysis of iOS system diagnostics'),
  logcat('Logcat Analysis', 'Analyze Android logcat for malware'),
  bugreport('Bugreport Analysis', 'Analyze Android bugreport for malware'),
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
///
/// Built from a backend `Anomaly` (anomalies[]) or `DetectedThreat`
/// (detected_threats[]) entry of a ForensicResult response.
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

/// Detected threat (backend `detected_threats[]` entry).
/// e.g. Pegasus, Predator, stalkerware infections identified server-side.
class DetectedThreat {
  final String type; // pegasus, predator, stalkerware, ...
  final String name;
  final double confidence; // 0.0 - 1.0
  final FindingSeverity severity;
  final String description;
  final String attribution;
  final List<String> mitreTechniques;
  final List<String> remediation;

  DetectedThreat({
    required this.type,
    required this.name,
    required this.confidence,
    required this.severity,
    required this.description,
    this.attribution = '',
    this.mitreTechniques = const [],
    this.remediation = const [],
  });
}

/// Forensic analysis result
class ForensicAnalysisResult {
  final String id;
  final ForensicAnalysisType type;
  final DateTime startedAt;
  final DateTime? completedAt;
  final bool isComplete;
  final List<ForensicFinding> findings;
  final List<DetectedThreat> detectedThreats;

  /// Backend-computed infection likelihood (0.0 - 1.0).
  final double infectionLikelihood;
  final List<String> recommendations;
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
    this.detectedThreats = const [],
    this.infectionLikelihood = 0.0,
    this.recommendations = const [],
    this.totalIndicatorsChecked = 0,
    this.matchedIndicators = 0,
    this.error,
  });

  /// A threat is present when the backend explicitly detected one
  /// (detected_threats), reported high infection likelihood, or any
  /// critical/high severity finding exists. A backend-detected Pegasus
  /// infection must never render as "No Threats Found".
  bool get hasThreat =>
      detectedThreats.isNotEmpty ||
      infectionLikelihood >= 0.5 ||
      findings.any((f) =>
          f.severity == FindingSeverity.critical ||
          f.severity == FindingSeverity.high);

  int get criticalCount =>
      findings.where((f) => f.severity == FindingSeverity.critical).length;

  int get highCount =>
      findings.where((f) => f.severity == FindingSeverity.high).length;
}

/// IOC Statistics — mirrors GET /api/v1/forensics/iocs/stats which returns
/// {domains, ips, hashes, path_patterns, process_patterns, total}.
class IOCStats {
  final int totalIOCs;
  final int domains;
  final int ips;
  final int hashes;
  final int pathPatterns;
  final int processPatterns;

  // The backend does not break IOCs down by campaign (Pegasus/Predator/...).
  // These remain for UI compatibility and are always 0 until the backend
  // exposes a per-campaign breakdown.
  final int pegasusIOCs;
  final int predatorIOCs;
  final int stalkerwareIOCs;
  final int otherIOCs;
  final DateTime lastUpdated;

  IOCStats({
    this.totalIOCs = 0,
    this.domains = 0,
    this.ips = 0,
    this.hashes = 0,
    this.pathPatterns = 0,
    this.processPatterns = 0,
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

  /// Native system-metrics channel (Android: SystemMetricsHandler.kt).
  static const MethodChannel _systemChannel =
      MethodChannel('com.orb.guard/system');

  // State
  final List<ForensicAnalysisResult> _analysisHistory = [];
  ForensicAnalysisResult? _currentAnalysis;
  IOCStats _iocStats = IOCStats();
  bool _iocStatsLoaded = false;
  Map<String, dynamic>? _capabilities;
  String? _cachedDeviceId;

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

  /// True once IOC stats have been successfully fetched from the backend.
  bool get iocStatsLoaded => _iocStatsLoaded;
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

  /// Load IOC statistics.
  ///
  /// Parses the live backend shape from GET /forensics/iocs/stats:
  /// {domains, ips, hashes, path_patterns, process_patterns, total}.
  /// On failure the error is surfaced — no fabricated statistics.
  Future<void> loadIOCStats() async {
    _isLoadingStats = true;
    notifyListeners();

    try {
      final stats = await _api.getIOCStats();
      if (stats['total'] == null) {
        throw const FormatException(
            'Unexpected IOC stats response: missing "total"');
      }
      _iocStats = IOCStats(
        totalIOCs: (stats['total'] as num).toInt(),
        domains: (stats['domains'] as num?)?.toInt() ?? 0,
        ips: (stats['ips'] as num?)?.toInt() ?? 0,
        hashes: (stats['hashes'] as num?)?.toInt() ?? 0,
        pathPatterns: (stats['path_patterns'] as num?)?.toInt() ?? 0,
        processPatterns: (stats['process_patterns'] as num?)?.toInt() ?? 0,
        lastUpdated: DateTime.now(),
      );
      _iocStatsLoaded = true;
      _error = null;
    } catch (e) {
      _iocStatsLoaded = false;
      _error = 'Failed to load IOC statistics: $e';
    }

    _isLoadingStats = false;
    notifyListeners();
  }

  /// Analyze iOS shutdown log.
  /// Backend: POST /forensics/analyze/shutdown-log {device_id, log_data}
  Future<ForensicAnalysisResult?> analyzeShutdownLog(String logContent) async {
    return _runAnalysis(
      ForensicAnalysisType.shutdownLog,
      () async => _api.analyzeShutdownLog({
        'device_id': await _deviceId(),
        'log_data': logContent,
      }),
    );
  }

  /// Upload an iOS backup archive (.zip of the backup directory) and run the
  /// server-side backup analyzer on it.
  /// Backend: POST /forensics/ios/backup/upload (multipart: file + device_id).
  /// The legacy path-based /forensics/analyze/backup endpoint is service-only
  /// (403 for app callers) because device-local paths do not exist on the
  /// server — uploads are the only honest client flow.
  Future<ForensicAnalysisResult?> uploadIosBackup(String filePath) async {
    return _runAnalysis(
      ForensicAnalysisType.backup,
      () async => _api.uploadIosBackup(
        filePath,
        deviceId: await _deviceId(),
        onSendProgress: _onUploadProgress,
      ),
    );
  }

  /// Upload an iOS sysdiagnose archive (.tar.gz/.tgz/.zip) and run the
  /// server-side sysdiagnose analyzer on it.
  /// Backend: POST /forensics/ios/sysdiagnose/upload (multipart: file + device_id).
  Future<ForensicAnalysisResult?> uploadSysdiagnose(String filePath) async {
    return _runAnalysis(
      ForensicAnalysisType.sysdiagnose,
      () async => _api.uploadSysdiagnose(
        filePath,
        deviceId: await _deviceId(),
        onSendProgress: _onUploadProgress,
      ),
    );
  }

  /// Upload an Android bugreport (.zip archive or raw .txt) and run the
  /// server-side bugreport/logcat analyzer on it.
  /// Backend: POST /forensics/android/bugreport/upload (multipart: file + device_id).
  Future<ForensicAnalysisResult?> uploadAndroidBugreport(String filePath) async {
    return _runAnalysis(
      ForensicAnalysisType.bugreport,
      () async => _api.uploadAndroidBugreport(
        filePath,
        deviceId: await _deviceId(),
        onSendProgress: _onUploadProgress,
      ),
    );
  }

  /// Real upload progress from dio's onSendProgress. Upload occupies the
  /// 0–90% band of the progress bar; the final 10% is server-side analysis.
  void _onUploadProgress(int sent, int total) {
    if (total <= 0) return;
    final fraction = sent / total;
    final newProgress = (fraction * 0.9).clamp(0.0, 0.9);
    // Throttle: only notify on >=1% movement or completion.
    if ((newProgress - _progress).abs() < 0.01 && sent != total) return;
    _progress = newProgress;
    _currentPhase = sent >= total
        ? 'Upload complete — analyzing on server...'
        : 'Uploading... ${(fraction * 100).toStringAsFixed(0)}%';
    notifyListeners();
  }

  /// Analyze Android logcat.
  /// Backend: POST /forensics/analyze/logcat {device_id, log_data}
  Future<ForensicAnalysisResult?> analyzeLogcat(String logcatContent) async {
    return _runAnalysis(
      ForensicAnalysisType.logcat,
      () async => _api.analyzeLogcat({
        'device_id': await _deviceId(),
        'log_data': logcatContent,
      }),
    );
  }

  /// Capture device logs via the native system channel and run the logcat
  /// analyzer on them — no manual log export needed.
  ///
  /// Native: com.orb.guard/system captureLogs {lines: 500} returning
  /// {logs, line_count, pid, scope, note}. The capture is scoped to
  /// OrbGuard's own process (full-device logs require the privileged
  /// READ_LOGS permission, which is system/ADB only).
  Future<ForensicAnalysisResult?> captureAndAnalyzeLogcat({
    int lines = 500,
  }) async {
    if (!PlatformInfo.isAndroid) {
      _error = 'Logcat capture is only available on Android';
      notifyListeners();
      return null;
    }

    try {
      final captured = await _systemChannel
          .invokeMapMethod<String, dynamic>('captureLogs', {'lines': lines});
      final logs = captured?['logs'] as String?;
      if (logs == null || logs.trim().isEmpty) {
        _error = 'Log capture returned no log lines';
        notifyListeners();
        return null;
      }
      return analyzeLogcat(logs);
    } on PlatformException catch (e) {
      _error = 'Log capture failed: ${e.message ?? e.code}';
      notifyListeners();
      return null;
    } on MissingPluginException {
      _error = 'Log capture is not supported on this platform build';
      notifyListeners();
      return null;
    }
  }

  /// Run full forensic analysis.
  /// Backend: POST /forensics/full-analysis
  /// {device_id, platform, include_timeline, ...optional in-band artifacts}.
  /// Server-side path fields (backup_path, data_usage_path, sysdiagnose_path)
  /// are service-only on the backend and are intentionally not sent here —
  /// archive artifacts go through the dedicated upload endpoints instead.
  Future<ForensicAnalysisResult?> runFullAnalysis({
    String? shutdownLog,
    String? logcatData,
  }) async {
    return _runAnalysis(
      ForensicAnalysisType.fullScan,
      () async => _api.runFullForensicAnalysis({
        'device_id': await _deviceId(),
        'platform': _platformName(),
        'include_timeline': true,
        if (shutdownLog != null && shutdownLog.isNotEmpty)
          'shutdown_log': shutdownLog,
        if (logcatData != null && logcatData.isNotEmpty)
          'logcat_data': logcatData,
      }),
    );
  }

  /// Quick check for known IOCs in raw log data.
  ///
  /// Backend: POST /forensics/quick-check {platform, log_data} returning
  /// {platform, checked_at, is_suspicious, indicators_found,
  ///  recommend_full_scan, indicators: [{type, value, confidence, description}]}.
  Future<ForensicAnalysisResult?> quickCheck({
    String? platform,
    required String logData,
  }) async {
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
      final response = await _api.quickForensicCheck({
        'platform': platform ?? _platformName(),
        'log_data': logData,
      });

      if (response['indicators_found'] == null &&
          response['is_suspicious'] == null) {
        throw const FormatException(
            'Unexpected quick-check response: missing "indicators_found"');
      }

      final findings = <ForensicFinding>[];
      final indicators = response['indicators'];
      if (indicators is List) {
        for (final raw in indicators) {
          if (raw is! Map) continue;
          final indicator = Map<String, dynamic>.from(raw);
          final confidence =
              (indicator['confidence'] as num?)?.toDouble() ?? 0.0;
          findings.add(ForensicFinding(
            id: '${indicator['type'] ?? 'indicator'}-${indicator['value'] ?? findings.length}',
            title: (indicator['description'] as String?) ??
                'Suspicious indicator',
            description:
                'Matched ${indicator['type'] ?? 'indicator'}: ${indicator['value'] ?? ''}',
            severity: confidence >= 0.8
                ? FindingSeverity.high
                : FindingSeverity.medium,
            category: (indicator['type'] as String?) ?? 'indicator',
            indicators: [
              if (indicator['value'] is String) indicator['value'] as String,
            ],
            metadata: {'confidence': confidence},
          ));
        }
      }

      final isSuspicious = response['is_suspicious'] == true;
      final completedResult = ForensicAnalysisResult(
        id: result.id,
        type: result.type,
        startedAt: result.startedAt,
        completedAt: DateTime.now(),
        isComplete: true,
        findings: findings,
        infectionLikelihood: isSuspicious ? 0.5 : 0.0,
        recommendations: [
          if (response['recommend_full_scan'] == true)
            'Suspicious indicators found — run a full forensic analysis.',
        ],
        totalIndicatorsChecked:
            (response['indicators_found'] as num?)?.toInt() ?? findings.length,
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

  /// Run analysis and parse the backend ForensicResult response:
  /// {id, device_id, platform, scan_type, started_at, completed_at,
  ///  total_anomalies, critical_count, high_count, medium_count, low_count,
  ///  anomalies[], infection_likelihood, detected_threats[], recommendations[]}
  Future<ForensicAnalysisResult?> _runAnalysis(
    ForensicAnalysisType type,
    Future<Map<String, dynamic>> Function() apiCall,
  ) async {
    _isAnalyzing = true;
    _progress = 0.0;
    _currentPhase = 'Running ${type.displayName}...';
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
      final response = await apiCall();

      if (response['anomalies'] == null &&
          response['total_anomalies'] == null) {
        throw const FormatException(
            'Unexpected forensic analysis response: missing "anomalies"');
      }

      final findings = <ForensicFinding>[];

      // Anomalies detected by the backend analyzers.
      final anomalies = response['anomalies'];
      if (anomalies is List) {
        for (final raw in anomalies) {
          if (raw is! Map) continue;
          final anomaly = Map<String, dynamic>.from(raw);
          final indicators = <String>[];
          final iocMatch = anomaly['ioc_match'];
          if (iocMatch is Map && iocMatch['value'] is String) {
            indicators.add(iocMatch['value'] as String);
          }
          final mitre = anomaly['mitre_techniques'];
          if (mitre is List) {
            indicators.addAll(mitre.whereType<String>());
          }
          findings.add(ForensicFinding(
            id: (anomaly['id'] as String?) ?? '',
            title: (anomaly['title'] as String?) ?? 'Unknown Finding',
            description: (anomaly['description'] as String?) ?? '',
            severity: _parseSeverity(anomaly['severity'] as String?),
            category: (anomaly['type'] as String?) ?? 'unknown',
            indicators: indicators,
            metadata: {
              if (anomaly['confidence'] != null)
                'confidence': anomaly['confidence'],
              if (anomaly['path'] != null) 'path': anomaly['path'],
              if (anomaly['process_name'] != null)
                'process_name': anomaly['process_name'],
              if (anomaly['evidence'] is Map)
                ...Map<String, dynamic>.from(anomaly['evidence'] as Map),
            },
            detectedAt: DateTime.tryParse(
                (anomaly['timestamp'] as String?) ?? ''),
          ));
        }
      }

      // Threats explicitly identified by the backend (Pegasus, Predator...).
      final detectedThreats = <DetectedThreat>[];
      final threats = response['detected_threats'];
      if (threats is List) {
        for (final raw in threats) {
          if (raw is! Map) continue;
          final threat = Map<String, dynamic>.from(raw);
          final severity = _parseSeverity(threat['severity'] as String?);
          final mitre = (threat['mitre_techniques'] is List)
              ? List<String>.from(
                  (threat['mitre_techniques'] as List).whereType<String>())
              : const <String>[];
          final remediation = (threat['remediation'] is List)
              ? List<String>.from(
                  (threat['remediation'] as List).whereType<String>())
              : const <String>[];
          detectedThreats.add(DetectedThreat(
            type: (threat['type'] as String?) ?? 'unknown',
            name: (threat['name'] as String?) ?? 'Unknown Threat',
            confidence: (threat['confidence'] as num?)?.toDouble() ?? 0.0,
            severity: severity,
            description: (threat['description'] as String?) ?? '',
            attribution: (threat['attribution'] as String?) ?? '',
            mitreTechniques: mitre,
            remediation: remediation,
          ));
          // Surface the threat as a finding too, so detected infections are
          // always visible in finding-based UI.
          findings.add(ForensicFinding(
            id: 'threat-${threat['type'] ?? detectedThreats.length}',
            title: (threat['name'] as String?) ?? 'Detected Threat',
            description: (threat['description'] as String?) ?? '',
            severity: severity,
            category: (threat['type'] as String?) ?? 'threat',
            indicators: mitre,
            metadata: {
              'confidence': threat['confidence'],
              if (threat['attribution'] != null)
                'attribution': threat['attribution'],
              if (remediation.isNotEmpty) 'remediation': remediation,
            },
          ));
        }
      }

      final recommendations = (response['recommendations'] is List)
          ? List<String>.from(
              (response['recommendations'] as List).whereType<String>())
          : const <String>[];

      final completedResult = ForensicAnalysisResult(
        id: (response['id'] as String?) ?? result.id,
        type: type,
        startedAt:
            DateTime.tryParse((response['started_at'] as String?) ?? '') ??
                result.startedAt,
        completedAt:
            DateTime.tryParse((response['completed_at'] as String?) ?? '') ??
                DateTime.now(),
        isComplete: true,
        findings: findings,
        detectedThreats: detectedThreats,
        infectionLikelihood:
            (response['infection_likelihood'] as num?)?.toDouble() ?? 0.0,
        recommendations: recommendations,
        totalIndicatorsChecked:
            (response['total_anomalies'] as num?)?.toInt() ?? findings.length,
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

  /// Stable device identifier matching what device registration sends.
  Future<String> _deviceId() async {
    final cached = _cachedDeviceId;
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (PlatformInfo.isAndroid) {
        final info = await deviceInfo.androidInfo;
        _cachedDeviceId = info.id;
      } else if (PlatformInfo.isIOS) {
        final info = await deviceInfo.iosInfo;
        _cachedDeviceId = info.identifierForVendor ?? '';
      } else {
        _cachedDeviceId = '';
      }
    } catch (_) {
      _cachedDeviceId = '';
    }
    return _cachedDeviceId ?? '';
  }

  String _platformName() {
    if (PlatformInfo.isIOS) return 'ios';
    if (PlatformInfo.isAndroid) return 'android';
    return PlatformInfo.operatingSystem;
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
