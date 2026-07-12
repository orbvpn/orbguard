/// Network Firewall Provider
/// State management for network firewall and connection monitoring

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../services/security/network_firewall_service.dart';

class NetworkFirewallProvider extends ChangeNotifier {
  final NetworkFirewallService _service = NetworkFirewallService();

  // State
  List<NetworkConnection> _connections = [];
  List<FirewallRule> _rules = [];
  List<AppNetworkProfile> _appProfiles = [];
  FirewallStats _stats = FirewallStats();

  // Loading states
  bool _isLoading = false;
  bool _isEnabled = false;

  // Error state
  String? _error;

  // Stream subscriptions
  StreamSubscription<NetworkConnection>? _connectionSub;
  StreamSubscription<NetworkConnection>? _alertSub;

  // Recent alerts
  final List<NetworkConnection> _recentAlerts = [];

  // Getters
  List<NetworkConnection> get connections => _connections;
  List<FirewallRule> get rules => _rules;
  List<AppNetworkProfile> get appProfiles => _appProfiles;
  FirewallStats get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isEnabled => _isEnabled;
  String? get error => _error;
  List<NetworkConnection> get recentAlerts => _recentAlerts;

  // Computed getters
  List<NetworkConnection> get blockedConnections =>
      _connections.where((c) => c.status == ConnectionStatus.blocked).toList();

  int get totalBlockedToday {
    final today = DateTime.now();
    return _connections
        .where((c) =>
            c.status == ConnectionStatus.blocked &&
            c.timestamp.day == today.day &&
            c.timestamp.month == today.month &&
            c.timestamp.year == today.year)
        .length;
  }

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.initialize();

      // Listen to connections
      _connectionSub = _service.connectionStream.listen((connection) {
        _connections.insert(0, connection);
        if (_connections.length > 500) {
          _connections.removeLast();
        }
        _updateStats();
        notifyListeners();
      });

      // Listen to alerts
      _alertSub = _service.alertStream.listen((alert) {
        _recentAlerts.insert(0, alert);
        if (_recentAlerts.length > 50) {
          _recentAlerts.removeLast();
        }
        notifyListeners();
      });

      await _loadRules();
      _updateStats();
    } catch (e) {
      _error = 'Failed to initialize firewall';
      debugPrint('Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Enable firewall
  Future<void> enable() async {
    if (_isEnabled) return;

    try {
      await _service.enable();
      _isEnabled = true;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to enable firewall';
      notifyListeners();
    }
  }

  /// Disable firewall
  Future<void> disable() async {
    if (!_isEnabled) return;

    try {
      await _service.disable();
      _isEnabled = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to disable firewall';
      notifyListeners();
    }
  }

  /// Toggle firewall
  Future<void> toggle() async {
    if (_isEnabled) {
      await disable();
    } else {
      await enable();
    }
  }

  /// Load firewall rules
  Future<void> _loadRules() async {
    _rules = _service.getRules();
    notifyListeners();
  }

  /// Add firewall rule
  FirewallRule addRule({
    required String name,
    required RuleType type,
    required String pattern,
    required RuleAction action,
  }) {
    final rule = _service.addRule(
      name: name,
      type: type,
      pattern: pattern,
      action: action,
    );
    _rules = _service.getRules();
    notifyListeners();
    return rule;
  }

  /// Remove firewall rule
  void removeRule(String ruleId) {
    _service.removeRule(ruleId);
    _rules = _service.getRules();
    notifyListeners();
  }

  /// Toggle rule enabled state
  void toggleRule(String ruleId, bool enabled) {
    _service.setRuleEnabled(ruleId, enabled);
    _rules = _service.getRules();
    notifyListeners();
  }

  /// Block domain
  void blockDomain(String domain) {
    _service.blockDomain(domain);
    notifyListeners();
  }

  /// Unblock domain
  void unblockDomain(String domain) {
    _service.unblockDomain(domain);
    notifyListeners();
  }

  /// Block IP
  void blockIp(String ip) {
    _service.blockIp(ip);
    notifyListeners();
  }

  /// Unblock IP
  void unblockIp(String ip) {
    _service.unblockIp(ip);
    notifyListeners();
  }

  /// Block app
  void blockApp(String appId) {
    _service.blockApp(appId);
    _updateAppProfiles();
    notifyListeners();
  }

  /// Unblock app
  void unblockApp(String appId) {
    _service.unblockApp(appId);
    _updateAppProfiles();
    notifyListeners();
  }

  /// Block country
  void blockCountry(String countryCode) {
    _service.blockCountry(countryCode);
    notifyListeners();
  }

  /// Unblock country
  void unblockCountry(String countryCode) {
    _service.unblockCountry(countryCode);
    notifyListeners();
  }

  /// Get connections for app
  List<NetworkConnection> getAppConnections(String appId) {
    return _service.getConnections(appId: appId);
  }

  /// Update app profiles
  void _updateAppProfiles() {
    _appProfiles = _service.getAppProfiles();
  }

  /// Update stats
  void _updateStats() {
    _stats = _service.getStats();
    _updateAppProfiles();
  }

  /// Clear connection history
  void clearHistory() {
    _service.clearHistory();
    _connections.clear();
    _updateStats();
    notifyListeners();
  }

  /// Import threat intelligence
  Future<void> importThreatIntel({
    List<String>? domains,
    List<String>? ips,
  }) async {
    await _service.importThreatIntel(domains: domains, ips: ips);
    notifyListeners();
  }

  /// Get status color
  static int getStatusColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.allowed:
        return 0xFF4CAF50;
      case ConnectionStatus.blocked:
        return 0xFFFF5252;
      case ConnectionStatus.pending:
        return 0xFFFF9800;
    }
  }

  /// Get block reason icon
  static String getBlockReasonIcon(BlockReason reason) {
    switch (reason) {
      case BlockReason.maliciousDomain:
        return 'dangerous';
      case BlockReason.maliciousIp:
        return 'gpp_bad';
      case BlockReason.userRule:
        return 'rule';
      case BlockReason.appBlocked:
        return 'block';
      case BlockReason.countryBlocked:
        return 'flag';
      case BlockReason.rateLimit:
        return 'speed';
      case BlockReason.suspiciousPattern:
        return 'pattern';
      case BlockReason.none:
        return 'check';
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
    _connectionSub?.cancel();
    _alertSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
