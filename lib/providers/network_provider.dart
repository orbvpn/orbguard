/// Network Provider
/// State management for network security features

import 'package:flutter/foundation.dart';

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
    _loadMockData();
  }

  /// Refresh network information
  Future<void> refreshNetworkInfo() async {
    _isLoading = true;
    notifyListeners();

    try {
      // TODO: Use platform channel to get real network info
      _currentNetwork = WifiNetwork(
        ssid: 'Home Network',
        bssid: 'AA:BB:CC:DD:EE:FF',
        security: WifiSecurityLevel.wpa2Psk,
        signalStrength: -55,
        frequency: 5180,
        isConnected: true,
      );
    } catch (e) {
      _error = 'Failed to get network info: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Scan nearby networks
  Future<void> scanNetworks() async {
    if (_isScanning) return;

    _isScanning = true;
    notifyListeners();

    try {
      // TODO: Use platform channel to scan networks
      await Future.delayed(const Duration(seconds: 2));
      _nearbyNetworks.clear();
      _nearbyNetworks.addAll(_getMockNetworks());
      _checkForThreats();
      _updateStats();
    } catch (e) {
      _error = 'Failed to scan networks: $e';
    }

    _isScanning = false;
    notifyListeners();
  }

  /// Refresh VPN status
  Future<void> refreshVpnStatus() async {
    // TODO: Get actual VPN status
    _vpnStatus = VpnStatus(
      isConnected: false,
      serverLocation: null,
    );
    notifyListeners();
  }

  /// Connect to VPN
  Future<bool> connectVpn(String server) async {
    _isLoading = true;
    notifyListeners();

    try {
      // TODO: Actually connect to VPN
      await Future.delayed(const Duration(seconds: 2));
      _vpnStatus = VpnStatus(
        isConnected: true,
        serverLocation: server,
        serverIp: '10.0.0.1',
        protocol: 'WireGuard',
        connectedAt: DateTime.now(),
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to connect VPN: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Disconnect VPN
  Future<void> disconnectVpn() async {
    _vpnStatus = VpnStatus(isConnected: false);
    notifyListeners();
  }

  /// Refresh DNS status
  Future<void> refreshDnsStatus() async {
    // TODO: Get actual DNS status
    _dnsStatus = DnsProtectionStatus(
      isEnabled: true,
      provider: 'OrbGuard DNS',
      primaryDns: '1.1.1.3',
      secondaryDns: '1.0.0.3',
      isMalwareBlocking: true,
      isAdBlocking: false,
      isTrackingBlocking: true,
      blockedQueries: 1247,
    );
    notifyListeners();
  }

  /// Enable DNS protection
  Future<void> enableDnsProtection({
    bool malwareBlocking = true,
    bool adBlocking = false,
    bool trackingBlocking = true,
  }) async {
    _dnsStatus = DnsProtectionStatus(
      isEnabled: true,
      provider: 'OrbGuard DNS',
      primaryDns: '1.1.1.3',
      secondaryDns: '1.0.0.3',
      isMalwareBlocking: malwareBlocking,
      isAdBlocking: adBlocking,
      isTrackingBlocking: trackingBlocking,
      blockedQueries: _dnsStatus.blockedQueries,
    );
    notifyListeners();
  }

  /// Disable DNS protection
  Future<void> disableDnsProtection() async {
    _dnsStatus = DnsProtectionStatus(
      isEnabled: false,
      provider: 'Default',
      primaryDns: '',
      blockedQueries: _dnsStatus.blockedQueries,
    );
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

  /// Get mock nearby networks
  List<WifiNetwork> _getMockNetworks() {
    return [
      WifiNetwork(
        ssid: 'Home Network',
        bssid: 'AA:BB:CC:DD:EE:FF',
        security: WifiSecurityLevel.wpa2Psk,
        signalStrength: -55,
        frequency: 5180,
        isConnected: true,
      ),
      WifiNetwork(
        ssid: 'Neighbor_5G',
        bssid: '11:22:33:44:55:66',
        security: WifiSecurityLevel.wpa3,
        signalStrength: -72,
        frequency: 5240,
      ),
      WifiNetwork(
        ssid: 'FreeWifi',
        bssid: '77:88:99:AA:BB:CC',
        security: WifiSecurityLevel.open,
        signalStrength: -65,
        frequency: 2437,
      ),
      WifiNetwork(
        ssid: 'CoffeeShop',
        bssid: 'DD:EE:FF:00:11:22',
        security: WifiSecurityLevel.wpa2Psk,
        signalStrength: -78,
        frequency: 2462,
      ),
      WifiNetwork(
        ssid: 'DIRECT-xxx',
        bssid: '33:44:55:66:77:88',
        security: WifiSecurityLevel.wpa2Psk,
        signalStrength: -80,
        frequency: 2412,
        isHidden: true,
      ),
    ];
  }

  /// Load mock data
  void _loadMockData() {
    _nearbyNetworks.clear();
    _nearbyNetworks.addAll(_getMockNetworks());
    _checkForThreats();
    _updateStats();
    notifyListeners();
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
}
