/// Identity Protection Provider
/// State management for identity theft protection and monitoring

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/security/identity_theft_protection_service.dart';

class IdentityProtectionProvider extends ChangeNotifier {
  final IdentityTheftProtectionService _service =
      IdentityTheftProtectionService();

  // State
  List<MonitoredAsset> _monitoredAssets = [];
  List<IdentityAlert> _alerts = [];
  List<RecoveryCase> _recoveryCases = [];
  Map<CreditBureau, CreditScoreUpdate> _creditScores = {};
  Map<CreditBureau, CreditFreezeStatus> _freezeStatus = {};
  IdentityProtectionSummary? _summary;

  // Loading states
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isAddingAsset = false;

  // Error state
  String? _error;

  // Stream subscription
  StreamSubscription<IdentityAlert>? _alertSub;

  // Getters
  List<MonitoredAsset> get monitoredAssets => _monitoredAssets;
  List<IdentityAlert> get alerts => _alerts;
  List<RecoveryCase> get recoveryCases => _recoveryCases;
  Map<CreditBureau, CreditScoreUpdate> get creditScores => _creditScores;
  Map<CreditBureau, CreditFreezeStatus> get freezeStatus => _freezeStatus;
  IdentityProtectionSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  bool get isAddingAsset => _isAddingAsset;
  String? get error => _error;

  // Computed getters
  List<IdentityAlert> get activeAlerts =>
      _alerts.where((a) => !a.isResolved).toList();

  List<IdentityAlert> get criticalAlerts => _alerts
      .where((a) => !a.isResolved && a.severity == AlertSeverity.critical)
      .toList();

  int get protectionScore => _summary?.protectionScore ?? 0;

  String get protectionGrade => _summary?.protectionGrade ?? 'N/A';

  int get averageCreditScore {
    if (_creditScores.isEmpty) return 0;
    final total = _creditScores.values.fold<int>(0, (sum, s) => sum + s.score);
    return total ~/ _creditScores.length;
  }

  int get frozenBureausCount =>
      _freezeStatus.values.where((s) => s.isFrozen).length;

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Listen to alerts
      _alertSub = _service.alertStream.listen((alert) {
        _alerts.insert(0, alert);
        _updateSummary();
        notifyListeners();
      });

      // Load initial data
      _monitoredAssets = _service.getMonitoredAssets();
      _alerts = _service.getAlerts(includeResolved: true);
      _creditScores = _service.getCreditScores();
      _freezeStatus = _service.getFreezeStatus();
      _recoveryCases = _service.getRecoveryCases();
      _updateSummary();

