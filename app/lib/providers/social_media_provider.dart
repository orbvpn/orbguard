// Social Media Monitor Provider
// State management for social media security monitoring

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/api/api_interceptors.dart';
import '../services/security/social_media_monitor_service.dart';

class SocialMediaProvider extends ChangeNotifier {
  final SocialMediaMonitorService _service = SocialMediaMonitorService();

  // State
  List<SocialAccount> _accounts = [];
  List<ImpersonationAlert> _alerts = [];
  List<DataExposure> _exposures = [];
  MonitoringResult? _lastScanResult;

  // Username presence scan (REAL backend capability, independent of the
  // still-unavailable impersonation/privacy/exposure features).
  UsernameScanResult? _usernameScanResult;
  bool _isUsernameScanning = false;
  String? _usernameScanError;

  // Loading states
  bool _isLoading = false;
  bool _isScanning = false;

  // Error state
  String? _error;

  // Stream subscriptions
  StreamSubscription<ImpersonationAlert>? _alertSub;
  StreamSubscription<DataExposure>? _exposureSub;
  StreamSubscription<MonitoringResult>? _resultSub;

  // Getters
  List<SocialAccount> get accounts => _accounts;
  List<ImpersonationAlert> get alerts => _alerts;
  List<DataExposure> get exposures => _exposures;
  MonitoringResult? get lastScanResult => _lastScanResult;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get error => _error;

  // Username presence scan getters
  UsernameScanResult? get usernameScanResult => _usernameScanResult;
  bool get isUsernameScanning => _isUsernameScanning;
  String? get usernameScanError => _usernameScanError;

  // Computed getters
  List<ImpersonationAlert> get activeAlerts =>
      _alerts.where((a) => a.status == AlertStatus.active).toList();

  int get totalAlerts => _alerts.length;

  int get criticalAlerts => _alerts
      .where((a) =>
          a.status == AlertStatus.active &&
          (a.threatLevel == 'Critical' || a.threatLevel == 'High'))
      .length;

  /// Average of real backend privacy-audit scores. 0 means "no audit data"
  /// (no backend signal), never a measured score — see
  /// [privacyAnalysisAvailable] to distinguish the two.
  int get averagePrivacyScore {
    if (_accounts.isEmpty) return 0;
    final scores = _accounts.where((a) => a.privacyScore != null);
    if (scores.isEmpty) return 0;
    return (scores.map((a) => a.privacyScore!.overallScore).reduce((a, b) => a + b) /
            scores.length)
        .round();
  }

  /// True when at least one account has a real privacy-audit result.
  /// When false, the privacy section has nothing measured to show.
  bool get privacyAnalysisAvailable =>
      _accounts.any((a) => a.privacyScore != null);

  /// True only when a live analysis backend is connected. There is currently
  /// no social-media analysis backend, so this is false and the UI must show
  /// an explicit "not connected / unavailable" state for every result rather
  /// than implying the user's accounts were checked and found safe.
  bool get analysisAvailable => _service.isBackendConfigured;

  /// True only when the last scan actually performed a backend data-exposure
  /// analysis. When false, an empty [exposures] list means "not analyzable"
  /// (no backend signal), NOT "no exposures found".
  bool get exposureAnalysisPerformed =>
      _lastScanResult?.exposureAnalysisPerformed ?? false;

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.initialize();

      // Listen to alerts
      _alertSub = _service.onAlert.listen((alert) {
        _alerts.insert(0, alert);
        notifyListeners();
      });

      // Listen to exposures
      _exposureSub = _service.onExposure.listen((exposure) {
        _exposures.insert(0, exposure);
        notifyListeners();
      });

      // Listen to scan results
      _resultSub = _service.onResult.listen((result) {
        _lastScanResult = result;
        _updateAccounts();
        notifyListeners();
      });

