/// URL Provider
/// State management for URL/web protection features
library url_provider;

import 'package:flutter/foundation.dart';

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

  UrlListEntry({
    required this.domain,
    required this.addedAt,
    this.reason,
  });
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
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  final List<UrlCheckEntry> _history = [];
  final List<UrlListEntry> _whitelist = [];
  final List<UrlListEntry> _blacklist = [];
  UrlStats _stats = UrlStats();
  DomainReputation? _currentDomainDetails;

  bool _isLoading = false;
  bool _isCheckingUrl = false;
  String? _error;

  // Getters
  List<UrlCheckEntry> get history => List.unmodifiable(_history);
  List<UrlListEntry> get whitelist => List.unmodifiable(_whitelist);
  List<UrlListEntry> get blacklist => List.unmodifiable(_blacklist);
  UrlStats get stats => _stats;
  DomainReputation? get currentDomainDetails => _currentDomainDetails;
  bool get isLoading => _isLoading;
  bool get isCheckingUrl => _isCheckingUrl;
  String? get error => _error;

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
  }

  /// Check a URL
  Future<UrlReputationResult?> checkUrl(String url) async {
    if (url.isEmpty) return null;

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
        severity: SeverityLevel.info,
        riskScore: 0.0,
        categories: [UrlCategory.safe],
        threats: [],
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
        severity: SeverityLevel.high,
        riskScore: 1.0,
        categories: [],
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

  /// Add domain to whitelist
  void addToWhitelist(String domain, {String? reason}) {
    final normalized = _extractDomain(domain);
    if (_whitelist.any((e) => e.domain == normalized)) return;

    // Remove from blacklist if present
    _blacklist.removeWhere((e) => e.domain == normalized);

    _whitelist.add(UrlListEntry(
      domain: normalized,
      addedAt: DateTime.now(),
      reason: reason,
    ));
    _updateStats();
    _saveLists();
    notifyListeners();
  }

  /// Remove domain from whitelist
  void removeFromWhitelist(String domain) {
    _whitelist.removeWhere((e) => e.domain == domain);
    _updateStats();
    _saveLists();
    notifyListeners();
  }

  /// Add domain to blacklist
  void addToBlacklist(String domain, {String? reason}) {
    final normalized = _extractDomain(domain);
    if (_blacklist.any((e) => e.domain == normalized)) return;

    // Remove from whitelist if present
    _whitelist.removeWhere((e) => e.domain == normalized);

    _blacklist.add(UrlListEntry(
      domain: normalized,
      addedAt: DateTime.now(),
      reason: reason,
    ));
    _updateStats();
    _saveLists();
    notifyListeners();
  }

  /// Remove domain from blacklist
  void removeFromBlacklist(String domain) {
    _blacklist.removeWhere((e) => e.domain == domain);
    _updateStats();
    _saveLists();
    notifyListeners();
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

  /// Load history from storage
  Future<void> loadHistory() async {
    // TODO: Load from persistent storage
  }

  /// Save history to storage
  Future<void> _saveHistory() async {
    // TODO: Save to persistent storage
  }

  /// Load whitelist/blacklist from storage
  Future<void> loadLists() async {
    // TODO: Load from persistent storage
  }

  /// Save lists to storage
  Future<void> _saveLists() async {
    // TODO: Save to persistent storage
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
        for (final cat in entry.result!.categories) {
          if (cat == UrlCategory.phishing) phishing++;
          if (cat == UrlCategory.malware) malware++;
          if (cat == UrlCategory.scam) scams++;
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
