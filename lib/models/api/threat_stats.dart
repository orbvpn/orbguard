/// Threat Statistics Models
/// Models for statistics and dashboard data from OrbGuard Lab API

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

  factory ThreatStats.fromJson(Map<String, dynamic> json) {
    return ThreatStats(
      totalIndicators: json['total_indicators'] as int? ?? 0,
      activeIndicators: json['active_indicators'] as int? ?? 0,
      totalCampaigns: json['total_campaigns'] as int? ?? 0,
      activeCampaigns: json['active_campaigns'] as int? ?? 0,
      totalActors: json['total_actors'] as int? ?? 0,
      totalSources: json['total_sources'] as int? ?? 0,
      indicatorsByType:
          (json['indicators_by_type'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as int),
              ) ??
              {},
      indicatorsBySeverity:
          (json['indicators_by_severity'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as int),
              ) ??
              {},
      indicatorsByPlatform:
          (json['indicators_by_platform'] as Map<String, dynamic>?)?.map(
                (k, v) => MapEntry(k, v as int),
              ) ??
              {},
      indicatorsLast24h: json['indicators_last_24h'] as int? ?? 0,
      indicatorsLast7d: json['indicators_last_7d'] as int? ?? 0,
      indicatorsLast30d: json['indicators_last_30d'] as int? ?? 0,
      lastUpdated: DateTime.parse(
          json['last_updated'] as String? ?? DateTime.now().toIso8601String()),
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

/// Dashboard summary
class DashboardSummary {
  final ProtectionOverview protection;
  final ThreatOverview threats;
  final List<RecentAlert> recentAlerts;
  final List<RecentScan> recentScans;
  final DeviceHealthStatus deviceHealth;
  final DateTime generatedAt;

  DashboardSummary({
    required this.protection,
    required this.threats,
    required this.recentAlerts,
    required this.recentScans,
    required this.deviceHealth,
    required this.generatedAt,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      protection:
          ProtectionOverview.fromJson(json['protection'] as Map<String, dynamic>),
      threats: ThreatOverview.fromJson(json['threats'] as Map<String, dynamic>),
      recentAlerts: (json['recent_alerts'] as List<dynamic>?)
              ?.map((a) => RecentAlert.fromJson(a as Map<String, dynamic>))
              .toList() ??
          [],
      recentScans: (json['recent_scans'] as List<dynamic>?)
              ?.map((s) => RecentScan.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      deviceHealth:
          DeviceHealthStatus.fromJson(json['device_health'] as Map<String, dynamic>),
      generatedAt: DateTime.parse(
          json['generated_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Protection overview for dashboard
class ProtectionOverview {
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
    return ProtectionOverview(
      isProtected: json['is_protected'] as bool? ?? false,
      protectionScore: (json['protection_score'] as num?)?.toDouble() ?? 0.0,
      protectionGrade: json['protection_grade'] as String? ?? 'U',
      smsProtection:
          FeatureStatus.fromJson(json['sms_protection'] as Map<String, dynamic>? ?? {}),
      webProtection:
          FeatureStatus.fromJson(json['web_protection'] as Map<String, dynamic>? ?? {}),
      appProtection:
          FeatureStatus.fromJson(json['app_protection'] as Map<String, dynamic>? ?? {}),
      networkProtection: FeatureStatus.fromJson(
          json['network_protection'] as Map<String, dynamic>? ?? {}),
      vpnProtection:
          FeatureStatus.fromJson(json['vpn_protection'] as Map<String, dynamic>? ?? {}),
      lastScan: DateTime.parse(
          json['last_scan'] as String? ?? DateTime.now().toIso8601String()),
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

/// Individual feature status
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

  factory FeatureStatus.fromJson(Map<String, dynamic> json) {
    return FeatureStatus(
      name: json['name'] as String? ?? 'Unknown',
      isEnabled: json['is_enabled'] as bool? ?? false,
      isHealthy: json['is_healthy'] as bool? ?? true,
      status: json['status'] as String?,
      threatsBlocked: json['threats_blocked'] as int?,
      lastActivity: json['last_activity'] != null
          ? DateTime.parse(json['last_activity'] as String)
          : null,
    );
  }
}

/// Threat overview for dashboard
class ThreatOverview {
  final int threatsBlockedToday;
  final int threatsBlockedWeek;
  final int threatsBlockedMonth;
  final int activeCampaignsTargetingDevice;
  final int highSeverityThreats;
  final List<ThreatTrend> trends;

  ThreatOverview({
    required this.threatsBlockedToday,
    required this.threatsBlockedWeek,
    required this.threatsBlockedMonth,
    required this.activeCampaignsTargetingDevice,
    required this.highSeverityThreats,
    required this.trends,
  });

  factory ThreatOverview.fromJson(Map<String, dynamic> json) {
    return ThreatOverview(
      threatsBlockedToday: json['threats_blocked_today'] as int? ?? 0,
      threatsBlockedWeek: json['threats_blocked_week'] as int? ?? 0,
      threatsBlockedMonth: json['threats_blocked_month'] as int? ?? 0,
      activeCampaignsTargetingDevice:
          json['active_campaigns_targeting_device'] as int? ?? 0,
      highSeverityThreats: json['high_severity_threats'] as int? ?? 0,
      trends: (json['trends'] as List<dynamic>?)
              ?.map((t) => ThreatTrend.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
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
      date: DateTime.parse(json['date'] as String),
      count: json['count'] as int? ?? 0,
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

  factory RecentAlert.fromJson(Map<String, dynamic> json) {
    return RecentAlert(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'unknown',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'info'),
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['is_read'] as bool? ?? false,
      actionUrl: json['action_url'] as String?,
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
      id: json['id'] as String,
      type: json['type'] as String? ?? 'unknown',
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: json['status'] as String? ?? 'unknown',
      itemsScanned: json['items_scanned'] as int? ?? 0,
      threatsFound: json['threats_found'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
    );
  }

  bool get foundThreats => threatsFound > 0;
}

/// Device health status
class DeviceHealthStatus {
  final double overallScore;
  final String grade;
  final bool isRooted;
  final bool hasSecureScreenLock;
  final bool isEncrypted;
  final bool hasLatestSecurityPatch;
  final bool developerOptionsEnabled;
  final bool usbDebuggingEnabled;
  final List<String> issues;
  final List<String> recommendations;

  DeviceHealthStatus({
    required this.overallScore,
    required this.grade,
    required this.isRooted,
    required this.hasSecureScreenLock,
    required this.isEncrypted,
    required this.hasLatestSecurityPatch,
    required this.developerOptionsEnabled,
    required this.usbDebuggingEnabled,
    required this.issues,
    required this.recommendations,
  });

  factory DeviceHealthStatus.fromJson(Map<String, dynamic> json) {
    return DeviceHealthStatus(
      overallScore: (json['overall_score'] as num?)?.toDouble() ?? 0.0,
      grade: json['grade'] as String? ?? 'U',
      isRooted: json['is_rooted'] as bool? ?? false,
      hasSecureScreenLock: json['has_secure_screen_lock'] as bool? ?? false,
      isEncrypted: json['is_encrypted'] as bool? ?? false,
      hasLatestSecurityPatch:
          json['has_latest_security_patch'] as bool? ?? false,
      developerOptionsEnabled:
          json['developer_options_enabled'] as bool? ?? false,
      usbDebuggingEnabled: json['usb_debugging_enabled'] as bool? ?? false,
      issues: (json['issues'] as List<dynamic>?)?.cast<String>() ?? [],
      recommendations:
          (json['recommendations'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  bool get hasIssues => issues.isNotEmpty;
  bool get isHealthy => overallScore >= 80;
}

/// Protection status
class ProtectionStatus {
  final bool isActive;
  final double score;
  final String grade;
  final Map<String, bool> features;
  final DateTime lastSync;
  final int indicatorsLoaded;
  final int rulesLoaded;

  ProtectionStatus({
    required this.isActive,
    required this.score,
    required this.grade,
    required this.features,
    required this.lastSync,
    required this.indicatorsLoaded,
    required this.rulesLoaded,
  });

  factory ProtectionStatus.fromJson(Map<String, dynamic> json) {
    return ProtectionStatus(
      isActive: json['is_active'] as bool? ?? false,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      grade: json['grade'] as String? ?? 'U',
      features: (json['features'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as bool),
          ) ??
          {},
      lastSync: DateTime.parse(
          json['last_sync'] as String? ?? DateTime.now().toIso8601String()),
      indicatorsLoaded: json['indicators_loaded'] as int? ?? 0,
      rulesLoaded: json['rules_loaded'] as int? ?? 0,
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
