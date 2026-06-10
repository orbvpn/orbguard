/// URL Reputation Models
/// Models for URL/web protection from OrbGuard Lab API
///
/// Wire formats in this file mirror the live Go backend:
/// - POST /url/check            -> models.URLCheckResponse
/// - GET  /url/reputation/{d}   -> models.URLReputation (DNS/TLS/RDAP enriched)
/// - POST /url/report           -> 201 {id, status, created_at, message}
/// - POST /apps/analyze         -> models.AppAnalysisResult (nested analyses)
/// - POST /network/wifi/audit   -> models.WiFiAuditResult

import 'threat_indicator.dart';

/// URL categories (mirrors backend models.URLCategory)
enum UrlCategory {
  safe('safe'),
  phishing('phishing'),
  malware('malware'),
  scam('scam'),
  spam('spam'),
  adult('adult'),
  gambling('gambling'),
  drugs('drugs'),
  violence('violence'),
  ads('ads'),
  tracking('tracking'),
  cryptomining('cryptomining'),
  cryptojacking('cryptojacking'),
  ransomware('ransomware'),
  commandAndControl('command_and_control'),
  botnet('botnet'),
  exploit('exploit'),
  driveByDownload('drive_by_download'),
  suspicious('suspicious'),
  uncategorized('uncategorized'),
  parked('parked'),
  suspiciousTld('suspicious_tld'),
  typosquatting('typosquatting'),
  unknown('unknown');

  final String value;
  const UrlCategory(this.value);

  static UrlCategory fromString(String value) {
    return UrlCategory.values.firstWhere(
      (e) => e.value == value,
      orElse: () => UrlCategory.unknown,
    );
  }

  String get displayName {
    switch (this) {
      case UrlCategory.safe:
        return 'Safe';
      case UrlCategory.phishing:
        return 'Phishing';
      case UrlCategory.malware:
        return 'Malware';
      case UrlCategory.scam:
        return 'Scam';
      case UrlCategory.spam:
        return 'Spam';
      case UrlCategory.adult:
        return 'Adult Content';
      case UrlCategory.gambling:
        return 'Gambling';
      case UrlCategory.drugs:
        return 'Drugs';
      case UrlCategory.violence:
        return 'Violence';
      case UrlCategory.ads:
        return 'Advertising';
      case UrlCategory.tracking:
        return 'Tracking';
      case UrlCategory.cryptomining:
        return 'Cryptomining';
      case UrlCategory.cryptojacking:
        return 'Cryptojacking';
      case UrlCategory.ransomware:
        return 'Ransomware';
      case UrlCategory.commandAndControl:
        return 'Command & Control';
      case UrlCategory.botnet:
        return 'Botnet';
      case UrlCategory.exploit:
        return 'Exploit';
      case UrlCategory.driveByDownload:
        return 'Drive-by Download';
      case UrlCategory.suspicious:
        return 'Suspicious';
      case UrlCategory.uncategorized:
        return 'Uncategorized';
      case UrlCategory.parked:
        return 'Parked Domain';
      case UrlCategory.suspiciousTld:
        return 'Suspicious TLD';
      case UrlCategory.typosquatting:
        return 'Typosquatting';
      case UrlCategory.unknown:
        return 'Unknown';
    }
  }

  bool get isDangerous =>
      this == UrlCategory.phishing ||
      this == UrlCategory.malware ||
      this == UrlCategory.scam ||
      this == UrlCategory.ransomware ||
      this == UrlCategory.cryptojacking ||
      this == UrlCategory.commandAndControl ||
      this == UrlCategory.botnet ||
      this == UrlCategory.exploit ||
      this == UrlCategory.driveByDownload;
}

/// URL reputation result (mirrors backend models.URLCheckResponse)
class UrlReputationResult {
  final String url;
  final String domain;
  final bool isSafe;
  final bool shouldBlock;
  final UrlCategory category;
  final SeverityLevel threatLevel;
  final double confidence;
  final String? description;
  final List<String> warnings;
  final String? blockReason;
  final bool allowOverride;
  final String? campaignName;
  final String? threatActorName;
  final bool cacheHit;
  final DateTime checkedAt;
  final List<UrlThreat> threats;
  final String? recommendation;

  UrlReputationResult({
    required this.url,
    required this.domain,
    required this.isSafe,
    required this.shouldBlock,
    required this.category,
    required this.threatLevel,
    required this.confidence,
    this.description,
    this.warnings = const [],
    this.blockReason,
    this.allowOverride = false,
    this.campaignName,
    this.threatActorName,
    this.cacheHit = false,
    required this.checkedAt,
    this.threats = const [],
    this.recommendation,
  });

  factory UrlReputationResult.fromJson(Map<String, dynamic> json) {
    final url = json['url'] as String?;
    final isSafe = json['is_safe'] as bool?;
    final shouldBlock = json['should_block'] as bool?;
    final categoryStr = json['category'] as String?;
    final threatLevelStr = json['threat_level'] as String?;
    final checkedAtStr = json['checked_at'] as String?;

    if (url == null ||
        isSafe == null ||
        shouldBlock == null ||
        categoryStr == null ||
        threatLevelStr == null ||
        checkedAtStr == null) {
      throw FormatException(
        'URL check response missing required fields '
        '(url/is_safe/should_block/category/threat_level/checked_at); '
        'received keys: ${json.keys.join(', ')}',
      );
    }

    final category = UrlCategory.fromString(categoryStr);
    final threatLevel = SeverityLevel.fromString(threatLevelStr);
    final description = json['description'] as String?;
    final blockReason = json['block_reason'] as String?;
    final warnings =
        (json['warnings'] as List<dynamic>?)?.cast<String>() ?? const <String>[];
    final campaignName = json['campaign_name'] as String?;
    final threatActorName = json['threat_actor_name'] as String?;

    // Derive the threat list shown in the UI from the real fields the
    // backend emits for an unsafe URL.
    final threats = <UrlThreat>[];
    if (!isSafe || shouldBlock) {
      final detail = blockReason ?? description;
      threats.add(UrlThreat(
        type: category.value,
        severity: threatLevel,
        description: (detail != null && detail.isNotEmpty)
            ? detail
            : 'Flagged as ${category.displayName.toLowerCase()}',
        source: campaignName != null && campaignName.isNotEmpty
            ? 'campaign: $campaignName'
            : null,
      ));
    }

    String? recommendation;
    if (shouldBlock && blockReason != null && blockReason.isNotEmpty) {
      recommendation = blockReason;
    } else if (warnings.isNotEmpty) {
      recommendation = warnings.join(' ');
    }

    return UrlReputationResult(
      url: url,
      domain: json['domain'] as String? ?? '',
      isSafe: isSafe,
      shouldBlock: shouldBlock,
      category: category,
      threatLevel: threatLevel,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      description: description,
      warnings: warnings,
      blockReason: blockReason,
      allowOverride: json['allow_override'] as bool? ?? false,
      campaignName: campaignName,
      threatActorName: threatActorName,
      cacheHit: json['cache_hit'] as bool? ?? false,
      checkedAt: DateTime.parse(checkedAtStr),
      threats: threats,
      recommendation: recommendation,
    );
  }

