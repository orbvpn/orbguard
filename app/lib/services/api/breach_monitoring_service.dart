// Breach Monitoring Service
//
// All breach lookups are proxied through the OrbGuard Lab backend
// (`/api/v1/darkweb/*`) so that no third-party API credentials (HIBP,
// LeakCheck, Intelligence X) ever ship inside the client binary. The
// backend owns provider selection, credentials, rate limiting, and
// result aggregation.
//
// Password checks remain privacy-preserving: the password is hashed
// with SHA-1 on-device and only the first five characters of the hash
// (k-anonymity prefix) are sent to the backend.

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../models/api/sms_analysis.dart';
import 'api_interceptors.dart';
import 'orbguard_api_client.dart';

/// Capabilities exposed by this service.
enum BreachCapability {
  emailCheck('Email breach check'),
  passwordCheck('Password breach check'),
  domainCheck('Domain breach check'),
  breachCatalog('Known-breach catalog'),
  breachStats('Breach corpus statistics');

  final String displayName;
  const BreachCapability(this.displayName);
}

/// Result wrapper for capabilities that may not yet be served by the
/// backend. When [isSupported] is false, [data] is null and
/// [pendingReason] explains which backend endpoint is missing. Callers
/// must surface this state honestly instead of showing empty results
/// as "no breaches found".
class BreachCapabilityResult<T> {
  final BreachCapability capability;
  final bool isSupported;
  final T? data;
  final String? pendingReason;
  final DateTime checkedAt;

  BreachCapabilityResult.supported({
    required this.capability,
    required T this.data,
  })  : isSupported = true,
        pendingReason = null,
        checkedAt = DateTime.now();

  BreachCapabilityResult.pendingBackendSupport({
    required this.capability,
    required String this.pendingReason,
  })  : isSupported = false,
        data = null,
        checkedAt = DateTime.now();
}

/// Breach Monitoring Service — thin facade over the OrbGuard Lab
/// dark-web endpoints. Holds a short-lived in-memory cache so repeated
/// checks of the same asset within a session do not re-hit the backend.
class BreachMonitoringService {
  final OrbGuardApiClient _api;
  final Map<String, _CachedEmailResult> _emailCache = {};
  final Duration _cacheDuration;

  BreachMonitoringService({
    OrbGuardApiClient? apiClient,
    Duration cacheDuration = const Duration(hours: 1),
  })  : _api = apiClient ?? OrbGuardApiClient.instance,
        _cacheDuration = cacheDuration;

