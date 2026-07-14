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
import 'package:http/http.dart' as http;

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

/// Social Media Monitor Service
class SocialMediaMonitorService {
  // API configuration
  static const String _apiBaseUrl = 'https://api.orbguard.io/v1/social';
  String? _apiKey;

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

  /// Initialize the service
  Future<void> initialize({String? apiKey}) async {
    _apiKey = apiKey;
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

    // Perform initial scan
    await scanAccount(accountId);

    return account;
  }

  /// Remove a monitored account
  void removeAccount(String accountId) {
    _accounts.remove(accountId);
  }

  /// Get all monitored accounts
  List<SocialAccount> getAccounts() => _accounts.values.toList();

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
    if (_apiKey == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/privacy-audit'
            '?platform=${account.platform.name}'
            '&username=${Uri.encodeComponent(account.username)}'),
        headers: {'Authorization': 'Bearer $_apiKey'},
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final score = data['overall_score'];
      if (score is! num) return null;

      final settings = <String, PrivacySetting>{};
      final rawSettings = data['settings'];
      if (rawSettings is Map<String, dynamic>) {
        rawSettings.forEach((key, value) {
          if (value is Map<String, dynamic>) {
            settings[key] = PrivacySetting(
              name: value['name'] as String? ?? key,
              currentValue: value['current_value'] as String? ?? '',
              recommendedValue: value['recommended_value'] as String? ?? '',
              isOptimal: value['is_optimal'] as bool? ?? false,
              description: value['description'] as String? ?? '',
            );
          }
        });
      }

      final risks = <PrivacyRisk>[];
      final rawRisks = data['risks'];
      if (rawRisks is List) {
        for (final raw in rawRisks.whereType<Map<String, dynamic>>()) {
          risks.add(PrivacyRisk(
            id: raw['id'] as String? ??
                'risk_${DateTime.now().millisecondsSinceEpoch}',
            title: raw['title'] as String? ?? '',
            description: raw['description'] as String? ?? '',
            severity: RiskSeverity.values.firstWhere(
              (s) => s.name == raw['severity'],
              orElse: () => RiskSeverity.informational,
            ),
            remediation: raw['remediation'] as String? ?? '',
          ));
        }
      }

      return PrivacyScore(
        overallScore: score.toInt().clamp(0, 100),
        settings: settings,
        risks: risks,
        recommendations: (data['recommendations'] as List?)
                ?.whereType<String>()
                .toList() ??
            const [],
      );
    } catch (e) {
      debugPrint('Privacy audit failed: $e');
      return null;
    }
  }

  /// Check for impersonation
  Future<List<ImpersonationAlert>> _checkImpersonation(SocialAccount account) async {
    final alerts = <ImpersonationAlert>[];

    // Impersonation detection requires a live similar-account search API.
    // Without one this check honestly returns no alerts rather than
    // fabricating matches from username patterns.
    if (_apiKey != null) {
      try {
        final response = await http.get(
          Uri.parse('$_apiBaseUrl/impersonation-check'),
          headers: {'Authorization': 'Bearer $_apiKey'},
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body) as Map<String, dynamic>;
          final rawAlerts = data['alerts'];
          if (rawAlerts is List) {
            for (final raw in rawAlerts.whereType<Map<String, dynamic>>()) {
              alerts.add(ImpersonationAlert(
                id: raw['id'] as String? ??
                    'imp_${DateTime.now().millisecondsSinceEpoch}',
                platform: account.platform,
                impersonatorUsername:
                    raw['impersonator_username'] as String? ?? '',
                targetUsername: account.username,
                similarityScore:
                    (raw['similarity_score'] as num?)?.toDouble() ?? 0.0,
                indicators: (raw['indicators'] as List?)
                        ?.whereType<String>()
                        .toList() ??
                    const [],
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('Impersonation check failed: $e');
      }
    }

    return alerts;
  }

  /// Check for data exposure.
  ///
  /// Exposures are derived ONLY from real backend scan responses — never
  /// asserted from "typical" platform patterns. Returns null when the scan
  /// could not be performed (no backend configured, or the request failed),
  /// which callers surface as an explicit "not analyzable" state.
  Future<List<DataExposure>?> _checkDataExposure(SocialAccount account) async {
    if (_apiKey == null) return null;

    try {
      final response = await http.get(
        Uri.parse('$_apiBaseUrl/data-exposure'
            '?platform=${account.platform.name}'
            '&username=${Uri.encodeComponent(account.username)}'),
        headers: {'Authorization': 'Bearer $_apiKey'},
      );

      if (response.statusCode != 200) return null;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final rawExposures = data['exposures'];
      if (rawExposures is! List) return null;

      final exposures = <DataExposure>[];
      for (final raw in rawExposures.whereType<Map<String, dynamic>>()) {
        exposures.add(DataExposure(
          id: raw['id'] as String? ??
              'exp_${account.id}_${DateTime.now().millisecondsSinceEpoch}',
          type: ExposureType.values.firstWhere(
            (t) => t.name == raw['type'],
            orElse: () => ExposureType.personalInfo,
          ),
          description: raw['description'] as String? ?? '',
          source: raw['source'] as String? ?? account.platform.displayName,
          exposedData: raw['exposed_data'] as String? ?? '',
          severity: RiskSeverity.values.firstWhere(
            (s) => s.name == raw['severity'],
            orElse: () => RiskSeverity.informational,
          ),
          recommendation: raw['recommendation'] as String? ?? '',
        ));
      }

      // An empty list here is a real "analyzed and clean" verdict.
      return exposures;
    } catch (e) {
      debugPrint('Data exposure check failed: $e');
      return null;
    }
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
    final alert = _alerts.firstWhere(
      (a) => a.id == alertId,
      orElse: () => throw ArgumentError('Alert not found'),
    );

    if (_apiKey == null) return false;

    try {
      final response = await http.post(
        Uri.parse('$_apiBaseUrl/report-impersonator'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'alert_id': alert.id,
          'platform': alert.platform.name,
          'impersonator_username': alert.impersonatorUsername,
          'target_username': alert.targetUsername,
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('Impersonator report failed: $e');
      return false;
    }
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
