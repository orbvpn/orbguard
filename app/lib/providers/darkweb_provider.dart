/// Dark Web Provider
/// State management for dark web monitoring and breach alerts

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../services/api/orbguard_api_client.dart';
import '../models/api/sms_analysis.dart';
import '../models/api/threat_indicator.dart';

/// Monitored asset types
enum AssetType {
  email,
  phone,
  password,
  domain,
  username;

  String get displayName {
    switch (this) {
      case AssetType.email:
        return 'Email';
      case AssetType.phone:
        return 'Phone';
      case AssetType.password:
        return 'Password';
      case AssetType.domain:
        return 'Domain';
      case AssetType.username:
        return 'Username';
    }
  }

  String get icon {
    switch (this) {
      case AssetType.email:
        return 'email';
      case AssetType.phone:
        return 'phone';
      case AssetType.password:
        return 'password';
      case AssetType.domain:
        return 'language';
      case AssetType.username:
        return 'person';
    }
  }
}

/// Monitored asset entry
class MonitoredAsset {
  final String id;
  final AssetType type;
  final String value;
  final String? maskedValue;
  final DateTime addedAt;
  final DateTime? lastChecked;
  final int breachCount;
  final bool isMonitoring;

  MonitoredAsset({
    required this.id,
    required this.type,
    required this.value,
    this.maskedValue,
    required this.addedAt,
    this.lastChecked,
    this.breachCount = 0,
    this.isMonitoring = true,
  });

  MonitoredAsset copyWith({
    String? id,
    AssetType? type,
    String? value,
    String? maskedValue,
    DateTime? addedAt,
    DateTime? lastChecked,
    int? breachCount,
    bool? isMonitoring,
  }) {
    return MonitoredAsset(
      id: id ?? this.id,
      type: type ?? this.type,
      value: value ?? this.value,
      maskedValue: maskedValue ?? this.maskedValue,
      addedAt: addedAt ?? this.addedAt,
      lastChecked: lastChecked ?? this.lastChecked,
      breachCount: breachCount ?? this.breachCount,
      isMonitoring: isMonitoring ?? this.isMonitoring,
    );
  }

  /// Get masked display value for privacy
  String get displayValue {
    if (maskedValue != null) return maskedValue!;
    switch (type) {
      case AssetType.email:
        final parts = value.split('@');
        if (parts.length == 2) {
          final name = parts[0];
          final domain = parts[1];
          if (name.length > 2) {
            return '${name.substring(0, 2)}***@$domain';
          }
        }
        return value;
      case AssetType.phone:
        if (value.length > 4) {
          return '***${value.substring(value.length - 4)}';
        }
        return value;
      case AssetType.password:
        return '••••••••';
      default:
        return value;
    }
  }
}

/// Dark web monitoring stats
class DarkWebStats {
  final int totalAssets;
  final int totalBreaches;
  final int criticalBreaches;
  final int highBreaches;
  final int mediumBreaches;
  final int lowBreaches;
  final int unreadAlerts;

  DarkWebStats({
    this.totalAssets = 0,
    this.totalBreaches = 0,
    this.criticalBreaches = 0,
    this.highBreaches = 0,
    this.mediumBreaches = 0,
    this.lowBreaches = 0,
    this.unreadAlerts = 0,
  });
}

