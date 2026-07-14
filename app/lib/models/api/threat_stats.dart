// Threat Statistics Models
// Models for statistics and dashboard data from OrbGuard Lab API

import 'threat_indicator.dart';

/// Overall threat statistics
class ThreatStats {
  final int totalIndicators;
  final int activeIndicators;
  final int totalCampaigns;
  final int activeCampaigns;
  final int totalActors;
  final int totalSources;
  final Map<String, int> indicatorsByType;
  final Map<String, int> indicatorsBySeverity;
  final Map<String, int> indicatorsByPlatform;
  final int indicatorsLast24h;
  final int indicatorsLast7d;
  final int indicatorsLast30d;
  final DateTime lastUpdated;

  ThreatStats({
    required this.totalIndicators,
    required this.activeIndicators,
    required this.totalCampaigns,
    required this.activeCampaigns,
    required this.totalActors,
    required this.totalSources,
    required this.indicatorsByType,
    required this.indicatorsBySeverity,
    required this.indicatorsByPlatform,
    required this.indicatorsLast24h,
    required this.indicatorsLast7d,
    required this.indicatorsLast30d,
    required this.lastUpdated,
  });

  /// Parses the live GET /api/v1/stats response (Go `models.Stats`):
  /// time-window counts arrive as `today_new_iocs` / `weekly_new_iocs` /
  /// `monthly_new_iocs` and the timestamp as `last_update`.
  factory ThreatStats.fromJson(Map<String, dynamic> json) {
    return ThreatStats(
      totalIndicators: (json['total_indicators'] as num?)?.toInt() ?? 0,
      // The backend does not currently report a separate active-indicator
      // count; the field stays 0 unless the API starts emitting it.
      activeIndicators: (json['active_indicators'] as num?)?.toInt() ?? 0,
      totalCampaigns: (json['total_campaigns'] as num?)?.toInt() ?? 0,
      activeCampaigns: (json['active_campaigns'] as num?)?.toInt() ?? 0,
      totalActors: (json['total_actors'] as num?)?.toInt() ?? 0,
      totalSources: (json['total_sources'] as num?)?.toInt() ?? 0,
      indicatorsByType: _intMap(json['indicators_by_type']),
      indicatorsBySeverity: _intMap(json['indicators_by_severity']),
      indicatorsByPlatform: _intMap(json['indicators_by_platform']),
      indicatorsLast24h: (json['today_new_iocs'] as num?)?.toInt() ?? 0,
      indicatorsLast7d: (json['weekly_new_iocs'] as num?)?.toInt() ?? 0,
      indicatorsLast30d: (json['monthly_new_iocs'] as num?)?.toInt() ?? 0,
      lastUpdated: DateTime.tryParse(json['last_update'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Get count for specific indicator type
  int getCountByType(IndicatorType type) {
    return indicatorsByType[type.value] ?? 0;
  }

  /// Get count for specific severity
  int getCountBySeverity(SeverityLevel severity) {
    return indicatorsBySeverity[severity.value] ?? 0;
  }

  /// Get critical + high threat count
  int get criticalAndHighCount =>
      getCountBySeverity(SeverityLevel.critical) +
      getCountBySeverity(SeverityLevel.high);
}

/// Parses a JSON object of counts into a `Map<String, int>`.
Map<String, int> _intMap(dynamic value) {
  if (value is! Map<String, dynamic>) return {};
  return value.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
}

/// Dashboard summary — mirrors GET /api/v1/stats/dashboard.
///
/// The backend omits sections whose data source is unavailable instead of
/// fabricating them:
/// - `protection`, `activity`: present only for authenticated devices
/// - `threats`: present only when the indicators database is reachable
/// - `device_health`: present only when the device has a security
///   registration
///
/// Optional sections are surfaced as partial data (`available == false` /
/// null) rather than throwing.
class DashboardSummary {
  final ProtectionOverview protection;
  final ThreatOverview threats;
  final List<RecentAlert> recentAlerts;
  final List<RecentScan> recentScans;
  final DeviceHealthStatus? deviceHealth;
  final int unreadAlerts;
  final int totalAlerts;
  final DateTime generatedAt;

  DashboardSummary({
    required this.protection,
    required this.threats,
    required this.recentAlerts,
    this.recentScans = const [],
    this.deviceHealth,
    this.unreadAlerts = 0,
    this.totalAlerts = 0,
    required this.generatedAt,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final protectionJson = json['protection'];
    final threatsJson = json['threats'];
    final activityJson = json['activity'];
    final healthJson = json['device_health'];

    return DashboardSummary(
      protection: protectionJson is Map<String, dynamic>
          ? ProtectionOverview.fromJson(protectionJson)
          : ProtectionOverview.unavailable(),
      threats: ThreatOverview.fromSections(
        threatsJson is Map<String, dynamic> ? threatsJson : null,
        activityJson is Map<String, dynamic> ? activityJson : null,
      ),
      recentAlerts: (json['recent_alerts'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(RecentAlert.fromJson)
              .toList() ??
          [],
      recentScans: (json['recent_scans'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(RecentScan.fromJson)
              .toList() ??
          [],
      deviceHealth: healthJson is Map<String, dynamic>
          ? DeviceHealthStatus.fromJson(healthJson)
          : null,
      unreadAlerts: (json['unread_alerts'] as num?)?.toInt() ?? 0,
      totalAlerts: (json['total_alerts'] as num?)?.toInt() ?? 0,
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// Protection overview for dashboard.
///
/// Mirrors the `protection` section of GET /api/v1/stats/dashboard, which is
/// the same shape as GET /api/v1/stats/protection (Go `models.ProtectionStatus`):
/// `{is_active, score, grade, features: {sms|web|app|network|vpn:
/// {enabled, status}}, last_scan}`.
class ProtectionOverview {
  /// False when the backend omitted the protection section (no device
  /// identity). All other values are then "unknown", not real measurements.
  final bool available;
  final bool isProtected;
  final double protectionScore;
  final String protectionGrade;
  final FeatureStatus smsProtection;
  final FeatureStatus webProtection;
  final FeatureStatus appProtection;
  final FeatureStatus networkProtection;
  final FeatureStatus vpnProtection;
  final DateTime lastScan;

  ProtectionOverview({
    this.available = true,
    required this.isProtected,
    required this.protectionScore,
    required this.protectionGrade,
    required this.smsProtection,
    required this.webProtection,
    required this.appProtection,
    required this.networkProtection,
    required this.vpnProtection,
    required this.lastScan,
  });

  factory ProtectionOverview.fromJson(Map<String, dynamic> json) {
    final features = json['features'];
    final featureMap =
        features is Map<String, dynamic> ? features : const <String, dynamic>{};

    FeatureStatus feature(String key, String name) =>
        FeatureStatus.fromFeatureJson(
          name,
          featureMap[key] is Map<String, dynamic>
              ? featureMap[key] as Map<String, dynamic>
              : null,
        );

    return ProtectionOverview(
      isProtected: json['is_active'] as bool? ?? false,
      protectionScore: (json['score'] as num?)?.toDouble() ?? 0.0,
      protectionGrade: json['grade'] as String? ?? 'U',
      smsProtection: feature('sms', 'SMS'),
      webProtection: feature('web', 'Web'),
      appProtection: feature('app', 'App'),
      networkProtection: feature('network', 'Network'),
      vpnProtection: feature('vpn', 'VPN'),
      lastScan: DateTime.tryParse(json['last_scan'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Placeholder used when the backend omitted the protection section
  /// (unauthenticated request). Grade 'U' is the app-wide "unknown"
  /// sentinel; nothing here is a real measurement.
  factory ProtectionOverview.unavailable() {
    return ProtectionOverview(
      available: false,
      isProtected: false,
      protectionScore: 0.0,
      protectionGrade: 'U',
      smsProtection: FeatureStatus.unknown('SMS'),
      webProtection: FeatureStatus.unknown('Web'),
      appProtection: FeatureStatus.unknown('App'),
      networkProtection: FeatureStatus.unknown('Network'),
      vpnProtection: FeatureStatus.unknown('VPN'),
      lastScan: DateTime.now(),
    );
  }

  /// Get all features as a list
  List<FeatureStatus> get allFeatures => [
        smsProtection,
        webProtection,
        appProtection,
        networkProtection,
        vpnProtection,
      ];

  /// Count of enabled features
  int get enabledFeatureCount =>
      allFeatures.where((f) => f.isEnabled).length;
}

/// Individual feature status.
///
/// The backend emits `{enabled: bool, status: "protected"|"disabled"}` per
/// feature inside `protection.features`.
class FeatureStatus {
  final String name;
  final bool isEnabled;
  final bool isHealthy;
  final String? status;
  final int? threatsBlocked;
  final DateTime? lastActivity;

  FeatureStatus({
    required this.name,
    required this.isEnabled,
    required this.isHealthy,
    this.status,
    this.threatsBlocked,
    this.lastActivity,
  });

  /// Parses one entry of the backend `features` map; [name] is the display
  /// name derived from the feature key.
  factory FeatureStatus.fromFeatureJson(String name, Map<String, dynamic>? json) {
    if (json == null) return FeatureStatus.unknown(name);
    final status = json['status'] as String?;
    return FeatureStatus(
      name: name,
      isEnabled: json['enabled'] as bool? ?? false,
      isHealthy: status != 'error',
      status: status,
      threatsBlocked: (json['threats_blocked'] as num?)?.toInt(),
      lastActivity: json['last_activity'] != null
          ? DateTime.tryParse(json['last_activity'] as String)
          : null,
    );
  }

  /// Feature whose state is unknown (section missing from the response).
  factory FeatureStatus.unknown(String name) {
    return FeatureStatus(
      name: name,
      isEnabled: false,
      isHealthy: true,
      status: 'unknown',
    );
  }
}

/// Threat overview for dashboard.
///
/// Combines two backend sections of GET /api/v1/stats/dashboard:
/// - `threats`: global threat-intelligence stats from the indicators DB
/// - `activity`: per-device detection stats (authenticated devices only)
class ThreatOverview {
  /// False when the backend omitted both sections (no data sources
  /// available); all counts are then 0 because nothing was measured.
  final bool available;

  // Global threat-intelligence stats (`threats` section).
  final int totalIndicators;
  final Map<String, int> byType;
  final Map<String, int> bySeverity;
  final int highSeverityThreats;
  final int newIndicatorsToday;
  final int newIndicatorsWeek;
  final int newIndicatorsMonth;
  final int pegasusIndicators;
  final int mobileIndicators;
  final int activeCampaigns;
  final int campaignsTargetingDevice;

  // Per-device detection activity (`activity` section).
  final int threatsDetectedToday;
  final int threatsDetectedWeek;
  final int threatsDetectedMonth;
  final int threatsDetectedTotal;
  final int messagesAnalyzedTotal;
  final List<ThreatTrend> trends;

  ThreatOverview({
    this.available = true,
    this.totalIndicators = 0,
    this.byType = const {},
    this.bySeverity = const {},
    this.highSeverityThreats = 0,
    this.newIndicatorsToday = 0,
    this.newIndicatorsWeek = 0,
    this.newIndicatorsMonth = 0,
    this.pegasusIndicators = 0,
    this.mobileIndicators = 0,
    this.activeCampaigns = 0,
    this.campaignsTargetingDevice = 0,
    this.threatsDetectedToday = 0,
    this.threatsDetectedWeek = 0,
    this.threatsDetectedMonth = 0,
    this.threatsDetectedTotal = 0,
    this.messagesAnalyzedTotal = 0,
    this.trends = const [],
  });

  /// Builds the overview from the backend `threats` and `activity`
  /// sections; either may be null when the backend omitted it.
  factory ThreatOverview.fromSections(
    Map<String, dynamic>? threats,
    Map<String, dynamic>? activity,
  ) {
    if (threats == null && activity == null) {
      return ThreatOverview(available: false);
    }

    List<ThreatTrend> trends = const [];
    final trendJson = activity?['trend'];
    if (trendJson is List) {
      trends = trendJson
          .whereType<Map<String, dynamic>>()
          .map(ThreatTrend.fromJson)
          .toList();
    }

    return ThreatOverview(
      totalIndicators: (threats?['total_indicators'] as num?)?.toInt() ?? 0,
      byType: _intMap(threats?['by_type']),
      bySeverity: _intMap(threats?['by_severity']),
      highSeverityThreats: (threats?['high_severity'] as num?)?.toInt() ?? 0,
      newIndicatorsToday: (threats?['new_today'] as num?)?.toInt() ?? 0,
      newIndicatorsWeek: (threats?['new_week'] as num?)?.toInt() ?? 0,
      newIndicatorsMonth: (threats?['new_month'] as num?)?.toInt() ?? 0,
      pegasusIndicators: (threats?['pegasus_indicators'] as num?)?.toInt() ?? 0,
      mobileIndicators: (threats?['mobile_indicators'] as num?)?.toInt() ?? 0,
      activeCampaigns: (threats?['active_campaigns'] as num?)?.toInt() ?? 0,
      campaignsTargetingDevice:
          (threats?['campaigns_targeting_device'] as num?)?.toInt() ?? 0,
      threatsDetectedToday:
          (activity?['threats_detected_today'] as num?)?.toInt() ?? 0,
      threatsDetectedWeek:
          (activity?['threats_detected_week'] as num?)?.toInt() ?? 0,
      threatsDetectedMonth:
          (activity?['threats_detected_month'] as num?)?.toInt() ?? 0,
      threatsDetectedTotal:
          (activity?['threats_detected_total'] as num?)?.toInt() ?? 0,
      messagesAnalyzedTotal:
          (activity?['messages_analyzed_total'] as num?)?.toInt() ?? 0,
      trends: trends,
    );
  }

  // Legacy accessors kept for existing UI call sites. These map to the
  // real per-device detection counts from the `activity` section.
  int get threatsBlockedToday => threatsDetectedToday;
  int get threatsBlockedWeek => threatsDetectedWeek;
  int get threatsBlockedMonth => threatsDetectedMonth;

  /// Active campaigns whose target platforms include this device's
  /// platform (backend-computed when the request is device-authenticated).
  int get activeCampaignsTargetingDevice => campaignsTargetingDevice;
}

/// Threat trend data point
class ThreatTrend {
  final DateTime date;
  final int count;
  final String? category;

  ThreatTrend({
    required this.date,
    required this.count,
    this.category,
  });

  factory ThreatTrend.fromJson(Map<String, dynamic> json) {
    return ThreatTrend(
      date: json['date'] is String
          ? (DateTime.tryParse(json['date'] as String) ?? DateTime.now())
          : DateTime.now(),
      count: (json['count'] as num?)?.toInt() ?? 0,
      category: json['category'] as String?,
    );
  }
}

/// Recent alert
class RecentAlert {
  final String id;
  final String type;
  final String title;
  final String message;
  final SeverityLevel severity;
  final DateTime timestamp;
  final bool isRead;
  final String? actionUrl;

  RecentAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    required this.timestamp,
    required this.isRead,
    this.actionUrl,
  });

  /// Parses a backend alert item: `{id, title, description, severity,
  /// category, source, is_read, created_at, metadata?}` (see LAB
  /// handlers/alerts.go `alertItem`).
  factory RecentAlert.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    return RecentAlert(
      id: json['id'] as String? ?? '',
      type: json['category'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      message: json['description'] as String? ?? '',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'info'),
      timestamp: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      isRead: json['is_read'] as bool? ?? false,
      actionUrl: metadata is Map<String, dynamic>
          ? metadata['action_url'] as String?
          : null,
    );
  }
}

/// Recent scan
class RecentScan {
  final String id;
  final String type;
  final DateTime timestamp;
  final String status;
  final int itemsScanned;
  final int threatsFound;
  final int duration;

  RecentScan({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.status,
    required this.itemsScanned,
    required this.threatsFound,
    required this.duration,
  });

  factory RecentScan.fromJson(Map<String, dynamic> json) {
    return RecentScan(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      timestamp: json['timestamp'] is String
          ? (DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now())
          : DateTime.now(),
      status: json['status'] as String? ?? 'unknown',
      itemsScanned: (json['items_scanned'] as num?)?.toInt() ?? 0,
      threatsFound: (json['threats_found'] as num?)?.toInt() ?? 0,
      duration: (json['duration'] as num?)?.toInt() ?? 0,
    );
  }

  bool get foundThreats => threatsFound > 0;
}

/// Device health status.
///
/// Mirrors the `device_health` section of GET /api/v1/stats/dashboard,
/// computed by the backend from the device's security registration:
/// `{score, grade, is_rooted, is_encrypted, has_screen_lock,
/// security_patch, has_latest_security_patch, platform, os_version, model,
/// issues, recommendations}`.
class DeviceHealthStatus {
  final double overallScore;
  final String grade;
  final bool isRooted;
  final bool hasSecureScreenLock;
  final bool isEncrypted;
  final bool hasLatestSecurityPatch;

  /// Not reported by the backend yet; false until the device agent reports
  /// these flags (`developer_options_enabled` / `usb_debugging_enabled`).
  final bool developerOptionsEnabled;
  final bool usbDebuggingEnabled;

  final String securityPatch;
  final String platform;
  final String osVersion;
  final String model;
  final List<String> issues;
  final List<String> recommendations;

  DeviceHealthStatus({
    required this.overallScore,
    required this.grade,
    required this.isRooted,
    required this.hasSecureScreenLock,
    required this.isEncrypted,
    required this.hasLatestSecurityPatch,
    this.developerOptionsEnabled = false,
    this.usbDebuggingEnabled = false,
    this.securityPatch = '',
    this.platform = '',
    this.osVersion = '',
    this.model = '',
    required this.issues,
    required this.recommendations,
  });

  factory DeviceHealthStatus.fromJson(Map<String, dynamic> json) {
    return DeviceHealthStatus(
      overallScore: (json['score'] as num?)?.toDouble() ?? 0.0,
      grade: json['grade'] as String? ?? 'U',
      isRooted: json['is_rooted'] as bool? ?? false,
      hasSecureScreenLock: json['has_screen_lock'] as bool? ?? false,
      isEncrypted: json['is_encrypted'] as bool? ?? false,
      hasLatestSecurityPatch:
          json['has_latest_security_patch'] as bool? ?? false,
      developerOptionsEnabled:
          json['developer_options_enabled'] as bool? ?? false,
      usbDebuggingEnabled: json['usb_debugging_enabled'] as bool? ?? false,
      securityPatch: json['security_patch'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      osVersion: json['os_version'] as String? ?? '',
      model: json['model'] as String? ?? '',
      issues: (json['issues'] as List<dynamic>?)?.cast<String>() ?? [],
      recommendations:
          (json['recommendations'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  bool get hasIssues => issues.isNotEmpty;
  bool get isHealthy => overallScore >= 80;
}

/// Protection status — mirrors GET /api/v1/stats/protection
/// (Go `models.ProtectionStatus`): `{is_active, score, grade,
/// features: {sms|web|app|network|vpn: {enabled, status}}, last_scan}`.
class ProtectionStatus {
  final bool isActive;
  final double score;
  final String grade;

  /// Feature key → enabled, flattened from the backend's
  /// `{enabled, status}` objects.
  final Map<String, bool> features;

  /// Per-feature status strings ("protected"/"disabled") as reported by
  /// the backend.
  final Map<String, String> featureStates;
  final DateTime lastSync;

  ProtectionStatus({
    required this.isActive,
    required this.score,
    required this.grade,
    required this.features,
    this.featureStates = const {},
    required this.lastSync,
  });

  factory ProtectionStatus.fromJson(Map<String, dynamic> json) {
    final features = <String, bool>{};
    final featureStates = <String, String>{};
    final rawFeatures = json['features'];
    if (rawFeatures is Map<String, dynamic>) {
      rawFeatures.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          features[key] = value['enabled'] as bool? ?? false;
          final status = value['status'] as String?;
          if (status != null) featureStates[key] = status;
        } else if (value is bool) {
          // Tolerate the flattened boolean form as well.
          features[key] = value;
        }
      });
    }

    return ProtectionStatus(
      isActive: json['is_active'] as bool? ?? false,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      grade: json['grade'] as String? ?? 'U',
      features: features,
      featureStates: featureStates,
      lastSync: DateTime.tryParse(json['last_scan'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Check if specific feature is enabled
  bool isFeatureEnabled(String feature) => features[feature] ?? false;

  /// Get list of enabled features
  List<String> get enabledFeatures =>
      features.entries.where((e) => e.value).map((e) => e.key).toList();

  /// Get list of disabled features
  List<String> get disabledFeatures =>
      features.entries.where((e) => !e.value).map((e) => e.key).toList();
}

/// Scan result summary
class ScanResultSummary {
  final String scanId;
  final String scanType;
  final DateTime startTime;
  final DateTime endTime;
  final int duration;
  final int itemsScanned;
  final int threatsFound;
  final int threatsCleaned;
  final int threatsQuarantined;
  final List<DetectedThreat> detectedThreats;
  final String status;

  ScanResultSummary({
    required this.scanId,
    required this.scanType,
    required this.startTime,
    required this.endTime,
    required this.duration,
    required this.itemsScanned,
    required this.threatsFound,
    required this.threatsCleaned,
    required this.threatsQuarantined,
    required this.detectedThreats,
    required this.status,
  });

  factory ScanResultSummary.fromJson(Map<String, dynamic> json) {
    return ScanResultSummary(
      scanId: json['scan_id'] as String,
      scanType: json['scan_type'] as String? ?? 'unknown',
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      duration: json['duration'] as int? ?? 0,
      itemsScanned: json['items_scanned'] as int? ?? 0,
      threatsFound: json['threats_found'] as int? ?? 0,
      threatsCleaned: json['threats_cleaned'] as int? ?? 0,
      threatsQuarantined: json['threats_quarantined'] as int? ?? 0,
      detectedThreats: (json['detected_threats'] as List<dynamic>?)
              ?.map((t) => DetectedThreat.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      status: json['status'] as String? ?? 'unknown',
    );
  }

  bool get isClean => threatsFound == 0;
  bool get allThreatsCleaned => threatsCleaned == threatsFound;
}

/// Detected threat in scan
class DetectedThreat {
  final String id;
  final String name;
  final String type;
  final SeverityLevel severity;
  final String location;
  final String? action;
  final String? actionStatus;

  DetectedThreat({
    required this.id,
    required this.name,
    required this.type,
    required this.severity,
    required this.location,
    this.action,
    this.actionStatus,
  });

  factory DetectedThreat.fromJson(Map<String, dynamic> json) {
    return DetectedThreat(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      location: json['location'] as String? ?? '',
      action: json['action'] as String?,
      actionStatus: json['action_status'] as String?,
    );
  }
}

/// API health check response
class HealthCheckResponse {
  final bool healthy;
  final String status;
  final Map<String, ServiceHealth> services;
  final DateTime checkedAt;

  HealthCheckResponse({
    required this.healthy,
    required this.status,
    required this.services,
    required this.checkedAt,
  });

  factory HealthCheckResponse.fromJson(Map<String, dynamic> json) {
    return HealthCheckResponse(
      healthy: json['healthy'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      services: (json['services'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, ServiceHealth.fromJson(v as Map<String, dynamic>)),
          ) ??
          {},
      checkedAt: DateTime.parse(
          json['checked_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Individual service health
class ServiceHealth {
  final String name;
  final bool healthy;
  final String? status;
  final int? latencyMs;

  ServiceHealth({
    required this.name,
    required this.healthy,
    this.status,
    this.latencyMs,
  });

  factory ServiceHealth.fromJson(Map<String, dynamic> json) {
    return ServiceHealth(
      name: json['name'] as String? ?? '',
      healthy: json['healthy'] as bool? ?? false,
      status: json['status'] as String?,
      latencyMs: json['latency_ms'] as int?,
    );
  }
}
