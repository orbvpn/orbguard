/// Policy Management Service
///
/// Read model + fetch layer for the backend's Zero Trust conditional
/// access policies (GET /api/v1/enterprise/policies).
///
/// Policies are authored and enforced server-side; the app renders them.
/// Parsing is deliberately defensive: any field the backend stops sending
/// becomes null/empty and is rendered as "not available" by the UI.
library;

import '../../api/orbguard_api_client.dart';

/// Conditional access policy as served by the backend.
class ConditionalAccessPolicy {
  final String id;
  final String name;
  final String description;
  final bool enabled;
  final int? priority; // lower = higher priority; null if not provided
  final PolicyConditions conditions;
  final PolicyGrantControls grantControls;
  final List<String> includeUsers;
  final List<String> excludeUsers;
  final List<String> includeGroups;
  final List<String> excludeGroups;
  final List<String> includeApps;
  final List<String> excludeApps;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ConditionalAccessPolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.enabled,
    required this.priority,
    required this.conditions,
    required this.grantControls,
    this.includeUsers = const [],
    this.excludeUsers = const [],
    this.includeGroups = const [],
    this.excludeGroups = const [],
    this.includeApps = const [],
    this.excludeApps = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory ConditionalAccessPolicy.fromJson(Map<String, dynamic> json) {
    return ConditionalAccessPolicy(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      priority: (json['priority'] as num?)?.toInt(),
      conditions: PolicyConditions.fromJson(
          json['conditions'] as Map<String, dynamic>? ?? const {}),
      grantControls: PolicyGrantControls.fromJson(
          json['grant_controls'] as Map<String, dynamic>? ?? const {}),
      includeUsers: _stringList(json['include_users']),
      excludeUsers: _stringList(json['exclude_users']),
      includeGroups: _stringList(json['include_groups']),
      excludeGroups: _stringList(json['exclude_groups']),
      includeApps: _stringList(json['include_apps']),
      excludeApps: _stringList(json['exclude_apps']),
      createdAt: _dateTime(json['created_at']),
      updatedAt: _dateTime(json['updated_at']),
    );
  }

  /// True when the policy applies to everyone (no user/group scoping).
  bool get appliesToAll =>
      includeUsers.isEmpty && includeGroups.isEmpty && includeApps.isEmpty;
}

/// Conditions under which a policy applies. All fields optional — the
/// backend omits conditions that are not configured.
class PolicyConditions {
  final String? minTrustLevel;
  final int? minPostureScore;
  final bool requireCompliance;
  final bool requireManaged;
  final bool requireVpn;
  final bool requireSecureNetwork;
  final bool blockOnActiveThreats;
  final String? maxRiskLevel;
  final List<String> allowedPlatforms;
  final List<String> blockedPlatforms;
  final List<String> allowedCountries;
  final List<String> blockedCountries;
  final List<String> allowedNetworks;
  final List<String> blockedNetworks;

  PolicyConditions({
    this.minTrustLevel,
    this.minPostureScore,
    this.requireCompliance = false,
    this.requireManaged = false,
    this.requireVpn = false,
    this.requireSecureNetwork = false,
    this.blockOnActiveThreats = false,
    this.maxRiskLevel,
    this.allowedPlatforms = const [],
    this.blockedPlatforms = const [],
    this.allowedCountries = const [],
    this.blockedCountries = const [],
    this.allowedNetworks = const [],
    this.blockedNetworks = const [],
  });

  factory PolicyConditions.fromJson(Map<String, dynamic> json) {
    return PolicyConditions(
      minTrustLevel: json['min_trust_level']?.toString(),
      minPostureScore: (json['min_posture_score'] as num?)?.toInt(),
      requireCompliance: json['require_compliance'] as bool? ?? false,
      requireManaged: json['require_managed'] as bool? ?? false,
      requireVpn: json['require_vpn'] as bool? ?? false,
      requireSecureNetwork: json['require_secure_network'] as bool? ?? false,
      blockOnActiveThreats: json['block_on_active_threats'] as bool? ?? false,
      maxRiskLevel: json['max_risk_level']?.toString(),
      allowedPlatforms: _stringList(json['allowed_platforms']),
      blockedPlatforms: _stringList(json['blocked_platforms']),
      allowedCountries: _stringList(json['allowed_countries']),
      blockedCountries: _stringList(json['blocked_countries']),
      allowedNetworks: _stringList(json['allowed_networks']),
      blockedNetworks: _stringList(json['blocked_networks']),
    );
  }

