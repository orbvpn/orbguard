// Dark Web Provider
// State management for dark web monitoring and breach alerts

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../presentation/theme/colors.dart';

import '../services/api/api_config.dart';
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

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'value': value,
        if (maskedValue != null) 'masked_value': maskedValue,
        'added_at': addedAt.toIso8601String(),
        if (lastChecked != null)
          'last_checked': lastChecked!.toIso8601String(),
        'breach_count': breachCount,
        'is_monitoring': isMonitoring,
      };

  factory MonitoredAsset.fromJson(Map<String, dynamic> json) {
    return MonitoredAsset(
      id: json['id'] as String,
      type: AssetType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => AssetType.email,
      ),
      value: json['value'] as String,
      maskedValue: json['masked_value'] as String?,
      addedAt: DateTime.parse(json['added_at'] as String),
      lastChecked: json['last_checked'] != null
          ? DateTime.parse(json['last_checked'] as String)
          : null,
      breachCount: json['breach_count'] as int? ?? 0,
      isMonitoring: json['is_monitoring'] as bool? ?? true,
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
  static const _prefsAssetsKey = 'darkweb_monitored_assets';

  static final String _monitorPath = '${ApiConfig.apiVersion}/darkweb/monitor';
  static String _monitorAssetPath(String id) =>
      '${ApiConfig.apiVersion}/darkweb/monitor/$id';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;
  SharedPreferences? _prefs;

  /// Restores the cached assets and pulls the per-user server state as soon
  /// as the provider is created (the dark web screen reads the provider
  /// without calling [init] itself).
  DarkWebProvider() {
    unawaited(init());
  }

  /// True once the asset list reflects the backend monitor state.
  bool _assetsSynced = false;
  String? _assetSyncError;

  bool get assetsSynced => _assetsSynced;
  String? get assetSyncError => _assetSyncError;

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

  /// Add asset to monitoring.
  ///
  /// Registers the asset with the live backend
  /// (POST /darkweb/monitor, per-user scoped) and caches it locally.
  /// Returns false (with [error] set) when the backend rejects the asset, so
  /// the UI never claims an asset is monitored when it is not.
  Future<bool> addAsset(AssetType type, String value) async {
    if (value.isEmpty) return false;

    // Check if already monitoring
    if (_assets.any((a) => a.type == type && a.value == value)) {
      _error = 'This ${type.displayName.toLowerCase()} is already being monitored';
      notifyListeners();
      return false;
    }

    Map<String, dynamic> created;
    try {
      created = await _api.post<Map<String, dynamic>>(
        _monitorPath,
        data: {
          'asset_type': type.name,
          'value': value,
        },
      );
    } catch (e) {
      _error = 'Failed to add ${type.displayName.toLowerCase()} '
          'to dark web monitoring: $e';
      notifyListeners();
      return false;
    }

    final asset = MonitoredAsset(
      id: created['id'] as String? ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      value: value,
      maskedValue: created['display_name'] as String?,
      addedAt: created['created_at'] != null
          ? DateTime.tryParse(created['created_at'] as String) ??
              DateTime.now()
          : DateTime.now(),
      breachCount: created['breach_count'] as int? ?? 0,
      lastChecked: created['last_checked'] != null
          ? DateTime.tryParse(created['last_checked'] as String)
          : null,
    );

    _assets.add(asset);
    _updateStats();
    await _saveAssets();
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
          await _saveAssets();
          notifyListeners();
        }
      }
    }

    return true;
  }

  /// Remove asset from monitoring (DELETE /darkweb/monitor/{id}).
  ///
  /// The asset is only removed locally once the backend confirms (or reports
  /// it already gone), so the UI never claims monitoring stopped while the
  /// server still tracks the asset.
  Future<bool> removeAsset(String id) async {
    try {
      await _api.delete<dynamic>(_monitorAssetPath(id));
    } catch (e) {
      final message = e.toString();
      // 404 = the server no longer knows the asset; safe to drop locally.
      if (!message.contains('404') && !message.contains('not found')) {
        _error = 'Failed to remove monitored asset: $e';
        notifyListeners();
        return false;
      }
    }

    _assets.removeWhere((a) => a.id == id);
    _updateStats();
    await _saveAssets();
    notifyListeners();
    return true;
  }

  /// Toggle client-side monitoring for an asset.
  ///
  /// Note: the backend has no pause endpoint (only add/remove), so this flag
  /// controls whether OrbGuard actively re-checks the asset from this device;
  /// the asset stays registered server-side until it is removed.
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
        try {
          final result = await _api.checkEmailBreaches(asset.value);
          final index = _assets.indexWhere((a) => a.id == asset.id);
          if (index >= 0) {
            _assets[index] = asset.copyWith(
              lastChecked: DateTime.now(),
              breachCount: result.breachCount,
            );
          }
          _checkResults[asset.value] = result;
        } catch (e) {
          _error = 'Failed to re-check ${asset.displayValue}: $e';
          debugPrint('DarkWebProvider: $_error');
        }
      }
    }

    _updateStats();
    await _saveAssets();
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

  /// Load assets: local cache first (instant UI), then the authoritative
  /// per-user list from the live backend (GET /darkweb/monitor).
  Future<void> loadAssets() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('DarkWebProvider: failed to open preferences: $e');
    }

    // 1. Local cache
    final raw = _prefs?.getString(_prefsAssetsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final restored = <MonitoredAsset>[];
        for (final item in decoded) {
          try {
            restored.add(
                MonitoredAsset.fromJson(Map<String, dynamic>.from(item as Map)));
          } catch (e) {
            debugPrint('DarkWebProvider: skipping corrupt cached asset: $e');
          }
        }
        _assets
          ..clear()
          ..addAll(restored);
        notifyListeners();
      } catch (e) {
        debugPrint('DarkWebProvider: failed to restore asset cache: $e');
      }
    }

    // 2. Authoritative server state
    try {
      final response = await _api.get<Map<String, dynamic>>(_monitorPath);
      final serverAssets = response['assets'] as List<dynamic>? ?? const [];

      // Preserve locally-known plaintext values and client-side monitoring
      // toggles; the server stores values encrypted/hashed.
      final localById = {for (final a in _assets) a.id: a};

      _assets
        ..clear()
        ..addAll(serverAssets.map((raw) {
          final map = Map<String, dynamic>.from(raw as Map);
          final id = map['id'] as String? ?? '';
          final local = localById[id];
          return MonitoredAsset(
            id: id,
            type: _assetTypeFromBackend(map['asset_type'] as String?),
            value: local?.value ??
                (map['asset_value'] as String? ??
                    map['display_name'] as String? ??
                    ''),
            maskedValue: map['display_name'] as String?,
            addedAt: map['created_at'] != null
                ? DateTime.tryParse(map['created_at'] as String) ??
                    DateTime.now()
                : (local?.addedAt ?? DateTime.now()),
            lastChecked: map['last_checked'] != null
                ? DateTime.tryParse(map['last_checked'] as String)
                : local?.lastChecked,
            breachCount: map['breach_count'] as int? ?? 0,
            isMonitoring: local?.isMonitoring ?? true,
          );
        }));

      _assetsSynced = true;
      _assetSyncError = null;
      await _saveAssets();
    } catch (e) {
      _assetsSynced = false;
      _assetSyncError = 'Failed to sync monitored assets with backend: $e';
      debugPrint('DarkWebProvider: $_assetSyncError');
    }

    _updateStats();
    notifyListeners();
  }

  AssetType _assetTypeFromBackend(String? backendType) {
    switch (backendType) {
      case 'email':
        return AssetType.email;
      case 'phone':
        return AssetType.phone;
      case 'password':
        return AssetType.password;
      case 'username':
        return AssetType.username;
      case 'domain':
        return AssetType.domain;
      default:
        return AssetType.email;
    }
  }

  /// Save assets to the local cache.
  Future<void> _saveAssets() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(
        _prefsAssetsKey,
        jsonEncode(_assets.map((a) => a.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('DarkWebProvider: failed to persist asset cache: $e');
    }
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
        return AppColors.severityCritical.toARGB32();
      case SeverityLevel.high:
        return AppColors.severityHigh.toARGB32();
      case SeverityLevel.medium:
        return AppColors.severityMedium.toARGB32();
      case SeverityLevel.low:
        return AppColors.severityLow.toARGB32();
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        return AppColors.severityInfo.toARGB32();
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