      // Start monitoring
      _service.startMonitoring();
    } catch (e) {
      _error = 'Failed to initialize identity protection';
      debugPrint('Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add asset for monitoring
  Future<MonitoredAsset?> addMonitoredAsset({
    required AssetType type,
    required String value,
  }) async {
    _isAddingAsset = true;
    _error = null;
    notifyListeners();

    try {
      final asset = await _service.addMonitoredAsset(type: type, value: value);
      _monitoredAssets = _service.getMonitoredAssets();
      _updateSummary();
      notifyListeners();
      return asset;
    } catch (e) {
      _error = 'Failed to add asset';
      notifyListeners();
      return null;
    } finally {
      _isAddingAsset = false;
      notifyListeners();
    }
  }

  /// Remove asset from monitoring
  Future<void> removeMonitoredAsset(String assetId) async {
    try {
      await _service.removeMonitoredAsset(assetId);
      _monitoredAssets = _service.getMonitoredAssets();
      _updateSummary();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to remove asset';
      notifyListeners();
    }
  }

  /// Scan all assets
  Future<void> scanAllAssets() async {
    _isScanning = true;
    _error = null;
    notifyListeners();

    try {
      await _service.scanAllAssets();
      _alerts = _service.getAlerts(includeResolved: true);
      _updateSummary();
    } catch (e) {
      _error = 'Scan failed';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Acknowledge alert
  Future<void> acknowledgeAlert(String alertId) async {
    try {
      await _service.acknowledgeAlert(alertId);
      _alerts = _service.getAlerts(includeResolved: true);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to acknowledge alert';
      notifyListeners();
    }
  }

  /// Resolve alert
  Future<void> resolveAlert(String alertId) async {
    try {
      await _service.resolveAlert(alertId);
      _alerts = _service.getAlerts(includeResolved: true);
      _updateSummary();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to resolve alert';
      notifyListeners();
    }
  }

  /// Freeze credit at bureau
  Future<CreditFreezeStatus?> freezeCredit(CreditBureau bureau) async {
    try {
      final status = await _service.freezeCredit(bureau);
      _freezeStatus = _service.getFreezeStatus();
      _updateSummary();
      notifyListeners();
      return status;
    } catch (e) {
      _error = 'Failed to freeze credit';
      notifyListeners();
      return null;
    }
  }

  /// Unfreeze credit at bureau
  Future<CreditFreezeStatus?> unfreezeCredit(
    CreditBureau bureau, {
    Duration? temporaryDuration,
  }) async {
    try {
      final status = await _service.unfreezeCredit(
        bureau,
        temporaryDuration: temporaryDuration,
      );
      _freezeStatus = _service.getFreezeStatus();
      _updateSummary();
      notifyListeners();
      return status;
    } catch (e) {
      _error = 'Failed to unfreeze credit';
      notifyListeners();
      return null;
    }
  }

  /// Open recovery case
  Future<RecoveryCase?> openRecoveryCase({
    required String title,
    required double estimatedLoss,
    List<String> documentsRequired = const [],
  }) async {
    try {
      final recoveryCase = await _service.openRecoveryCase(
        title: title,
        estimatedLoss: estimatedLoss,
        documentsRequired: documentsRequired,
      );
      _recoveryCases = _service.getRecoveryCases();
      notifyListeners();
      return recoveryCase;
    } catch (e) {
      _error = 'Failed to open recovery case';
      notifyListeners();
      return null;
    }
  }

  /// Update summary
  void _updateSummary() {
    _summary = _service.getSummary();
  }

  /// Get severity color
  static int getSeverityColor(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.critical:
        return 0xFFB71C1C;
      case AlertSeverity.high:
        return 0xFFFF5722;
      case AlertSeverity.medium:
        return 0xFFFF9800;
      case AlertSeverity.low:
        return 0xFFFFEB3B;
      case AlertSeverity.info:
        return 0xFF2196F3;
    }
  }

  /// Get asset type icon
  static String getAssetTypeIcon(AssetType type) {
    switch (type) {
      case AssetType.ssn:
        return 'badge';
      case AssetType.creditCard:
        return 'credit_card';
      case AssetType.bankAccount:
        return 'account_balance';
      case AssetType.email:
        return 'email';
      case AssetType.phone:
        return 'phone';
      case AssetType.driversLicense:
        return 'directions_car';
      case AssetType.passport:
        return 'flight';
      case AssetType.address:
        return 'home';
      case AssetType.dateOfBirth:
        return 'cake';
      case AssetType.mothersMaidenName:
        return 'person';
      case AssetType.medicalId:
        return 'medical_services';
      case AssetType.other:
        return 'description';
    }
  }

  /// Get bureau color
  static int getBureauColor(CreditBureau bureau) {
    switch (bureau) {
      case CreditBureau.equifax:
        return 0xFFE31837;
      case CreditBureau.experian:
        return 0xFF0066CC;
      case CreditBureau.transunion:
        return 0xFF009FDA;
    }
  }

  /// Get credit score color
  static int getCreditScoreColor(int score) {
    if (score >= 800) return 0xFF4CAF50;
    if (score >= 740) return 0xFF8BC34A;
    if (score >= 670) return 0xFFFFEB3B;
    if (score >= 580) return 0xFFFF9800;
    return 0xFFFF5722;
  }

  /// Get monitoring status color
  static int getStatusColor(MonitoringStatus status) {
    switch (status) {
      case MonitoringStatus.active:
        return 0xFF4CAF50;
      case MonitoringStatus.paused:
        return 0xFFFF9800;
      case MonitoringStatus.inactive:
        return 0xFF9E9E9E;
      case MonitoringStatus.alertTriggered:
        return 0xFFFF5722;
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
