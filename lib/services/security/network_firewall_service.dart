/// Network Firewall Service
///
/// Network-level attack blocking and monitoring:
/// - Outbound connection monitoring
/// - Malicious domain blocking
/// - IP reputation checking
/// - Traffic analysis
/// - Per-app network rules
/// - Connection alerts

import 'dart:async';
import 'package:flutter/services.dart';

/// Connection direction
enum ConnectionDirection {
  inbound('Inbound'),
  outbound('Outbound');

  final String displayName;

  const ConnectionDirection(this.displayName);
}

/// Connection protocol
enum ConnectionProtocol {
  tcp('TCP'),
  udp('UDP'),
  icmp('ICMP'),
  other('Other');

  final String displayName;

  const ConnectionProtocol(this.displayName);
}

/// Connection status
enum ConnectionStatus {
  allowed('Allowed'),
  blocked('Blocked'),
  pending('Pending');

  final String displayName;

  const ConnectionStatus(this.displayName);
}

/// Block reason
enum BlockReason {
  maliciousDomain('Malicious Domain'),
  maliciousIp('Malicious IP'),
  userRule('User Rule'),
  appBlocked('App Blocked'),
  countryBlocked('Country Blocked'),
  rateLimit('Rate Limited'),
  suspiciousPattern('Suspicious Pattern'),
  none('None');

  final String displayName;

  const BlockReason(this.displayName);
}

/// Network connection
class NetworkConnection {
  final String id;
  final String appId;
  final String? appName;
  final String localAddress;
  final int localPort;
  final String remoteAddress;
  final int remotePort;
  final String? remoteDomain;
  final ConnectionDirection direction;
  final ConnectionProtocol protocol;
  final ConnectionStatus status;
  final BlockReason? blockReason;
  final DateTime timestamp;
  final int bytesIn;
  final int bytesOut;
  final String? country;
  final String? asn;

  NetworkConnection({
    required this.id,
    required this.appId,
    this.appName,
    required this.localAddress,
    required this.localPort,
    required this.remoteAddress,
    required this.remotePort,
    this.remoteDomain,
    required this.direction,
    required this.protocol,
    required this.status,
    this.blockReason,
    required this.timestamp,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.country,
    this.asn,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'app_id': appId,
    'app_name': appName,
    'local_address': localAddress,
    'local_port': localPort,
    'remote_address': remoteAddress,
    'remote_port': remotePort,
    'remote_domain': remoteDomain,
    'direction': direction.name,
    'protocol': protocol.name,
    'status': status.name,
    'block_reason': blockReason?.name,
    'timestamp': timestamp.toIso8601String(),
    'bytes_in': bytesIn,
    'bytes_out': bytesOut,
    'country': country,
    'asn': asn,
  };
}

/// Firewall rule
class FirewallRule {
  final String id;
  final String name;
  final RuleType type;
  final String pattern;
  final RuleAction action;
  final bool isEnabled;
  final DateTime createdAt;
  final int matchCount;

  FirewallRule({
    required this.id,
    required this.name,
    required this.type,
    required this.pattern,
    required this.action,
    this.isEnabled = true,
    required this.createdAt,
    this.matchCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type.name,
    'pattern': pattern,
    'action': action.name,
    'is_enabled': isEnabled,
    'created_at': createdAt.toIso8601String(),
    'match_count': matchCount,
  };

  factory FirewallRule.fromJson(Map<String, dynamic> json) {
    return FirewallRule(
      id: json['id'] as String,
      name: json['name'] as String,
      type: RuleType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RuleType.domain,
      ),
      pattern: json['pattern'] as String,
      action: RuleAction.values.firstWhere(
        (a) => a.name == json['action'],
        orElse: () => RuleAction.block,
      ),
      isEnabled: json['is_enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      matchCount: json['match_count'] as int? ?? 0,
    );
  }
}

/// Rule type
enum RuleType {
  domain('Domain'),
  ip('IP Address'),
  ipRange('IP Range'),
  app('Application'),
  port('Port'),
  country('Country');

