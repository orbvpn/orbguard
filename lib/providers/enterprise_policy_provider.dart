/// Enterprise Policy Provider
/// State management for enterprise security policy management

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/security/enterprise/policy_management_service.dart';

class EnterprisePolicyProvider extends ChangeNotifier {
  final PolicyManagementService _service = PolicyManagementService();

  // State
  List<SecurityPolicy> _policies = [];
  List<PolicyTemplate> _templates = [];
  List<PolicyViolation> _violations = [];
  SecurityPolicy? _selectedPolicy;

  // Loading states
  bool _isLoading = false;
  bool _isSaving = false;

  // Error state
  String? _error;

  // Stream subscriptions
  StreamSubscription<SecurityPolicy>? _policySub;
  StreamSubscription<PolicyViolation>? _violationSub;

  // Getters
  List<SecurityPolicy> get policies => _policies;
  List<PolicyTemplate> get templates => _templates;
  List<PolicyViolation> get violations => _violations;
  SecurityPolicy? get selectedPolicy => _selectedPolicy;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  // Computed getters
  List<SecurityPolicy> get enabledPolicies =>
      _policies.where((p) => p.isEnabled).toList();

  List<SecurityPolicy> get securityPolicies =>
      _policies.where((p) => p.type == PolicyType.security).toList();

  List<SecurityPolicy> get compliancePolicies =>
      _policies.where((p) => p.type == PolicyType.compliance).toList();

  List<SecurityPolicy> get byodPolicies =>
      _policies.where((p) => p.type == PolicyType.byod).toList();

  int get totalViolations => _violations.length;

  int get unresolvedViolations =>
      _violations.where((v) => !v.isResolved).length;

  int get criticalViolations => _violations
      .where((v) => !v.isResolved && v.severity == 'critical')
      .length;

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.initialize();

      // Listen to policy updates
      _policySub = _service.onPolicyUpdate.listen((policy) {
        final index = _policies.indexWhere((p) => p.id == policy.id);
        if (index >= 0) {
          _policies[index] = policy;
        } else {
          _policies.add(policy);
        }
        notifyListeners();
      });

      // Listen to violations
      _violationSub = _service.onViolation.listen((violation) {
        _violations.insert(0, violation);
        notifyListeners();
      });

