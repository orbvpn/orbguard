// Social Media Monitoring Service
//
// Monitors social media for security and privacy concerns:
// - Account impersonation detection
// - Privacy setting audits
// - Data exposure monitoring
// - Reputation monitoring
// - Fake account detection
// - Social engineering attack detection

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/orbguard_api_client.dart';

/// Social media platform
enum SocialPlatform {
  facebook('Facebook', 'facebook.com'),
  instagram('Instagram', 'instagram.com'),
  twitter('Twitter/X', 'twitter.com'),
  linkedin('LinkedIn', 'linkedin.com'),
  tiktok('TikTok', 'tiktok.com'),
  snapchat('Snapchat', 'snapchat.com'),
  youtube('YouTube', 'youtube.com'),
  reddit('Reddit', 'reddit.com'),
  whatsapp('WhatsApp', 'whatsapp.com'),
  telegram('Telegram', 'telegram.org');

  final String displayName;
  final String domain;
  const SocialPlatform(this.displayName, this.domain);
}

/// Connected social account
class SocialAccount {
  final String id;
  final SocialPlatform platform;
  final String username;
  final String? displayName;
  final String? profileUrl;
  final bool isVerified;
  final DateTime? lastChecked;
  final PrivacyScore? privacyScore;

  SocialAccount({
    required this.id,
    required this.platform,
    required this.username,
    this.displayName,
    this.profileUrl,
    this.isVerified = false,
    this.lastChecked,
    this.privacyScore,
  });