  final String displayName;

  const RuleType(this.displayName);
}

/// Rule action
enum RuleAction {
  allow('Allow'),
  block('Block'),
  alert('Alert Only');

  final String displayName;

  const RuleAction(this.displayName);
}

/// App network profile
class AppNetworkProfile {
  final String appId;
  final String appName;
  final bool isAllowed;
  final int connectionCount;
  final int blockedCount;
  final int bytesIn;
  final int bytesOut;
  final Set<String> connectedDomains;
  final Set<String> connectedIps;
  final DateTime? lastActivity;

  AppNetworkProfile({
    required this.appId,
    required this.appName,
    this.isAllowed = true,
    this.connectionCount = 0,
    this.blockedCount = 0,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.connectedDomains = const {},
    this.connectedIps = const {},
    this.lastActivity,
  });
}

/// Firewall statistics
class FirewallStats {
  final int totalConnections;
  final int blockedConnections;
  final int allowedConnections;
  final int totalBytesIn;
  final int totalBytesOut;
  final int activeRules;
  final Map<String, int> blocksByReason;
  final Map<String, int> connectionsByApp;
  final DateTime? lastUpdate;

  FirewallStats({
    this.totalConnections = 0,
    this.blockedConnections = 0,
    this.allowedConnections = 0,
    this.totalBytesIn = 0,
    this.totalBytesOut = 0,
    this.activeRules = 0,
    this.blocksByReason = const {},
    this.connectionsByApp = const {},
    this.lastUpdate,
  });
}

/// Network Firewall Service
class NetworkFirewallService {
  static const _channel = MethodChannel('com.orbvpn.orbguard/firewall');
  static const _eventChannel = EventChannel('com.orbvpn.orbguard/firewall_events');

  final List<NetworkConnection> _connections = [];
  final List<FirewallRule> _rules = [];
  final Map<String, AppNetworkProfile> _appProfiles = {};

  // Default blocked domains
  final Set<String> _blockedDomains = {};
  final Set<String> _blockedIps = {};
  final Set<String> _blockedCountries = {};
  final Set<String> _blockedApps = {};

  StreamSubscription? _eventSubscription;
  final _connectionController = StreamController<NetworkConnection>.broadcast();
  final _alertController = StreamController<NetworkConnection>.broadcast();

  Stream<NetworkConnection> get connectionStream => _connectionController.stream;
  Stream<NetworkConnection> get alertStream => _alertController.stream;

  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  // Known malicious domains (sample list)
  static const _maliciousDomains = [
    'malware-domain.com',
    'phishing-site.net',
    'c2-server.org',
    // Would be populated from threat intelligence
  ];

  // Known malicious IPs (sample list)
  static const _maliciousIps = [
    '185.220.101.0/24', // Example Tor exit nodes
    '192.42.116.0/24',
    // Would be populated from threat intelligence
  ];

  /// Initialize the firewall service
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('initialize');

      // Load default malicious entries
      _blockedDomains.addAll(_maliciousDomains);
    } on PlatformException catch (e) {
      print('Firewall initialization failed: ${e.message}');
    }
  }

  /// Enable firewall monitoring
  Future<void> enable() async {
    if (_isEnabled) return;

    try {
      await _channel.invokeMethod('enable');

      _eventSubscription = _eventChannel
          .receiveBroadcastStream()
          .map((event) => event as Map<dynamic, dynamic>)
          .listen((data) {
        _onConnectionEvent(data.cast<String, dynamic>());
      });

      _isEnabled = true;
    } on PlatformException catch (e) {
      print('Failed to enable firewall: ${e.message}');
    }
  }

  /// Disable firewall monitoring
  Future<void> disable() async {
    if (!_isEnabled) return;

    try {
      await _channel.invokeMethod('disable');
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _isEnabled = false;
    } on PlatformException catch (e) {
      print('Failed to disable firewall: ${e.message}');
    }
  }

