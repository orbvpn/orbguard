/// Rogue AP Detection Provider
/// State management for detecting rogue access points and WiFi threats

import 'package:flutter/foundation.dart';

/// AP threat level
enum APThreatLevel {
  dangerous('Dangerous', 0xFFB71C1C),
  suspicious('Suspicious', 0xFFE53935),
  caution('Caution', 0xFFFFA726),
  safe('Safe', 0xFF4CAF50),
  unknown('Unknown', 0xFF9E9E9E);

  final String displayName;
  final int color;

  const APThreatLevel(this.displayName, this.color);
}

/// Security type
enum WiFiSecurity {
  wpa3('WPA3', true),
  wpa2('WPA2', true),
  wpa('WPA', false),
  wep('WEP', false),
  open('Open', false),
  unknown('Unknown', false);

  final String displayName;
  final bool isSecure;

  const WiFiSecurity(this.displayName, this.isSecure);
}

/// Threat type
enum APThreatType {
  evilTwin('Evil Twin', 'Duplicate network impersonating legitimate AP'),
  fakeHotspot('Fake Hotspot', 'Suspicious public-looking network'),
  sslStripping('SSL Stripping', 'AP may intercept HTTPS traffic'),
  deauthAttack('Deauth Attack', 'Disconnection attack detected'),
  weakEncryption('Weak Encryption', 'Outdated or weak security'),
  openNetwork('Open Network', 'No password protection'),
  suspiciousSSID('Suspicious SSID', 'Name mimics common networks'),
  macSpoofing('MAC Spoofing', 'Potential MAC address impersonation');

  final String displayName;
  final String description;

  const APThreatType(this.displayName, this.description);
}

/// Detected access point
class DetectedAP {
  final String id;
  final String ssid;
  final String bssid;
  final int signalStrength;
  final WiFiSecurity security;
  final APThreatLevel threatLevel;
  final List<APThreatType> threats;
  final String? vendor;
  final int channel;
  final bool isConnected;
  final DateTime detectedAt;
  final DateTime? lastSeen;

  DetectedAP({
    required this.id,
    required this.ssid,
    required this.bssid,
    required this.signalStrength,
    required this.security,
    required this.threatLevel,
    this.threats = const [],
    this.vendor,
    required this.channel,
    this.isConnected = false,
    required this.detectedAt,
    this.lastSeen,
  });
}

/// Known/trusted AP
class TrustedAP {
  final String id;
  final String ssid;
  final String bssid;
  final DateTime addedAt;

  TrustedAP({
    required this.id,
    required this.ssid,
    required this.bssid,
    required this.addedAt,
  });
}

/// Rogue AP detection statistics
class RogueAPStats {
  final int totalAPs;
  final int rogueAPs;
  final int suspiciousAPs;
  final int safeAPs;
  final int trustedAPs;
  final int openNetworks;
  final DateTime? lastScan;

  RogueAPStats({
    this.totalAPs = 0,
    this.rogueAPs = 0,
    this.suspiciousAPs = 0,
    this.safeAPs = 0,
    this.trustedAPs = 0,
    this.openNetworks = 0,
    this.lastScan,
  });
}

class RogueAPProvider extends ChangeNotifier {
  // State
  List<DetectedAP> _detectedAPs = [];
  List<TrustedAP> _trustedAPs = [];
  RogueAPStats _stats = RogueAPStats();
  DetectedAP? _currentConnection;

  // Loading states
  bool _isLoading = false;
  bool _isScanning = false;
  double _scanProgress = 0.0;
  String _scanStatus = '';

  // Error state
  String? _error;

  // Protection settings
  bool _autoProtect = true;
  bool _alertOnRogue = true;
  bool _alertOnOpen = true;

  // Getters
  List<DetectedAP> get detectedAPs => _detectedAPs;
  List<TrustedAP> get trustedAPs => _trustedAPs;
  RogueAPStats get stats => _stats;
  DetectedAP? get currentConnection => _currentConnection;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  double get scanProgress => _scanProgress;
  String get scanStatus => _scanStatus;
  String? get error => _error;
  bool get autoProtect => _autoProtect;
  bool get alertOnRogue => _alertOnRogue;
  bool get alertOnOpen => _alertOnOpen;

