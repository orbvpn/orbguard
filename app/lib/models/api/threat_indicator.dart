/// Threat Indicator Models
/// Models for threat indicators from OrbGuard Lab API

/// Types of threat indicators
enum IndicatorType {
  domain('domain'),
  ipv4('ipv4'),
  ipv6('ipv6'),
  url('url'),
  sha256('sha256'),
  sha1('sha1'),
  md5('md5'),
  email('email'),
  phoneNumber('phone_number'),
  processName('process_name'),
  bundleId('bundle_id'),
  packageName('package_name'),
  ssid('ssid'),
  certificate('certificate'),
  unknown('unknown');

  final String value;
  const IndicatorType(this.value);

  static IndicatorType fromString(String value) {
    return IndicatorType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => IndicatorType.unknown,
    );
  }
}

/// Severity levels for threats
enum SeverityLevel {
  critical('critical', 10),
  high('high', 8),
  medium('medium', 5),
  low('low', 3),
  info('info', 1),
  unknown('unknown', 0);

  final String value;
  final int score;
  const SeverityLevel(this.value, this.score);

  static SeverityLevel fromString(String value) {
    return SeverityLevel.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SeverityLevel.unknown,
    );
  }

  /// Get color for UI display
  int get color {
    switch (this) {
      case SeverityLevel.critical:
        return 0xFFD32F2F; // Red
      case SeverityLevel.high:
        return 0xFFF57C00; // Orange
      case SeverityLevel.medium:
        return 0xFFFBC02D; // Yellow
      case SeverityLevel.low:
        return 0xFF388E3C; // Green
      case SeverityLevel.info:
        return 0xFF1976D2; // Blue
      case SeverityLevel.unknown:
        return 0xFF757575; // Grey
    }
  }

  /// Get display name for UI
  String get displayName {
    switch (this) {
      case SeverityLevel.critical:
        return 'Critical';
      case SeverityLevel.high:
        return 'High';
      case SeverityLevel.medium:
        return 'Medium';
      case SeverityLevel.low:
        return 'Low';
      case SeverityLevel.info:
        return 'Info';
      case SeverityLevel.unknown:
        return 'Unknown';
    }
  }
}

/// Platforms affected by threats
enum ThreatPlatform {
  android('android'),
  ios('ios'),
  both('both'),
  unknown('unknown');

  final String value;
  const ThreatPlatform(this.value);

  static ThreatPlatform fromString(String value) {
    return ThreatPlatform.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ThreatPlatform.unknown,
    );
  }
}

/// Threat indicator from the API
class ThreatIndicator {
  final String id;
  final String value;
  final IndicatorType type;
  final SeverityLevel severity;
  final double confidence;
  final List<String> tags;
  final List<ThreatPlatform> platforms;
  final String? description;
  final String? sourceId;
  final String? sourceName;
  final String? campaignId;
  final String? campaignName;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;
  final List<String>? mitreTechniques;

  ThreatIndicator({
    required this.id,
    required this.value,
    required this.type,
    required this.severity,
    required this.confidence,
    required this.tags,
    required this.platforms,
    this.description,
    this.sourceId,
    this.sourceName,
    this.campaignId,
    this.campaignName,
    this.firstSeen,
    this.lastSeen,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
    this.mitreTechniques,
  });

  factory ThreatIndicator.fromJson(Map<String, dynamic> json) {
    return ThreatIndicator(
      id: json['id'] as String,
      value: json['value'] as String,
      type: IndicatorType.fromString(json['type'] as String? ?? 'unknown'),
      severity: SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      platforms: (json['platforms'] as List<dynamic>?)
              ?.map((p) => ThreatPlatform.fromString(p as String))
              .toList() ??
          [],
      description: json['description'] as String?,
      sourceId: json['source_id'] as String?,
      sourceName: json['source_name'] as String?,
      campaignId: json['campaign_id'] as String?,
      campaignName: json['campaign_name'] as String?,
      firstSeen: json['first_seen'] != null
          ? DateTime.parse(json['first_seen'] as String)
          : null,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'value': value,
      'type': type.value,
      'severity': severity.value,
      'confidence': confidence,
      'tags': tags,
      'platforms': platforms.map((p) => p.value).toList(),
      'description': description,
      'source_id': sourceId,
      'source_name': sourceName,
      'campaign_id': campaignId,
      'campaign_name': campaignName,
      'first_seen': firstSeen?.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'metadata': metadata,
      'mitre_techniques': mitreTechniques,
    };
  }

