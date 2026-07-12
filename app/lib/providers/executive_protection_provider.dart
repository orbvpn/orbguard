/// Executive Protection Provider
/// State management for BEC and CEO fraud detection

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/security/executive_protection_service.dart';

class ExecutiveProtectionProvider extends ChangeNotifier {
  final ExecutiveProtectionService _service = ExecutiveProtectionService();

  // State
  List<ExecutiveProfile> _executives = [];
  List<ImpersonationResult> _alerts = [];
  Map<String, dynamic> _stats = {};

  // Loading states
  bool _isLoading = false;
  bool _isAnalyzing = false;

  // Error state
  String? _error;

  // Stream subscription
  StreamSubscription<ImpersonationResult>? _alertSub;

  // Getters
  List<ExecutiveProfile> get executives => _executives;
  List<ImpersonationResult> get alerts => _alerts;
  Map<String, dynamic> get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isAnalyzing => _isAnalyzing;
  String? get error => _error;

  // Computed getters
  List<ExecutiveProfile> get highValueExecutives =>
      _executives.where((e) => e.isHighValue).toList();

  List<ImpersonationResult> get criticalAlerts =>
      _alerts.where((a) => a.riskLevel == 'critical').toList();

  List<ImpersonationResult> get highRiskAlerts =>
      _alerts.where((a) => a.riskLevel == 'high' || a.riskLevel == 'critical').toList();

  int get totalAlertsCount => _alerts.length;

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.initialize();

      // Listen to alerts
      _alertSub = _service.onAlert.listen((result) {
        _alerts.insert(0, result);
        if (_alerts.length > 100) {
          _alerts.removeLast();
        }
        notifyListeners();
      });

      _executives = _service.executives;
      _updateStats();
    } catch (e) {
      _error = 'Failed to initialize executive protection';
      debugPrint('Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add executive profile
  void addExecutive(ExecutiveProfile executive) {
    _service.addExecutive(executive);
    _executives = _service.executives;
    _updateStats();
    notifyListeners();
  }

  /// Remove executive profile
  void removeExecutive(String id) {
    _service.removeExecutive(id);
    _executives = _service.executives;
    _updateStats();
    notifyListeners();
  }

  /// Add corporate domain
  void addCorporateDomain(String domain) {
    _service.addCorporateDomain(domain);
    _updateStats();
    notifyListeners();
  }

  /// Analyze message for impersonation
  Future<ImpersonationResult> analyzeMessage({
    required String senderName,
    required String senderEmail,
    required String subject,
    required String body,
    String? replyTo,
  }) async {
    _isAnalyzing = true;
    _error = null;
    notifyListeners();

    try {
      final request = MessageAnalysisRequest(
        senderName: senderName,
        senderEmail: senderEmail,
        subject: subject,
        body: body,
        timestamp: DateTime.now(),
        replyTo: replyTo,
      );

      final result = await _service.analyzeMessage(request);

      if (result.isImpersonation) {
        _alerts.insert(0, result);
      }

      return result;
    } catch (e) {
      _error = 'Analysis failed';
      rethrow;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  /// Import executives from directory
  Future<int> importFromDirectory(List<Map<String, dynamic>> directory) async {
    try {
      final count = await _service.importFromDirectory(directory);
      _executives = _service.executives;
      _updateStats();
      notifyListeners();
      return count;
    } catch (e) {
      _error = 'Import failed';
      notifyListeners();
      return 0;
    }
  }

  /// Clear alert
  void clearAlert(int index) {
    if (index >= 0 && index < _alerts.length) {
      _alerts.removeAt(index);
      notifyListeners();
    }
  }

  /// Clear all alerts
  void clearAllAlerts() {
    _alerts.clear();
    notifyListeners();
  }

  /// Update statistics
  void _updateStats() {
    _stats = _service.getStatistics();
  }

  /// Get risk level color
  static int getRiskLevelColor(String riskLevel) {
    switch (riskLevel.toLowerCase()) {
      case 'critical':
        return 0xFFB71C1C;
      case 'high':
        return 0xFFFF5722;
      case 'medium':
        return 0xFFFF9800;
      case 'low':
        return 0xFFFFEB3B;
      default:
        return 0xFF4CAF50;
    }
  }

  /// Get impersonation type icon
  static String getImpersonationTypeIcon(ImpersonationType? type) {
    if (type == null) return 'warning';
    switch (type) {
      case ImpersonationType.ceoFraud:
        return 'account_circle';
      case ImpersonationType.vendorFraud:
        return 'store';
      case ImpersonationType.attorneyFraud:
        return 'gavel';
      case ImpersonationType.dataTheft:
        return 'folder';
      case ImpersonationType.w2Scam:
        return 'description';
      case ImpersonationType.giftCardScam:
        return 'card_giftcard';
      case ImpersonationType.unknown:
        return 'help';
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
    _alertSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
