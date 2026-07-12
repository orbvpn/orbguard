/// Policy Management Service
///
/// Enterprise security policy management:
/// - Policy creation and configuration
/// - Policy assignment to devices/groups
/// - Compliance rule definitions
/// - Policy enforcement settings
/// - Conditional access rules

import 'dart:async';

import '../../api/orbguard_api_client.dart';

/// Policy type
enum PolicyType {
  security('Security', 'Security requirements'),
  compliance('Compliance', 'Compliance rules'),
  restriction('Restriction', 'Device restrictions'),
  configuration('Configuration', 'Device configuration'),
  conditional('Conditional Access', 'Access conditions'),
  byod('BYOD', 'Bring Your Own Device policies');

  final String displayName;
  final String description;

  const PolicyType(this.displayName, this.description);
}

/// Device ownership type for BYOD
enum DeviceOwnershipType {
  corporate('Corporate', 'Company-owned device'),
  personal('Personal', 'Employee-owned device (BYOD)'),
  shared('Shared', 'Shared/kiosk device'),
  contractor('Contractor', 'Third-party contractor device'),
  unknown('Unknown', 'Ownership not determined');

  final String displayName;
  final String description;

  const DeviceOwnershipType(this.displayName, this.description);

  static DeviceOwnershipType fromString(String? value) {
    return DeviceOwnershipType.values.firstWhere(
      (e) => e.name.toLowerCase() == value?.toLowerCase(),
      orElse: () => DeviceOwnershipType.unknown,
    );
  }
}

/// BYOD policy settings
class BYODPolicySettings {
  final bool allowPersonalApps;
  final bool requireWorkProfile;
  final bool allowCameraAccess;
  final bool allowLocationAccess;
  final bool allowClipboardSharing;
  final bool allowScreenCapture;
  final bool requireEncryption;
  final bool requirePasscode;
  final int minimumPasscodeLength;
  final bool requireBiometric;
  final bool allowUSBDebugging;
  final bool allowUnknownSources;
  final List<String> blockedApps;
  final List<String> requiredApps;
  final int maxInactivityLockMinutes;
  final int dataRetentionDays;
  final bool wipeOnUnenroll;
  final bool selectiveWipeOnly;

  BYODPolicySettings({
    this.allowPersonalApps = true,
    this.requireWorkProfile = true,
    this.allowCameraAccess = true,
    this.allowLocationAccess = true,
    this.allowClipboardSharing = false,
    this.allowScreenCapture = false,
    this.requireEncryption = true,
    this.requirePasscode = true,
    this.minimumPasscodeLength = 6,
    this.requireBiometric = false,
    this.allowUSBDebugging = false,
    this.allowUnknownSources = false,
    this.blockedApps = const [],
    this.requiredApps = const [],
    this.maxInactivityLockMinutes = 5,
    this.dataRetentionDays = 90,
    this.wipeOnUnenroll = false,
    this.selectiveWipeOnly = true,
  });

