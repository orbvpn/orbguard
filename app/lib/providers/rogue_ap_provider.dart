// Rogue AP Detection Provider
// State management for detecting rogue access points and WiFi threats

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/orbguard_api_client.dart';
import '../services/notifications/notification_service.dart';
import '../services/notifications/notification_channels.dart';

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
  // API client
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;
  static const _wifiChannel = MethodChannel('com.orb.guard/wifi');

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

  // Protection settings (persisted)
  static const _prefsAutoProtectKey = 'rogueap_auto_protect';
  static const _prefsAlertOnRogueKey = 'rogueap_alert_on_rogue';
  static const _prefsAlertOnOpenKey = 'rogueap_alert_on_open';

  SharedPreferences? _prefs;
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

  /// OrbGuard does not bundle a VPN engine, so the "auto protection"
  /// preference cannot switch a VPN on by itself. It is stored and shown
  /// honestly: when enabled, threat notifications tell the user to connect
  /// their VPN manually. UI should label the switch accordingly.
  bool get autoProtectVpnSwitchAvailable => false;

  /// Why the VPN auto-switch is inert on this build.
  String get autoProtectLimitation =>
      'OrbGuard cannot enable a VPN automatically on this build because no '
      'VPN engine is bundled. When a rogue network is detected you will be '
      'alerted and asked to switch networks or connect your VPN manually.';

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
      await _loadSettings();
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

  /// Load trusted APs from API
  Future<void> _loadTrustedAPs() async {
    try {
      final trustedData = await _api.getTrustedAPs();
      _trustedAPs = trustedData.map((data) => TrustedAP(
        id: data['id'] as String? ?? '',
        ssid: data['ssid'] as String? ?? '',
        bssid: data['bssid'] as String? ?? '',
        addedAt: data['added_at'] != null
            ? DateTime.tryParse(data['added_at'] as String) ?? DateTime.now()
            : DateTime.now(),
      )).toList();
    } catch (e) {
      debugPrint('Failed to load trusted APs: $e');
      _trustedAPs = [];
    }
    notifyListeners();
  }

  /// Scan for access points using platform channel and API
  Future<void> scanForAPs() async {
    if (_isScanning) return;

    _isScanning = true;
    _scanProgress = 0.0;
    _scanStatus = 'Initializing scan...';
    notifyListeners();

    try {
      // Step 1: Scan for nearby APs using platform channel
      _scanStatus = 'Scanning nearby networks...';
      _scanProgress = 0.2;
      notifyListeners();

      List<Map<String, dynamic>> nearbyAPs = [];
      try {
        final result = await _wifiChannel.invokeMethod<List<dynamic>>('scanWifiNetworks');
        if (result != null) {
          nearbyAPs = result.map((ap) => Map<String, dynamic>.from(ap as Map)).toList();
        }
      } on PlatformException catch (e) {
        debugPrint('Platform WiFi scan failed: $e');
      }

      // Step 2: Send to API for threat analysis
      _scanStatus = 'Analyzing threats...';
      _scanProgress = 0.5;
      notifyListeners();

      final analysisResult = await _api.scanRogueAPs(nearbyAPs);

      // Step 3: Parse results
      _scanStatus = 'Processing results...';
      _scanProgress = 0.8;
      notifyListeners();

      final detectedList = analysisResult['access_points'] as List<dynamic>? ?? [];
      _detectedAPs = detectedList.map((data) {
        final apData = data as Map<String, dynamic>;
        return DetectedAP(
          id: apData['id'] as String? ?? '',
          ssid: apData['ssid'] as String? ?? 'Unknown',
          bssid: apData['bssid'] as String? ?? '',
          signalStrength: (apData['signal_strength'] as num?)?.toInt() ?? -100,
          security: _parseWifiSecurity(apData['security'] as String?),
          threatLevel: _parseThreatLevel(apData['threat_level'] as String?),
          threats: _parseThreats(apData['threats'] as List<dynamic>?),
          vendor: apData['vendor'] as String?,
          channel: (apData['channel'] as num?)?.toInt() ?? 0,
          isConnected: apData['is_connected'] as bool? ?? false,
          detectedAt: DateTime.now(),
          lastSeen: DateTime.now(),
        );
      }).toList();

      // Find current connection
      _currentConnection = _detectedAPs.where((a) => a.isConnected).firstOrNull;

      _scanStatus = 'Scan complete';
      _scanProgress = 1.0;
      _updateStats();

      // Fire real alert notifications according to the persisted settings.
      await _emitScanAlerts();
    } catch (e) {
      _error = 'Scan failed: $e';
      debugPrint('Rogue AP scan failed: $e');
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Send local notifications for the findings of the scan that just
  /// completed, honoring the user's alert settings. This is the real consumer
  /// of [alertOnRogue] / [alertOnOpen]; [autoProtect] cannot switch a VPN
  /// (see [autoProtectLimitation]) so its notification says so explicitly.
  Future<void> _emitScanAlerts() async {
    final notifications = NotificationService.instance;

    if (_alertOnRogue) {
      final dangerous = _detectedAPs
          .where((a) =>
              !isTrusted(a) &&
              (a.threatLevel == APThreatLevel.dangerous ||
                  a.threatLevel == APThreatLevel.suspicious))
          .toList();
      if (dangerous.isNotEmpty) {
        final names = dangerous.map((a) => a.ssid).take(3).join(', ');
        final suffix =
            dangerous.length > 3 ? ' and ${dangerous.length - 3} more' : '';
        final action = _autoProtect
            ? ' Auto-protection cannot switch your VPN on this build — '
                'connect your VPN or switch networks manually.'
            : '';
        try {
          await notifications.showNotification(
            title: dangerous.length == 1
                ? 'Rogue access point detected'
                : '${dangerous.length} rogue access points detected',
            body: 'Dangerous Wi-Fi nearby: $names$suffix.$action',
            channel: NotificationChannels.high,
            payload: 'rogue_ap_scan',
          );
        } catch (e) {
          debugPrint('RogueAPProvider: failed to show rogue AP alert: $e');
        }
      }
    }

    if (_alertOnOpen) {
      final connectedOpen = _currentConnection != null &&
          _currentConnection!.security == WiFiSecurity.open;
      if (connectedOpen) {
        try {
          await notifications.showNotification(
            title: 'Connected to an unencrypted network',
            body: 'The network "${_currentConnection!.ssid}" has no '
                'encryption. Traffic on it can be read by others nearby.',
            channel: NotificationChannels.medium,
            payload: 'rogue_ap_open_network',
          );
        } catch (e) {
          debugPrint('RogueAPProvider: failed to show open-network alert: $e');
        }
      }
    }
  }

  /// Add AP to trusted list
  Future<bool> addTrustedAP(DetectedAP ap) async {
    try {
      final result = await _api.addTrustedAP(ap.ssid, ap.bssid);
      final trusted = TrustedAP(
        id: result['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
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
      debugPrint('Failed to add trusted AP: $e');
      notifyListeners();
      return false;
    }
  }

  /// Remove from trusted list
  Future<bool> removeTrustedAP(String apId) async {
    try {
      await _api.removeTrustedAP(apId);
      _trustedAPs.removeWhere((a) => a.id == apId);
      _updateStats();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to remove trusted AP: $e');
      return false;
    }
  }

  /// Check if AP is trusted
  bool isTrusted(DetectedAP ap) {
    return _trustedAPs.any((t) => t.bssid == ap.bssid);
  }

  /// Load persisted protection settings.
  Future<void> _loadSettings() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('RogueAPProvider: failed to open preferences: $e');
      return;
    }
    _autoProtect = _prefs!.getBool(_prefsAutoProtectKey) ?? true;
    _alertOnRogue = _prefs!.getBool(_prefsAlertOnRogueKey) ?? true;
    _alertOnOpen = _prefs!.getBool(_prefsAlertOnOpenKey) ?? true;
  }

  /// Update protection settings (persisted across restarts).
  Future<void> updateSettings({
    bool? autoProtect,
    bool? alertOnRogue,
    bool? alertOnOpen,
  }) async {
    if (autoProtect != null) _autoProtect = autoProtect;
    if (alertOnRogue != null) _alertOnRogue = alertOnRogue;
    if (alertOnOpen != null) _alertOnOpen = alertOnOpen;
    notifyListeners();

    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setBool(_prefsAutoProtectKey, _autoProtect);
      await _prefs!.setBool(_prefsAlertOnRogueKey, _alertOnRogue);
      await _prefs!.setBool(_prefsAlertOnOpenKey, _alertOnOpen);
    } catch (e) {
      debugPrint('RogueAPProvider: failed to persist settings: $e');
    }
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

  /// Parse WiFi security from API response
  WiFiSecurity _parseWifiSecurity(String? security) {
    if (security == null) return WiFiSecurity.unknown;
    switch (security.toUpperCase()) {
      case 'WPA3':
        return WiFiSecurity.wpa3;
      case 'WPA2':
        return WiFiSecurity.wpa2;
      case 'WPA':
        return WiFiSecurity.wpa;
      case 'WEP':
        return WiFiSecurity.wep;
      case 'OPEN':
      case 'NONE':
        return WiFiSecurity.open;
      default:
        return WiFiSecurity.unknown;
    }
  }

  /// Parse threat level from API response
  APThreatLevel _parseThreatLevel(String? level) {
    if (level == null) return APThreatLevel.unknown;
    switch (level.toLowerCase()) {
      case 'dangerous':
      case 'critical':
      case 'high':
        return APThreatLevel.dangerous;
      case 'suspicious':
      case 'medium':
        return APThreatLevel.suspicious;
      case 'caution':
      case 'low':
        return APThreatLevel.caution;
      case 'safe':
      case 'none':
        return APThreatLevel.safe;
      default:
        return APThreatLevel.unknown;
    }
  }

  /// Parse threats list from API response
  List<APThreatType> _parseThreats(List<dynamic>? threats) {
    if (threats == null || threats.isEmpty) return [];
    return threats.map((t) {
      final threatStr = (t as String?)?.toLowerCase() ?? '';
      switch (threatStr) {
        case 'evil_twin':
        case 'eviltwin':
          return APThreatType.evilTwin;
        case 'fake_hotspot':
        case 'fakehotspot':
          return APThreatType.fakeHotspot;
        case 'ssl_stripping':
        case 'sslstripping':
          return APThreatType.sslStripping;
        case 'deauth_attack':
        case 'deauthattack':
          return APThreatType.deauthAttack;
        case 'weak_encryption':
        case 'weakencryption':
          return APThreatType.weakEncryption;
        case 'open_network':
        case 'opennetwork':
          return APThreatType.openNetwork;
        case 'suspicious_ssid':
        case 'suspiciousssid':
          return APThreatType.suspiciousSSID;
        case 'mac_spoofing':
        case 'macspoofing':
          return APThreatType.macSpoofing;
        default:
          return null;
      }
    }).whereType<APThreatType>().toList();
  }
}