  /// Human-readable summary lines for the configured conditions.
  List<String> get summary {
    final lines = <String>[];
    if (minTrustLevel != null) lines.add('Minimum trust level: $minTrustLevel');
    if (minPostureScore != null) {
      lines.add('Minimum posture score: $minPostureScore');
    }
    if (requireCompliance) lines.add('Device must be compliant');
    if (requireManaged) lines.add('Device must be managed');
    if (requireVpn) lines.add('VPN required');
    if (requireSecureNetwork) lines.add('Secure network required');
    if (blockOnActiveThreats) lines.add('Blocked while threats are active');
    if (maxRiskLevel != null) lines.add('Maximum risk level: $maxRiskLevel');
    if (allowedPlatforms.isNotEmpty) {
      lines.add('Allowed platforms: ${allowedPlatforms.join(', ')}');
    }
    if (blockedPlatforms.isNotEmpty) {
      lines.add('Blocked platforms: ${blockedPlatforms.join(', ')}');
    }
    if (allowedCountries.isNotEmpty) {
      lines.add('Allowed countries: ${allowedCountries.join(', ')}');
    }
    if (blockedCountries.isNotEmpty) {
      lines.add('Blocked countries: ${blockedCountries.join(', ')}');
    }
    if (allowedNetworks.isNotEmpty) {
      lines.add('Allowed networks: ${allowedNetworks.join(', ')}');
    }
    if (blockedNetworks.isNotEmpty) {
      lines.add('Blocked networks: ${blockedNetworks.join(', ')}');
    }
    return lines;
  }
}

/// Grant controls — what is required when the policy matches.
class PolicyGrantControls {
  final String? operator; // AND / OR
  final bool requireMfa;
  final bool requireApprovedApp;
  final bool requirePasswordChange;
  final String? termsOfUse;
  final List<String> customControls;

  PolicyGrantControls({
    this.operator,
    this.requireMfa = false,
    this.requireApprovedApp = false,
    this.requirePasswordChange = false,
    this.termsOfUse,
    this.customControls = const [],
  });

  factory PolicyGrantControls.fromJson(Map<String, dynamic> json) {
    return PolicyGrantControls(
      operator: json['operator'] as String?,
      requireMfa: json['require_mfa'] as bool? ?? false,
      requireApprovedApp: json['require_approved_app'] as bool? ?? false,
      requirePasswordChange: json['require_password_change'] as bool? ?? false,
      termsOfUse: json['terms_of_use'] as String?,
      customControls: _stringList(json['custom_controls']),
    );
  }

  /// Human-readable summary lines for the configured grant controls.
  List<String> get summary {
    final lines = <String>[];
    if (requireMfa) lines.add('Multi-factor authentication required');
    if (requireApprovedApp) lines.add('Approved client app required');
    if (requirePasswordChange) lines.add('Password change required');
    if (termsOfUse != null && termsOfUse!.isNotEmpty) {
      lines.add('Terms of use: $termsOfUse');
    }
    for (final c in customControls) {
      lines.add('Custom control: $c');
    }
    return lines;
  }
}

List<String> _stringList(dynamic value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return const [];
}

DateTime? _dateTime(dynamic value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
}

/// Fetches conditional access policies from the backend.
class PolicyManagementService {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  /// Load all conditional access policies. Throws [ApiError] on failure.
  Future<List<ConditionalAccessPolicy>> fetchPolicies() async {
    final raw = await _api.getEnterprisePolicies();
    return raw.map(ConditionalAccessPolicy.fromJson).toList();
  }
}