  factory BYODPolicySettings.fromJson(Map<String, dynamic> json) {
    return BYODPolicySettings(
      allowPersonalApps: json['allow_personal_apps'] as bool? ?? true,
      requireWorkProfile: json['require_work_profile'] as bool? ?? true,
      allowCameraAccess: json['allow_camera_access'] as bool? ?? true,
      allowLocationAccess: json['allow_location_access'] as bool? ?? true,
      allowClipboardSharing: json['allow_clipboard_sharing'] as bool? ?? false,
      allowScreenCapture: json['allow_screen_capture'] as bool? ?? false,
      requireEncryption: json['require_encryption'] as bool? ?? true,
      requirePasscode: json['require_passcode'] as bool? ?? true,
      minimumPasscodeLength: json['minimum_passcode_length'] as int? ?? 6,
      requireBiometric: json['require_biometric'] as bool? ?? false,
      allowUSBDebugging: json['allow_usb_debugging'] as bool? ?? false,
      allowUnknownSources: json['allow_unknown_sources'] as bool? ?? false,
      blockedApps: (json['blocked_apps'] as List<dynamic>?)?.cast<String>() ?? [],
      requiredApps: (json['required_apps'] as List<dynamic>?)?.cast<String>() ?? [],
      maxInactivityLockMinutes: json['max_inactivity_lock_minutes'] as int? ?? 5,
      dataRetentionDays: json['data_retention_days'] as int? ?? 90,
      wipeOnUnenroll: json['wipe_on_unenroll'] as bool? ?? false,
      selectiveWipeOnly: json['selective_wipe_only'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'allow_personal_apps': allowPersonalApps,
    'require_work_profile': requireWorkProfile,
    'allow_camera_access': allowCameraAccess,
    'allow_location_access': allowLocationAccess,
    'allow_clipboard_sharing': allowClipboardSharing,
    'allow_screen_capture': allowScreenCapture,
    'require_encryption': requireEncryption,
    'require_passcode': requirePasscode,
    'minimum_passcode_length': minimumPasscodeLength,
    'require_biometric': requireBiometric,
    'allow_usb_debugging': allowUSBDebugging,
    'allow_unknown_sources': allowUnknownSources,
    'blocked_apps': blockedApps,
    'required_apps': requiredApps,
    'max_inactivity_lock_minutes': maxInactivityLockMinutes,
    'data_retention_days': dataRetentionDays,
    'wipe_on_unenroll': wipeOnUnenroll,
    'selective_wipe_only': selectiveWipeOnly,
  };

  /// Get default corporate device settings (stricter)
  static BYODPolicySettings corporateDefaults() {
    return BYODPolicySettings(
      allowPersonalApps: false,
      requireWorkProfile: false,
      allowCameraAccess: true,
      allowLocationAccess: true,
      allowClipboardSharing: true,
      allowScreenCapture: true,
      requireEncryption: true,
      requirePasscode: true,
      minimumPasscodeLength: 8,
      requireBiometric: true,
      allowUSBDebugging: false,
      allowUnknownSources: false,
      blockedApps: [],
      requiredApps: ['com.orbguard.security'],
      maxInactivityLockMinutes: 2,
      dataRetentionDays: 365,
      wipeOnUnenroll: true,
      selectiveWipeOnly: false,
    );
  }

  /// Get default BYOD settings (balanced privacy/security)
  static BYODPolicySettings byodDefaults() {
    return BYODPolicySettings(
      allowPersonalApps: true,
      requireWorkProfile: true,
      allowCameraAccess: true,
      allowLocationAccess: true,
      allowClipboardSharing: false,
      allowScreenCapture: false,
      requireEncryption: true,
      requirePasscode: true,
      minimumPasscodeLength: 6,
      requireBiometric: false,
      allowUSBDebugging: false,
      allowUnknownSources: false,
      blockedApps: [],
      requiredApps: ['com.orbguard.security'],
      maxInactivityLockMinutes: 5,
      dataRetentionDays: 90,
      wipeOnUnenroll: false,
      selectiveWipeOnly: true,
    );
  }
}

/// BYOD enrollment request
class BYODEnrollmentRequest {
  final String userId;
  final String userEmail;
  final DeviceOwnershipType ownershipType;
  final String deviceModel;
  final String osVersion;
  final String serialNumber;
  final bool acceptedTerms;
  final DateTime requestedAt;

  BYODEnrollmentRequest({
    required this.userId,
    required this.userEmail,
    required this.ownershipType,
    required this.deviceModel,
    required this.osVersion,
    required this.serialNumber,
    required this.acceptedTerms,
    DateTime? requestedAt,
  }) : requestedAt = requestedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'user_email': userEmail,
    'ownership_type': ownershipType.name,
    'device_model': deviceModel,
    'os_version': osVersion,
    'serial_number': serialNumber,
    'accepted_terms': acceptedTerms,
    'requested_at': requestedAt.toIso8601String(),
  };
}

/// Policy enforcement level
enum EnforcementLevel {
  monitor('Monitor', 'Log violations only'),
  warn('Warn', 'Warn user of violations'),
  block('Block', 'Block non-compliant actions'),
  quarantine('Quarantine', 'Isolate non-compliant devices');

