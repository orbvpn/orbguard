/// URL Provider
/// State management for URL/web protection features
library url_provider;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/api_config.dart';
import '../services/api/orbguard_api_client.dart';
import '../models/api/url_reputation.dart';
import '../models/api/threat_indicator.dart';

/// URL check history entry
class UrlCheckEntry {
  final String id;
  final String url;
  final DateTime checkedAt;
  final UrlReputationResult? result;
  final bool isPending;

  UrlCheckEntry({
    required this.id,
    required this.url,
    required this.checkedAt,
    this.result,
    this.isPending = false,
  });

  UrlCheckEntry copyWith({
    String? id,
    String? url,
    DateTime? checkedAt,
    UrlReputationResult? result,
    bool? isPending,
  }) {
    return UrlCheckEntry(
      id: id ?? this.id,
      url: url ?? this.url,
      checkedAt: checkedAt ?? this.checkedAt,
      result: result ?? this.result,
      isPending: isPending ?? this.isPending,
    );
  }

  bool get isSafe => result?.isSafe ?? true;
  bool get isBlocked => result?.shouldBlock ?? false;
}

/// Whitelist/Blacklist entry
class UrlListEntry {
  final String domain;
  final DateTime addedAt;
  final String? reason;

  /// Server-side entry id (uuid) once synced with the backend list.
  final String? serverId;

  /// True while the entry only exists locally and still needs to be pushed
  /// to the backend.
  final bool pendingSync;

  UrlListEntry({
    required this.domain,
    required this.addedAt,
    this.reason,
    this.serverId,
    this.pendingSync = false,
  });

  UrlListEntry copyWith({
    String? domain,
    DateTime? addedAt,
    String? reason,
    String? serverId,
    bool? pendingSync,
  }) {
    return UrlListEntry(
      domain: domain ?? this.domain,
      addedAt: addedAt ?? this.addedAt,
      reason: reason ?? this.reason,
      serverId: serverId ?? this.serverId,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  Map<String, dynamic> toJson() => {
        'domain': domain,
        'added_at': addedAt.toIso8601String(),
        if (reason != null) 'reason': reason,
        if (serverId != null) 'server_id': serverId,
        'pending_sync': pendingSync,
      };

  factory UrlListEntry.fromJson(Map<String, dynamic> json) => UrlListEntry(
        domain: json['domain'] as String,
        addedAt: DateTime.parse(json['added_at'] as String),
        reason: json['reason'] as String?,
        serverId: json['server_id'] as String?,
        pendingSync: json['pending_sync'] as bool? ?? false,
      );
}

/// URL protection stats
class UrlStats {
  final int totalChecked;
  final int threatsBlocked;
  final int safeSites;
  final int phishingBlocked;
  final int malwareBlocked;
  final int scamsBlocked;
  final int whitelistCount;
  final int blacklistCount;

  UrlStats({
    this.totalChecked = 0,
    this.threatsBlocked = 0,
    this.safeSites = 0,
    this.phishingBlocked = 0,
    this.malwareBlocked = 0,
    this.scamsBlocked = 0,
    this.whitelistCount = 0,
    this.blacklistCount = 0,
  });
}

/// URL Protection Provider
class UrlProvider extends ChangeNotifier {
  static const _prefsHistoryKey = 'url_check_history';
  static const _prefsWhitelistKey = 'url_whitelist';
  static const _prefsBlacklistKey = 'url_blacklist';
  static const _prefsPendingRemovalsKey = 'url_list_pending_removals';
  static const _maxPersistedEntries = 100;

  /// Master URL-protection flag persisted by the Settings screen
  /// (ProtectionSettings → SettingsProvider, key `prot_url`).
  static const _kMasterProtectionKey = 'prot_url';

  static final String _whitelistPath =
      '${ApiConfig.apiVersion}/url/whitelist';
  static final String _blacklistPath =
      '${ApiConfig.apiVersion}/url/blacklist';
  static String _listEntryPath(String id) =>
      '${ApiConfig.apiVersion}/url/list/$id';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;
  SharedPreferences? _prefs;

  // State
  final List<UrlCheckEntry> _history = [];
  final List<UrlListEntry> _whitelist = [];
  final List<UrlListEntry> _blacklist = [];

  /// Server entry ids whose DELETE failed and must be retried on next sync.
  final Set<String> _pendingRemovals = {};

  UrlStats _stats = UrlStats();
  DomainReputation? _currentDomainDetails;

  bool _isLoading = false;
  bool _isCheckingUrl = false;
  bool _listsSynced = false;
  String? _listSyncError;
  String? _error;

  // Getters
  List<UrlCheckEntry> get history => List.unmodifiable(_history);
  List<UrlListEntry> get whitelist => List.unmodifiable(_whitelist);
  List<UrlListEntry> get blacklist => List.unmodifiable(_blacklist);
  UrlStats get stats => _stats;
  DomainReputation? get currentDomainDetails => _currentDomainDetails;
  bool get isLoading => _isLoading;
  bool get isCheckingUrl => _isCheckingUrl;

  /// True once the local custom lists reflect the backend state.
  bool get listsSynced => _listsSynced;

  /// Last backend list-sync failure, if any (local cache stays usable).
  String? get listSyncError => _listSyncError;

  String? get error => _error;

  /// True when the user turned URL protection off in the app Settings
  /// (`prot_url`). While set, URL checks are skipped entirely.
  bool get protectionDisabledByUser => _protectionDisabledByUser;
  bool _protectionDisabledByUser = false;

  /// Reads the persisted Settings flag. Fails open (enabled) when
  /// preferences are unavailable — an unreadable setting is not a user
  /// opt-out.
  Future<bool> _isProtectionEnabledByUser() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('UrlProvider: cannot read protection setting: $e');
    }
    final enabled = _prefs?.getBool(_kMasterProtectionKey) ?? true;
    _protectionDisabledByUser = !enabled;
    return enabled;
  }