      _accounts = _service.getAccounts();
      _alerts = _service.getAlerts();
      _exposures = _service.getExposures();
    } catch (e) {
      _error = 'Failed to initialize social media monitor';
      debugPrint('Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add social account for monitoring
  Future<SocialAccount?> addAccount(
    SocialPlatform platform,
    String username, {
    String? displayName,
  }) async {
    try {
      final account = await _service.addAccount(
        platform,
        username,
        displayName: displayName,
      );
      _accounts = _service.getAccounts();
      notifyListeners();
      return account;
    } catch (e) {
      _error = 'Failed to add account';
      notifyListeners();
      return null;
    }
  }

  /// Remove account from monitoring
  Future<void> removeAccount(String accountId) async {
    await _service.removeAccount(accountId);
    _accounts = _service.getAccounts();
    notifyListeners();
  }

  /// Dismiss an impersonation alert the user has reviewed (local only).
  void dismissAlert(String alertId) {
    _service.dismissAlert(alertId);
    _alerts = _service.getAlerts();
    notifyListeners();
  }

  /// Scan specific account
  Future<MonitoringResult?> scanAccount(String accountId) async {
    _isScanning = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.scanAccount(accountId);
      _lastScanResult = result;
      _updateAccounts();
      return result;
    } catch (e) {
      _error = 'Scan failed: $e';
      return null;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Scan all accounts
  Future<void> scanAllAccounts() async {
    _isScanning = true;
    _error = null;
    notifyListeners();

    try {
      await _service.scanAllAccounts();
      _updateAccounts();
      _alerts = _service.getAlerts();
      _exposures = _service.getExposures();
    } catch (e) {
      _error = 'Scan failed: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Run a REAL username presence scan across public platforms.
  ///
  /// Unlike the impersonation/privacy/exposure features (which have no backend
  /// and stay unavailable), this hits the live backend and returns real
  /// per-platform existence results. Each platform is "found", "not_found" or
  /// "unknown" — "unknown" is honest (blocked/unreachable), never a guessed
  /// absence.
  Future<void> scanUsername(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return;

    _isUsernameScanning = true;
    _usernameScanError = null;
    notifyListeners();

    try {
      _usernameScanResult = await _service.scanUsername(trimmed);
    } on ApiError catch (e) {
      _usernameScanError = e.message;
    } catch (e) {
      _usernameScanError = 'Username scan failed';
      debugPrint('Username scan error: $e');
    } finally {
      _isUsernameScanning = false;
      notifyListeners();
    }
  }

  /// Clear the last username presence scan result and error.
  void clearUsernameScan() {
    _usernameScanResult = null;
    _usernameScanError = null;
    notifyListeners();
  }

  /// Update accounts list
  void _updateAccounts() {
    _accounts = _service.getAccounts();
  }

  /// Report impersonator
  Future<bool> reportImpersonator(String alertId) async {
    try {
      final success = await _service.reportImpersonator(alertId);
      if (success) {
        _alerts = _service.getAlerts();
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Failed to report impersonator';
      notifyListeners();
      return false;
    }
  }

  /// Start continuous monitoring
  void startMonitoring() {
    _service.startMonitoring();
  }

  /// Stop continuous monitoring
  void stopMonitoring() {
    _service.stopMonitoring();
  }

  /// Get platform color
  static int getPlatformColor(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.facebook:
        return 0xFF1877F2;
      case SocialPlatform.instagram:
        return 0xFFE1306C;
      case SocialPlatform.twitter:
        return 0xFF1DA1F2;
      case SocialPlatform.linkedin:
        return 0xFF0A66C2;
      case SocialPlatform.tiktok:
        return 0xFF000000;
      case SocialPlatform.snapchat:
        return 0xFFFFFC00;
      case SocialPlatform.youtube:
        return 0xFFFF0000;
      case SocialPlatform.reddit:
        return 0xFFFF4500;
      case SocialPlatform.whatsapp:
        return 0xFF25D366;
      case SocialPlatform.telegram:
        return 0xFF0088CC;
    }
  }

  /// Get platform icon name
  static String getPlatformIcon(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.facebook:
        return 'facebook';
      case SocialPlatform.instagram:
        return 'camera_alt';
      case SocialPlatform.twitter:
        return 'tag';
      case SocialPlatform.linkedin:
        return 'work';
      case SocialPlatform.tiktok:
        return 'music_note';
      case SocialPlatform.snapchat:
        return 'camera';
      case SocialPlatform.youtube:
        return 'play_circle';
      case SocialPlatform.reddit:
        return 'forum';
      case SocialPlatform.whatsapp:
        return 'chat';
      case SocialPlatform.telegram:
        return 'send';
    }
  }

  /// Get severity color
  static int getSeverityColor(RiskSeverity severity) {
    switch (severity) {
      case RiskSeverity.critical:
        return 0xFFFF1744;
      case RiskSeverity.high:
        return 0xFFFF5722;
      case RiskSeverity.medium:
        return 0xFFFF9800;
      case RiskSeverity.low:
        return 0xFFFFEB3B;
      case RiskSeverity.informational:
        return 0xFF2196F3;
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
    _exposureSub?.cancel();
    _resultSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