  /// Check an email address against the backend breach aggregator
  /// (POST /api/v1/darkweb/check/email). The backend queries its
  /// configured providers (HIBP today; LeakCheck/IntelX as they are
  /// enabled server-side) and returns the merged result.
  Future<BreachCheckResult> checkEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) {
      throw ArgumentError.value(email, 'email', 'must not be empty');
    }

    final cached = _emailCache[normalized];
    if (cached != null &&
        DateTime.now().difference(cached.cachedAt) < _cacheDuration) {
      return cached.result;
    }

    try {
      final result = await _api.checkEmailBreaches(normalized);
      _emailCache[normalized] = _CachedEmailResult(result, DateTime.now());
      return result;
    } on ApiError catch (e) {
      debugPrint(
        'BreachMonitoringService: email breach check failed '
        '(${e.statusCode}): ${e.message}',
      );
      rethrow;
    }
  }

  /// Check a password using SHA-1 k-anonymity
  /// (POST /api/v1/darkweb/check/password). Only the first five hex
  /// characters of the SHA-1 hash leave the device; the backend proxies
  /// the range query so no third-party endpoint is contacted directly.
  Future<PasswordBreachResult> checkPassword(String password) async {
    if (password.isEmpty) {
      throw ArgumentError.value('<redacted>', 'password', 'must not be empty');
    }

    final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    final hashPrefix = hash.substring(0, 5);

    try {
      return await _api.checkPasswordBreaches(hashPrefix);
    } on ApiError catch (e) {
      debugPrint(
        'BreachMonitoringService: password breach check failed '
        '(${e.statusCode}): ${e.message}',
      );
      rethrow;
    }
  }

  /// Get breach alerts for the device's monitored assets
  /// (GET /api/v1/darkweb/alerts).
  Future<List<BreachAlert>> getBreachAlerts() async {
    try {
      return await _api.getBreachAlerts();
    } on ApiError catch (e) {
      debugPrint(
        'BreachMonitoringService: breach alerts fetch failed '
        '(${e.statusCode}): ${e.message}',
      );
      rethrow;
    }
  }

  /// Domain-wide breach lookup. The backend does not expose a
  /// domain-scoped breach endpoint yet, so this capability is reported
  /// as pending rather than returning fabricated or empty "safe"
  /// results.
  Future<BreachCapabilityResult<List<BreachInfo>>> checkDomain(
    String domain,
  ) async {
    debugPrint(
      'BreachMonitoringService: domain breach check for "$domain" is '
      'disabled — backend endpoint /api/v1/darkweb/check/domain is not '
      'available yet.',
    );
    return BreachCapabilityResult.pendingBackendSupport(
      capability: BreachCapability.domainCheck,
      pendingReason:
          'Domain breach lookup requires backend support (planned: '
          'POST /api/v1/darkweb/check/domain proxying the HIBP domain '
          'search API).',
    );
  }

  /// Full known-breach catalog. The backend route
  /// GET /api/v1/darkweb/breaches exists but does not serve catalog
  /// data yet, so this capability is reported as pending instead of
  /// returning an empty catalog as if it were real.
  Future<BreachCapabilityResult<List<BreachInfo>>> getAllBreaches() async {
    debugPrint(
      'BreachMonitoringService: known-breach catalog is disabled — '
      'GET /api/v1/darkweb/breaches does not serve catalog data yet.',
    );
    return BreachCapabilityResult.pendingBackendSupport(
      capability: BreachCapability.breachCatalog,
      pendingReason:
          'Breach catalog requires the backend to serve real data from '
          'GET /api/v1/darkweb/breaches (HIBP all-breaches feed).',
    );
  }

  /// Aggregate statistics over the breach corpus (total breaches,
  /// exposed accounts, data-class distribution). Depends on the breach
  /// catalog, which the backend does not serve yet.
  Future<BreachCapabilityResult<BreachStats>> getStats() async {
    debugPrint(
      'BreachMonitoringService: breach corpus statistics are disabled — '
      'they depend on the breach catalog endpoint, which is not served '
      'by the backend yet.',
    );
    return BreachCapabilityResult.pendingBackendSupport(
      capability: BreachCapability.breachStats,
      pendingReason:
          'Breach statistics require the backend breach catalog '
          '(GET /api/v1/darkweb/breaches) to serve real data.',
    );
  }

  /// Clear the in-memory result cache.
  void clearCache() {
    _emailCache.clear();
  }
}

class _CachedEmailResult {
  final BreachCheckResult result;
  final DateTime cachedAt;

  _CachedEmailResult(this.result, this.cachedAt);
}

/// Breach statistics
class BreachStats {
  final int totalBreaches;
  final int totalAccounts;
  final Map<String, int> dataClassCounts;
  final Map<int, int> yearlyBreaches;
  final DateTime lastUpdated;

  BreachStats({
    required this.totalBreaches,
    required this.totalAccounts,
    required this.dataClassCounts,
    required this.yearlyBreaches,
    required this.lastUpdated,
  });

  String get formattedTotalAccounts {
    if (totalAccounts >= 1000000000) {
      return '${(totalAccounts / 1000000000).toStringAsFixed(1)}B';
    } else if (totalAccounts >= 1000000) {
      return '${(totalAccounts / 1000000).toStringAsFixed(1)}M';
    } else if (totalAccounts >= 1000) {
      return '${(totalAccounts / 1000).toStringAsFixed(1)}K';
    }
    return totalAccounts.toString();
  }

  List<MapEntry<String, int>> get topDataClasses {
    final sorted = dataClassCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).toList();
  }
}