  final String displayName;
  final String description;

  const EnforcementLevel(this.displayName, this.description);
}

/// Policy rule model
class PolicyRule {
  final String id;
  final String name;
  final String description;
  final String condition;
  final String action;
  final Map<String, dynamic> parameters;
  final bool isEnabled;

  PolicyRule({
    required this.id,
    required this.name,
    required this.description,
    required this.condition,
    required this.action,
    this.parameters = const {},
    this.isEnabled = true,
  });

  factory PolicyRule.fromJson(Map<String, dynamic> json) {
    return PolicyRule(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      condition: json['condition'] as String? ?? '',
      action: json['action'] as String? ?? '',
      parameters: (json['parameters'] as Map<String, dynamic>?) ?? {},
      isEnabled: json['is_enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'condition': condition,
    'action': action,
    'parameters': parameters,
    'is_enabled': isEnabled,
  };
}

/// Security policy model
class SecurityPolicy {
  final String id;
  final String name;
  final String description;
  final PolicyType type;
  final EnforcementLevel enforcement;
  final List<PolicyRule> rules;
  final List<String> assignedGroups;
  final List<String> assignedDevices;
  final List<String> platforms; // iOS, Android, etc.
  final int priority;
  final bool isEnabled;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? createdBy;

  SecurityPolicy({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.enforcement,
    this.rules = const [],
    this.assignedGroups = const [],
    this.assignedDevices = const [],
    this.platforms = const [],
    this.priority = 0,
    this.isEnabled = true,
    this.isDefault = false,
    required this.createdAt,
    required this.updatedAt,
    this.createdBy,
  });

  factory SecurityPolicy.fromJson(Map<String, dynamic> json) {
    return SecurityPolicy(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: _parsePolicyType(json['type'] as String?),
      enforcement: _parseEnforcement(json['enforcement'] as String?),
      rules: (json['rules'] as List<dynamic>?)
              ?.map((r) => PolicyRule.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      assignedGroups: (json['assigned_groups'] as List<dynamic>?)?.cast<String>() ?? [],
      assignedDevices: (json['assigned_devices'] as List<dynamic>?)?.cast<String>() ?? [],
      platforms: (json['platforms'] as List<dynamic>?)?.cast<String>() ?? [],
      priority: json['priority'] as int? ?? 0,
      isEnabled: json['is_enabled'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
      createdBy: json['created_by'] as String?,
    );
  }

  static PolicyType _parsePolicyType(String? type) {
    switch (type?.toLowerCase()) {
      case 'security':
        return PolicyType.security;
      case 'compliance':
        return PolicyType.compliance;
      case 'restriction':
        return PolicyType.restriction;
      case 'configuration':
        return PolicyType.configuration;
      case 'conditional':
        return PolicyType.conditional;
      case 'byod':
        return PolicyType.byod;
      default:
        return PolicyType.security;
    }
  }

  static EnforcementLevel _parseEnforcement(String? level) {
    switch (level?.toLowerCase()) {
      case 'monitor':
        return EnforcementLevel.monitor;
      case 'warn':
        return EnforcementLevel.warn;
      case 'block':
        return EnforcementLevel.block;
      case 'quarantine':
        return EnforcementLevel.quarantine;
      default:
        return EnforcementLevel.warn;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'enforcement': enforcement.name,
    'rules': rules.map((r) => r.toJson()).toList(),
    'assigned_groups': assignedGroups,
    'assigned_devices': assignedDevices,
    'platforms': platforms,
    'priority': priority,
    'is_enabled': isEnabled,
    'is_default': isDefault,
  };
}

/// Policy violation record
class PolicyViolation {
  final String id;
  final String policyId;
  final String policyName;
  final String deviceId;
  final String deviceName;
  final String ruleId;
  final String ruleName;
  final String violationType;
  final String details;
  final String severity;
  final DateTime detectedAt;
  final bool isResolved;
  final DateTime? resolvedAt;

  PolicyViolation({
    required this.id,
    required this.policyId,
    required this.policyName,
    required this.deviceId,
    required this.deviceName,
    required this.ruleId,
    required this.ruleName,
    required this.violationType,
    required this.details,
    required this.severity,
    required this.detectedAt,
    this.isResolved = false,
    this.resolvedAt,
  });

  factory PolicyViolation.fromJson(Map<String, dynamic> json) {
    return PolicyViolation(
      id: json['id'] as String? ?? '',
      policyId: json['policy_id'] as String? ?? '',
      policyName: json['policy_name'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? '',
      ruleId: json['rule_id'] as String? ?? '',
      ruleName: json['rule_name'] as String? ?? '',
      violationType: json['violation_type'] as String? ?? '',
      details: json['details'] as String? ?? '',
      severity: json['severity'] as String? ?? 'medium',
      detectedAt: json['detected_at'] != null
          ? DateTime.parse(json['detected_at'] as String)
          : DateTime.now(),
      isResolved: json['is_resolved'] as bool? ?? false,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
    );
  }
}

/// Policy templates
class PolicyTemplate {
  final String id;
  final String name;
  final String description;
  final PolicyType type;
  final List<PolicyRule> rules;
  final String category; // HIPAA, PCI-DSS, SOC2, etc.

  PolicyTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.type,
    required this.rules,
    required this.category,
  });

  factory PolicyTemplate.fromJson(Map<String, dynamic> json) {
    return PolicyTemplate(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      type: SecurityPolicy._parsePolicyType(json['type'] as String?),
      rules: (json['rules'] as List<dynamic>?)
              ?.map((r) => PolicyRule.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      category: json['category'] as String? ?? 'General',
    );
  }
}

/// Policy Management Service
/// Uses local in-memory storage (enterprise API not yet implemented)
class PolicyManagementService {
  // API client
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // Cached data (local storage)
  List<SecurityPolicy> _policies = [];
  List<PolicyTemplate> _templates = [];
  List<PolicyViolation> _violations = [];
  int _nextPolicyId = 1;
  int _nextRuleId = 1;

  // Stream controllers
  final _policyUpdateController = StreamController<SecurityPolicy>.broadcast();
  final _violationController = StreamController<PolicyViolation>.broadcast();

  Stream<SecurityPolicy> get onPolicyUpdate => _policyUpdateController.stream;
  Stream<PolicyViolation> get onViolation => _violationController.stream;

  // Getters
  List<SecurityPolicy> get policies => List.unmodifiable(_policies);
  List<PolicyTemplate> get templates => List.unmodifiable(_templates);

  /// Initialize the service
  Future<void> initialize() async {
    await Future.wait([
      loadPolicies(),
      loadTemplates(),
    ]);
  }

  /// Load all policies (local storage)
  Future<List<SecurityPolicy>> loadPolicies() async {
    // Return cached policies (in real impl, would sync with API)
    return _policies;
  }

  /// Get single policy
  Future<SecurityPolicy?> getPolicy(String policyId) async {
    return _policies.where((p) => p.id == policyId).firstOrNull;
  }

  /// Create new policy (local storage)
  Future<SecurityPolicy?> createPolicy({
    required String name,
    required String description,
    required PolicyType type,
    required EnforcementLevel enforcement,
    List<PolicyRule>? rules,
    List<String>? platforms,
    int priority = 0,
  }) async {
    final now = DateTime.now();
    final policy = SecurityPolicy(
      id: 'policy-${_nextPolicyId++}',
      name: name,
      description: description,
      type: type,
      enforcement: enforcement,
      rules: rules ?? [],
      platforms: platforms ?? [],
      priority: priority,
      createdAt: now,
      updatedAt: now,
    );

    _policies.add(policy);
    _policyUpdateController.add(policy);
    return policy;
  }

  /// Update policy (local storage)
  Future<SecurityPolicy?> updatePolicy(
    String policyId, {
    String? name,
    String? description,
    EnforcementLevel? enforcement,
    List<PolicyRule>? rules,
    List<String>? platforms,
    int? priority,
    bool? isEnabled,
  }) async {
    final index = _policies.indexWhere((p) => p.id == policyId);
    if (index < 0) return null;

    final existing = _policies[index];
    final updated = SecurityPolicy(
      id: existing.id,
      name: name ?? existing.name,
      description: description ?? existing.description,
      type: existing.type,
      enforcement: enforcement ?? existing.enforcement,
      rules: rules ?? existing.rules,
      platforms: platforms ?? existing.platforms,
      priority: priority ?? existing.priority,
      isEnabled: isEnabled ?? existing.isEnabled,
      isDefault: existing.isDefault,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now(),
      createdBy: existing.createdBy,
    );

    _policies[index] = updated;
    _policyUpdateController.add(updated);
    return updated;
  }

  /// Delete policy (local storage)
  Future<bool> deletePolicy(String policyId) async {
    _policies.removeWhere((p) => p.id == policyId);
    return true;
  }

  /// Assign policy to groups
  Future<bool> assignPolicyToGroups(
    String policyId,
    List<String> groupIds,
  ) async {
    try {
      return await _api.assignPolicyToGroups(policyId, groupIds);
    } catch (e) {
      return false;
    }
  }

  /// Assign policy to devices
  Future<bool> assignPolicyToDevices(
    String policyId,
    List<String> deviceIds,
  ) async {
    try {
      return await _api.assignPolicyToDevices(policyId, deviceIds);
    } catch (e) {
      return false;
    }
  }

  /// Remove policy assignment
  Future<bool> removePolicyAssignment(
    String policyId, {
    List<String>? groupIds,
    List<String>? deviceIds,
  }) async {
    try {
      return await _api.removePolicyAssignment(policyId, groupIds: groupIds, deviceIds: deviceIds);
    } catch (e) {
      return false;
    }
  }

  /// Add rule to policy (local storage)
  Future<PolicyRule?> addRule(String policyId, PolicyRule rule) async {
    final index = _policies.indexWhere((p) => p.id == policyId);
    if (index < 0) return null;

    final newRule = PolicyRule(
      id: 'rule-${_nextRuleId++}',
      name: rule.name,
      description: rule.description,
      condition: rule.condition,
      action: rule.action,
      parameters: rule.parameters,
      isEnabled: rule.isEnabled,
    );

    // Create new policy with added rule
    final existing = _policies[index];
    final updatedRules = [...existing.rules, newRule];
    await updatePolicy(policyId, rules: updatedRules);

    return newRule;
  }

  /// Update rule (local storage)
  Future<bool> updateRule(
    String policyId,
    String ruleId,
    PolicyRule rule,
  ) async {
    final policyIndex = _policies.indexWhere((p) => p.id == policyId);
    if (policyIndex < 0) return false;

    final existing = _policies[policyIndex];
    final updatedRules = existing.rules.map((r) {
      if (r.id == ruleId) return rule;
      return r;
    }).toList();

    await updatePolicy(policyId, rules: updatedRules);
    return true;
  }

  /// Delete rule (local storage)
  Future<bool> deleteRule(String policyId, String ruleId) async {
    final policyIndex = _policies.indexWhere((p) => p.id == policyId);
    if (policyIndex < 0) return false;

    final existing = _policies[policyIndex];
    final updatedRules = existing.rules.where((r) => r.id != ruleId).toList();

    await updatePolicy(policyId, rules: updatedRules);
    return true;
  }

  /// Load policy templates (local storage)
  Future<List<PolicyTemplate>> loadTemplates() async {
    _templates = _getDefaultTemplates();
    return _templates;
  }

  List<PolicyTemplate> _getDefaultTemplates() {
    return [
      PolicyTemplate(
        id: 'template-basic-security',
        name: 'Basic Security',
        description: 'Essential security requirements for all devices',
        type: PolicyType.security,
        category: 'General',
        rules: [
          PolicyRule(
            id: 'rule-passcode',
            name: 'Require Passcode',
            description: 'Device must have a passcode set',
            condition: 'device.has_passcode == false',
            action: 'mark_non_compliant',
          ),
          PolicyRule(
            id: 'rule-encryption',
            name: 'Require Encryption',
            description: 'Device storage must be encrypted',
            condition: 'device.is_encrypted == false',
            action: 'mark_non_compliant',
          ),
          PolicyRule(
            id: 'rule-no-root',
            name: 'No Root/Jailbreak',
            description: 'Device must not be rooted or jailbroken',
            condition: 'device.is_rooted == true',
            action: 'quarantine',
          ),
        ],
      ),
      PolicyTemplate(
        id: 'template-hipaa',
        name: 'HIPAA Compliance',
        description: 'Healthcare data protection requirements',
        type: PolicyType.compliance,
        category: 'HIPAA',
        rules: [
          PolicyRule(
            id: 'rule-hipaa-encryption',
            name: 'Encryption Required',
            description: 'All data must be encrypted at rest and in transit',
            condition: 'device.is_encrypted == false',
            action: 'block',
          ),
          PolicyRule(
            id: 'rule-hipaa-timeout',
            name: 'Auto-lock Timeout',
            description: 'Screen must auto-lock within 2 minutes',
            condition: 'device.screen_timeout > 120',
            action: 'mark_non_compliant',
          ),
        ],
      ),
      PolicyTemplate(
        id: 'template-pci-dss',
        name: 'PCI-DSS Compliance',
        description: 'Payment card industry requirements',
        type: PolicyType.compliance,
        category: 'PCI-DSS',
        rules: [
          PolicyRule(
            id: 'rule-pci-passcode',
            name: 'Strong Passcode',
            description: 'Minimum 6-digit PIN or complex password',
            condition: 'device.passcode_strength < 6',
            action: 'block',
          ),
        ],
      ),
    ];
  }

  /// Create policy from template
  Future<SecurityPolicy?> createFromTemplate(
    String templateId, {
    required String name,
    String? description,
    EnforcementLevel enforcement = EnforcementLevel.warn,
  }) async {
    final template = _templates.where((t) => t.id == templateId).firstOrNull;
    if (template == null) return null;

    return createPolicy(
      name: name,
      description: description ?? template.description,
      type: template.type,
      enforcement: enforcement,
      rules: template.rules,
    );
  }

  /// Get policy violations (local storage)
  Future<List<PolicyViolation>> getViolations({
    String? policyId,
    String? deviceId,
    bool unresolvedOnly = false,
    int limit = 100,
  }) async {
    var violations = _violations.toList();

    if (policyId != null) {
      violations = violations.where((v) => v.policyId == policyId).toList();
    }
    if (deviceId != null) {
      violations = violations.where((v) => v.deviceId == deviceId).toList();
    }
    if (unresolvedOnly) {
      violations = violations.where((v) => !v.isResolved).toList();
    }

    return violations.take(limit).toList();
  }

  /// Resolve violation (local storage)
  Future<bool> resolveViolation(String violationId, {String? notes}) async {
    final index = _violations.indexWhere((v) => v.id == violationId);
    if (index >= 0) {
      _violations.removeAt(index);
    }
    return true;
  }

  /// Evaluate device compliance
  Future<Map<String, dynamic>> evaluateCompliance(String deviceId) async {
    try {
      return await _api.evaluateDeviceCompliance(deviceId);
    } catch (e) {
      return {
        'is_compliant': true,
        'violations': <Map<String, dynamic>>[],
        'evaluated_at': DateTime.now().toIso8601String(),
        'error': e.toString(),
      };
    }
  }

  // ========== BYOD POLICY METHODS ==========

  /// Get BYOD policy for a device ownership type
  Future<SecurityPolicy?> getBYODPolicy(DeviceOwnershipType ownershipType) async {
    return _policies.where((p) => p.type == PolicyType.byod).firstOrNull;
  }

  /// Create BYOD policy with settings (local storage)
  Future<SecurityPolicy?> createBYODPolicy({
    required String name,
    required String description,
    required DeviceOwnershipType targetOwnership,
    required BYODPolicySettings settings,
    EnforcementLevel enforcement = EnforcementLevel.warn,
    List<String>? platforms,
  }) async {
    final rules = _generateBYODRules(settings);
    return createPolicy(
      name: name,
      description: description,
      type: PolicyType.byod,
      enforcement: enforcement,
      rules: rules,
      platforms: platforms,
    );
  }

  /// Generate BYOD rules from settings
  List<PolicyRule> _generateBYODRules(BYODPolicySettings settings) {
    final rules = <PolicyRule>[];

    if (settings.requireEncryption) {
      rules.add(PolicyRule(
        id: 'byod-encryption',
        name: 'Require Encryption',
        description: 'Device storage must be encrypted',
        condition: 'device.is_encrypted == false',
        action: 'block',
      ));
    }

    if (settings.requirePasscode) {
      rules.add(PolicyRule(
        id: 'byod-passcode',
        name: 'Require Passcode',
        description: 'Device must have a passcode of at least ${settings.minimumPasscodeLength} characters',
        condition: 'device.passcode_length < ${settings.minimumPasscodeLength}',
        action: 'mark_non_compliant',
        parameters: {'min_length': settings.minimumPasscodeLength},
      ));
    }

    if (settings.requireBiometric) {
      rules.add(PolicyRule(
        id: 'byod-biometric',
        name: 'Require Biometric',
        description: 'Device must have biometric authentication enabled',
        condition: 'device.has_biometric == false',
        action: 'warn',
      ));
    }

    if (!settings.allowUSBDebugging) {
      rules.add(PolicyRule(
        id: 'byod-no-usb-debug',
        name: 'Disable USB Debugging',
        description: 'USB debugging must be disabled',
        condition: 'device.usb_debugging == true',
        action: 'mark_non_compliant',
      ));
    }

    if (!settings.allowUnknownSources) {
      rules.add(PolicyRule(
        id: 'byod-no-unknown-sources',
        name: 'Block Unknown Sources',
        description: 'Installing apps from unknown sources must be disabled',
        condition: 'device.unknown_sources == true',
        action: 'mark_non_compliant',
      ));
    }

    if (settings.requireWorkProfile) {
      rules.add(PolicyRule(
        id: 'byod-work-profile',
        name: 'Require Work Profile',
        description: 'Android Work Profile must be enabled for BYOD devices',
        condition: 'device.platform == "android" && device.has_work_profile == false',
        action: 'warn',
      ));
    }

    if (settings.blockedApps.isNotEmpty) {
      rules.add(PolicyRule(
        id: 'byod-blocked-apps',
        name: 'Blocked Apps',
        description: 'Certain apps are not allowed on enrolled devices',
        condition: 'device.installed_apps intersects blocked_apps',
        action: 'warn',
        parameters: {'blocked_apps': settings.blockedApps},
      ));
    }

    if (settings.requiredApps.isNotEmpty) {
      rules.add(PolicyRule(
        id: 'byod-required-apps',
        name: 'Required Apps',
        description: 'Certain apps must be installed on enrolled devices',
        condition: 'NOT(device.installed_apps contains required_apps)',
        action: 'mark_non_compliant',
        parameters: {'required_apps': settings.requiredApps},
      ));
    }

    rules.add(PolicyRule(
      id: 'byod-auto-lock',
      name: 'Auto-lock Timeout',
      description: 'Screen must auto-lock within ${settings.maxInactivityLockMinutes} minutes',
      condition: 'device.screen_timeout > ${settings.maxInactivityLockMinutes * 60}',
      action: 'warn',
      parameters: {'max_timeout_seconds': settings.maxInactivityLockMinutes * 60},
    ));

    return rules;
  }

  /// Enroll device as BYOD
  Future<Map<String, dynamic>> enrollBYODDevice(BYODEnrollmentRequest request) async {
    try {
      return await _api.enrollBYODDevice(request.toJson());
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get BYOD enrollment status
  Future<Map<String, dynamic>> getBYODEnrollmentStatus(String deviceId) async {
    try {
      return await _api.getBYODEnrollmentStatus(deviceId);
    } catch (e) {
      return {
        'is_enrolled': false,
        'ownership_type': 'unknown',
        'error': e.toString(),
      };
    }
  }

  /// Unenroll BYOD device
  Future<bool> unenrollBYODDevice(String deviceId, {bool wipeWorkData = true}) async {
    try {
      return await _api.unenrollBYODDevice(deviceId, wipeWorkData: wipeWorkData);
    } catch (e) {
      return false;
    }
  }

  /// Get BYOD policy templates
  List<PolicyTemplate> getBYODTemplates() {
    return [
      PolicyTemplate(
        id: 'template-byod-standard',
        name: 'Standard BYOD',
        description: 'Balanced security and privacy for personal devices',
        type: PolicyType.byod,
        category: 'BYOD',
        rules: _generateBYODRules(BYODPolicySettings.byodDefaults()),
      ),
      PolicyTemplate(
        id: 'template-byod-strict',
        name: 'Strict BYOD',
        description: 'Enhanced security for BYOD with sensitive data access',
        type: PolicyType.byod,
        category: 'BYOD',
        rules: _generateBYODRules(BYODPolicySettings(
          allowPersonalApps: true,
          requireWorkProfile: true,
          allowClipboardSharing: false,
          allowScreenCapture: false,
          requireEncryption: true,
          requirePasscode: true,
          minimumPasscodeLength: 8,
          requireBiometric: true,
          allowUSBDebugging: false,
          allowUnknownSources: false,
          maxInactivityLockMinutes: 2,
          wipeOnUnenroll: false,
          selectiveWipeOnly: true,
        )),
      ),
      PolicyTemplate(
        id: 'template-corporate',
        name: 'Corporate Device',
        description: 'Full management for company-owned devices',
        type: PolicyType.byod,
        category: 'Corporate',
        rules: _generateBYODRules(BYODPolicySettings.corporateDefaults()),
      ),
      PolicyTemplate(
        id: 'template-contractor',
        name: 'Contractor Device',
        description: 'Temporary access policy for contractor devices',
        type: PolicyType.byod,
        category: 'Contractor',
        rules: _generateBYODRules(BYODPolicySettings(
          allowPersonalApps: true,
          requireWorkProfile: true,
          allowClipboardSharing: false,
          allowScreenCapture: false,
          requireEncryption: true,
          requirePasscode: true,
          minimumPasscodeLength: 6,
          requireBiometric: false,
          allowUSBDebugging: false,
          allowUnknownSources: false,
          dataRetentionDays: 30,
          wipeOnUnenroll: true,
          selectiveWipeOnly: true,
        )),
      ),
    ];
  }

  /// Check device ownership type
  Future<DeviceOwnershipType> detectDeviceOwnership(String deviceId) async {
    try {
      final ownershipStr = await _api.detectDeviceOwnership(deviceId);
      return DeviceOwnershipType.values.firstWhere(
        (t) => t.name == ownershipStr,
        orElse: () => DeviceOwnershipType.unknown,
      );
    } catch (e) {
      return DeviceOwnershipType.unknown;
    }
  }

  /// Set device ownership type
  Future<bool> setDeviceOwnership(String deviceId, DeviceOwnershipType ownershipType) async {
    try {
      return await _api.setDeviceOwnership(deviceId, ownershipType.name);
    } catch (e) {
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _policyUpdateController.close();
    _violationController.close();
  }
}
