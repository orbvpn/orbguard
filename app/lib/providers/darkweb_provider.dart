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
  static const _prefsReadAlertsKey = 'darkweb_read_alert_ids';
  static const _prefsHandledKey = 'darkweb_handled_breaches';

  static final String _monitorPath = '${ApiConfig.apiVersion}/darkweb/monitor';
  static String _monitorAssetPath(String id) =>
      '${ApiConfig.apiVersion}/darkweb/monitor/$id';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;
  SharedPreferences? _prefs;

  /// Restores the cached assets and pulls the per-user server state as soon
  /// as the provider is created (the dark web screen reads the provider
  /// without calling [init] itself).
  ///
  /// [autoInit] false skips that start, so a test can load known state
  /// through [debugLoad] without any network call.
  DarkWebProvider({@visibleForTesting bool autoInit = true}) {
    if (autoInit) unawaited(init());
  }

  /// True once the asset list reflects the backend monitor state.
  bool _assetsSynced = false;
  String? _assetSyncError;

  bool get assetsSynced => _assetsSynced;
  String? get assetSyncError => _assetSyncError;

  // State
  final List<MonitoredAsset> _assets = [];
  final List<BreachAlert> _alerts = [];

  /// Ids of alerts the user has marked read locally. Persisted to
  /// SharedPreferences so read state survives restarts — the backend alert
  /// feed has no per-device read endpoint, so this is the source of truth
  /// for local read state.
  final Set<String> _readAlertIds = {};

  final Map<String, BreachCheckResult> _checkResults = {};

  /// Addresses the person said they dealt with, by asset id. Persisted under
  /// [_prefsHandledKey]; see [markBreachHandled].
  final Map<String, _HandledBreach> _handled = {};
  DarkWebStats _stats = DarkWebStats();
  BreachCheckResult? _lastCheckResult;
  PasswordBreachResult? _lastPasswordResult;

  bool _isLoading = false;
  bool _isCheckingEmail = false;
  bool _isCheckingPassword = false;
  String? _error;

  // Getters
  List<MonitoredAsset> get assets => List.unmodifiable(_assets);

  /// All alerts, with [BreachAlert.isRead] reflecting the locally-persisted
  /// read set so read/unread styling stays correct without a backend call.
  List<BreachAlert> get alerts =>
      List.unmodifiable(_alerts.map(_reflectRead));
  DarkWebStats get stats => _stats;
  BreachCheckResult? get lastCheckResult => _lastCheckResult;
  PasswordBreachResult? get lastPasswordResult => _lastPasswordResult;
  bool get isLoading => _isLoading;
  bool get isCheckingEmail => _isCheckingEmail;
  bool get isCheckingPassword => _isCheckingPassword;
  String? get error => _error;

  /// Unread alerts (excludes ids in the locally-persisted read set).
  List<BreachAlert> get unreadAlerts =>
      _alerts.where((a) => !_isAlertRead(a)).toList();

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
    await _loadReadAlerts();
    await _loadHandled();
    await refreshAlerts();
    _updateStats();
  }

  /// Replaces the in-memory state with known values and restores the
  /// persisted read and handled sets, exactly as [init] would after a sync.
  @visibleForTesting
  Future<void> debugLoad({
    List<MonitoredAsset> assets = const [],
    List<BreachAlert> alerts = const [],
    Map<String, BreachCheckResult> checkResults = const {},
  }) async {
    _assets
      ..clear()
      ..addAll(assets);
    _alerts
      ..clear()
      ..addAll(alerts);
    _checkResults
      ..clear()
      ..addAll(checkResults);
    await _loadReadAlerts();
    await _loadHandled();
    _updateStats();
    notifyListeners();
  }

  // ── Open breaches: the signal Home reads ─────────────────────────────────
  //
  // Two real sources say an address is in a breach, and they can disagree:
  //
  //  * `breachCount` on the asset, the size of the provider result from the
  //    latest check. It can go DOWN while the breach is still real: a re-add
  //    whose check fails stores 0 (the backend upsert overwrites it), and a
  //    refresh where one of several providers fails merges fewer breaches.
  //  * the alert feed. The backend writes one alert per (asset, breach name)
  //    and never deletes it, so an alert can name a breach the count no
  //    longer includes. The reverse also happens: alerts are skipped when the
  //    Dark Web toggle is off or the feed fails to load.
  //
  // So the evidence for an address is the union: every breach name seen in
  // its alerts or in a check result held in memory, and a count that is the
  // largest of breachCount, the check result's count and those names.

  /// Watched email addresses.
  Iterable<MonitoredAsset> get _emailAssets =>
      _assets.where((a) => a.type == AssetType.email);

  /// Alerts that belong to [asset]. The live payload links by `asset_id`; an
  /// alert without one is matched by its address when the payload has it.
  List<BreachAlert> _alertsFor(MonitoredAsset asset) => _alerts.where((a) {
        if (a.assetId.isNotEmpty) return a.assetId == asset.id;
        return a.assetValue.isNotEmpty &&
            a.assetValue.toLowerCase() == asset.value.toLowerCase();
      }).toList();

  static String _breachKey(String name) => name.trim().toLowerCase();

  /// Every breach name known for [asset], normalised.
  Set<String> _breachNamesFor(MonitoredAsset asset) {
    final names = <String>{};
    for (final a in _alertsFor(asset)) {
      final k = _breachKey(a.breach.name);
      if (k.isNotEmpty) names.add(k);
    }
    for (final b
        in _checkResults[asset.value]?.breaches ?? const <BreachInfo>[]) {
      final k = _breachKey(b.name);
      if (k.isNotEmpty) names.add(k);
    }
    return names;
  }

  int _evidenceCount(MonitoredAsset asset) {
    final counts = [
      asset.breachCount,
      _checkResults[asset.value]?.breachCount ?? 0,
      _breachNamesFor(asset).length,
      _alertsFor(asset).length,
    ];
    return counts.reduce((a, b) => a > b ? a : b);
  }

  /// True when anything real has been learned about [asset]: a completed
  /// check, an alert, or a check result in memory.
  bool _isKnown(MonitoredAsset asset) =>
      asset.lastChecked != null ||
      _alertsFor(asset).isNotEmpty ||
      _checkResults[asset.value] != null;

  bool _isOpen(MonitoredAsset asset) {
    if (!_isKnown(asset)) return false;
    final count = _evidenceCount(asset);
    if (count == 0) return false;
    final h = _handled[asset.id];
    if (h == null) return true;
    if (count > h.count) return true;
    // A breach the person never saw when they said they dealt with it.
    return !h.names.containsAll(_breachNamesFor(asset));
  }

  /// Watched email addresses whose known breaches the person has not marked
  /// handled, in the order they were added.
  List<MonitoredAsset> get openBreaches =>
      List.unmodifiable(_emailAssets.where(_isOpen));

  /// How many watched email addresses have breaches still open.
  ///
  /// Null when no email address is watched, or none has ever been checked
  /// (no check, no alert, no result in memory): nothing is known, which is
  /// never the same as safe. Addresses not yet checked add nothing to the
  /// count.
  int? get openBreachedAccounts {
    final emails = _emailAssets.toList();
    if (emails.isEmpty || !emails.any(_isKnown)) return null;
    return openBreaches.length;
  }

  /// The most recent check among watched email addresses, or null.
  DateTime? get lastBreachCheckAt {
    DateTime? newest;
    for (final a in _emailAssets) {
      final t = a.lastChecked;
      if (t != null && (newest == null || t.isAfter(newest))) newest = t;
    }
    return newest;
  }

  /// The number of breaches known for the address with [assetId] (see the
  /// note above on how the sources combine), or 0 when it is not watched.
  int breachCountFor(String assetId) {
    final asset = _emailById(assetId);
    return asset == null ? 0 : _evidenceCount(asset);
  }

  /// A real, named breach for the address with [assetId], preferring one the
  /// person has not already dealt with, then the newest by breach date.
  /// From a check result in memory (name, and date when the source gave one)
  /// or else from the alert feed (name only). Null when no name is known.
  BreachInfo? newestNamedBreachFor(String assetId) {
    final asset = _emailById(assetId);
    if (asset == null) return null;
    final handledNames = _handled[asset.id]?.names ?? const <String>{};

    final fromCheck = (_checkResults[asset.value]?.breaches ??
            const <BreachInfo>[])
        .where((b) => _breachKey(b.name).isNotEmpty)
        .toList()
      ..sort((a, b) {
        final ad = a.breachDate, bd = b.breachDate;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
    final fromAlerts = _alertsFor(asset)
        .where((a) => _breachKey(a.breach.name).isNotEmpty)
        .toList()
      ..sort((a, b) => b.alertedAt.compareTo(a.alertedAt));

    final candidates = [
      ...fromCheck,
      ...fromAlerts.map((a) => a.breach),
    ];
    if (candidates.isEmpty) return null;
    return candidates.firstWhere(
      (b) => !handledNames.contains(_breachKey(b.name)),
      orElse: () => candidates.first,
    );
  }

  /// True when the person marked the address with [assetId] handled, its
  /// breaches are still known, and nothing new has reopened it.
  bool isBreachHandled(String assetId) {
    final asset = _emailById(assetId);
    if (asset == null || !_handled.containsKey(asset.id)) return false;
    return _isKnown(asset) && _evidenceCount(asset) > 0 && !_isOpen(asset);
  }

  /// A full address OrbGuard can send to the breach check. An address the
  /// server only returned in masked form ("al***@x.com") cannot be checked.
  static bool _checkable(String value) =>
      value.contains('@') && !value.contains('*');

  /// Whether [showLeakDetailsFor] can put the details of what leaked for the
  /// address with [assetId] on the Email tab: a check result for it is in
  /// memory, or its full address is known so a check can run.
  bool canShowLeakDetailsFor(String assetId) {
    final asset = _emailById(assetId);
    if (asset == null) return false;
    return _checkResults[asset.value] != null || _checkable(asset.value);
  }

  /// Makes the breach details for the address with [assetId] the Email
  /// tab's result: the result already in memory, or else a fresh check of
  /// that address. Does nothing when neither is possible.
  Future<void> showLeakDetailsFor(String assetId) async {
    final asset = _emailById(assetId);
    if (asset == null) return;
    final known = _checkResults[asset.value];
    if (known != null) {
      _lastCheckResult = known;
      notifyListeners();
      return;
    }
    if (_checkable(asset.value)) await checkEmail(asset.value);
  }

  MonitoredAsset? _emailById(String id) {
    for (final a in _emailAssets) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Records that the person dealt with every breach known for [assetId]
  /// right now. Stored as the count and the breach names handled, so a later
  /// check that finds MORE breaches, or a breach by a new name, reopens the
  /// address; a check that finds the same ones does not.
  ///
  /// Also marks the address's alerts read, so the Alerts tab and Home never
  /// disagree. [reopenBreach] puts back only the ones this call marked.
  Future<void> markBreachHandled(String assetId) async {
    final asset = _emailById(assetId);
    if (asset == null) return;

    final newlyRead = <String>[
      for (final a in _alertsFor(asset))
        if (a.id.isNotEmpty && !_isAlertRead(a)) a.id,
    ];
    _handled[asset.id] = _HandledBreach(
      count: _evidenceCount(asset),
      names: _breachNamesFor(asset),
      at: DateTime.now(),
      readIds: newlyRead,
    );
    _readAlertIds.addAll(newlyRead);
    _updateStats();
    await _saveHandled();
    await _saveReadAlerts();
    notifyListeners();
  }

  /// Undoes [markBreachHandled] for [assetId].
  Future<void> reopenBreach(String assetId) async {
    final h = _handled.remove(assetId);
    if (h == null) return;
    _readAlertIds.removeAll(h.readIds);
    _updateStats();
    await _saveHandled();
    await _saveReadAlerts();
    notifyListeners();
  }

  Future<void> _loadHandled() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('DarkWebProvider: failed to open preferences: $e');
      return;
    }
    _handled.clear();
    final raw = _prefs?.getString(_prefsHandledKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      decoded.forEach((id, value) {
        try {
          _handled[id] =
              _HandledBreach.fromJson(Map<String, dynamic>.from(value as Map));
        } catch (e) {
          debugPrint('DarkWebProvider: skipping corrupt handled entry: $e');
        }
      });
    } catch (e) {
      debugPrint('DarkWebProvider: failed to restore handled breaches: $e');
    }
  }

  Future<void> _saveHandled() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(
        _prefsHandledKey,
        jsonEncode({
          for (final e in _handled.entries) e.key: e.value.toJson(),
        }),
      );
    } catch (e) {
      debugPrint('DarkWebProvider: failed to persist handled breaches: $e');
    }
  }

  /// Reads the Dark Web Monitoring master toggle (Settings → `prot_darkweb`).
  /// Fails open (enabled) when preferences are unavailable.
  Future<bool> _isMonitoringEnabledByUser() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      return _prefs?.getBool('prot_darkweb') ?? true;
    } catch (_) {
      return true;
    }
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
    if (_handled.remove(id) != null) await _saveHandled();
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
    // Honor the Dark Web Monitoring master toggle (Settings → prot_darkweb):
    // when off, skip automatic breach-alert polling. Explicit user checks
    // (checkEmail/checkPassword) remain available. Fails open.
    if (!await _isMonitoringEnabledByUser()) {
      _isLoading = false;
      notifyListeners();
      return;
    }

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

  /// Mark a single alert as read. Records its id in the locally-persisted
  /// read set (BreachAlert is immutable and the backend has no per-device
  /// read endpoint), refreshes unread state, and survives restarts.
  Future<void> markAlertAsRead(String id) async {
    if (id.isEmpty || _readAlertIds.contains(id)) return;
    _readAlertIds.add(id);
    _updateStats();
    await _saveReadAlerts();
    notifyListeners();
  }

  /// Mark every current alert as read.
  Future<void> markAllAlertsAsRead() async {
    final ids = _alerts.map((a) => a.id).where((id) => id.isNotEmpty).toSet();
    final before = _readAlertIds.length;
    _readAlertIds.addAll(ids);
    if (_readAlertIds.length == before) return;
    _updateStats();
    await _saveReadAlerts();
    notifyListeners();
  }

  /// True when an alert is read: either the backend already marked it read,
  /// or the user marked it read locally.
  bool _isAlertRead(BreachAlert alert) =>
      alert.isRead || _readAlertIds.contains(alert.id);

  /// Returns [alert] with [BreachAlert.isRead] reflecting the local read set.
  /// BreachAlert is immutable with no copyWith, so a locally-read alert is
  /// rebuilt through the public constructor.
  BreachAlert _reflectRead(BreachAlert alert) {
    if (alert.isRead || !_readAlertIds.contains(alert.id)) return alert;
    return BreachAlert(
      id: alert.id,
      assetId: alert.assetId,
      breachId: alert.breachId,
      assetType: alert.assetType,
      assetValue: alert.assetValue,
      breach: alert.breach,
      dataExposed: alert.dataExposed,
      severity: alert.severity,
      alertedAt: alert.alertedAt,
      ackedAt: alert.ackedAt,
      isRead: true,
    );
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

  /// Restore the locally-persisted set of read alert ids.
  Future<void> _loadReadAlerts() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('DarkWebProvider: failed to open preferences: $e');
      return;
    }
    _readAlertIds
      ..clear()
      ..addAll(_prefs!.getStringList(_prefsReadAlertsKey) ?? const []);
  }

  /// Persist the set of read alert ids.
  Future<void> _saveReadAlerts() async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setStringList(_prefsReadAlertsKey, _readAlertIds.toList());
    } catch (e) {
      debugPrint('DarkWebProvider: failed to persist read alerts: $e');
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
      if (!_isAlertRead(alert)) unread++;
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

/// What the person dealt with for one address, when they said so.
class _HandledBreach {
  /// The breach count known at that moment.
  final int count;

  /// The normalised breach names known at that moment.
  final Set<String> names;

  final DateTime at;

  /// Alert ids that marking handled turned read (so undo restores only them).
  final List<String> readIds;

  const _HandledBreach({
    required this.count,
    required this.names,
    required this.at,
    required this.readIds,
  });

  Map<String, dynamic> toJson() => {
        'count': count,
        'names': names.toList(),
        'at': at.toIso8601String(),
        'read_ids': readIds,
      };

  factory _HandledBreach.fromJson(Map<String, dynamic> json) => _HandledBreach(
        count: (json['count'] as num).toInt(),
        names: ((json['names'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet(),
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(1970),
        readIds: ((json['read_ids'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}
