/// Threat Hunting Provider
/// State management for proactive threat detection and investigation

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/security/threat_hunting_service.dart';

class ThreatHuntingProvider extends ChangeNotifier {
  final ThreatHuntingService _service = ThreatHuntingService();

  // State
  List<ThreatHunt> _availableHunts = [];
  Map<String, HuntResult> _huntResults = {};
  List<InvestigationCase> _cases = [];
  Map<String, dynamic> _stats = {};

  // Current hunt state
  String? _activeHuntId;
  HuntProgress? _currentProgress;

  // Loading states
  bool _isLoading = false;
  bool _isHunting = false;

  // Error state
  String? _error;

  // Stream subscriptions
  StreamSubscription<HuntProgress>? _progressSub;
  StreamSubscription<HuntFinding>? _findingSub;
  StreamSubscription<InvestigationCase>? _caseSub;

  // Recent findings
  final List<HuntFinding> _recentFindings = [];

  // Getters
  List<ThreatHunt> get availableHunts => _availableHunts;
  Map<String, HuntResult> get huntResults => _huntResults;
  List<InvestigationCase> get cases => _cases;
  Map<String, dynamic> get stats => _stats;
  String? get activeHuntId => _activeHuntId;
  HuntProgress? get currentProgress => _currentProgress;
  bool get isLoading => _isLoading;
  bool get isHunting => _isHunting;
  String? get error => _error;
  List<HuntFinding> get recentFindings => _recentFindings;

  // Computed getters
  List<ThreatHunt> get criticalHunts =>
      _availableHunts.where((h) => h.priority == HuntPriority.critical).toList();

  List<ThreatHunt> get highPriorityHunts => _availableHunts
      .where((h) =>
          h.priority == HuntPriority.critical ||
          h.priority == HuntPriority.high)
      .toList();

  int get totalFindings => _huntResults.values
      .fold<int>(0, (sum, r) => sum + r.findings.length);

  int get criticalFindingsCount => _huntResults.values.fold<int>(
      0, (sum, r) => sum + r.findings.where((f) => f.severity >= 0.9).length);

  List<InvestigationCase> get openCases =>
      _cases.where((c) => c.status == CaseStatus.open).toList();

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.initialize();

      // Listen to hunt progress
      _progressSub = _service.onHuntProgress.listen((progress) {
        _currentProgress = progress;
        notifyListeners();
      });

      // Listen to findings
      _findingSub = _service.onFinding.listen((finding) {
        _recentFindings.insert(0, finding);
        if (_recentFindings.length > 50) {
          _recentFindings.removeLast();
        }
        notifyListeners();
      });

      // Listen to case updates
      _caseSub = _service.onCaseUpdate.listen((caseUpdate) {
        final index = _cases.indexWhere((c) => c.id == caseUpdate.id);
        if (index >= 0) {
          _cases[index] = caseUpdate;
        } else {
          _cases.add(caseUpdate);
        }
        notifyListeners();
      });