  // Computed getters
  List<DetectedAP> get rogueAPs =>
      _detectedAPs.where((a) => a.threatLevel == APThreatLevel.dangerous).toList();
  List<DetectedAP> get suspiciousAPs =>
      _detectedAPs.where((a) => a.threatLevel == APThreatLevel.suspicious).toList();

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _loadTrustedAPs();
      await scanForAPs();
    } catch (e) {
      _error = 'Failed to initialize rogue AP detection';
      debugPrint('Error initializing: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load trusted APs
  Future<void> _loadTrustedAPs() async {
    _trustedAPs = [
      TrustedAP(
        id: '1',
        ssid: 'Home-Network',
        bssid: 'AA:BB:CC:DD:EE:FF',
        addedAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      TrustedAP(
        id: '2',
        ssid: 'Office-WiFi',
        bssid: '11:22:33:44:55:66',
        addedAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
    ];
    notifyListeners();
  }

  /// Scan for access points
  Future<void> scanForAPs() async {
    if (_isScanning) return;

    _isScanning = true;
    _scanProgress = 0.0;
    _scanStatus = 'Initializing scan...';
    notifyListeners();

    try {
      final steps = [
        'Scanning 2.4GHz band...',
        'Scanning 5GHz band...',
        'Analyzing access points...',
        'Checking for evil twins...',
        'Verifying security...',
        'Generating report...',
      ];

      for (int i = 0; i < steps.length; i++) {
        _scanStatus = steps[i];
        _scanProgress = (i + 1) / steps.length;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 400));
      }

      // Simulated detected APs
      _detectedAPs = [
        DetectedAP(
          id: '1',
          ssid: 'Home-Network',
          bssid: 'AA:BB:CC:DD:EE:FF',
          signalStrength: -45,
          security: WiFiSecurity.wpa3,
          threatLevel: APThreatLevel.safe,
          vendor: 'ASUS',
          channel: 6,
          isConnected: true,
          detectedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        ),
        DetectedAP(
          id: '2',
          ssid: 'Free_WiFi',
          bssid: '00:11:22:33:44:55',
          signalStrength: -55,
          security: WiFiSecurity.open,
          threatLevel: APThreatLevel.suspicious,
          threats: [APThreatType.openNetwork, APThreatType.suspiciousSSID],
          vendor: 'Unknown',
          channel: 11,
          detectedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        ),
        DetectedAP(
          id: '3',
          ssid: 'Home-Network',
          bssid: 'XX:YY:ZZ:AA:BB:CC',
          signalStrength: -60,
          security: WiFiSecurity.wpa2,
          threatLevel: APThreatLevel.dangerous,
          threats: [APThreatType.evilTwin, APThreatType.macSpoofing],
          vendor: 'Unknown',
          channel: 6,
          detectedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        ),
        DetectedAP(
          id: '4',
          ssid: 'Office-WiFi',
          bssid: '11:22:33:44:55:66',
          signalStrength: -70,
          security: WiFiSecurity.wpa2,
          threatLevel: APThreatLevel.safe,
          vendor: 'Cisco',
          channel: 1,
          detectedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        ),
        DetectedAP(
          id: '5',
          ssid: 'Starbucks',
          bssid: 'FF:EE:DD:CC:BB:AA',
          signalStrength: -75,
          security: WiFiSecurity.open,
          threatLevel: APThreatLevel.caution,
          threats: [APThreatType.openNetwork],
          vendor: 'Aruba',
          channel: 36,
          detectedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        ),
        DetectedAP(
          id: '6',
          ssid: 'NetGear-Guest',
          bssid: '99:88:77:66:55:44',
          signalStrength: -80,
          security: WiFiSecurity.wep,
          threatLevel: APThreatLevel.suspicious,
          threats: [APThreatType.weakEncryption],
          vendor: 'Netgear',
          channel: 11,
          detectedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        ),
      ];

      _currentConnection = _detectedAPs.firstWhere(
        (a) => a.isConnected,
        orElse: () => _detectedAPs.first,
      );

      _scanStatus = 'Scan complete';
      _updateStats();
    } catch (e) {
      _error = 'Scan failed';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Add AP to trusted list
  Future<bool> addTrustedAP(DetectedAP ap) async {
    try {
      final trusted = TrustedAP(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        ssid: ap.ssid,
        bssid: ap.bssid,
        addedAt: DateTime.now(),
      );
      _trustedAPs.add(trusted);
      _updateStats();
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add trusted AP';
      notifyListeners();
      return false;
    }
  }

  /// Remove from trusted list
  Future<bool> removeTrustedAP(String apId) async {
    try {
      _trustedAPs.removeWhere((a) => a.id == apId);
      _updateStats();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Check if AP is trusted
  bool isTrusted(DetectedAP ap) {
    return _trustedAPs.any((t) => t.bssid == ap.bssid);
  }

  /// Update protection settings
  void updateSettings({
    bool? autoProtect,
    bool? alertOnRogue,
    bool? alertOnOpen,
  }) {
    if (autoProtect != null) _autoProtect = autoProtect;
    if (alertOnRogue != null) _alertOnRogue = alertOnRogue;
    if (alertOnOpen != null) _alertOnOpen = alertOnOpen;
    notifyListeners();
  }

  /// Update statistics
  void _updateStats() {
    _stats = RogueAPStats(
      totalAPs: _detectedAPs.length,
      rogueAPs: _detectedAPs.where((a) => a.threatLevel == APThreatLevel.dangerous).length,
      suspiciousAPs: _detectedAPs.where((a) => a.threatLevel == APThreatLevel.suspicious).length,
      safeAPs: _detectedAPs.where((a) => a.threatLevel == APThreatLevel.safe).length,
      trustedAPs: _trustedAPs.length,
      openNetworks: _detectedAPs.where((a) => a.security == WiFiSecurity.open).length,
      lastScan: DateTime.now(),
    );
  }

  /// Get signal strength description
  static String getSignalDescription(int strength) {
    if (strength >= -50) return 'Excellent';
    if (strength >= -60) return 'Good';
    if (strength >= -70) return 'Fair';
    if (strength >= -80) return 'Weak';
    return 'Very Weak';
  }

  /// Get signal icon
  static String getSignalIcon(int strength) {
    if (strength >= -50) return 'signal_wifi_4_bar';
    if (strength >= -60) return 'network_wifi_3_bar';
    if (strength >= -70) return 'network_wifi_2_bar';
    if (strength >= -80) return 'network_wifi_1_bar';
    return 'signal_wifi_off';
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