  /// Check if this indicator is considered dangerous
  bool get isDangerous =>
      severity == SeverityLevel.critical || severity == SeverityLevel.high;

  /// Get human-readable type name
  String get typeName {
    switch (type) {
      case IndicatorType.domain:
        return 'Domain';
      case IndicatorType.ipv4:
        return 'IPv4 Address';
      case IndicatorType.ipv6:
        return 'IPv6 Address';
      case IndicatorType.url:
        return 'URL';
      case IndicatorType.sha256:
        return 'SHA-256 Hash';
      case IndicatorType.sha1:
        return 'SHA-1 Hash';
      case IndicatorType.md5:
        return 'MD5 Hash';
      case IndicatorType.email:
        return 'Email Address';
      case IndicatorType.phoneNumber:
        return 'Phone Number';
      case IndicatorType.processName:
        return 'Process Name';
      case IndicatorType.bundleId:
        return 'iOS Bundle ID';
      case IndicatorType.packageName:
        return 'Android Package';
      case IndicatorType.ssid:
        return 'WiFi SSID';
      case IndicatorType.certificate:
        return 'Certificate';
      case IndicatorType.unknown:
        return 'Unknown';
    }
  }
}

/// Request to check indicators
class IndicatorCheckRequest {
  final String value;
  final IndicatorType? type;

  IndicatorCheckRequest({
    required this.value,
    this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      if (type != null) 'type': type!.value,
    };
  }
}

/// Result of indicator check
class IndicatorCheckResult {
  final String value;
  final bool isThreat;
  final IndicatorType? type;
  final SeverityLevel? severity;
  final double? confidence;
  final List<String>? tags;
  final String? campaignName;
  final String? description;
  final List<String>? mitreTechniques;

  IndicatorCheckResult({
    required this.value,
    required this.isThreat,
    this.type,
    this.severity,
    this.confidence,
    this.tags,
    this.campaignName,
    this.description,
    this.mitreTechniques,
  });

  factory IndicatorCheckResult.fromJson(Map<String, dynamic> json) {
    return IndicatorCheckResult(
      value: json['value'] as String,
      isThreat: json['is_threat'] as bool? ?? false,
      type: json['type'] != null
          ? IndicatorType.fromString(json['type'] as String)
          : null,
      severity: json['severity'] != null
          ? SeverityLevel.fromString(json['severity'] as String)
          : null,
      confidence: (json['confidence'] as num?)?.toDouble(),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      campaignName: json['campaign_name'] as String?,
      description: json['description'] as String?,
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>(),
    );
  }
}

/// DNS block check result
class DnsBlockResult {
  final String domain;
  final bool shouldBlock;
  final String? reason;
  final String? category;
  final SeverityLevel? severity;

  DnsBlockResult({
    required this.domain,
    required this.shouldBlock,
    this.reason,
    this.category,
    this.severity,
  });

  factory DnsBlockResult.fromJson(Map<String, dynamic> json) {
    return DnsBlockResult(
      domain: json['domain'] as String,
      shouldBlock: json['should_block'] as bool? ?? false,
      reason: json['reason'] as String?,
      category: json['category'] as String?,
      severity: json['severity'] != null
          ? SeverityLevel.fromString(json['severity'] as String)
          : null,
    );
  }
}

