// Identity Protection Provider
// State management for identity theft protection and monitoring.
//
// Honesty notes:
// - Email assets are scanned against live backend services (dark-web
//   breach corpus + digital footprint scanner). Other asset types have no
//   live data source and surface an explicit "Unavailable" status.
// - Credit freeze state is self-reported by the user after they act on
//   the bureau's official freeze page; OrbGuard never claims to have
//   frozen credit itself.

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
  Map<CreditBureau, CreditFreezeStatus> get freezeStatus => _freezeStatus;
  IdentityProtectionSummary? get summary => _summary;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  bool get isAddingAsset => _isAddingAsset;
  String? get error => _error;

  /// Per-asset failures from the most recent scan (asset id -> message).
  Map<String, String> get lastScanErrors => _service.lastScanErrors;

  // Computed getters
  List<IdentityAlert> get activeAlerts =>
      _alerts.where((a) => !a.isResolved).toList();

  List<IdentityAlert> get criticalAlerts => _alerts
      .where((a) => !a.isResolved && a.severity == AlertSeverity.critical)
      .toList();

  /// Assets stored locally but with no live monitoring source.
  List<MonitoredAsset> get unmonitorableAssets => _monitoredAssets
      .where((a) => a.status == MonitoringStatus.unavailable)
      .toList();

  int get protectionScore => _summary?.protectionScore ?? 0;

  String get protectionGrade => _summary?.protectionGrade ?? 'N/A';

  /// Number of bureaus the user has declared frozen (self-reported, not
  /// verified by OrbGuard).
  int get frozenBureausCount =>
      _freezeStatus.values.where((s) => s.isFrozen).length;

  /// The bureau's official self-service freeze page.
  String officialFreezeUrl(CreditBureau bureau) => bureau.officialFreezeUrl;

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Listen to alerts
      _alertSub = _service.alertStream.listen((alert) {
        if (!_alerts.any((a) => a.id == alert.id)) {
          _alerts.insert(0, alert);
        }
        _updateSummary();
        notifyListeners();
      });

      // Load persisted state, then expose it.
      await _service.initialize();
      _monitoredAssets = _service.getMonitoredAssets();
      _alerts = _service.getAlerts(includeResolved: true);
      _freezeStatus = _service.getFreezeStatus();
      _recoveryCases = _service.getRecoveryCases();
      _updateSummary();

      // Start monitoring
      _service.startMonitoring();
    } catch (e) {
      _error = 'Failed to initialize identity protection: $e';
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
      _alerts = _service.getAlerts(includeResolved: true);
      _updateSummary();
      notifyListeners();
      return asset;
    } catch (e) {
      _error = 'Failed to add asset: $e';
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
      _error = 'Failed to remove asset: $e';
      notifyListeners();
    }
  }

  /// Scan all assets against the live backend services
  Future<void> scanAllAssets() async {
    _isScanning = true;
    _error = null;
    notifyListeners();

    try {
      await _service.scanAllAssets();
      if (_service.lastScanErrors.isNotEmpty) {
        _error =
            '${_service.lastScanErrors.length} asset scan(s) failed — '
            'results may be incomplete';
      }
    } catch (e) {
      _error = 'Scan failed: $e';
    } finally {
      _monitoredAssets = _service.getMonitoredAssets();
      _alerts = _service.getAlerts(includeResolved: true);
      _updateSummary();
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
      _error = 'Failed to acknowledge alert: $e';
      notifyListeners();
    }
  }

  /// Resolve alert
  Future<void> resolveAlert(String alertId) async {
    try {
      await _service.resolveAlert(alertId);
      _alerts = _service.getAlerts(includeResolved: true);
      _monitoredAssets = _service.getMonitoredAssets();
      _updateSummary();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to resolve alert: $e';
      notifyListeners();
    }
  }

  /// Record the user's self-declared freeze status for a bureau.
  /// This does NOT freeze credit — the user must do that on the bureau's
  /// official page (see [officialFreezeUrl]).
  Future<CreditFreezeStatus?> setSelfReportedFreeze(
    CreditBureau bureau,
    bool isFrozen,
  ) async {
    try {
      final status =
          await _service.setSelfReportedFreezeStatus(bureau, isFrozen);
      _freezeStatus = _service.getFreezeStatus();
      _updateSummary();
      notifyListeners();
      return status;
    } catch (e) {
      _error = 'Failed to record freeze status: $e';
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
      _error = 'Failed to open recovery case: $e';
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
      case MonitoringStatus.unavailable:
        return 0xFF9E9E9E;
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