  /// Handle connection event
  void _onConnectionEvent(Map<String, dynamic> data) {
    final connection = _parseConnection(data);

    // Check against rules
    final checkResult = _checkConnection(connection);

    // Update connection status based on check
    final updatedConnection = NetworkConnection(
      id: connection.id,
      appId: connection.appId,
      appName: connection.appName,
      localAddress: connection.localAddress,
      localPort: connection.localPort,
      remoteAddress: connection.remoteAddress,
      remotePort: connection.remotePort,
      remoteDomain: connection.remoteDomain,
      direction: connection.direction,
      protocol: connection.protocol,
      status: checkResult['status'] as ConnectionStatus,
      blockReason: checkResult['reason'] as BlockReason?,
      timestamp: connection.timestamp,
      bytesIn: connection.bytesIn,
      bytesOut: connection.bytesOut,
      country: connection.country,
      asn: connection.asn,
    );

    _connections.add(updatedConnection);
    _connectionController.add(updatedConnection);

    // Update app profile
    _updateAppProfile(updatedConnection);

    // Send alert for blocked connections
    if (updatedConnection.status == ConnectionStatus.blocked) {
      _alertController.add(updatedConnection);
    }

    // Limit connection history
    if (_connections.length > 10000) {
      _connections.removeRange(0, 1000);
    }
  }

  NetworkConnection _parseConnection(Map<String, dynamic> data) {
    return NetworkConnection(
      id: data['id'] as String? ?? 'conn_${DateTime.now().millisecondsSinceEpoch}',
      appId: data['app_id'] as String? ?? 'unknown',
      appName: data['app_name'] as String?,
      localAddress: data['local_address'] as String? ?? '0.0.0.0',
      localPort: data['local_port'] as int? ?? 0,
      remoteAddress: data['remote_address'] as String? ?? '0.0.0.0',
      remotePort: data['remote_port'] as int? ?? 0,
      remoteDomain: data['remote_domain'] as String?,
      direction: ConnectionDirection.values.firstWhere(
        (d) => d.name == data['direction'],
        orElse: () => ConnectionDirection.outbound,
      ),
      protocol: ConnectionProtocol.values.firstWhere(
        (p) => p.name == data['protocol'],
        orElse: () => ConnectionProtocol.tcp,
      ),
      status: ConnectionStatus.pending,
      timestamp: DateTime.now(),
      bytesIn: data['bytes_in'] as int? ?? 0,
      bytesOut: data['bytes_out'] as int? ?? 0,
      country: data['country'] as String?,
      asn: data['asn'] as String?,
    );
  }

  /// Check connection against rules
  Map<String, dynamic> _checkConnection(NetworkConnection connection) {
    // Check blocked apps
    if (_blockedApps.contains(connection.appId)) {
      return {
        'status': ConnectionStatus.blocked,
        'reason': BlockReason.appBlocked,
      };
    }

    // Check blocked domains
    if (connection.remoteDomain != null &&
        _isDomainBlocked(connection.remoteDomain!)) {
      return {
        'status': ConnectionStatus.blocked,
        'reason': BlockReason.maliciousDomain,
      };
    }

    // Check blocked IPs
    if (_isIpBlocked(connection.remoteAddress)) {
      return {
        'status': ConnectionStatus.blocked,
        'reason': BlockReason.maliciousIp,
      };
    }

    // Check blocked countries
    if (connection.country != null &&
        _blockedCountries.contains(connection.country)) {
      return {
        'status': ConnectionStatus.blocked,
        'reason': BlockReason.countryBlocked,
      };
    }

    // Check custom rules
    for (final rule in _rules.where((r) => r.isEnabled)) {
      if (_ruleMatches(rule, connection)) {
        if (rule.action == RuleAction.block) {
          return {
            'status': ConnectionStatus.blocked,
            'reason': BlockReason.userRule,
          };
        } else if (rule.action == RuleAction.allow) {
          return {
            'status': ConnectionStatus.allowed,
            'reason': BlockReason.none,
          };
        }
      }
    }

    // Default: allow
    return {
      'status': ConnectionStatus.allowed,
      'reason': BlockReason.none,
    };
  }