  /// Recent threats from history
  List<UrlCheckEntry> get recentThreats => _history
      .where((e) => e.result != null && !e.result!.isSafe)
      .take(10)
      .toList();

  /// Initialize provider
  Future<void> init() async {
    await loadHistory();
    await loadLists();
    _updateStats();
    notifyListeners();
    await syncListsWithBackend();
  }

  /// Check a URL
  Future<UrlReputationResult?> checkUrl(String url) async {
    if (url.isEmpty) return null;

    if (!await _isProtectionEnabledByUser()) {
      _error = 'URL protection is disabled in Settings.';
      notifyListeners();
      return null;
    }

    // Normalize URL
    final normalizedUrl = _normalizeUrl(url);

    // Check if in whitelist
    final domain = _extractDomain(normalizedUrl);
    if (_whitelist.any((e) => e.domain == domain)) {
      return UrlReputationResult(
        url: normalizedUrl,
        domain: domain,
        isSafe: true,
        shouldBlock: false,
        category: UrlCategory.safe,
        threatLevel: SeverityLevel.info,
        confidence: 1.0,
        recommendation: 'This domain is on your whitelist.',
        checkedAt: DateTime.now(),
      );
    }

    // Check if in blacklist
    if (_blacklist.any((e) => e.domain == domain)) {
      return UrlReputationResult(
        url: normalizedUrl,
        domain: domain,
        isSafe: false,
        shouldBlock: true,
        category: UrlCategory.unknown,
        threatLevel: SeverityLevel.high,
        confidence: 1.0,
        blockReason: 'This domain is on your blacklist.',
        threats: [
          UrlThreat(
            type: 'blacklisted',
            severity: SeverityLevel.high,
            description: 'This domain is on your blacklist.',
          )
        ],
        recommendation: 'This domain has been manually blocked.',
        checkedAt: DateTime.now(),
      );
    }

    // Create history entry
    final entryId = DateTime.now().millisecondsSinceEpoch.toString();
    final entry = UrlCheckEntry(
      id: entryId,
      url: normalizedUrl,
      checkedAt: DateTime.now(),
      isPending: true,
    );
    _history.insert(0, entry);
    _isCheckingUrl = true;
    notifyListeners();

    try {
      final result = await _api.checkUrl(normalizedUrl);

      // Update history entry
      final index = _history.indexWhere((e) => e.id == entryId);
      if (index >= 0) {
        _history[index] = entry.copyWith(
          result: result,
          isPending: false,
        );
      }

      _updateStats();
      _isCheckingUrl = false;
      await _saveHistory();
      notifyListeners();
      return result;
    } catch (e) {
      // Remove pending entry on error
      _history.removeWhere((e) => e.id == entryId);
      _isCheckingUrl = false;
      _error = 'Failed to check URL: $e';
      notifyListeners();
      return null;
    }
  }