  /// Severity for UI display, derived from the backend threat_level.
  SeverityLevel get severity => threatLevel;

  /// Risk score (0.0-1.0) derived from threat level weighted by the
  /// backend's confidence in the classification.
  double get riskScore {
    final double base;
    switch (threatLevel) {
      case SeverityLevel.critical:
        base = 1.0;
        break;
      case SeverityLevel.high:
        base = 0.85;
        break;
      case SeverityLevel.medium:
        base = 0.6;
        break;
      case SeverityLevel.low:
        base = 0.35;
        break;
      case SeverityLevel.info:
      case SeverityLevel.unknown:
        base = 0.0;
        break;
    }
    if (base == 0.0) return 0.0;
    final weight = confidence > 0 ? confidence.clamp(0.0, 1.0) : 1.0;
    return base * weight;
  }

  /// Category list for UI chips (backend emits a single category).
  List<UrlCategory> get categories =>
      category == UrlCategory.unknown ? const [] : [category];

  /// Get the primary category
  UrlCategory? get primaryCategory =>
      category == UrlCategory.unknown ? null : category;

  /// Check if URL has dangerous categories
  bool get hasDangerousCategories => category.isDangerous;
}

/// URL threat info (derived client-side from the check response)
class UrlThreat {
  final String type;
  final SeverityLevel severity;
  final String description;
  final String? source;
  final DateTime? firstSeen;

  UrlThreat({
    required this.type,
    required this.severity,
    required this.description,
    this.source,
    this.firstSeen,
  });
}

/// Result of POST /url/report (201 Created)
class UrlReportResult {
  final String id;
  final String status;
  final DateTime createdAt;
  final String? message;

  UrlReportResult({
    required this.id,
    required this.status,
    required this.createdAt,
    this.message,
  });

  factory UrlReportResult.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final status = json['status'] as String?;
    final createdAt = json['created_at'] as String?;
    if (id == null || status == null || createdAt == null) {
      throw FormatException(
        'URL report response missing required fields (id/status/created_at); '
        'received keys: ${json.keys.join(', ')}',
      );
    }
    return UrlReportResult(
      id: id,
      status: status,
      createdAt: DateTime.parse(createdAt),
      message: json['message'] as String?,
    );
  }
}

/// Detailed domain reputation (mirrors backend models.URLReputation as
/// returned by GET /url/reputation/{domain}: threat-intel DB hit, built-in
/// whitelist hit, or live DNS/TLS/RDAP enrichment with heuristic scoring).
class DomainReputation {
  final String id;
  final String domain;
  final UrlCategory category;
  final SeverityLevel threatLevel;
  final double confidence;
  final bool isMalicious;
  final bool isBlocked;
  final List<String> sources;
  final List<String> tags;
  final String? description;

  /// Registration date when RDAP data was obtainable (backend first_seen).
  final DateTime? registeredAt;
  final DateTime? lastChecked;

  /// TLS certificate validity; null when the backend could not inspect TLS.
  final bool? certValid;
  final String? certIssuer;

  final String? ipAddress;
  final String? asn;
  final String? country;
  final String? registrar;

  final bool isShortened;
  final bool isNewDomain;
  final bool hasSuspiciousTld;

  /// Risk score 0.0-1.0 as computed by the backend.
  final double riskScore;

  DomainReputation({
    required this.id,
    required this.domain,
    required this.category,
    required this.threatLevel,
    required this.confidence,
    required this.isMalicious,
    required this.isBlocked,
    this.sources = const [],
    this.tags = const [],
    this.description,
    this.registeredAt,
    this.lastChecked,
    this.certValid,
    this.certIssuer,
    this.ipAddress,
    this.asn,
    this.country,
    this.registrar,
    this.isShortened = false,
    this.isNewDomain = false,
    this.hasSuspiciousTld = false,
    required this.riskScore,
  });

  factory DomainReputation.fromJson(Map<String, dynamic> json) {
    final domain = json['domain'] as String?;
    final categoryStr = json['category'] as String?;
    final threatLevelStr = json['threat_level'] as String?;
    final riskScore = (json['risk_score'] as num?)?.toDouble();
    final isMalicious = json['is_malicious'] as bool?;
    final isBlocked = json['is_blocked'] as bool?;

    if (domain == null ||
        categoryStr == null ||
        threatLevelStr == null ||
        riskScore == null ||
        isMalicious == null ||
        isBlocked == null) {
      throw FormatException(
        'Domain reputation response missing required fields '
        '(domain/category/threat_level/risk_score/is_malicious/is_blocked); '
        'received keys: ${json.keys.join(', ')}',
      );
    }

    return DomainReputation(
      id: json['id'] as String? ?? '',
      domain: domain,
      category: UrlCategory.fromString(categoryStr),
      threatLevel: SeverityLevel.fromString(threatLevelStr),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      isMalicious: isMalicious,
      isBlocked: isBlocked,
      sources: (json['sources'] as List<dynamic>?)?.cast<String>() ?? const [],
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
      description: json['description'] as String?,
      registeredAt: _parseNonZeroTime(json['first_seen'] as String?),
      lastChecked: _parseNonZeroTime(json['last_checked'] as String?),
      certValid: json['cert_valid'] as bool?,
      certIssuer: json['cert_issuer'] as String?,
      ipAddress: json['ip_address'] as String?,
      asn: json['asn'] as String?,
      country: json['country'] as String?,
      registrar: json['registrar'] as String?,
      isShortened: json['is_shortened'] as bool? ?? false,
      isNewDomain: json['is_new_domain'] as bool? ?? false,
      hasSuspiciousTld: json['has_suspicious_tld'] as bool? ?? false,
      riskScore: riskScore,
    );
  }

