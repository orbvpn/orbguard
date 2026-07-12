/// Network Provider
/// State management for network security features

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/api/url_reputation.dart';
import '../services/api/orbguard_api_client.dart';

/// WiFi security level
enum WifiSecurityLevel {
  open,
  wep,
  wpaPsk,
  wpa2Psk,
  wpa3,
  enterprise;

  String get displayName {
    switch (this) {
      case WifiSecurityLevel.open:
        return 'Open (Unsecured)';
      case WifiSecurityLevel.wep:
        return 'WEP';
      case WifiSecurityLevel.wpaPsk:
        return 'WPA-PSK';
      case WifiSecurityLevel.wpa2Psk:
        return 'WPA2-PSK';
      case WifiSecurityLevel.wpa3:
        return 'WPA3';
      case WifiSecurityLevel.enterprise:
        return 'Enterprise';
    }
  }

  bool get isSecure => this != open && this != wep;
  bool get isRecommended => this == wpa2Psk || this == wpa3 || this == enterprise;

  int get color {
    switch (this) {
      case WifiSecurityLevel.open:
        return 0xFFFF1744;
      case WifiSecurityLevel.wep:
        return 0xFFFF5722;
      case WifiSecurityLevel.wpaPsk:
        return 0xFFFF9800;
      case WifiSecurityLevel.wpa2Psk:
        return 0xFF4CAF50;
      case WifiSecurityLevel.wpa3:
        return 0xFF00D9FF;
      case WifiSecurityLevel.enterprise:
        return 0xFF00D9FF;
    }
  }
}

/// WiFi network info
class WifiNetwork {
  final String ssid;
  final String bssid;
  final WifiSecurityLevel security;
  final int signalStrength;
  final int frequency;
  final bool isConnected;
  final bool isHidden;
  final DateTime? firstSeen;

  WifiNetwork({
    required this.ssid,
    required this.bssid,
    required this.security,
    required this.signalStrength,
    required this.frequency,
    this.isConnected = false,
    this.isHidden = false,
    this.firstSeen,
  });

  bool get is5GHz => frequency > 5000;
  bool get isStrongSignal => signalStrength > -60;
  bool get isMediumSignal => signalStrength > -70 && signalStrength <= -60;
  bool get isWeakSignal => signalStrength <= -70;
}

/// Network threat info
class NetworkThreat {
  final String id;
  final String type;
  final String title;
  final String description;
  final String severity;
  final DateTime detectedAt;
  final bool isActive;
  final String? recommendation;

  NetworkThreat({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.severity,
    required this.detectedAt,
    this.isActive = true,
    this.recommendation,
  });

  bool get isCritical => severity == 'critical' || severity == 'high';
}

/// VPN connection status
class VpnStatus {
  final bool isConnected;
  final String? serverLocation;
  final String? serverIp;
  final String? protocol;
  final DateTime? connectedAt;
  final int? bytesIn;
  final int? bytesOut;

  VpnStatus({
    this.isConnected = false,
    this.serverLocation,
    this.serverIp,
    this.protocol,
    this.connectedAt,
    this.bytesIn,
    this.bytesOut,
  });

  Duration? get connectionDuration {
    if (connectedAt == null || !isConnected) return null;
    return DateTime.now().difference(connectedAt!);
  }
}

/// DNS protection status
class DnsProtectionStatus {
  final bool isEnabled;
  final String provider;
  final String primaryDns;
  final String? secondaryDns;
  final bool isMalwareBlocking;
  final bool isAdBlocking;
  final bool isTrackingBlocking;
  final int blockedQueries;

  DnsProtectionStatus({
    this.isEnabled = false,
    this.provider = 'Default',
    this.primaryDns = '',
    this.secondaryDns,
    this.isMalwareBlocking = false,
    this.isAdBlocking = false,
    this.isTrackingBlocking = false,
    this.blockedQueries = 0,
  });
}