      _policies = _service.policies;
      _templates = _service.templates;
      await loadViolations();
    } catch (e) {
      _error = 'Failed to initialize policy management';
      debugPrint('Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load all policies
  Future<void> loadPolicies() async {
    try {
      _policies = await _service.loadPolicies();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load policies';
      notifyListeners();
    }
  }

  /// Load policy templates
  Future<void> loadTemplates() async {
    try {
      _templates = await _service.loadTemplates();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load templates';
      notifyListeners();
    }
  }

  /// Load violations
  Future<void> loadViolations({bool unresolvedOnly = false}) async {
    try {
      _violations = await _service.getViolations(unresolvedOnly: unresolvedOnly);
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load violations';
      notifyListeners();
    }
  }

  /// Select a policy for viewing/editing
  void selectPolicy(SecurityPolicy? policy) {
    _selectedPolicy = policy;
    notifyListeners();
  }

  /// Create new policy
  Future<SecurityPolicy?> createPolicy({
    required String name,
    required String description,
    required PolicyType type,
    required EnforcementLevel enforcement,
    List<PolicyRule>? rules,
    List<String>? platforms,
    int priority = 0,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final policy = await _service.createPolicy(
        name: name,
        description: description,
        type: type,
        enforcement: enforcement,
        rules: rules,
        platforms: platforms,
        priority: priority,
      );

      if (policy != null) {
        _policies = _service.policies;
        notifyListeners();
      }

      return policy;
    } catch (e) {
      _error = 'Failed to create policy';
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Create policy from template
  Future<SecurityPolicy?> createFromTemplate(
    String templateId, {
    required String name,
    String? description,
    EnforcementLevel enforcement = EnforcementLevel.warn,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final policy = await _service.createFromTemplate(
        templateId,
        name: name,
        description: description,
        enforcement: enforcement,
      );

      if (policy != null) {
        _policies = _service.policies;
        notifyListeners();
      }

      return policy;
    } catch (e) {
      _error = 'Failed to create policy from template';
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Update policy
  Future<bool> updatePolicy(
    String policyId, {
    String? name,
    String? description,
    EnforcementLevel? enforcement,
    List<PolicyRule>? rules,
    int? priority,
    bool? isEnabled,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final policy = await _service.updatePolicy(
        policyId,
        name: name,
        description: description,
        enforcement: enforcement,
        rules: rules,
        priority: priority,
        isEnabled: isEnabled,
      );

      if (policy != null) {
        _policies = _service.policies;
        if (_selectedPolicy?.id == policyId) {
          _selectedPolicy = policy;
        }
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      _error = 'Failed to update policy';
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Toggle policy enabled state
  Future<bool> togglePolicyEnabled(String policyId, bool enabled) async {
    return updatePolicy(policyId, isEnabled: enabled);
  }

  /// Delete policy
  Future<bool> deletePolicy(String policyId) async {
    try {
      final success = await _service.deletePolicy(policyId);
      if (success) {
        _policies.removeWhere((p) => p.id == policyId);
        if (_selectedPolicy?.id == policyId) {
          _selectedPolicy = null;
        }
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Failed to delete policy';
      notifyListeners();
      return false;
    }
  }

  /// Assign policy to groups
  Future<bool> assignToGroups(String policyId, List<String> groupIds) async {
    try {
      final success = await _service.assignPolicyToGroups(policyId, groupIds);
      if (success) {
        await loadPolicies();
      }
      return success;
    } catch (e) {
      _error = 'Failed to assign policy';
      notifyListeners();
      return false;
    }
  }

  /// Assign policy to devices
  Future<bool> assignToDevices(String policyId, List<String> deviceIds) async {
    try {
      final success = await _service.assignPolicyToDevices(policyId, deviceIds);
      if (success) {
        await loadPolicies();
      }
      return success;
    } catch (e) {
      _error = 'Failed to assign policy';
      notifyListeners();
      return false;
    }
  }

  /// Add rule to policy
  Future<PolicyRule?> addRule(String policyId, PolicyRule rule) async {
    try {
      final newRule = await _service.addRule(policyId, rule);
      if (newRule != null) {
        _policies = _service.policies;
        notifyListeners();
      }
      return newRule;
    } catch (e) {
      _error = 'Failed to add rule';
      notifyListeners();
      return null;
    }
  }

  /// Delete rule from policy
  Future<bool> deleteRule(String policyId, String ruleId) async {
    try {
      final success = await _service.deleteRule(policyId, ruleId);
      if (success) {
        _policies = _service.policies;
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Failed to delete rule';
      notifyListeners();
      return false;
    }
  }

  /// Resolve violation
  Future<bool> resolveViolation(String violationId, {String? notes}) async {
    try {
      final success = await _service.resolveViolation(violationId, notes: notes);
      if (success) {
        _violations.removeWhere((v) => v.id == violationId);
        notifyListeners();
      }
      return success;
    } catch (e) {
      _error = 'Failed to resolve violation';
      notifyListeners();
      return false;
    }
  }

  /// Evaluate device compliance
  Future<Map<String, dynamic>> evaluateCompliance(String deviceId) async {
    try {
      return await _service.evaluateCompliance(deviceId);
    } catch (e) {
      _error = 'Failed to evaluate compliance';
      notifyListeners();
      return {'error': e.toString()};
    }
  }

  /// Get BYOD templates
  List<PolicyTemplate> getBYODTemplates() {
    return _service.getBYODTemplates();
  }

  /// Create BYOD policy
  Future<SecurityPolicy?> createBYODPolicy({
    required String name,
    required String description,
    required DeviceOwnershipType targetOwnership,
    required BYODPolicySettings settings,
    EnforcementLevel enforcement = EnforcementLevel.warn,
  }) async {
    _isSaving = true;
    _error = null;
    notifyListeners();

    try {
      final policy = await _service.createBYODPolicy(
        name: name,
        description: description,
        targetOwnership: targetOwnership,
        settings: settings,
        enforcement: enforcement,
      );

      if (policy != null) {
        _policies = _service.policies;
        notifyListeners();
      }

      return policy;
    } catch (e) {
      _error = 'Failed to create BYOD policy';
      return null;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Get policy type color
  static int getPolicyTypeColor(PolicyType type) {
    switch (type) {
      case PolicyType.security:
        return 0xFF2196F3;
      case PolicyType.compliance:
        return 0xFF9C27B0;
      case PolicyType.restriction:
        return 0xFFFF5722;
      case PolicyType.configuration:
        return 0xFF607D8B;
      case PolicyType.conditional:
        return 0xFF009688;
      case PolicyType.byod:
        return 0xFF4CAF50;
    }
  }

  /// Get policy type icon
  static String getPolicyTypeIcon(PolicyType type) {
    switch (type) {
      case PolicyType.security:
        return 'security';
      case PolicyType.compliance:
        return 'verified_user';
      case PolicyType.restriction:
        return 'block';
      case PolicyType.configuration:
        return 'settings';
      case PolicyType.conditional:
        return 'rule';
      case PolicyType.byod:
        return 'phone_android';
    }
  }

  /// Get enforcement level color
  static int getEnforcementColor(EnforcementLevel level) {
    switch (level) {
      case EnforcementLevel.monitor:
        return 0xFF2196F3;
      case EnforcementLevel.warn:
        return 0xFFFF9800;
      case EnforcementLevel.block:
        return 0xFFFF5722;
      case EnforcementLevel.quarantine:
        return 0xFFB71C1C;
    }
  }

  /// Get severity color
  static int getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return 0xFFB71C1C;
      case 'high':
        return 0xFFFF5722;
      case 'medium':
        return 0xFFFF9800;
      case 'low':
        return 0xFFFFEB3B;
      default:
        return 0xFF9E9E9E;
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Dispose
  @override
  void dispose() {
    _policySub?.cancel();
    _violationSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