  /// Go encodes zero time.Time as 0001-01-01T00:00:00Z; treat it as absent.
  static DateTime? _parseNonZeroTime(String? value) {
    if (value == null || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.year <= 1) return null;
    return parsed;
  }

  /// Reputation score 0-100 (higher is better), derived from the backend
  /// risk score (0.0-1.0, higher is worse).
  double get reputationScore => ((1.0 - riskScore) * 100).clamp(0.0, 100.0);

  /// Domain age in days from the RDAP registration date; 0 when the
  /// registration date is unknown (check [registeredAt] for null).
  int get ageInDays => registeredAt != null
      ? DateTime.now().difference(registeredAt!).inDays
      : 0;

  /// Country reported by hosting/registration data (when available).
  String? get registrantCountry =>
      (country != null && country!.isNotEmpty) ? country : null;

  /// ASN organisation (backend emits asn only when known).
  String? get asnOrg => (asn != null && asn!.isNotEmpty) ? asn : null;

  /// Whether the domain is on a blocklist (threat-intel DB hit).
  bool get isOnBlocklist => isBlocked;

  /// TLS certificate details, present when the backend inspected TLS.
  SslInfo? get ssl => certValid != null
      ? SslInfo(
          hasValidSsl: certValid!,
          issuer: (certIssuer != null && certIssuer!.isNotEmpty)
              ? certIssuer
              : null,
        )
      : null;

  /// Check if domain is newly registered (backend computes from RDAP age)
  bool get isNewlyRegistered => isNewDomain;

  /// Check if domain is suspicious based on backend classification
  bool get isSuspicious =>
      isMalicious ||
      isBlocked ||
      category == UrlCategory.suspicious ||
      riskScore >= 0.45;
}

/// TLS certificate information (subset the backend can observe)
class SslInfo {
  final bool hasValidSsl;
  final String? issuer;

  /// The backend folds expiry into cert validity (cert_valid is false for
  /// expired certificates), so no separate expiry flag is emitted.
  final bool isExpired;
  final String? grade;

  SslInfo({
    required this.hasValidSsl,
    this.issuer,
    this.isExpired = false,
    this.grade,
  });
}

/// A single permission entry sent to the app analyzer
/// (mirrors backend models.AppPermission request fields).
class AppPermissionInfo {
  final String name;
  final bool isGranted;
  final bool isDangerous;

  AppPermissionInfo({
    required this.name,
    required this.isGranted,
    required this.isDangerous,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'is_granted': isGranted,
        'is_dangerous': isDangerous,
      };

  /// Android dangerous (runtime) permissions, matching the analyzer's
  /// server-side classification list.
  static const Set<String> _dangerousPermissions = {
    'android.permission.READ_CONTACTS',
    'android.permission.WRITE_CONTACTS',
    'android.permission.READ_CALL_LOG',
    'android.permission.WRITE_CALL_LOG',
    'android.permission.PROCESS_OUTGOING_CALLS',
    'android.permission.READ_SMS',
    'android.permission.SEND_SMS',
    'android.permission.RECEIVE_SMS',
    'android.permission.READ_PHONE_STATE',
    'android.permission.CALL_PHONE',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.ACCESS_BACKGROUND_LOCATION',
    'android.permission.CAMERA',
    'android.permission.RECORD_AUDIO',
    'android.permission.READ_EXTERNAL_STORAGE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.READ_CALENDAR',
    'android.permission.WRITE_CALENDAR',
    'android.permission.BODY_SENSORS',
    'android.permission.ACTIVITY_RECOGNITION',
    'android.permission.READ_MEDIA_IMAGES',
    'android.permission.READ_MEDIA_VIDEO',
    'android.permission.READ_MEDIA_AUDIO',
  };

  static bool isDangerousPermission(String name) =>
      _dangerousPermissions.contains(name);
}

/// App analysis request (mirrors backend models.AppAnalysisRequest)
class AppAnalysisRequest {
  final String packageName;
  final String? appName;
  final String? versionName;
  final int? versionCode;
  final List<AppPermissionInfo> permissions;

  /// Raw install source (installer package name or backend enum value);
  /// mapped to the backend enum in [toJson].
  final String installSource;
  final int? targetSdk;
  final int? minSdk;
  final bool? isSystemApp;
  final String? signatureHash;
  final String? apkHash;
  final String? deviceId;

  /// SDK/library package prefixes detected inside the app; the backend
  /// matches these against its known-tracker list.
  final List<String>? detectedLibraries;

  AppAnalysisRequest({
    required this.packageName,
    this.appName,
    this.versionName,
    this.versionCode,
    required this.permissions,
    required this.installSource,
    this.targetSdk,
    this.minSdk,
    this.isSystemApp,
    this.signatureHash,
    this.apkHash,
    this.deviceId,
    this.detectedLibraries,
  });