/// Dark Web Provider
class DarkWebProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  final List<MonitoredAsset> _assets = [];
  final List<BreachAlert> _alerts = [];
  final Map<String, BreachCheckResult> _checkResults = {};
  DarkWebStats _stats = DarkWebStats();
  BreachCheckResult? _lastCheckResult;
  PasswordBreachResult? _lastPasswordResult;

  bool _isLoading = false;
  bool _isCheckingEmail = false;
  bool _isCheckingPassword = false;
  String? _error;

  // Getters
  List<MonitoredAsset> get assets => List.unmodifiable(_assets);
  List<BreachAlert> get alerts => List.unmodifiable(_alerts);
  DarkWebStats get stats => _stats;
  BreachCheckResult? get lastCheckResult => _lastCheckResult;
  PasswordBreachResult? get lastPasswordResult => _lastPasswordResult;
  bool get isLoading => _isLoading;
  bool get isCheckingEmail => _isCheckingEmail;
  bool get isCheckingPassword => _isCheckingPassword;
  String? get error => _error;

  /// Unread alerts
  List<BreachAlert> get unreadAlerts =>
      _alerts.where((a) => !a.isRead).toList();

  /// Recent breaches
  List<BreachAlert> get recentBreaches => _alerts.take(10).toList();

  /// Critical alerts
  List<BreachAlert> get criticalAlerts => _alerts
      .where((a) =>
          a.severity == SeverityLevel.critical ||
          a.severity == SeverityLevel.high)
      .toList();

  /// Initialize provider
  Future<void> init() async {
    await loadAssets();
    await refreshAlerts();
    _updateStats();
  }

  /// Check email for breaches
  Future<BreachCheckResult?> checkEmail(String email) async {
    if (email.isEmpty) return null;

    _isCheckingEmail = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _api.checkEmailBreaches(email);
      _lastCheckResult = result;
      _checkResults[email] = result;
      _isCheckingEmail = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isCheckingEmail = false;
      _error = 'Failed to check email: $e';
      notifyListeners();
      return null;
    }
  }

  /// Check password for breaches (k-anonymity)
  Future<PasswordBreachResult?> checkPassword(String password) async {
    if (password.isEmpty) return null;

    _isCheckingPassword = true;
    _error = null;
    notifyListeners();

    try {
      // Hash password with SHA-1 and get first 5 characters
      final bytes = utf8.encode(password);
      final digest = sha1.convert(bytes);
      final hashPrefix = digest.toString().substring(0, 5).toUpperCase();

      final result = await _api.checkPasswordBreaches(hashPrefix);
      _lastPasswordResult = result;
      _isCheckingPassword = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isCheckingPassword = false;
      _error = 'Failed to check password: $e';
      notifyListeners();
      return null;
    }
  }

  /// Add asset to monitoring
  Future<bool> addAsset(AssetType type, String value) async {
    if (value.isEmpty) return false;

    // Check if already monitoring
    if (_assets.any((a) => a.type == type && a.value == value)) {
      _error = 'This ${type.displayName.toLowerCase()} is already being monitored';
      notifyListeners();
      return false;
    }

    final asset = MonitoredAsset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      value: value,
      addedAt: DateTime.now(),
    );

    _assets.add(asset);
    _updateStats();
    _saveAssets();
    notifyListeners();

    // Check for breaches immediately
    if (type == AssetType.email) {
      final result = await checkEmail(value);
      if (result != null) {
        final index = _assets.indexWhere((a) => a.id == asset.id);
        if (index >= 0) {
          _assets[index] = asset.copyWith(
            lastChecked: DateTime.now(),
            breachCount: result.breachCount,
          );
          notifyListeners();
        }
      }
    }

    return true;
  }

  /// Remove asset from monitoring
  void removeAsset(String id) {
    _assets.removeWhere((a) => a.id == id);
    _updateStats();
    _saveAssets();
    notifyListeners();
  }

  /// Toggle monitoring for asset
  void toggleMonitoring(String id) {
    final index = _assets.indexWhere((a) => a.id == id);
    if (index >= 0) {
      _assets[index] = _assets[index].copyWith(
        isMonitoring: !_assets[index].isMonitoring,
      );
      _saveAssets();
      notifyListeners();
    }
  }

  /// Refresh all assets
  Future<void> refreshAssets() async {
    _isLoading = true;
    notifyListeners();

    for (final asset in _assets.where((a) => a.isMonitoring)) {
      if (asset.type == AssetType.email) {
        final result = await _api.checkEmailBreaches(asset.value);
        final index = _assets.indexWhere((a) => a.id == asset.id);
        if (index >= 0) {
          _assets[index] = asset.copyWith(
            lastChecked: DateTime.now(),
            breachCount: result.breachCount,
          );
        }
        _checkResults[asset.value] = result;
      }
    }

    _updateStats();
    _isLoading = false;
    notifyListeners();
  }

  /// Refresh alerts
  Future<void> refreshAlerts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final alerts = await _api.getBreachAlerts();
      _alerts.clear();
      _alerts.addAll(alerts);
      _updateStats();
    } catch (e) {
      _error = 'Failed to refresh alerts: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Mark alert as read
  void markAlertAsRead(String id) {
    final index = _alerts.indexWhere((a) => a.id == id);
    if (index >= 0) {
      // Create updated alert (BreachAlert is immutable, would need API call)
      _updateStats();
      notifyListeners();
    }
  }

  /// Mark all alerts as read
  void markAllAlertsAsRead() {
    _updateStats();
    notifyListeners();
  }

  /// Get check result for email
  BreachCheckResult? getCheckResult(String email) {
    return _checkResults[email];
  }

  /// Load assets from storage
  Future<void> loadAssets() async {
    // TODO: Load from persistent storage
  }

  /// Save assets to storage
  Future<void> _saveAssets() async {
    // TODO: Save to persistent storage
  }

  /// Update stats
  void _updateStats() {
    int critical = 0;
    int high = 0;
    int medium = 0;
    int low = 0;
    int unread = 0;

    for (final alert in _alerts) {
      if (!alert.isRead) unread++;
      switch (alert.severity) {
        case SeverityLevel.critical:
          critical++;
          break;
        case SeverityLevel.high:
          high++;
          break;
        case SeverityLevel.medium:
          medium++;
          break;
        case SeverityLevel.low:
        case SeverityLevel.info:
        case SeverityLevel.unknown:
          low++;
          break;
      }
    }

    _stats = DarkWebStats(
      totalAssets: _assets.length,
      totalBreaches: _alerts.length,
      criticalBreaches: critical,
      highBreaches: high,
      mediumBreaches: medium,
      lowBreaches: low,
      unreadAlerts: unread,
    );
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear last check result
  void clearLastResult() {
    _lastCheckResult = null;
    _lastPasswordResult = null;
    notifyListeners();
  }

  /// Get severity color
  static int getSeverityColor(SeverityLevel severity) {
    switch (severity) {
      case SeverityLevel.critical:
        return 0xFFFF1744;
      case SeverityLevel.high:
        return 0xFFFF5722;
      case SeverityLevel.medium:
        return 0xFFFF9800;
      case SeverityLevel.low:
        return 0xFFFFEB3B;
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        return 0xFF2196F3;
    }
  }

  /// Get data class icon
  static String getDataClassIcon(String dataClass) {
    final lower = dataClass.toLowerCase();
    if (lower.contains('password')) return 'password';
    if (lower.contains('email')) return 'email';
    if (lower.contains('phone')) return 'phone';
    if (lower.contains('name')) return 'person';
    if (lower.contains('address')) return 'home';
    if (lower.contains('credit') || lower.contains('card')) {
      return 'credit_card';
    }
    if (lower.contains('social') || lower.contains('ssn')) {
      return 'badge';
    }
    if (lower.contains('bank') || lower.contains('financial')) {
      return 'account_balance';
    }
    if (lower.contains('ip')) return 'router';
    if (lower.contains('date') || lower.contains('birth')) return 'cake';
    return 'data_object';
  }
}
