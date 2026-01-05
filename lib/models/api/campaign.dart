/// Campaign and Threat Actor Models
/// Models for campaigns and threat actors from OrbGuard Lab API

import 'threat_indicator.dart';

/// Threat campaign
class Campaign {
  final String id;
  final String name;
  final String? description;
  final String? objective;
  final List<String> aliases;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final bool isActive;
  final List<String> targetedPlatforms;
  final List<String> targetedCountries;
  final List<String> targetedIndustries;
  final List<String> mitreTechniques;
  final List<String> associatedActors;
  final int indicatorCount;
  final SeverityLevel severity;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  Campaign({
    required this.id,
    required this.name,
    this.description,
    this.objective,
    required this.aliases,
    this.firstSeen,
    this.lastSeen,
    required this.isActive,
    required this.targetedPlatforms,
    required this.targetedCountries,
    required this.targetedIndustries,
    required this.mitreTechniques,
    required this.associatedActors,
    required this.indicatorCount,
    required this.severity,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  factory Campaign.fromJson(Map<String, dynamic> json) {
    return Campaign(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      objective: json['objective'] as String?,
      aliases: (json['aliases'] as List<dynamic>?)?.cast<String>() ?? [],
      firstSeen: json['first_seen'] != null
          ? DateTime.parse(json['first_seen'] as String)
          : null,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? false,
      targetedPlatforms:
          (json['targeted_platforms'] as List<dynamic>?)?.cast<String>() ?? [],
      targetedCountries:
          (json['targeted_countries'] as List<dynamic>?)?.cast<String>() ?? [],
      targetedIndustries:
          (json['targeted_industries'] as List<dynamic>?)?.cast<String>() ?? [],
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>() ?? [],
      associatedActors:
          (json['associated_actors'] as List<dynamic>?)?.cast<String>() ?? [],
      indicatorCount: json['indicator_count'] as int? ?? 0,
      severity:
          SeverityLevel.fromString(json['severity'] as String? ?? 'unknown'),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'objective': objective,
      'aliases': aliases,
      'first_seen': firstSeen?.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
      'is_active': isActive,
      'targeted_platforms': targetedPlatforms,
      'targeted_countries': targetedCountries,
      'targeted_industries': targetedIndustries,
      'mitre_techniques': mitreTechniques,
      'associated_actors': associatedActors,
      'indicator_count': indicatorCount,
      'severity': severity.value,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Check if campaign targets mobile platforms
  bool get targetsMobile =>
      targetedPlatforms.contains('android') ||
      targetedPlatforms.contains('ios') ||
      targetedPlatforms.contains('mobile');

  /// Get duration of campaign activity
  Duration? get activeDuration {
    if (firstSeen == null) return null;
    final end = lastSeen ?? DateTime.now();
    return end.difference(firstSeen!);
  }
}

/// Threat actor type
enum ActorType {
  nationState('nation_state'),
  criminalGroup('criminal_group'),
  hacktivist('hacktivist'),
  insider('insider'),
  unknown('unknown');

  final String value;
  const ActorType(this.value);

  static ActorType fromString(String value) {
    return ActorType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ActorType.unknown,
    );
  }

  String get displayName {
    switch (this) {
      case ActorType.nationState:
        return 'Nation State';
      case ActorType.criminalGroup:
        return 'Criminal Group';
      case ActorType.hacktivist:
        return 'Hacktivist';
      case ActorType.insider:
        return 'Insider Threat';
      case ActorType.unknown:
        return 'Unknown';
    }
  }
}

/// Motivation types
enum ActorMotivation {
  financial('financial'),
  espionage('espionage'),
  sabotage('sabotage'),
  hacktivism('hacktivism'),
  unknown('unknown');

  final String value;
  const ActorMotivation(this.value);

  static ActorMotivation fromString(String value) {
    return ActorMotivation.values.firstWhere(
      (e) => e.value == value,
      orElse: () => ActorMotivation.unknown,
    );
  }
}

/// Threat actor
class ThreatActor {
  final String id;
  final String name;
  final String? description;
  final ActorType type;
  final List<String> aliases;
  final List<ActorMotivation> motivations;
  final String? country;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final bool isActive;
  final List<String> targetedPlatforms;
  final List<String> targetedCountries;
  final List<String> targetedIndustries;
  final List<String> mitreTechniques;
  final List<String> associatedCampaigns;
  final List<String> tools;
  final int indicatorCount;
  final SeverityLevel sophisticationLevel;
  final List<String>? references;
  final DateTime createdAt;
  final DateTime updatedAt;

  ThreatActor({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.aliases,
    required this.motivations,
    this.country,
    this.firstSeen,
    this.lastSeen,
    required this.isActive,
    required this.targetedPlatforms,
    required this.targetedCountries,
    required this.targetedIndustries,
    required this.mitreTechniques,
    required this.associatedCampaigns,
    required this.tools,
    required this.indicatorCount,
    required this.sophisticationLevel,
    this.references,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ThreatActor.fromJson(Map<String, dynamic> json) {
    return ThreatActor(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      type: ActorType.fromString(json['type'] as String? ?? 'unknown'),
      aliases: (json['aliases'] as List<dynamic>?)?.cast<String>() ?? [],
      motivations: (json['motivations'] as List<dynamic>?)
              ?.map((m) => ActorMotivation.fromString(m as String))
              .toList() ??
          [],
      country: json['country'] as String?,
      firstSeen: json['first_seen'] != null
          ? DateTime.parse(json['first_seen'] as String)
          : null,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? false,
      targetedPlatforms:
          (json['targeted_platforms'] as List<dynamic>?)?.cast<String>() ?? [],
      targetedCountries:
          (json['targeted_countries'] as List<dynamic>?)?.cast<String>() ?? [],
      targetedIndustries:
          (json['targeted_industries'] as List<dynamic>?)?.cast<String>() ?? [],
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>() ?? [],
      associatedCampaigns:
          (json['associated_campaigns'] as List<dynamic>?)?.cast<String>() ??
              [],
      tools: (json['tools'] as List<dynamic>?)?.cast<String>() ?? [],
      indicatorCount: json['indicator_count'] as int? ?? 0,
      sophisticationLevel: SeverityLevel.fromString(
          json['sophistication_level'] as String? ?? 'unknown'),
      references: (json['references'] as List<dynamic>?)?.cast<String>(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.value,
      'aliases': aliases,
      'motivations': motivations.map((m) => m.value).toList(),
      'country': country,
      'first_seen': firstSeen?.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
      'is_active': isActive,
      'targeted_platforms': targetedPlatforms,
      'targeted_countries': targetedCountries,
      'targeted_industries': targetedIndustries,
      'mitre_techniques': mitreTechniques,
      'associated_campaigns': associatedCampaigns,
      'tools': tools,
      'indicator_count': indicatorCount,
      'sophistication_level': sophisticationLevel.value,
      'references': references,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Check if actor is nation-state sponsored
  bool get isNationState => type == ActorType.nationState;

  /// Check if actor targets mobile
  bool get targetsMobile =>
      targetedPlatforms.contains('android') ||
      targetedPlatforms.contains('ios');

  /// Get primary motivation
  ActorMotivation? get primaryMotivation =>
      motivations.isNotEmpty ? motivations.first : null;
}

/// MITRE ATT&CK tactic
class MitreTactic {
  final String id;
  final String name;
  final String? description;
  final String? shortName;
  final int techniqueCount;
  final String domain;

  MitreTactic({
    required this.id,
    required this.name,
    this.description,
    this.shortName,
    required this.techniqueCount,
    required this.domain,
  });

  factory MitreTactic.fromJson(Map<String, dynamic> json) {
    return MitreTactic(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      shortName: json['short_name'] as String?,
      techniqueCount: json['technique_count'] as int? ?? 0,
      domain: json['domain'] as String? ?? 'mobile-attack',
    );
  }
}

/// MITRE ATT&CK technique
class MitreTechnique {
  final String id;
  final String name;
  final String? description;
  final String tacticId;
  final String? tacticName;
  final bool isSubtechnique;
  final String? parentId;
  final List<String> platforms;
  final List<String>? dataSources;
  final List<String>? detections;
  final List<String>? mitigations;
  final String? url;

  MitreTechnique({
    required this.id,
    required this.name,
    this.description,
    required this.tacticId,
    this.tacticName,
    required this.isSubtechnique,
    this.parentId,
    required this.platforms,
    this.dataSources,
    this.detections,
    this.mitigations,
    this.url,
  });

  factory MitreTechnique.fromJson(Map<String, dynamic> json) {
    return MitreTechnique(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      tacticId: json['tactic_id'] as String? ?? '',
      tacticName: json['tactic_name'] as String?,
      isSubtechnique: json['is_subtechnique'] as bool? ?? false,
      parentId: json['parent_id'] as String?,
      platforms: (json['platforms'] as List<dynamic>?)?.cast<String>() ?? [],
      dataSources: (json['data_sources'] as List<dynamic>?)?.cast<String>(),
      detections: (json['detections'] as List<dynamic>?)?.cast<String>(),
      mitigations: (json['mitigations'] as List<dynamic>?)?.cast<String>(),
      url: json['url'] as String?,
    );
  }

  /// Check if technique applies to mobile
  bool get isMobile =>
      platforms.contains('Android') ||
      platforms.contains('iOS') ||
      platforms.contains('mobile');

  /// Get MITRE ATT&CK URL
  String get attackUrl =>
      url ??
      'https://attack.mitre.org/techniques/${id.replaceAll('.', '/')}';
}

/// Tool/malware information
class MalwareTool {
  final String id;
  final String name;
  final String? description;
  final String type;
  final List<String> aliases;
  final List<String> platforms;
  final List<String> associatedActors;
  final List<String> mitreTechniques;
  final String? url;

  MalwareTool({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.aliases,
    required this.platforms,
    required this.associatedActors,
    required this.mitreTechniques,
    this.url,
  });

  factory MalwareTool.fromJson(Map<String, dynamic> json) {
    return MalwareTool(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      type: json['type'] as String? ?? 'unknown',
      aliases: (json['aliases'] as List<dynamic>?)?.cast<String>() ?? [],
      platforms: (json['platforms'] as List<dynamic>?)?.cast<String>() ?? [],
      associatedActors:
          (json['associated_actors'] as List<dynamic>?)?.cast<String>() ?? [],
      mitreTechniques:
          (json['mitre_techniques'] as List<dynamic>?)?.cast<String>() ?? [],
      url: json['url'] as String?,
    );
  }
}

/// Campaign timeline event
class CampaignEvent {
  final String id;
  final String campaignId;
  final DateTime timestamp;
  final String eventType;
  final String description;
  final List<String>? indicators;
  final String? source;

  CampaignEvent({
    required this.id,
    required this.campaignId,
    required this.timestamp,
    required this.eventType,
    required this.description,
    this.indicators,
    this.source,
  });

  factory CampaignEvent.fromJson(Map<String, dynamic> json) {
    return CampaignEvent(
      id: json['id'] as String,
      campaignId: json['campaign_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      eventType: json['event_type'] as String? ?? 'unknown',
      description: json['description'] as String? ?? '',
      indicators: (json['indicators'] as List<dynamic>?)?.cast<String>(),
      source: json['source'] as String?,
    );
  }
}