  bool _isDomainBlocked(String domain) {
    final lowerDomain = domain.toLowerCase();

    // Exact match
    if (_blockedDomains.contains(lowerDomain)) return true;

    // Subdomain match
    for (final blocked in _blockedDomains) {
      if (lowerDomain.endsWith('.$blocked')) return true;
    }

    return false;
  }

  bool _isIpBlocked(String ip) {
    // Exact match
    if (_blockedIps.contains(ip)) return true;

    // CIDR match would require IP parsing
    // Simplified: check prefix match
    for (final blocked in _blockedIps) {
      if (blocked.contains('/')) {
        final prefix = blocked.split('/')[0];
        final prefixParts = prefix.split('.');
        final ipParts = ip.split('.');

        // Match first 3 octets for /24
        if (blocked.endsWith('/24') &&
            prefixParts.length >= 3 &&
            ipParts.length >= 3) {
          if (prefixParts.sublist(0, 3).join('.') ==
              ipParts.sublist(0, 3).join('.')) {
            return true;
          }
        }
      }
    }

    return false;
  }

  bool _ruleMatches(FirewallRule rule, NetworkConnection connection) {
    switch (rule.type) {
      case RuleType.domain:
        if (connection.remoteDomain == null) return false;
        return connection.remoteDomain!.toLowerCase().contains(rule.pattern.toLowerCase());
      case RuleType.ip:
        return connection.remoteAddress == rule.pattern;
      case RuleType.ipRange:
        // Simplified CIDR matching
        return connection.remoteAddress.startsWith(
          rule.pattern.split('/')[0].split('.').sublist(0, 3).join('.'),
        );
      case RuleType.app:
        return connection.appId == rule.pattern ||
            connection.appName?.toLowerCase() == rule.pattern.toLowerCase();
      case RuleType.port:
        return connection.remotePort.toString() == rule.pattern;
      case RuleType.country:
        return connection.country?.toLowerCase() == rule.pattern.toLowerCase();
    }
  }

  void _updateAppProfile(NetworkConnection connection) {
    final existing = _appProfiles[connection.appId];

    final newDomains = Set<String>.from(existing?.connectedDomains ?? {});
    if (connection.remoteDomain != null) {
      newDomains.add(connection.remoteDomain!);
    }

    final newIps = Set<String>.from(existing?.connectedIps ?? {});
    newIps.add(connection.remoteAddress);

    _appProfiles[connection.appId] = AppNetworkProfile(
      appId: connection.appId,
      appName: connection.appName ?? existing?.appName ?? 'Unknown',
      isAllowed: !_blockedApps.contains(connection.appId),
      connectionCount: (existing?.connectionCount ?? 0) + 1,
      blockedCount: (existing?.blockedCount ?? 0) +
          (connection.status == ConnectionStatus.blocked ? 1 : 0),
      bytesIn: (existing?.bytesIn ?? 0) + connection.bytesIn,
      bytesOut: (existing?.bytesOut ?? 0) + connection.bytesOut,
      connectedDomains: newDomains,
      connectedIps: newIps,
      lastActivity: connection.timestamp,
    );
  }

  /// Add firewall rule
  FirewallRule addRule({
    required String name,
    required RuleType type,
    required String pattern,
    required RuleAction action,
  }) {
    final rule = FirewallRule(
      id: 'rule_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: type,
      pattern: pattern,
      action: action,
      createdAt: DateTime.now(),
    );

    _rules.add(rule);
    return rule;
  }

  /// Remove firewall rule
  void removeRule(String ruleId) {
    _rules.removeWhere((r) => r.id == ruleId);
  }