      _availableHunts = _service.getAvailableHunts();
      _cases = _service.getCases();
      _updateStats();
    } catch (e) {
      _error = 'Failed to initialize threat hunting';
      debugPrint('Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Execute a threat hunt
  Future<HuntResult?> executeHunt(String huntId) async {
    if (_isHunting) return null;

    _isHunting = true;
    _activeHuntId = huntId;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.executeHunt(huntId);
      _huntResults[huntId] = result;
      _updateStats();
      return result;
    } catch (e) {
      _error = 'Hunt failed: $e';
      return null;
    } finally {
      _isHunting = false;
      _activeHuntId = null;
      _currentProgress = null;
      notifyListeners();
    }
  }

  /// Execute all critical hunts
  Future<List<HuntResult>> executeAllCriticalHunts() async {
    if (_isHunting) return [];

    _isHunting = true;
    _error = null;
    notifyListeners();

    try {
      final results = await _service.executeAllCriticalHunts();
      for (final result in results) {
        _huntResults[result.huntId] = result;
      }
      _updateStats();
      return results;
    } catch (e) {
      _error = 'Critical hunts failed: $e';
      return [];
    } finally {
      _isHunting = false;
      _activeHuntId = null;
      _currentProgress = null;
      notifyListeners();
    }
  }

  /// Get hunt by ID
  ThreatHunt? getHunt(String huntId) {
    return _availableHunts.where((h) => h.id == huntId).firstOrNull;
  }

  /// Get hunt result
  HuntResult? getHuntResult(String huntId) {
    return _huntResults[huntId];
  }

  /// Create investigation case
  InvestigationCase? createCase(
    String title,
    String description,
    List<HuntFinding> findings, {
    CasePriority priority = CasePriority.medium,
  }) {
    try {
      final investigation = _service.createCase(
        title,
        description,
        findings,
        priority: priority,
      );
      _cases = _service.getCases();
      _updateStats();
      notifyListeners();
      return investigation;
    } catch (e) {
      _error = 'Failed to create case';
      notifyListeners();
      return null;
    }
  }

  /// Update stats
  void _updateStats() {
    _stats = _service.getStatistics();
  }

  /// Get hunt type color
  static int getHuntTypeColor(HuntType type) {
    switch (type) {
      case HuntType.iocSweep:
        return 0xFF2196F3;
      case HuntType.behaviorAnalysis:
        return 0xFF9C27B0;
      case HuntType.anomalyDetection:
        return 0xFFFF9800;
      case HuntType.attackPattern:
        return 0xFFE91E63;
      case HuntType.dataExfiltration:
        return 0xFFF44336;
      case HuntType.persistenceMechanism:
        return 0xFF795548;
      case HuntType.lateral:
        return 0xFF607D8B;
      case HuntType.privilegeEscalation:
        return 0xFFFF5722;
    }
  }

  /// Get priority color
  static int getPriorityColor(HuntPriority priority) {
    switch (priority) {
      case HuntPriority.critical:
        return 0xFFB71C1C;
      case HuntPriority.high:
        return 0xFFFF5722;
      case HuntPriority.medium:
        return 0xFFFF9800;
      case HuntPriority.low:
        return 0xFFFFEB3B;
    }
  }

  /// Get severity color
  static int getSeverityColor(double severity) {
    if (severity >= 0.9) return 0xFFB71C1C;
    if (severity >= 0.7) return 0xFFFF5722;
    if (severity >= 0.5) return 0xFFFF9800;
    if (severity >= 0.3) return 0xFFFFEB3B;
    return 0xFF2196F3;
  }

  /// Get case status color
  static int getCaseStatusColor(CaseStatus status) {
    switch (status) {
      case CaseStatus.open:
        return 0xFF2196F3;
      case CaseStatus.investigating:
        return 0xFFFF9800;
      case CaseStatus.pendingAction:
        return 0xFFFF5722;
      case CaseStatus.resolved:
        return 0xFF4CAF50;
      case CaseStatus.falsePositive:
        return 0xFF9E9E9E;
      case CaseStatus.closed:
        return 0xFF607D8B;
    }
  }

  /// Get finding type icon
  static String getFindingTypeIcon(FindingType type) {
    switch (type) {
      case FindingType.malwareIndicator:
        return 'bug_report';
      case FindingType.suspiciousApp:
        return 'apps';
      case FindingType.networkAnomaly:
        return 'wifi';
      case FindingType.dataExfiltration:
        return 'upload';
      case FindingType.persistenceMechanism:
        return 'repeat';
      case FindingType.privilegeAbuse:
        return 'admin_panel_settings';
      case FindingType.configurationRisk:
        return 'settings';
      case FindingType.vulnerableComponent:
        return 'warning';
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Dispose
  @override
  void dispose() {
    _progressSub?.cancel();
    _findingSub?.cancel();
    _caseSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