  factory SocialAccount.fromJson(Map<String, dynamic> json) {
    return SocialAccount(
      id: json['id'] as String,
      platform: SocialPlatform.values.firstWhere(
        (p) => p.name == json['platform'],
        orElse: () => SocialPlatform.facebook,
      ),
      username: json['username'] as String,
      displayName: json['display_name'] as String?,
      profileUrl: json['profile_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      lastChecked: json['last_checked'] != null
          ? DateTime.parse(json['last_checked'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.name,
    'username': username,
    'display_name': displayName,
    'profile_url': profileUrl,
    'is_verified': isVerified,
    'last_checked': lastChecked?.toIso8601String(),
  };
}

/// Privacy score for an account
class PrivacyScore {
  final int overallScore; // 0-100
  final Map<String, PrivacySetting> settings;
  final List<PrivacyRisk> risks;
  final List<String> recommendations;
  final DateTime assessedAt;

  PrivacyScore({
    required this.overallScore,
    required this.settings,
    required this.risks,
    required this.recommendations,
    DateTime? assessedAt,
  }) : assessedAt = assessedAt ?? DateTime.now();

  String get riskLevel {
    if (overallScore >= 80) return 'Excellent';
    if (overallScore >= 60) return 'Good';
    if (overallScore >= 40) return 'Fair';
    if (overallScore >= 20) return 'Poor';
    return 'Critical';
  }
}

/// Privacy setting status
class PrivacySetting {
  final String name;
  final String currentValue;
  final String recommendedValue;
  final bool isOptimal;
  final String description;

  PrivacySetting({
    required this.name,
    required this.currentValue,
    required this.recommendedValue,
    required this.isOptimal,
    required this.description,
  });
}

/// Privacy risk
class PrivacyRisk {
  final String id;
  final String title;
  final String description;
  final RiskSeverity severity;
  final String remediation;

  PrivacyRisk({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.remediation,
  });
}

/// Risk severity levels
enum RiskSeverity {
  critical,
  high,
  medium,
  low,
  informational,
}

/// Impersonation alert
class ImpersonationAlert {
  final String id;
  final SocialPlatform platform;
  final String impersonatorUsername;
  final String? impersonatorProfileUrl;
  final String targetUsername;
  final double similarityScore;
  final List<String> indicators;
  final DateTime detectedAt;
  final AlertStatus status;

  ImpersonationAlert({
    required this.id,
    required this.platform,
    required this.impersonatorUsername,
    this.impersonatorProfileUrl,
    required this.targetUsername,
    required this.similarityScore,
    required this.indicators,
    DateTime? detectedAt,
    this.status = AlertStatus.active,
  }) : detectedAt = detectedAt ?? DateTime.now();

  String get threatLevel {
    if (similarityScore >= 0.9) return 'Critical';
    if (similarityScore >= 0.7) return 'High';
    if (similarityScore >= 0.5) return 'Medium';
    return 'Low';
  }
}

/// Alert status
enum AlertStatus {
  active,
  investigating,
  resolved,
  falsePositive,
}

/// Data exposure finding
class DataExposure {
  final String id;
  final ExposureType type;
  final String description;
  final String source;
  final String exposedData;
  final DateTime discoveredAt;
  final RiskSeverity severity;
  final String recommendation;

  DataExposure({
    required this.id,
    required this.type,
    required this.description,
    required this.source,
    required this.exposedData,
    DateTime? discoveredAt,
    required this.severity,
    required this.recommendation,
  }) : discoveredAt = discoveredAt ?? DateTime.now();
}

/// Types of data exposure
enum ExposureType {
  personalInfo('Personal Information', 'Name, address, phone number exposed'),
  financialInfo('Financial Information', 'Financial data exposed'),
  locationData('Location Data', 'Location information exposed'),
  contactInfo('Contact Information', 'Email, phone exposed'),
  photos('Photos', 'Personal photos exposed'),
  workInfo('Work Information', 'Employment details exposed'),
  familyInfo('Family Information', 'Family member details exposed'),
  credentials('Credentials', 'Login credentials exposed');

  final String displayName;
  final String description;
  const ExposureType(this.displayName, this.description);
}

/// Social media monitoring result
class MonitoringResult {
  final SocialAccount account;

  /// Privacy audit result. Null means the audit could not be performed
  /// (no backend signal) — it does NOT mean "perfect privacy".
  final PrivacyScore? privacyScore;
  final List<ImpersonationAlert> impersonationAlerts;
  final List<DataExposure> exposures;

  /// True only when a real backend exposure scan actually ran. When false,
  /// [exposures] being empty means "not analyzable", not "no exposures".
  final bool exposureAnalysisPerformed;
  final DateTime scanTime;

  MonitoringResult({
    required this.account,
    this.privacyScore,
    required this.impersonationAlerts,
    required this.exposures,
    this.exposureAnalysisPerformed = false,
    DateTime? scanTime,
  }) : scanTime = scanTime ?? DateTime.now();

  bool get hasIssues =>
      impersonationAlerts.isNotEmpty ||
      exposures.isNotEmpty ||
      (privacyScore != null && privacyScore!.overallScore < 60);
}

/// Presence verdict for a username on one platform, as returned by the real
/// backend username-scan. [unknown] means the platform blocked/ratelimited or
/// was unreachable — it is NOT a guess of absence.
enum PresenceStatus {
  found,
  notFound,
  unknown;

  static PresenceStatus fromApi(String? raw) {
    switch (raw) {
      case 'found':
        return PresenceStatus.found;
      case 'not_found':
        return PresenceStatus.notFound;
      default:
        // 'unknown' and any unexpected value are treated as not-determinable.
        return PresenceStatus.unknown;
    }
  }
}

/// One platform's username-presence result from the real backend scan.
class UsernamePresence {
  final String platform;
  final String url;
  final PresenceStatus status;

  UsernamePresence({
    required this.platform,
    required this.url,
    required this.status,
  });

  factory UsernamePresence.fromJson(Map<String, dynamic> json) {
    return UsernamePresence(
      platform: json['platform'] as String? ?? '',
      url: json['url'] as String? ?? '',
      status: PresenceStatus.fromApi(json['status'] as String?),
    );
  }
}

/// Result of a real username presence enumeration across public platforms
/// (POST /api/v1/social/username-scan). This is genuinely available — the
/// backend HTTP-checks each platform's public profile URL.
class UsernameScanResult {
  final String username;
  final List<UsernamePresence> results;
  final DateTime scannedAt;

  UsernameScanResult({
    required this.username,
    required this.results,
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  List<UsernamePresence> get found =>
      results.where((r) => r.status == PresenceStatus.found).toList();

  List<UsernamePresence> get notFound =>
      results.where((r) => r.status == PresenceStatus.notFound).toList();

  /// Platforms that could not be determined (blocked / ratelimited /
  /// unreachable). These are explicitly NOT counted as absent.
  List<UsernamePresence> get unknown =>
      results.where((r) => r.status == PresenceStatus.unknown).toList();

  int get foundCount => found.length;
  int get platformCount => results.length;

  factory UsernameScanResult.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'];
    final parsed = <UsernamePresence>[];
    if (rawResults is List) {
      for (final entry in rawResults.whereType<Map>()) {
        parsed.add(UsernamePresence.fromJson(entry.cast<String, dynamic>()));
      }
    }

    DateTime? scannedAt;
    final rawScannedAt = json['scanned_at'];
    if (rawScannedAt is String) {
      scannedAt = DateTime.tryParse(rawScannedAt);
    }

    return UsernameScanResult(
      username: json['username'] as String? ?? '',
      results: parsed,
      scannedAt: scannedAt,
    );
  }
}

/// Social Media Monitor Service
class SocialMediaMonitorService {
  // Analysis backend configuration.
  //
  // Username presence enumeration ([scanUsername]) is REAL: it calls the live
  // OrbGuard backend (POST /api/v1/social/username-scan).
  //
  // The other three capabilities — privacy audit, impersonation detection and
  // data-exposure scanning — genuinely require platform search APIs (Meta /
  // X / etc.) that we do not have. There is no backend for them, so [_apiKey]
  // is never set, [isBackendConfigured] is always false, and each of those
  // paths honestly returns "not analyzable" rather than fabricating a result.
  String? _apiKey;

  // Persistence key for the user-entered account list.
  static const String _accountsPrefsKey = 'social_media_monitor.accounts.v1';

  // Connected accounts
  final Map<String, SocialAccount> _accounts = {};

  // Alerts and findings
  final List<ImpersonationAlert> _alerts = [];
  final List<DataExposure> _exposures = [];

  // Stream controllers
  final _alertController = StreamController<ImpersonationAlert>.broadcast();
  final _exposureController = StreamController<DataExposure>.broadcast();
  final _resultController = StreamController<MonitoringResult>.broadcast();

  // Monitoring timer
  Timer? _monitorTimer;

  /// Stream of impersonation alerts
  Stream<ImpersonationAlert> get onAlert => _alertController.stream;

  /// Stream of data exposures
  Stream<DataExposure> get onExposure => _exposureController.stream;

  /// Stream of monitoring results
  Stream<MonitoringResult> get onResult => _resultController.stream;

  /// True when a backend API key is configured. Without it, privacy audits,
  /// exposure scans and impersonation checks are honestly reported as
  /// "not analyzable" rather than fabricated.
  bool get isBackendConfigured => _apiKey != null;

  /// Initialize the service.
  ///
  /// Loads the user-entered account list from disk so it survives restarts.
  /// Only the accounts the user typed are persisted — never any analysis
  /// output, since none is ever fabricated.
  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey;
    await _loadAccounts();
  }

  /// Add a social account to monitor
  Future<SocialAccount> addAccount(
    SocialPlatform platform,
    String username, {
    String? displayName,
  }) async {
    final accountId = '${platform.name}_$username';

    final account = SocialAccount(
      id: accountId,
      platform: platform,
      username: username,
      displayName: displayName,
      profileUrl: 'https://${platform.domain}/$username',
    );

    _accounts[accountId] = account;
    await _persistAccounts();

    // Only run an analysis pass when a live backend actually exists. Without
    // one there is nothing to check, so we do NOT fabricate a "last checked"
    // timestamp or any result — the account is stored exactly as entered.
    if (isBackendConfigured) {
      await scanAccount(accountId);
    }

    return _accounts[accountId]!;
  }

  /// Remove a monitored account
  Future<void> removeAccount(String accountId) async {
    _accounts.remove(accountId);
    await _persistAccounts();
  }

  /// Get all monitored accounts
  List<SocialAccount> getAccounts() => _accounts.values.toList();

  /// Enumerate public username presence across platforms via the REAL backend
  /// (POST /api/v1/social/username-scan).
  ///
  /// This is genuinely available and does not depend on [isBackendConfigured]
  /// (which gates the still-unavailable privacy/impersonation/exposure
  /// features). The backend HTTP-checks each platform's public profile URL and
  /// classifies it as found / not_found / unknown — "unknown" for platforms
  /// that block or ratelimit, never a fabricated absence. Throws [ApiError] on
  /// failure so callers can surface a real error state.
  Future<UsernameScanResult> scanUsername(String username) async {
    final data = await OrbGuardApiClient.instance.scanUsername(username);
    return UsernameScanResult.fromJson(data);
  }

  /// Load the persisted account list. Analysis fields are intentionally not
  /// restored (they are never fabricated); accounts come back with no score.
  Future<void> _loadAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountsPrefsKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is! List) return;

      _accounts.clear();
      for (final entry in decoded.whereType<Map>()) {
        final account = SocialAccount.fromJson(entry.cast<String, dynamic>());
        _accounts[account.id] = account;
      }
    } catch (e) {
      debugPrint('SocialMediaMonitor: failed to load persisted accounts: $e');
    }
  }

  /// Persist the user-entered account list.
  Future<void> _persistAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _accountsPrefsKey,
        json.encode(_accounts.values.map((a) => a.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('SocialMediaMonitor: failed to persist accounts: $e');
    }
  }

  /// Scan a single account
  Future<MonitoringResult> scanAccount(String accountId) async {
    final account = _accounts[accountId];
    if (account == null) {
      throw ArgumentError('Account not found: $accountId');
    }

    // Perform privacy audit (null = not analyzable, never fabricated)
    final privacyScore = await _auditPrivacy(account);

    // Check for impersonation
    final impersonationAlerts = await _checkImpersonation(account);

    // Check for data exposure (null = not analyzable, never fabricated)
    final exposureFindings = await _checkDataExposure(account);
    final exposures = exposureFindings ?? const <DataExposure>[];

    // Update account
    _accounts[accountId] = SocialAccount(
      id: account.id,
      platform: account.platform,
      username: account.username,
      displayName: account.displayName,
      profileUrl: account.profileUrl,
      isVerified: account.isVerified,
      lastChecked: DateTime.now(),
      privacyScore: privacyScore,
    );

    final result = MonitoringResult(
      account: _accounts[accountId]!,
      privacyScore: privacyScore,
      impersonationAlerts: impersonationAlerts,
      exposures: exposures,
      exposureAnalysisPerformed: exposureFindings != null,
    );

    _resultController.add(result);

    // Add alerts
    for (final alert in impersonationAlerts) {
      if (!_alerts.any((a) => a.impersonatorUsername == alert.impersonatorUsername)) {
        _alerts.add(alert);
        _alertController.add(alert);
      }
    }

    // Add exposures
    for (final exposure in exposures) {
      if (!_exposures.any((e) => e.id == exposure.id)) {
        _exposures.add(exposure);
        _exposureController.add(exposure);
      }
    }

    return result;
  }

  /// Scan all accounts
  Future<List<MonitoringResult>> scanAllAccounts() async {
    final results = <MonitoringResult>[];

    for (final accountId in _accounts.keys) {
      final result = await scanAccount(accountId);
      results.add(result);
    }

    return results;
  }

  /// Audit privacy settings.
  ///
  /// OrbGuard cannot read a user's actual privacy settings on any social
  /// platform from the device, so no score or "current setting" is ever
  /// fabricated. The audit runs only against the backend audit API; when no
  /// backend is configured (or the call fails) this returns null, which the
  /// UI must treat as "not analyzable" — never as a measured score.
  Future<PrivacyScore?> _auditPrivacy(SocialAccount account) async {
    // No privacy-audit backend exists (reading a user's actual platform
    // privacy settings needs platform APIs we don't have). Return null =
    // "not analyzable"; the UI surfaces this honestly and never as a score.
    return null;
  }

  /// Check for impersonation.
  ///
  /// Detecting OTHER accounts that impersonate the user requires a live
  /// similar-account search API (Meta / X / etc.) that we do not have, so this
  /// honestly returns no alerts rather than fabricating matches from username
  /// patterns.
  Future<List<ImpersonationAlert>> _checkImpersonation(
      SocialAccount account) async {
    return const <ImpersonationAlert>[];
  }

  /// Check for data exposure.
  ///
  /// Exposures are derived ONLY from real backend scan responses — never
  /// asserted from "typical" platform patterns. Returns null when the scan
  /// could not be performed (no backend configured, or the request failed),
  /// which callers surface as an explicit "not analyzable" state.
  Future<List<DataExposure>?> _checkDataExposure(SocialAccount account) async {
    // No data-exposure scan backend exists. Return null = "not analyzable"
    // (distinct from an empty list, which would mean "scanned and clean"); the
    // UI surfaces this honestly rather than implying the data was checked.
    return null;
  }

  /// Start continuous monitoring
  void startMonitoring({Duration interval = const Duration(hours: 24)}) {
    stopMonitoring();

    _monitorTimer = Timer.periodic(interval, (_) {
      scanAllAccounts();
    });

    // Initial scan
    scanAllAccounts();
  }

  /// Stop continuous monitoring
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
  }