  /// Maps an installer package name (or pre-mapped value) to the backend
  /// AppInstallSource enum: play_store, app_store, sideloaded, adb,
  /// preloaded, enterprise, unknown.
  static String mapInstallSource(String source) {
    final s = source.trim().toLowerCase();
    if (s.isEmpty || s == 'unknown') return 'unknown';
    switch (s) {
      case 'play_store':
      case 'com.android.vending':
        return 'play_store';
      case 'app_store':
      case 'com.apple.appstore':
        return 'app_store';
      case 'adb':
        return 'adb';
      case 'preloaded':
      case 'system':
      case 'preinstalled':
        return 'preloaded';
      case 'enterprise':
        return 'enterprise';
      case 'sideloaded':
        return 'sideloaded';
      default:
        // Any other installer package (browsers, file managers,
        // third-party stores) counts as sideloading.
        return 'sideloaded';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'package_name': packageName,
      if (appName != null) 'app_name': appName,
      if (versionName != null) 'version_name': versionName,
      if (versionCode != null) 'version_code': versionCode,
      'permissions': permissions.map((p) => p.toJson()).toList(),
      'install_source': mapInstallSource(installSource),
      if (targetSdk != null) 'target_sdk': targetSdk,
      if (minSdk != null) 'min_sdk': minSdk,
      if (isSystemApp != null) 'is_system_app': isSystemApp,
      if (signatureHash != null) 'signature_hash': signatureHash,
      if (apkHash != null) 'apk_hash': apkHash,
      if (deviceId != null) 'device_id': deviceId,
      if (detectedLibraries != null && detectedLibraries!.isNotEmpty)
        'detected_libraries': detectedLibraries,
    };
  }
}

/// Permission-based risk analysis (mirrors backend PermissionRiskAnalysis)
class PermissionRiskAnalysis {
  final double score; // 0-100
  final int dangerousCount;
  final int grantedDangerous;
  final Map<String, int> permissionGroups;
  final List<DangerousPermissionCombo> dangerousCombos;
  final List<String> concerns;

  PermissionRiskAnalysis({
    required this.score,
    required this.dangerousCount,
    required this.grantedDangerous,
    this.permissionGroups = const {},
    this.dangerousCombos = const [],
    this.concerns = const [],
  });