/// Sync result
class SyncResult {
  final bool success;
  final int newIndicators;
  final int updatedIndicators;
  final int totalIndicators;
  final DateTime syncedAt;

  SyncResult({
    required this.success,
    required this.newIndicators,
    required this.updatedIndicators,
    required this.totalIndicators,
    required this.syncedAt,
  });

  factory SyncResult.fromJson(Map<String, dynamic> json) {
    return SyncResult(
      success: json['success'] as bool? ?? false,
      newIndicators: json['new_indicators'] as int? ?? 0,
      updatedIndicators: json['updated_indicators'] as int? ?? 0,
      totalIndicators: json['total_indicators'] as int? ?? 0,
      syncedAt: DateTime.parse(
          json['synced_at'] as String? ?? DateTime.now().toIso8601String()),
    );
  }
}

/// Correlation result
class CorrelationResult {
  final String indicatorId;
  final List<RelatedIndicator> relatedIndicators;
  final List<String>? sharedCampaigns;
  final List<String>? sharedActors;
  final List<String>? sharedInfrastructure;
  final double correlationScore;

  CorrelationResult({
    required this.indicatorId,
    required this.relatedIndicators,
    this.sharedCampaigns,
    this.sharedActors,
    this.sharedInfrastructure,
    required this.correlationScore,
  });

  factory CorrelationResult.fromJson(Map<String, dynamic> json) {
    return CorrelationResult(
      indicatorId: json['indicator_id'] as String,
      relatedIndicators: (json['related_indicators'] as List<dynamic>?)
              ?.map((i) => RelatedIndicator.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      sharedCampaigns:
          (json['shared_campaigns'] as List<dynamic>?)?.cast<String>(),
      sharedActors: (json['shared_actors'] as List<dynamic>?)?.cast<String>(),
      sharedInfrastructure:
          (json['shared_infrastructure'] as List<dynamic>?)?.cast<String>(),
      correlationScore: (json['correlation_score'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Related indicator in correlation
class RelatedIndicator {
  final String id;
  final String value;
  final IndicatorType type;
  final String relationship;
  final double strength;

  RelatedIndicator({
    required this.id,
    required this.value,
    required this.type,
    required this.relationship,
    required this.strength,
  });

  factory RelatedIndicator.fromJson(Map<String, dynamic> json) {
    return RelatedIndicator(
      id: json['id'] as String,
      value: json['value'] as String,
      type: IndicatorType.fromString(json['type'] as String? ?? 'unknown'),
      relationship: json['relationship'] as String? ?? 'related',
      strength: (json['strength'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Graph related entities result
class GraphRelatedResult {
  final String entityId;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  GraphRelatedResult({
    required this.entityId,
    required this.nodes,
    required this.edges,
  });

  factory GraphRelatedResult.fromJson(Map<String, dynamic> json) {
    return GraphRelatedResult(
      entityId: json['entity_id'] as String,
      nodes: (json['nodes'] as List<dynamic>?)
              ?.map((n) => GraphNode.fromJson(n as Map<String, dynamic>))
              .toList() ??
          [],
      edges: (json['edges'] as List<dynamic>?)
              ?.map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// Node in threat graph
class GraphNode {
  final String id;
  final String label;
  final String type;
  final Map<String, dynamic>? properties;

  GraphNode({
    required this.id,
    required this.label,
    required this.type,
    this.properties,
  });

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    return GraphNode(
      id: json['id'] as String,
      label: json['label'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      properties: json['properties'] as Map<String, dynamic>?,
    );
  }
}

/// Edge in threat graph
class GraphEdge {
  final String source;
  final String target;
  final String relationship;
  final Map<String, dynamic>? properties;

  GraphEdge({
    required this.source,
    required this.target,
    required this.relationship,
    this.properties,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    return GraphEdge(
      source: json['source'] as String,
      target: json['target'] as String,
      relationship: json['relationship'] as String? ?? 'related',
      properties: json['properties'] as Map<String, dynamic>?,
    );
  }
}