  /// Check multiple URLs
  Future<List<UrlReputationResult>> checkUrls(List<String> urls) async {
    if (urls.isEmpty) return [];

    if (!await _isProtectionEnabledByUser()) {
      _error = 'URL protection is disabled in Settings.';
      notifyListeners();
      return [];
    }

    _isCheckingUrl = true;
    notifyListeners();

    try {
      final results = await _api.checkUrlsBatch(urls);

      // Add to history
      for (final result in results) {
        final entry = UrlCheckEntry(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          url: result.url,
          checkedAt: DateTime.now(),
          result: result,
        );
        _history.insert(0, entry);
      }

      _updateStats();
      _isCheckingUrl = false;
      await _saveHistory();
      notifyListeners();
      return results;
    } catch (e) {
      _isCheckingUrl = false;
      _error = 'Failed to check URLs: $e';
      notifyListeners();
      return [];
    }
  }

  /// Get detailed domain reputation
  Future<DomainReputation?> getDomainDetails(String domain) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentDomainDetails = await _api.getDomainReputation(domain);
      _isLoading = false;
      notifyListeners();
      return _currentDomainDetails;
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to get domain details: $e';
      notifyListeners();
      return null;
    }
  }

  /// Clear current domain details
  void clearDomainDetails() {
    _currentDomainDetails = null;
    notifyListeners();
  }

  /// Add domain to whitelist (local + live backend list).
  Future<void> addToWhitelist(String domain, {String? reason}) async {
    await _addToList(domain, reason: reason, isWhitelist: true);
  }

  /// Remove domain from whitelist (local + live backend list).
  Future<void> removeFromWhitelist(String domain) async {
    await _removeFromList(domain, isWhitelist: true);
  }

  /// Add domain to blacklist (local + live backend list).
  Future<void> addToBlacklist(String domain, {String? reason}) async {
    await _addToList(domain, reason: reason, isWhitelist: false);
  }

  /// Remove domain from blacklist (local + live backend list).
  Future<void> removeFromBlacklist(String domain) async {
    await _removeFromList(domain, isWhitelist: false);
  }

  Future<void> _addToList(
    String domain, {
    String? reason,
    required bool isWhitelist,
  }) async {
    final normalized = _extractDomain(domain);
    final target = isWhitelist ? _whitelist : _blacklist;
    final opposite = isWhitelist ? _blacklist : _whitelist;
    if (target.any((e) => e.domain == normalized)) return;

    // Remove from the opposite list if present (server-side too).
    final conflicting =
        opposite.where((e) => e.domain == normalized).toList();
    for (final entry in conflicting) {
      await _removeFromList(entry.domain, isWhitelist: !isWhitelist);
    }

    var entry = UrlListEntry(
      domain: normalized,
      addedAt: DateTime.now(),
      reason: reason,
      pendingSync: true,
    );
    target.add(entry);
    _updateStats();
    notifyListeners();

    // Push to the live backend list.
    try {
      final created = await _api.post<Map<String, dynamic>>(
        isWhitelist ? _whitelistPath : _blacklistPath,
        data: {
          'domain': normalized,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      entry = entry.copyWith(
        serverId: created['id'] as String?,
        pendingSync: false,
      );
      final index = target.indexWhere((e) => e.domain == normalized);
      if (index >= 0) target[index] = entry;
      _listSyncError = null;
    } catch (e) {
      // Keep the local entry marked pending; it is re-pushed on next sync.
      _listSyncError = 'Failed to sync list entry "$normalized": $e';
      debugPrint('UrlProvider: $_listSyncError');
    }

    await _saveLists();
    notifyListeners();
  }

  Future<void> _removeFromList(
    String domain, {
    required bool isWhitelist,
  }) async {
    final target = isWhitelist ? _whitelist : _blacklist;
    final index = target.indexWhere((e) => e.domain == domain);
    if (index < 0) return;

    final entry = target.removeAt(index);
    _updateStats();
    notifyListeners();

    final serverId = entry.serverId;
    if (serverId != null) {
      try {
        await _api.delete<dynamic>(_listEntryPath(serverId));
        _listSyncError = null;
      } catch (e) {
        // Retry the server-side delete on the next sync; locally the entry
        // is gone, and the pull during sync skips ids queued for removal.
        _pendingRemovals.add(serverId);
        _listSyncError =
            'Failed to remove list entry "$domain" from the backend: $e';
        debugPrint('UrlProvider: $_listSyncError');
      }
    }

    await _saveLists();
    notifyListeners();
  }

  /// Synchronize local custom lists with the live backend
  /// (GET/POST /url/whitelist|blacklist, DELETE /url/list/{id}).
  Future<void> syncListsWithBackend() async {
    try {
      // 1. Retry pending server-side removals.
      for (final id in _pendingRemovals.toList()) {
        try {
          await _api.delete<dynamic>(_listEntryPath(id));
          _pendingRemovals.remove(id);
        } catch (e) {
          final message = e.toString();
          // A 404 means the entry is already gone server-side.
          if (message.contains('404') || message.contains('not found')) {
            _pendingRemovals.remove(id);
          } else {
            rethrow;
          }
        }
      }

      // 2. Push local entries that never reached the backend.
      for (final list in [_whitelist, _blacklist]) {
        final isWhitelist = identical(list, _whitelist);
        for (var i = 0; i < list.length; i++) {
          final entry = list[i];
          if (!entry.pendingSync && entry.serverId != null) continue;
          final created = await _api.post<Map<String, dynamic>>(
            isWhitelist ? _whitelistPath : _blacklistPath,
            data: {
              'domain': entry.domain,
              if (entry.reason != null && entry.reason!.isNotEmpty)
                'reason': entry.reason,
            },
          );
          list[i] = entry.copyWith(
            serverId: created['id'] as String?,
            pendingSync: false,
          );
        }
      }

      // 3. Pull the authoritative server state.
      final whitelistResponse =
          await _api.get<Map<String, dynamic>>(_whitelistPath);
      final blacklistResponse =
          await _api.get<Map<String, dynamic>>(_blacklistPath);

      _whitelist
        ..clear()
        ..addAll(_entriesFromServer(whitelistResponse));
      _blacklist
        ..clear()
        ..addAll(_entriesFromServer(blacklistResponse));

      _listsSynced = true;
      _listSyncError = null;
    } catch (e) {
      _listsSynced = false;
      _listSyncError = 'List sync with backend failed: $e';
      debugPrint('UrlProvider: $_listSyncError');
    }

    _updateStats();
    await _saveLists();
    notifyListeners();
  }

  List<UrlListEntry> _entriesFromServer(Map<String, dynamic> response) {
    final entries = response['entries'] as List<dynamic>? ?? const [];
    final result = <UrlListEntry>[];
    for (final raw in entries) {
      final map = Map<String, dynamic>.from(raw as Map);
      final id = map['id'] as String?;
      if (id != null && _pendingRemovals.contains(id)) continue;
      if (map['is_active'] == false) continue;
      final domain = (map['domain'] as String?)?.isNotEmpty == true
          ? map['domain'] as String
          : (map['url'] as String? ?? map['pattern'] as String? ?? '');
      if (domain.isEmpty) continue;
      result.add(UrlListEntry(
        domain: domain,
        addedAt: map['created_at'] != null
            ? DateTime.tryParse(map['created_at'] as String) ?? DateTime.now()
            : DateTime.now(),
        reason: map['reason'] as String?,
        serverId: id,
      ));
    }
    return result;
  }

  /// Check if domain is whitelisted
  bool isWhitelisted(String domain) {
    final normalized = _extractDomain(domain);
    return _whitelist.any((e) => e.domain == normalized);
  }

  /// Check if domain is blacklisted
  bool isBlacklisted(String domain) {
    final normalized = _extractDomain(domain);
    return _blacklist.any((e) => e.domain == normalized);
  }

  /// Clear history
  void clearHistory() {
    _history.clear();
    _updateStats();
    _saveHistory();
    notifyListeners();
  }

  /// Remove single history entry
  void removeFromHistory(String id) {
    _history.removeWhere((e) => e.id == id);
    _updateStats();
    _saveHistory();
    notifyListeners();
  }

  /// Load history from persistent storage.
  Future<void> loadHistory() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('UrlProvider: failed to open preferences: $e');
      return;
    }

    final raw = _prefs!.getString(_prefsHistoryKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final restored = <UrlCheckEntry>[];
      for (final item in decoded) {
        try {
          final map = Map<String, dynamic>.from(item as Map);
          final resultJson = map['result'];
          restored.add(UrlCheckEntry(
            id: map['id'] as String,
            url: map['url'] as String,
            checkedAt: DateTime.parse(map['checked_at'] as String),
            result: resultJson != null
                ? UrlReputationResult.fromJson(
                    Map<String, dynamic>.from(resultJson as Map))
                : null,
          ));
        } catch (e) {
          debugPrint('UrlProvider: skipping corrupt history entry: $e');
        }
      }
      _history
        ..clear()
        ..addAll(restored);
    } catch (e) {
      debugPrint('UrlProvider: failed to restore check history: $e');
    }
  }

  /// Save history to persistent storage.
  Future<void> _saveHistory() async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      final payload = _history
          .where((e) => !e.isPending)
          .take(_maxPersistedEntries)
          .map((e) => {
                'id': e.id,
                'url': e.url,
                'checked_at': e.checkedAt.toIso8601String(),
                if (e.result != null) 'result': _resultToJson(e.result!),
              })
          .toList();
      await prefs.setString(_prefsHistoryKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('UrlProvider: failed to persist check history: $e');
    }
  }

  /// Serialize a [UrlReputationResult] back to the backend wire shape so
  /// [UrlReputationResult.fromJson] can round-trip it on restore.
  Map<String, dynamic> _resultToJson(UrlReputationResult result) => {
        'url': result.url,
        'domain': result.domain,
        'is_safe': result.isSafe,
        'should_block': result.shouldBlock,
        'category': result.category.value,
        'threat_level': result.threatLevel.value,
        'confidence': result.confidence,
        if (result.description != null) 'description': result.description,
        'warnings': result.warnings,
        if (result.blockReason != null) 'block_reason': result.blockReason,
        'allow_override': result.allowOverride,
        if (result.campaignName != null) 'campaign_name': result.campaignName,
        if (result.threatActorName != null)
          'threat_actor_name': result.threatActorName,
        'cache_hit': result.cacheHit,
        'checked_at': result.checkedAt.toIso8601String(),
      };

  /// Load whitelist/blacklist (and pending removals) from local storage.
  Future<void> loadLists() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('UrlProvider: failed to open preferences: $e');
      return;
    }

    _whitelist
      ..clear()
      ..addAll(_decodeListPref(_prefsWhitelistKey));
    _blacklist
      ..clear()
      ..addAll(_decodeListPref(_prefsBlacklistKey));
    _pendingRemovals
      ..clear()
      ..addAll(_prefs!.getStringList(_prefsPendingRemovalsKey) ?? const []);
  }

  List<UrlListEntry> _decodeListPref(String key) {
    final raw = _prefs!.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) =>
              UrlListEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('UrlProvider: failed to restore list "$key": $e');
      return const [];
    }
  }

  /// Save lists to local storage.
  Future<void> _saveLists() async {
    final prefs = _prefs;
    if (prefs == null) return;

    try {
      await prefs.setString(
        _prefsWhitelistKey,
        jsonEncode(_whitelist.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _prefsBlacklistKey,
        jsonEncode(_blacklist.map((e) => e.toJson()).toList()),
      );
      await prefs.setStringList(
          _prefsPendingRemovalsKey, _pendingRemovals.toList());
    } catch (e) {
      debugPrint('UrlProvider: failed to persist lists: $e');
    }
  }

  /// Update stats
  void _updateStats() {
    int threats = 0;
    int safe = 0;
    int phishing = 0;
    int malware = 0;
    int scams = 0;

    for (final entry in _history) {
      if (entry.result == null) continue;

      if (entry.result!.isSafe) {
        safe++;
      } else {
        threats++;
        switch (entry.result!.category) {
          case UrlCategory.phishing:
          case UrlCategory.typosquatting:
            phishing++;
            break;
          case UrlCategory.malware:
          case UrlCategory.ransomware:
          case UrlCategory.cryptojacking:
          case UrlCategory.cryptomining:
          case UrlCategory.commandAndControl:
          case UrlCategory.botnet:
          case UrlCategory.exploit:
          case UrlCategory.driveByDownload:
            malware++;
            break;
          case UrlCategory.scam:
            scams++;
            break;
          default:
            break;
        }
      }
    }

    _stats = UrlStats(
      totalChecked: _history.where((e) => e.result != null).length,
      threatsBlocked: threats,
      safeSites: safe,
      phishingBlocked: phishing,
      malwareBlocked: malware,
      scamsBlocked: scams,
      whitelistCount: _whitelist.length,
      blacklistCount: _blacklist.length,
    );
  }

  /// Normalize URL
  String _normalizeUrl(String url) {
    var normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    return normalized;
  }

  /// Extract domain from URL
  String _extractDomain(String url) {
    try {
      final uri = Uri.parse(_normalizeUrl(url));
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