  factory PermissionRiskAnalysis.fromJson(Map<String, dynamic> json) {
    return PermissionRiskAnalysis(
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      dangerousCount: json['dangerous_count'] as int? ?? 0,
      grantedDangerous: json['granted_dangerous'] as int? ?? 0,
      permissionGroups: (json['permission_groups'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          const {},
      dangerousCombos: (json['dangerous_combos'] as List<dynamic>?)
              ?.map((c) =>
                  DangerousPermissionCombo.fromJson(c as Map<String, dynamic>))
              .toList() ??
          const [],
      concerns:
          (json['concerns'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}

/// A risky combination of permissions (mirrors backend DangerousPermissionCombo)
class DangerousPermissionCombo {
  final List<String> permissions;
  final String riskLevel;
  final String description;

  DangerousPermissionCombo({
    required this.permissions,
    required this.riskLevel,
    required this.description,
  });

  factory DangerousPermissionCombo.fromJson(Map<String, dynamic> json) {
    return DangerousPermissionCombo(
      permissions:
          (json['permissions'] as List<dynamic>?)?.cast<String>() ?? const [],
      riskLevel: json['risk_level'] as String? ?? 'low',
      description: json['description'] as String? ?? '',
    );
  }
}

/// What data an app may collect (mirrors backend DataCollectionInfo)
class DataCollectionInfo {
  final bool collectsLocation;
  final bool collectsContacts;
  final bool collectsCallLogs;
  final bool collectsSms;
  final bool collectsCamera;
  final bool collectsMicrophone;
  final bool collectsStorage;
  final bool collectsDeviceInfo;
  final bool collectsUsageStats;
  final bool collectsBiometrics;
  final bool hasInternetAccess;
  final bool canRunInBackground;

  DataCollectionInfo({
    this.collectsLocation = false,
    this.collectsContacts = false,
    this.collectsCallLogs = false,
    this.collectsSms = false,
    this.collectsCamera = false,
    this.collectsMicrophone = false,
    this.collectsStorage = false,
    this.collectsDeviceInfo = false,
    this.collectsUsageStats = false,
    this.collectsBiometrics = false,
    this.hasInternetAccess = false,
    this.canRunInBackground = false,
  });

  factory DataCollectionInfo.fromJson(Map<String, dynamic> json) {
    return DataCollectionInfo(
      collectsLocation: json['collects_location'] as bool? ?? false,
      collectsContacts: json['collects_contacts'] as bool? ?? false,
      collectsCallLogs: json['collects_call_logs'] as bool? ?? false,
      collectsSms: json['collects_sms'] as bool? ?? false,
      collectsCamera: json['collects_camera'] as bool? ?? false,
      collectsMicrophone: json['collects_microphone'] as bool? ?? false,
      collectsStorage: json['collects_storage'] as bool? ?? false,
      collectsDeviceInfo: json['collects_device_info'] as bool? ?? false,
      collectsUsageStats: json['collects_usage_stats'] as bool? ?? false,
      collectsBiometrics: json['collects_biometrics'] as bool? ?? false,
      hasInternetAccess: json['has_internet_access'] as bool? ?? false,
      canRunInBackground: json['can_run_in_background'] as bool? ?? false,
    );
  }
}

/// Privacy-focused risk analysis (mirrors backend PrivacyRiskAnalysis)
class PrivacyRiskAnalysis {
  final double score; // 0-100
  final List<String> dataAccessTypes;
  final List<TrackerInfo> trackerSdks;
  final List<String> networkDestinations;
  final DataCollectionInfo dataCollection;
  final List<String> concerns;

  PrivacyRiskAnalysis({
    required this.score,
    this.dataAccessTypes = const [],
    this.trackerSdks = const [],
    this.networkDestinations = const [],
    required this.dataCollection,
    this.concerns = const [],
  });

  factory PrivacyRiskAnalysis.fromJson(Map<String, dynamic> json) {
    return PrivacyRiskAnalysis(
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      dataAccessTypes: (json['data_access_types'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      trackerSdks: (json['tracker_sdks'] as List<dynamic>?)
              ?.map((t) => TrackerInfo.fromJson(t as Map<String, dynamic>))
              .toList() ??
          const [],
      networkDestinations: (json['network_destinations'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      dataCollection: json['data_collection'] != null
          ? DataCollectionInfo.fromJson(
              json['data_collection'] as Map<String, dynamic>)
          : DataCollectionInfo(),
      concerns:
          (json['concerns'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}

/// Security-focused risk analysis (mirrors backend SecurityRiskAnalysis)
class SecurityRiskAnalysis {
  final double score; // 0-100
  final bool isSideloaded;
  final bool isObfuscated;
  final bool hasDebugEnabled;
  final bool hasBackupAllowed;
  final bool usesHttp;
  final bool hasWeakCrypto;
  final bool targetsOldSdk;
  final bool signatureValid;
  final bool signatureTrusted;
  final List<String> knownVulnerabilities;
  final List<String> concerns;

  SecurityRiskAnalysis({
    required this.score,
    this.isSideloaded = false,
    this.isObfuscated = false,
    this.hasDebugEnabled = false,
    this.hasBackupAllowed = false,
    this.usesHttp = false,
    this.hasWeakCrypto = false,
    this.targetsOldSdk = false,
    this.signatureValid = false,
    this.signatureTrusted = false,
    this.knownVulnerabilities = const [],
    this.concerns = const [],
  });

  factory SecurityRiskAnalysis.fromJson(Map<String, dynamic> json) {
    return SecurityRiskAnalysis(
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      isSideloaded: json['is_sideloaded'] as bool? ?? false,
      isObfuscated: json['is_obfuscated'] as bool? ?? false,
      hasDebugEnabled: json['has_debug_enabled'] as bool? ?? false,
      hasBackupAllowed: json['has_backup_allowed'] as bool? ?? false,
      usesHttp: json['uses_http'] as bool? ?? false,
      hasWeakCrypto: json['has_weak_crypto'] as bool? ?? false,
      targetsOldSdk: json['targets_old_sdk'] as bool? ?? false,
      signatureValid: json['signature_valid'] as bool? ?? false,
      signatureTrusted: json['signature_trusted'] as bool? ?? false,
      knownVulnerabilities: (json['known_vulnerabilities'] as List<dynamic>?)
              ?.cast<String>() ??
          const [],
      concerns:
          (json['concerns'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}

/// Threat intelligence match (mirrors backend ThreatIntelMatch)
class ThreatIntelMatch {
  final bool isKnownMalware;
  final bool isPotentiallyHarmful;
  final String? malwareFamily;
  final String? campaignId;
  final String? threatActorId;
  final List<String> indicatorIds;
  final String detectionSource;
  final DateTime? firstSeen;

  ThreatIntelMatch({
    required this.isKnownMalware,
    required this.isPotentiallyHarmful,
    this.malwareFamily,
    this.campaignId,
    this.threatActorId,
    this.indicatorIds = const [],
    required this.detectionSource,
    this.firstSeen,
  });

  factory ThreatIntelMatch.fromJson(Map<String, dynamic> json) {
    return ThreatIntelMatch(
      isKnownMalware: json['is_known_malware'] as bool? ?? false,
      isPotentiallyHarmful: json['is_potentially_harmful'] as bool? ?? false,
      malwareFamily: json['malware_family'] as String?,
      campaignId: json['campaign_id'] as String?,
      threatActorId: json['threat_actor_id'] as String?,
      indicatorIds:
          (json['indicator_ids'] as List<dynamic>?)?.cast<String>() ??
              const [],
      detectionSource: json['detection_source'] as String? ?? '',
      firstSeen: json['first_seen'] != null
          ? DomainReputation._parseNonZeroTime(json['first_seen'] as String)
          : null,
    );
  }
}

/// A security recommendation for an app (mirrors backend AppRecommendation)
class AppRecommendation {
  final String id;
  final String priority; // critical, high, medium, low
  final String category; // permission, privacy, security, update
  final String title;
  final String description;
  final String action;

  AppRecommendation({
    required this.id,
    required this.priority,
    required this.category,
    required this.title,
    required this.description,
    required this.action,
  });

  factory AppRecommendation.fromJson(Map<String, dynamic> json) {
    return AppRecommendation(
      id: json['id'] as String? ?? '',
      priority: json['priority'] as String? ?? 'low',
      category: json['category'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      action: json['action'] as String? ?? '',
    );
  }

  int get priorityRank {
    switch (priority) {
      case 'critical':
        return 0;
      case 'high':
        return 1;
      case 'medium':
        return 2;
      default:
        return 3;
    }
  }
}

/// App analysis result (mirrors backend models.AppAnalysisResult)
class AppAnalysisResult {
  final String id;
  final String packageName;
  final String? appName;

  /// Overall risk score on the backend's 0-100 scale.
  final double riskScore;

  /// Risk level: safe, low, medium, high, critical.
  final String riskLevel;
  final String overallVerdict;
  final PermissionRiskAnalysis permissionRisk;
  final PrivacyRiskAnalysis privacyRisk;
  final SecurityRiskAnalysis securityRisk;
  final ThreatIntelMatch? threatIntelMatch;
  final List<AppRecommendation> recommendations;
  final DateTime analyzedAt;
  final String analysisVersion;

  AppAnalysisResult({
    required this.id,
    required this.packageName,
    this.appName,
    required this.riskScore,
    required this.riskLevel,
    required this.overallVerdict,
    required this.permissionRisk,
    required this.privacyRisk,
    required this.securityRisk,
    this.threatIntelMatch,
    this.recommendations = const [],
    required this.analyzedAt,
    required this.analysisVersion,
  });

  factory AppAnalysisResult.fromJson(Map<String, dynamic> json) {
    final packageName = json['package_name'] as String?;
    final riskLevel = json['risk_level'] as String?;
    final riskScore = (json['risk_score'] as num?)?.toDouble();
    final permissionRisk = json['permission_risk'];
    final privacyRisk = json['privacy_risk'];
    final securityRisk = json['security_risk'];
    final analyzedAt = json['analyzed_at'] as String?;

    if (packageName == null ||
        riskLevel == null ||
        riskScore == null ||
        permissionRisk is! Map<String, dynamic> ||
        privacyRisk is! Map<String, dynamic> ||
        securityRisk is! Map<String, dynamic> ||
        analyzedAt == null) {
      throw FormatException(
        'App analysis response missing required fields (package_name/'
        'risk_level/risk_score/permission_risk/privacy_risk/security_risk/'
        'analyzed_at); received keys: ${json.keys.join(', ')}',
      );
    }

    return AppAnalysisResult(
      id: json['id'] as String? ?? '',
      packageName: packageName,
      appName: json['app_name'] as String?,
      riskScore: riskScore,
      riskLevel: riskLevel,
      overallVerdict: json['overall_verdict'] as String? ?? '',
      permissionRisk: PermissionRiskAnalysis.fromJson(permissionRisk),
      privacyRisk: PrivacyRiskAnalysis.fromJson(privacyRisk),
      securityRisk: SecurityRiskAnalysis.fromJson(securityRisk),
      threatIntelMatch: json['threat_intel_match'] != null
          ? ThreatIntelMatch.fromJson(
              json['threat_intel_match'] as Map<String, dynamic>)
          : null,
      recommendations: (json['recommendations'] as List<dynamic>?)
              ?.map((r) =>
                  AppRecommendation.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
      analyzedAt: DateTime.parse(analyzedAt),
      analysisVersion: json['analysis_version'] as String? ?? '',
    );
  }

  /// Whether threat intelligence flagged this package as known malware.
  bool get isKnownMalware => threatIntelMatch?.isKnownMalware ?? false;

  /// Whether the backend classified the install source as sideloaded.
  bool get isSideloaded => securityRisk.isSideloaded;

  /// Trackers detected from the submitted library list.
  List<TrackerInfo> get detectedTrackers => privacyRisk.trackerSdks;

  /// Per-finding permission risks for UI display, derived from the
  /// backend's dangerous permission combinations.
  List<PermissionRisk> get permissionRisks => permissionRisk.dangerousCombos
      .map((combo) => PermissionRisk(
            permission: combo.permissions
                .map((p) => p.split('.').last)
                .join(' + '),
            riskLevel: combo.riskLevel,
            description: combo.description,
            isDangerous:
                combo.riskLevel == 'critical' || combo.riskLevel == 'high',
          ))
      .toList();

  /// All concerns raised across the permission, privacy, and security
  /// analyses (deduplicated, order preserved).
  List<String> get warnings {
    final seen = <String>{};
    final all = <String>[];
    for (final concern in [
      ...permissionRisk.concerns,
      ...privacyRisk.concerns,
      ...securityRisk.concerns,
    ]) {
      if (concern.isNotEmpty && seen.add(concern)) {
        all.add(concern);
      }
    }
    return all;
  }

  /// Top recommendation text for UI display (highest priority first),
  /// falling back to the backend's overall verdict.
  String? get recommendation {
    if (recommendations.isNotEmpty) {
      final sorted = List<AppRecommendation>.from(recommendations)
        ..sort((a, b) => a.priorityRank.compareTo(b.priorityRank));
      final top = sorted.first;
      return top.description.isNotEmpty
          ? '${top.title}. ${top.description}'
          : top.title;
    }
    return overallVerdict.isNotEmpty ? overallVerdict : null;
  }

  /// Privacy grade letter derived from the backend's privacy risk score
  /// (0-100, higher is worse).
  String get privacyGrade {
    final score = privacyRisk.score;
    if (score < 20) return 'A';
    if (score < 40) return 'B';
    if (score < 60) return 'C';
    if (score < 80) return 'D';
    return 'F';
  }
}

/// Permission risk info for UI display (derived from backend
/// dangerous permission combinations).
class PermissionRisk {
  final String permission;
  final String riskLevel;
  final String description;
  final bool isDangerous;

  PermissionRisk({
    required this.permission,
    required this.riskLevel,
    required this.description,
    required this.isDangerous,
  });
}

/// Tracker info (mirrors backend models.TrackerSDK)
class TrackerInfo {
  final String name;
  final String? company;
  final String category;
  final List<String> dataTypes;
  final String? website;

  /// Not emitted by the current backend; null unless a future API
  /// version provides it.
  final String? description;

  /// Not emitted by the current backend; null unless a future API
  /// version provides it.
  final List<String>? domains;

  TrackerInfo({
    required this.name,
    this.company,
    required this.category,
    this.dataTypes = const [],
    this.website,
    this.description,
    this.domains,
  });

  factory TrackerInfo.fromJson(Map<String, dynamic> json) {
    return TrackerInfo(
      name: json['name'] as String? ?? '',
      company: json['company'] as String?,
      category: json['category'] as String? ?? 'unknown',
      dataTypes:
          (json['data_types'] as List<dynamic>?)?.cast<String>() ?? const [],
      website: json['website'] as String?,
      description: json['description'] as String?,
      domains: (json['domains'] as List<dynamic>?)?.cast<String>(),
    );
  }

  /// Stable identifier (the backend keys trackers by name).
  String get id => name;
}

/// A scanned Wi-Fi network (mirrors backend models.WiFiNetwork)
class WifiNetworkInfo {
  final String ssid;
  final String? bssid;
  final String securityType;
  final int signalLevel; // dBm
  final int? frequency; // MHz
  final int? channel;
  final bool isConnected;
  final bool isHidden;

  WifiNetworkInfo({
    required this.ssid,
    this.bssid,
    required this.securityType,
    required this.signalLevel,
    this.frequency,
    this.channel,
    this.isConnected = false,
    this.isHidden = false,
  });

  /// Maps platform security descriptions (e.g. "WPA2-PSK", "wpa2Psk",
  /// "[WPA2-PSK-CCMP]") to the backend enum:
  /// open, wep, wpa, wpa2, wpa3, unknown.
  static String normalizeSecurityType(String securityType) {
    final s = securityType.toLowerCase();
    if (s.contains('wpa3')) return 'wpa3';
    if (s.contains('wpa2') || s.contains('enterprise')) return 'wpa2';
    if (s.contains('wpa')) return 'wpa';
    if (s.contains('wep')) return 'wep';
    if (s.contains('open') || s.contains('none')) return 'open';
    return 'unknown';
  }

  Map<String, dynamic> toJson() => {
        'ssid': ssid,
        if (bssid != null) 'bssid': bssid,
        'security_type': normalizeSecurityType(securityType),
        'signal_level': signalLevel,
        if (frequency != null) 'frequency': frequency,
        if (channel != null) 'channel': channel,
        'is_connected': isConnected,
        'is_hidden': isHidden,
      };
}

/// Wi-Fi audit request (mirrors backend models.WiFiAuditRequest:
/// {current_network: {...}, nearby_networks: [...], device_id, gateway_ip,
/// dns_ip})
class WifiAuditRequest {
  final String ssid;
  final String? bssid;
  final String securityType;
  final int signalStrength;
  final List<WifiNetworkInfo>? nearbyNetworks;
  final String? deviceId;
  final String? gateway;
  final List<String>? dnsServers;

  WifiAuditRequest({
    required this.ssid,
    this.bssid,
    required this.securityType,
    required this.signalStrength,
    this.nearbyNetworks,
    this.deviceId,
    this.gateway,
    this.dnsServers,
  });

  Map<String, dynamic> toJson() {
    return {
      'current_network': WifiNetworkInfo(
        ssid: ssid,
        bssid: bssid,
        securityType: securityType,
        signalLevel: signalStrength,
        isConnected: true,
      ).toJson(),
      if (nearbyNetworks != null && nearbyNetworks!.isNotEmpty)
        'nearby_networks':
            nearbyNetworks!.map((n) => n.toJson()).toList(),
      if (deviceId != null) 'device_id': deviceId,
      if (gateway != null) 'gateway_ip': gateway,
      if (dnsServers != null && dnsServers!.isNotEmpty)
        'dns_ip': dnsServers!.first,
    };
  }
}

/// A security issue found during a Wi-Fi audit
/// (mirrors backend WiFiSecurityIssue)
class WifiSecurityIssue {
  final String type;

  /// Backend NetworkRiskLevel: safe, low, medium, high, critical.
  final String severity;
  final String title;
  final String description;
  final String mitigation;

  WifiSecurityIssue({
    required this.type,
    required this.severity,
    required this.title,
    required this.description,
    required this.mitigation,
  });

  factory WifiSecurityIssue.fromJson(Map<String, dynamic> json) {
    return WifiSecurityIssue(
      type: json['type'] as String? ?? 'unknown',
      severity: json['severity'] as String? ?? 'low',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      mitigation: json['mitigation'] as String? ?? '',
    );
  }

  /// Map the backend NetworkRiskLevel to the app-wide SeverityLevel.
  SeverityLevel get severityLevel {
    switch (severity) {
      case 'safe':
        return SeverityLevel.info;
      case 'low':
        return SeverityLevel.low;
      case 'medium':
        return SeverityLevel.medium;
      case 'high':
        return SeverityLevel.high;
      case 'critical':
        return SeverityLevel.critical;
      default:
        return SeverityLevel.unknown;
    }
  }
}

/// A detected rogue access point (mirrors backend RogueAPAlert)
class RogueApAlert {
  final String ssid;
  final String bssid;
  final int signalStrength;
  final String securityType;
  final String riskLevel;
  final String reason;
  final DateTime? detectedAt;

  RogueApAlert({
    required this.ssid,
    required this.bssid,
    required this.signalStrength,
    required this.securityType,
    required this.riskLevel,
    required this.reason,
    this.detectedAt,
  });

  factory RogueApAlert.fromJson(Map<String, dynamic> json) {
    return RogueApAlert(
      ssid: json['ssid'] as String? ?? '',
      bssid: json['bssid'] as String? ?? '',
      signalStrength: json['signal_strength'] as int? ?? 0,
      securityType: json['security_type'] as String? ?? 'unknown',
      riskLevel: json['risk_level'] as String? ?? 'high',
      reason: json['reason'] as String? ?? '',
      detectedAt: json['detected_at'] != null
          ? DateTime.tryParse(json['detected_at'] as String)
          : null,
    );
  }
}

/// A detected evil twin attack (mirrors backend EvilTwinAlert)
class EvilTwinAlert {
  final String ssid;
  final String legitBssid;
  final String evilBssid;
  final String riskLevel;
  final double confidence;
  final String description;
  final String recommendation;
  final DateTime? detectedAt;

  EvilTwinAlert({
    required this.ssid,
    required this.legitBssid,
    required this.evilBssid,
    required this.riskLevel,
    required this.confidence,
    required this.description,
    required this.recommendation,
    this.detectedAt,
  });

  factory EvilTwinAlert.fromJson(Map<String, dynamic> json) {
    return EvilTwinAlert(
      ssid: json['ssid'] as String? ?? '',
      legitBssid: json['legit_bssid'] as String? ?? '',
      evilBssid: json['evil_bssid'] as String? ?? '',
      riskLevel: json['risk_level'] as String? ?? 'critical',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      recommendation: json['recommendation'] as String? ?? '',
      detectedAt: json['detected_at'] != null
          ? DateTime.tryParse(json['detected_at'] as String)
          : null,
    );
  }
}

/// A network security recommendation (mirrors backend NetworkRecommendation)
class NetworkRecommendationInfo {
  final String priority; // critical, high, medium, low
  final String title;
  final String description;
  final String? action;

  NetworkRecommendationInfo({
    required this.priority,
    required this.title,
    required this.description,
    this.action,
  });

  factory NetworkRecommendationInfo.fromJson(Map<String, dynamic> json) {
    return NetworkRecommendationInfo(
      priority: json['priority'] as String? ?? 'low',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      action: json['action'] as String?,
    );
  }
}

/// Wi-Fi audit result (mirrors backend models.WiFiAuditResult)
class WifiAuditResult {
  final String id;
  final String ssid;

  /// Backend NetworkRiskLevel: safe, low, medium, high, critical.
  final String riskLevel;

  /// Risk score 0.0-1.0 as computed by the backend.
  final double riskScore;
  final List<WifiSecurityIssue> securityIssues;
  final List<RogueApAlert> rogueApsDetected;
  final List<EvilTwinAlert> evilTwinsDetected;
  final List<NetworkRecommendationInfo> recommendationDetails;
  final DateTime auditedAt;

  WifiAuditResult({
    required this.id,
    required this.ssid,
    required this.riskLevel,
    required this.riskScore,
    this.securityIssues = const [],
    this.rogueApsDetected = const [],
    this.evilTwinsDetected = const [],
    this.recommendationDetails = const [],
    required this.auditedAt,
  });

  factory WifiAuditResult.fromJson(Map<String, dynamic> json) {
    final riskLevel = json['risk_level'] as String?;
    final riskScore = (json['risk_score'] as num?)?.toDouble();
    final auditedAt = json['audited_at'] as String?;

    if (riskLevel == null || riskScore == null || auditedAt == null) {
      throw FormatException(
        'Wi-Fi audit response missing required fields '
        '(risk_level/risk_score/audited_at); '
        'received keys: ${json.keys.join(', ')}',
      );
    }

    final network = json['network'] as Map<String, dynamic>?;

    return WifiAuditResult(
      id: json['id'] as String? ?? '',
      ssid: network?['ssid'] as String? ?? '',
      riskLevel: riskLevel,
      riskScore: riskScore,
      securityIssues: (json['security_issues'] as List<dynamic>?)
              ?.map((i) =>
                  WifiSecurityIssue.fromJson(i as Map<String, dynamic>))
              .toList() ??
          const [],
      rogueApsDetected: (json['rogue_ap_detected'] as List<dynamic>?)
              ?.map((r) => RogueApAlert.fromJson(r as Map<String, dynamic>))
              .toList() ??
          const [],
      evilTwinsDetected: (json['evil_twin_detected'] as List<dynamic>?)
              ?.map((e) => EvilTwinAlert.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      recommendationDetails: (json['recommendations'] as List<dynamic>?)
              ?.map((r) => NetworkRecommendationInfo.fromJson(
                  r as Map<String, dynamic>))
              .toList() ??
          const [],
      auditedAt: DateTime.parse(auditedAt),
    );
  }

  bool get rogueApDetected => rogueApsDetected.isNotEmpty;
  bool get evilTwinDetected => evilTwinsDetected.isNotEmpty;

  bool get isSecure => riskLevel == 'safe' || riskLevel == 'low';

  /// Security score 0-100 (higher is better), derived from the backend
  /// risk score (0.0-1.0, higher is worse).
  double get securityScore => ((1.0 - riskScore) * 100).clamp(0.0, 100.0);

  /// Letter grade derived from the backend risk level.
  String get securityGrade {
    switch (riskLevel) {
      case 'safe':
        return 'A';
      case 'low':
        return 'B';
      case 'medium':
        return 'C';
      case 'high':
        return 'D';
      case 'critical':
        return 'F';
      default:
        return 'U';
    }
  }

  /// Threats for UI display, derived from security issues plus rogue AP
  /// and evil twin detections.
  List<WifiThreat> get threats {
    final result = <WifiThreat>[];
    for (final issue in securityIssues) {
      result.add(WifiThreat(
        type: issue.type,
        severity: issue.severityLevel,
        description: issue.description.isNotEmpty
            ? issue.description
            : issue.title,
      ));
    }
    for (final rogue in rogueApsDetected) {
      result.add(WifiThreat(
        type: 'rogue_ap',
        severity: SeverityLevel.high,
        description: rogue.reason.isNotEmpty
            ? rogue.reason
            : 'Rogue access point detected: ${rogue.ssid}',
      ));
    }
    for (final twin in evilTwinsDetected) {
      result.add(WifiThreat(
        type: 'evil_twin',
        severity: SeverityLevel.critical,
        description: twin.description.isNotEmpty
            ? twin.description
            : 'Evil twin attack detected on ${twin.ssid}',
      ));
    }
    return result;
  }

  /// Recommendation texts for UI display.
  List<String> get recommendations => recommendationDetails
      .map((r) =>
          r.description.isNotEmpty ? '${r.title}. ${r.description}' : r.title)
      .toList();

  /// Whether a VPN is advisable on this network, derived from the audit
  /// outcome (medium+ risk or an active attack detection).
  bool get shouldUseVpn =>
      !isSecure || rogueApDetected || evilTwinDetected;
}

/// Wi-Fi threat for UI display (derived from the audit response)
class WifiThreat {
  final String type;
  final SeverityLevel severity;
  final String description;

  WifiThreat({
    required this.type,
    required this.severity,
    required this.description,
  });
}

/// YARA scan request
class YaraScanRequest {
  final String data;
  final String? filename;
  final bool isBase64;

  YaraScanRequest({
    required this.data,
    this.filename,
    this.isBase64 = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      if (filename != null) 'filename': filename,
      'is_base64': isBase64,
    };
  }
}

/// YARA scan result
class YaraScanResult {
  final bool hasMatches;
  final int matchCount;
  final List<YaraMatch> matches;
  final double riskScore;
  final String? recommendation;

  YaraScanResult({
    required this.hasMatches,
    required this.matchCount,
    required this.matches,
    required this.riskScore,
    this.recommendation,
  });

  factory YaraScanResult.fromJson(Map<String, dynamic> json) {
    return YaraScanResult(
      hasMatches: json['has_matches'] as bool? ?? false,
      matchCount: json['match_count'] as int? ?? 0,
      matches: (json['matches'] as List<dynamic>?)
              ?.map((m) => YaraMatch.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0.0,
      recommendation: json['recommendation'] as String?,
    );
  }
}

/// YARA match
class YaraMatch {
  final String ruleName;
  final String? ruleDescription;
  final String category;
  final SeverityLevel severity;
  final List<String>? tags;
  final List<String>? mitreTechniques;

  YaraMatch({
    required this.ruleName,
    this.ruleDescription,
    required this.category,
    required this.severity,
    this.tags,
    this.mitreTechniques,
  });

  factory YaraMatch.fromJson(Map<String, dynamic> json) {
    return YaraMatch(
      ruleName: json['rule_name'] as String? ?? '',
      ruleDescription: json['rule_description'] as String?,
      category: json['category'] as String? ?? 'unknown',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