  /// Enable/disable rule
  void setRuleEnabled(String ruleId, bool enabled) {
    final index = _rules.indexWhere((r) => r.id == ruleId);
    if (index >= 0) {
      final rule = _rules[index];
      _rules[index] = FirewallRule(
        id: rule.id,
        name: rule.name,
        type: rule.type,
        pattern: rule.pattern,
        action: rule.action,
        isEnabled: enabled,
        createdAt: rule.createdAt,
        matchCount: rule.matchCount,
      );
    }
  }

  /// Block domain
  void blockDomain(String domain) {
    _blockedDomains.add(domain.toLowerCase());
  }

  /// Unblock domain
  void unblockDomain(String domain) {
    _blockedDomains.remove(domain.toLowerCase());
  }

  /// Block IP
  void blockIp(String ip) {
    _blockedIps.add(ip);
  }

  /// Unblock IP
  void unblockIp(String ip) {
    _blockedIps.remove(ip);
  }

  /// Block country
  void blockCountry(String countryCode) {
    _blockedCountries.add(countryCode.toUpperCase());
  }

  /// Unblock country
  void unblockCountry(String countryCode) {
    _blockedCountries.remove(countryCode.toUpperCase());
  }

  /// Block app
  void blockApp(String appId) {
    _blockedApps.add(appId);
  }

  /// Unblock app
  void unblockApp(String appId) {
    _blockedApps.remove(appId);
  }

  /// Get all rules
  List<FirewallRule> getRules() => List.unmodifiable(_rules);

  /// Get connections
  List<NetworkConnection> getConnections({
    String? appId,
    ConnectionStatus? status,
    int? limit,
  }) {
    var connections = _connections.where((c) {
      if (appId != null && c.appId != appId) return false;
      if (status != null && c.status != status) return false;
      return true;
    }).toList();

    connections.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (limit != null && connections.length > limit) {
      connections = connections.sublist(0, limit);
    }

    return connections;
  }

  /// Get app profiles
  List<AppNetworkProfile> getAppProfiles() =>
      _appProfiles.values.toList();

  /// Get app profile
  AppNetworkProfile? getAppProfile(String appId) => _appProfiles[appId];

  /// Get statistics
  FirewallStats getStats() {
    final blocksByReason = <String, int>{};
    final connectionsByApp = <String, int>{};

    var blockedCount = 0;
    var allowedCount = 0;
    var totalBytesIn = 0;
    var totalBytesOut = 0;

    for (final conn in _connections) {
      if (conn.status == ConnectionStatus.blocked) {
        blockedCount++;
        if (conn.blockReason != null) {
          blocksByReason[conn.blockReason!.name] =
              (blocksByReason[conn.blockReason!.name] ?? 0) + 1;
        }
      } else {
        allowedCount++;
      }

      connectionsByApp[conn.appId] = (connectionsByApp[conn.appId] ?? 0) + 1;
      totalBytesIn += conn.bytesIn;
      totalBytesOut += conn.bytesOut;
    }

    return FirewallStats(
      totalConnections: _connections.length,
      blockedConnections: blockedCount,
      allowedConnections: allowedCount,
      totalBytesIn: totalBytesIn,
      totalBytesOut: totalBytesOut,
      activeRules: _rules.where((r) => r.isEnabled).length,
      blocksByReason: blocksByReason,
      connectionsByApp: connectionsByApp,
      lastUpdate: DateTime.now(),
    );
  }

  /// Import threat intelligence
  Future<void> importThreatIntel({
    List<String>? domains,
    List<String>? ips,
  }) async {
    if (domains != null) {
      _blockedDomains.addAll(domains.map((d) => d.toLowerCase()));
    }
    if (ips != null) {
      _blockedIps.addAll(ips);
    }
  }

  /// Clear connection history
  void clearHistory() {
    _connections.clear();
  }

  /// Dispose resources
  void dispose() {
    disable();
    _connectionController.close();
    _alertController.close();
  }
}