/// Network security stats
class NetworkSecurityStats {
  final int totalScans;
  final int threatsDetected;
  final int openNetworksFound;
  final int rogueApsDetected;
  final int dnsQueriesBlocked;
  final int maliciousSitesBlocked;

  NetworkSecurityStats({
    this.totalScans = 0,
    this.threatsDetected = 0,
    this.openNetworksFound = 0,
    this.rogueApsDetected = 0,
    this.dnsQueriesBlocked = 0,
    this.maliciousSitesBlocked = 0,
  });
}

/// Network Provider
class NetworkProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // Platform channel for native WiFi scanning
  static const _wifiChannel = MethodChannel('com.orb.guard/wifi');

  // State
  WifiNetwork? _currentNetwork;
  final List<WifiNetwork> _nearbyNetworks = [];
  final List<NetworkThreat> _threats = [];
  VpnStatus _vpnStatus = VpnStatus();
  DnsProtectionStatus _dnsStatus = DnsProtectionStatus();
  NetworkSecurityStats _stats = NetworkSecurityStats();

  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;

  // Getters
  WifiNetwork? get currentNetwork => _currentNetwork;
  List<WifiNetwork> get nearbyNetworks => List.unmodifiable(_nearbyNetworks);
  List<NetworkThreat> get threats => List.unmodifiable(_threats);
  VpnStatus get vpnStatus => _vpnStatus;
  DnsProtectionStatus get dnsStatus => _dnsStatus;
  NetworkSecurityStats get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get error => _error;

  /// Active threats
  List<NetworkThreat> get activeThreats =>
      _threats.where((t) => t.isActive).toList();

  /// Critical threats
  List<NetworkThreat> get criticalThreats =>
      _threats.where((t) => t.isCritical && t.isActive).toList();

  /// Open (unsecured) networks nearby
  List<WifiNetwork> get openNetworks =>
      _nearbyNetworks.where((n) => !n.security.isSecure).toList();

  /// Is current network secure?
  bool get isCurrentNetworkSecure =>
      _currentNetwork?.security.isSecure ?? true;

  /// Initialize provider
  Future<void> init() async {
    await refreshNetworkInfo();
    await refreshDnsStatus();
    await refreshVpnStatus();
    await loadNetworkThreats();
  }

  /// Refresh network information using platform channel
  Future<void> refreshNetworkInfo() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Use platform channel to get current network info from device
      final result = await _wifiChannel.invokeMethod<Map<dynamic, dynamic>>('getCurrentNetwork');

      if (result != null) {
        _currentNetwork = WifiNetwork(
          ssid: result['ssid'] as String? ?? 'Unknown',
          bssid: result['bssid'] as String? ?? '',
          security: _parseSecurityLevel(result['security'] as String?),
          signalStrength: result['signal_strength'] as int? ?? -100,
          frequency: result['frequency'] as int? ?? 2400,
          isConnected: true,
        );
      }
    } on PlatformException catch (e) {
      _error = 'Failed to get network info: ${e.message}';
    } catch (e) {
      _error = 'Failed to get network info: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Scan nearby networks using platform channel
  Future<void> scanNetworks() async {
    if (_isScanning) return;

    _isScanning = true;
    notifyListeners();

    try {
      // Use platform channel to scan nearby networks
      final result = await _wifiChannel.invokeMethod<List<dynamic>>('scanNetworks');

      _nearbyNetworks.clear();
      if (result != null) {
        for (final networkData in result) {
          final network = networkData as Map<dynamic, dynamic>;
          _nearbyNetworks.add(WifiNetwork(
            ssid: network['ssid'] as String? ?? 'Hidden Network',
            bssid: network['bssid'] as String? ?? '',
            security: _parseSecurityLevel(network['security'] as String?),
            signalStrength: network['signal_strength'] as int? ?? -100,
            frequency: network['frequency'] as int? ?? 2400,
            isConnected: network['is_connected'] as bool? ?? false,
            isHidden: network['is_hidden'] as bool? ?? false,
          ));
        }
      }

      // Also audit the current network via API
      if (_currentNetwork != null) {
        await _auditCurrentNetwork();
      }

      _checkForThreats();
      _updateStats();
    } on PlatformException catch (e) {
      _error = 'Failed to scan networks: ${e.message}';
    } catch (e) {
      _error = 'Failed to scan networks: $e';
    }

    _isScanning = false;
    notifyListeners();
  }

  /// Audit current network via API
  Future<void> _auditCurrentNetwork() async {
    if (_currentNetwork == null) return;

    try {
      final request = WifiAuditRequest(
        ssid: _currentNetwork!.ssid,
        bssid: _currentNetwork!.bssid,
        securityType: _currentNetwork!.security.name,
        signalStrength: _currentNetwork!.signalStrength,
      );

      final auditResult = await _api.auditWifi(request);

      // Add any threats from the audit
      if (auditResult.threats.isNotEmpty) {
        for (var i = 0; i < auditResult.threats.length; i++) {
          final threat = auditResult.threats[i];
          final threatId = 'wifi_${_currentNetwork!.bssid}_${threat.type}_$i';
          if (!_threats.any((t) => t.id == threatId)) {
            _threats.add(NetworkThreat(
              id: threatId,
              type: threat.type,
              title: _getThreatTitle(threat.type),
              description: threat.description,
              severity: threat.severity.name,
              detectedAt: DateTime.now(),
              recommendation: _getThreatRecommendation(threat.type),
            ));
          }
        }
      }
    } catch (e) {
      // Audit failure shouldn't break the scan
      debugPrint('Failed to audit network: $e');
    }
  }

  /// Load network threats from API
  Future<void> loadNetworkThreats() async {
    try {
      final threatsData = await _api.getNetworkThreats();

      _threats.clear();
      for (final threatJson in threatsData) {
        _threats.add(NetworkThreat(
          id: threatJson['id'] as String? ?? '',
          type: threatJson['type'] as String? ?? 'unknown',
          title: threatJson['title'] as String? ?? 'Network Threat',
          description: threatJson['description'] as String? ?? '',
          severity: threatJson['severity'] as String? ?? 'medium',
          detectedAt: threatJson['detected_at'] != null
              ? DateTime.parse(threatJson['detected_at'] as String)
              : DateTime.now(),
          isActive: threatJson['is_active'] as bool? ?? true,
          recommendation: threatJson['recommendation'] as String?,
        ));
      }
      _updateStats();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load network threats: $e');
    }
  }

  /// Parse security level from string
  WifiSecurityLevel _parseSecurityLevel(String? security) {
    if (security == null) return WifiSecurityLevel.open;
    final lower = security.toLowerCase();
    if (lower.contains('wpa3')) return WifiSecurityLevel.wpa3;
    if (lower.contains('wpa2') && lower.contains('enterprise')) return WifiSecurityLevel.enterprise;
    if (lower.contains('wpa2')) return WifiSecurityLevel.wpa2Psk;
    if (lower.contains('wpa')) return WifiSecurityLevel.wpaPsk;
    if (lower.contains('wep')) return WifiSecurityLevel.wep;
    return WifiSecurityLevel.open;
  }

  /// Refresh VPN status from API
  Future<void> refreshVpnStatus() async {
    try {
      final statusData = await _api.getVpnStatus();

      _vpnStatus = VpnStatus(
        isConnected: statusData['is_connected'] as bool? ?? false,
        serverLocation: statusData['server_location'] as String?,
        serverIp: statusData['server_ip'] as String?,
        protocol: statusData['protocol'] as String?,
        connectedAt: statusData['connected_at'] != null
            ? DateTime.parse(statusData['connected_at'] as String)
            : null,
        bytesIn: statusData['bytes_in'] as int?,
        bytesOut: statusData['bytes_out'] as int?,
      );
    } catch (e) {
      // VPN status failure shouldn't crash the app
      _vpnStatus = VpnStatus(isConnected: false);
    }
    notifyListeners();
  }

  /// Connect to VPN via API
  Future<bool> connectVpn(String server) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _api.connectVpn(server);

      _vpnStatus = VpnStatus(
        isConnected: result['success'] as bool? ?? false,
        serverLocation: result['server_location'] as String? ?? server,
        serverIp: result['server_ip'] as String?,
        protocol: result['protocol'] as String?,
        connectedAt: DateTime.now(),
      );
      _isLoading = false;
      notifyListeners();
      return _vpnStatus.isConnected;
    } catch (e) {
      _error = 'Failed to connect VPN: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect VPN via API
  Future<void> disconnectVpn() async {
    try {
      await _api.disconnectVpn();
    } catch (e) {
      debugPrint('Failed to disconnect VPN: $e');
    }
    _vpnStatus = VpnStatus(isConnected: false);
    notifyListeners();
  }

  /// Refresh DNS status from API
  Future<void> refreshDnsStatus() async {
    try {
      final statusData = await _api.getDnsStatus();

      _dnsStatus = DnsProtectionStatus(
        isEnabled: statusData['is_enabled'] as bool? ?? false,
        provider: statusData['provider'] as String? ?? 'Default',
        primaryDns: statusData['primary_dns'] as String? ?? '',
        secondaryDns: statusData['secondary_dns'] as String?,
        isMalwareBlocking: statusData['malware_blocking'] as bool? ?? false,
        isAdBlocking: statusData['ad_blocking'] as bool? ?? false,
        isTrackingBlocking: statusData['tracking_blocking'] as bool? ?? false,
        blockedQueries: statusData['blocked_queries'] as int? ?? 0,
      );
    } catch (e) {
      // DNS status failure shouldn't crash the app
      _dnsStatus = DnsProtectionStatus();
    }
    notifyListeners();
  }

  /// Enable DNS protection via API
  Future<void> enableDnsProtection({
    bool malwareBlocking = true,
    bool adBlocking = false,
    bool trackingBlocking = true,
  }) async {
    try {
      final result = await _api.enableDnsProtection(
        malwareBlocking: malwareBlocking,
        adBlocking: adBlocking,
        trackingBlocking: trackingBlocking,
      );

      _dnsStatus = DnsProtectionStatus(
        isEnabled: true,
        provider: result['provider'] as String? ?? 'OrbGuard DNS',
        primaryDns: result['primary_dns'] as String? ?? '',
        secondaryDns: result['secondary_dns'] as String?,
        isMalwareBlocking: malwareBlocking,
        isAdBlocking: adBlocking,
        isTrackingBlocking: trackingBlocking,
        blockedQueries: _dnsStatus.blockedQueries,
      );
    } catch (e) {
      _error = 'Failed to enable DNS protection: $e';
    }
    notifyListeners();
  }

  /// Disable DNS protection via API
  Future<void> disableDnsProtection() async {
    try {
      await _api.disableDnsProtection();

      _dnsStatus = DnsProtectionStatus(
        isEnabled: false,
        provider: 'Default',
        primaryDns: '',
        blockedQueries: _dnsStatus.blockedQueries,
      );
    } catch (e) {
      _error = 'Failed to disable DNS protection: $e';
    }
    notifyListeners();
  }

  /// Dismiss threat
  void dismissThreat(String id) {
    final index = _threats.indexWhere((t) => t.id == id);
    if (index >= 0) {
      _threats.removeAt(index);
      _updateStats();
      notifyListeners();
    }
  }

  /// Check for network threats
  void _checkForThreats() {
    _threats.clear();

    // Check for open networks
    for (final network in _nearbyNetworks) {
      if (network.security == WifiSecurityLevel.open) {
        // Check for potential evil twin
        if (_nearbyNetworks.any((n) =>
            n.ssid == network.ssid &&
            n.bssid != network.bssid &&
            n.security.isSecure)) {
          _threats.add(NetworkThreat(
            id: 'evil_twin_${network.bssid}',
            type: 'evil_twin',
            title: 'Potential Evil Twin Detected',
            description:
                'An unsecured network with the same name as "${network.ssid}" was found. This could be a rogue access point.',
            severity: 'high',
            detectedAt: DateTime.now(),
            recommendation:
                'Avoid connecting to this network. Verify with your network administrator.',
          ));
        }
      }
    }

    // Check current network security
    if (_currentNetwork != null && !_currentNetwork!.security.isSecure) {
      _threats.add(NetworkThreat(
        id: 'insecure_network',
        type: 'insecure_wifi',
        title: 'Insecure Network Connection',
        description:
            'You are connected to a network using ${_currentNetwork!.security.displayName} encryption which is not secure.',
        severity: 'high',
        detectedAt: DateTime.now(),
        recommendation:
            'Enable WPA2 or WPA3 encryption on your network, or use a VPN.',
      ));
    }
  }

  /// Update stats
  void _updateStats() {
    _stats = NetworkSecurityStats(
      totalScans: _stats.totalScans + 1,
      threatsDetected: _threats.length,
      openNetworksFound: openNetworks.length,
      rogueApsDetected: _threats.where((t) => t.type == 'evil_twin').length,
      dnsQueriesBlocked: _dnsStatus.blockedQueries,
      maliciousSitesBlocked: 0,
    );
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get signal strength icon name
  static String getSignalIcon(int strength) {
    if (strength > -60) return 'wifi';
    if (strength > -70) return 'wifi_2_bar';
    return 'wifi_1_bar';
  }

  /// Get signal strength description
  static String getSignalDescription(int strength) {
    if (strength > -60) return 'Excellent';
    if (strength > -70) return 'Good';
    if (strength > -80) return 'Fair';
    return 'Poor';
  }

  /// Get threat title from type
  String _getThreatTitle(String type) {
    switch (type.toLowerCase()) {
      case 'evil_twin':
        return 'Evil Twin Detected';
      case 'rogue_ap':
        return 'Rogue Access Point';
      case 'deauth_attack':
        return 'Deauthentication Attack';
      case 'mitm':
        return 'Man-in-the-Middle Attack';
      case 'weak_security':
        return 'Weak Security Protocol';
      case 'open_network':
        return 'Open Network Risk';
      case 'arp_spoofing':
        return 'ARP Spoofing Detected';
      case 'dns_hijacking':
        return 'DNS Hijacking Attempt';
      default:
        return 'Network Threat: ${type.replaceAll('_', ' ').toUpperCase()}';
    }
  }

  /// Get threat recommendation from type
  String _getThreatRecommendation(String type) {
    switch (type.toLowerCase()) {
      case 'evil_twin':
        return 'Disconnect immediately and verify the legitimate network with your administrator.';
      case 'rogue_ap':
        return 'Avoid connecting to this network. Report to your network security team.';
      case 'deauth_attack':
        return 'Consider using a VPN and avoid sensitive activities until the network is secure.';
      case 'mitm':
        return 'Disconnect immediately. Do not enter any credentials or sensitive data.';
      case 'weak_security':
        return 'Upgrade to WPA3 or WPA2. Avoid WEP and open networks.';
      case 'open_network':
        return 'Use a VPN if you must connect. Avoid sensitive activities.';
      case 'arp_spoofing':
        return 'Disconnect and alert your network administrator immediately.';
      case 'dns_hijacking':
        return 'Use secure DNS (DNS over HTTPS) and verify your DNS settings.';
      default:
        return 'Investigate this threat and consider disconnecting from the network.';
    }
  }
}
