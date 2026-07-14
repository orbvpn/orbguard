/// Enterprise Policy Provider
/// State management for the server-side Zero Trust conditional access
/// policy list (GET /api/v1/enterprise/policies).
library;

import 'package:flutter/foundation.dart';

import '../services/api/api_interceptors.dart' show ApiError;
import '../services/security/enterprise/policy_management_service.dart';

class EnterprisePolicyProvider extends ChangeNotifier {
  final PolicyManagementService _service = PolicyManagementService();

  List<ConditionalAccessPolicy> _policies = [];
  bool _isLoading = false;
  String? _error;
  bool _hasLoaded = false;

  List<ConditionalAccessPolicy> get policies => _policies;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Whether at least one load attempt has completed (success or failure).
  bool get hasLoaded => _hasLoaded;

  List<ConditionalAccessPolicy> get enabledPolicies =>
      _policies.where((p) => p.enabled).toList();

  List<ConditionalAccessPolicy> get disabledPolicies =>
      _policies.where((p) => !p.enabled).toList();

  /// Load (or reload) policies from the backend.
  Future<void> loadPolicies() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final policies = await _service.fetchPolicies();
      // Lower priority value = higher precedence; unknown priority sinks.
      policies.sort((a, b) =>
          (a.priority ?? 1 << 30).compareTo(b.priority ?? 1 << 30));
      _policies = policies;
    } catch (e) {
      // GET /enterprise/policies is an optional, config-gated enterprise
      // feature; a 404 means it isn't provisioned on this server — degrade to
      // the normal "No Policies" empty state instead of a scary error.
      final gone = e is ApiError && e.statusCode == 404;
      if (gone) {
        _policies = [];
        _error = null;
      } else {
        _error = e.toString();
      }
      debugPrint('Failed to load conditional access policies: $e');
    } finally {
      _isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