  /// Dismiss an impersonation alert the user has reviewed.
  ///
  /// This only clears it from the on-device list — there is no backend to
  /// notify. Impersonation alerts only ever originate from a live backend
  /// scan, so without one this list is empty and dismiss is a no-op by nature
  /// (never a fabricated "handled" state).
  void dismissAlert(String alertId) {
    _alerts.removeWhere((a) => a.id == alertId);
  }

  /// Get all alerts
  List<ImpersonationAlert> getAlerts({AlertStatus? status}) {
    var alerts = _alerts.toList();

    if (status != null) {
      alerts = alerts.where((a) => a.status == status).toList();
    }

    return alerts..sort((a, b) => b.detectedAt.compareTo(a.detectedAt));
  }

  /// Get all exposures
  List<DataExposure> getExposures({RiskSeverity? minSeverity}) {
    var exposures = _exposures.toList();

    if (minSeverity != null) {
      exposures = exposures.where((e) =>
        e.severity.index <= minSeverity.index
      ).toList();
    }

    return exposures..sort((a, b) => a.severity.index.compareTo(b.severity.index));
  }

  /// Report an impersonator through the backend.
  ///
  /// Returns true only when the backend actually accepted the report. There
  /// is no client-side reporting capability, so without a configured backend
  /// this honestly returns false instead of faking success.
  Future<bool> reportImpersonator(String alertId) async {
    // Impersonation alerts only ever originate from a live similar-account
    // search backend, which does not exist — so this list is always empty and
    // there is nothing (and no backend) to report to. Honestly returns false
    // instead of faking a "reported" success.
    return false;
  }

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'monitored_accounts': _accounts.length,
      'active_alerts': _alerts.where((a) => a.status == AlertStatus.active).length,
      'data_exposures': _exposures.length,
      'is_monitoring': _monitorTimer != null,
    };
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _alertController.close();
    _exposureController.close();
    _resultController.close();
  }
}
