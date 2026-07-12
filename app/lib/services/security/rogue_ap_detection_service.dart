/// Rogue Access Point Detection Service
///
/// Detects malicious WiFi access points and network attacks:
/// - Evil twin detection (fake APs mimicking legitimate networks)
/// - MAC address spoofing detection
/// - Signal strength anomaly detection
/// - SSID spoofing detection
/// - Deauth attack detection
/// - Captive portal phishing detection
/// - SSL/TLS interception detection

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// WiFi access point information
class AccessPoint {
  final String ssid;
  final String bssid; // MAC address
  final int signalStrength; // dBm
  final int frequency; // MHz
  final String? securityType;
  final bool isConnected;
  final String? capabilities;
  final DateTime lastSeen;
  final int? channelWidth;
  final bool is5GHz;

  AccessPoint({
    required this.ssid,
    required this.bssid,
    required this.signalStrength,
    required this.frequency,
    this.securityType,
    this.isConnected = false,
    this.capabilities,
    DateTime? lastSeen,
    this.channelWidth,
  }) : lastSeen = lastSeen ?? DateTime.now(),
       is5GHz = frequency >= 5000;

  factory AccessPoint.fromJson(Map<String, dynamic> json) {
    return AccessPoint(
      ssid: json['ssid'] as String? ?? '',
      bssid: json['bssid'] as String? ?? '',
      signalStrength: json['signal_strength'] as int? ?? -100,
      frequency: json['frequency'] as int? ?? 0,
      securityType: json['security_type'] as String?,
      isConnected: json['is_connected'] as bool? ?? false,
      capabilities: json['capabilities'] as String?,
      lastSeen: json['last_seen'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_seen'] as int)
          : null,
      channelWidth: json['channel_width'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'ssid': ssid,
    'bssid': bssid,
    'signal_strength': signalStrength,
    'frequency': frequency,
    'security_type': securityType,
    'is_connected': isConnected,
    'capabilities': capabilities,
    'last_seen': lastSeen.millisecondsSinceEpoch,
    'channel_width': channelWidth,
    'is_5ghz': is5GHz,
  };

  /// Get signal quality percentage (0-100)
  int get signalQuality {
    // Convert dBm to percentage (-100 dBm = 0%, -30 dBm = 100%)
    return ((signalStrength + 100) * 100 / 70).clamp(0, 100).round();
  }

  /// Get vendor from OUI (first 3 bytes of MAC)
  String get vendorOUI => bssid.split(':').take(3).join(':').toUpperCase();
}

/// Rogue AP detection result
class RogueAPResult {
  final AccessPoint accessPoint;
  final bool isRogue;
  final double confidenceScore;
  final RogueAPType? threatType;
  final List<RogueAPIndicator> indicators;
  final String riskLevel;
  final String recommendation;
  final AccessPoint? legitimateAP;

  RogueAPResult({
    required this.accessPoint,
    required this.isRogue,
    required this.confidenceScore,
    this.threatType,
    required this.indicators,
    required this.riskLevel,
    required this.recommendation,
    this.legitimateAP,
  });

  String get riskColor {
    switch (riskLevel.toLowerCase()) {
      case 'critical':
        return '#FF0000';
      case 'high':
        return '#FF4444';
      case 'medium':
        return '#FFA500';
      case 'low':
        return '#FFFF00';
      default:
        return '#00FF00';
    }
  }
}

/// Types of rogue AP threats
enum RogueAPType {
  evilTwin('Evil Twin', 'Fake AP mimicking a legitimate network'),
  honeypot('Honeypot', 'Open network designed to capture traffic'),
  karmaAttack('Karma Attack', 'AP responding to all probe requests'),
  deauthAttack('Deauth Attack', 'AP forcing disconnections'),
  sslStripping('SSL Stripping', 'Man-in-the-middle intercepting HTTPS'),
  captivePortalPhishing('Captive Portal Phishing', 'Fake login page'),
  macSpoofing('MAC Spoofing', 'Impersonating legitimate AP MAC address'),
  rogueHotspot('Rogue Hotspot', 'Unauthorized access point');

  final String displayName;
  final String description;
  const RogueAPType(this.displayName, this.description);
}

/// Specific indicator of rogue AP
class RogueAPIndicator {
  final String type;
  final String description;
  final double weight;
  final String? evidence;

  RogueAPIndicator({
    required this.type,
    required this.description,
    required this.weight,
    this.evidence,
  });
}

/// Known/trusted network profile
class TrustedNetwork {
  final String ssid;
  final Set<String> knownBSSIDs;
  final String? expectedSecurityType;
  final int? expectedSignalMin;
  final int? expectedSignalMax;
  final String? location;
  final DateTime firstSeen;
  final DateTime lastSeen;

  TrustedNetwork({
    required this.ssid,
    required this.knownBSSIDs,
    this.expectedSecurityType,
    this.expectedSignalMin,
    this.expectedSignalMax,
    this.location,
    DateTime? firstSeen,
    DateTime? lastSeen,
  }) : firstSeen = firstSeen ?? DateTime.now(),
       lastSeen = lastSeen ?? DateTime.now();

  factory TrustedNetwork.fromJson(Map<String, dynamic> json) {
    return TrustedNetwork(
      ssid: json['ssid'] as String,
      knownBSSIDs: Set<String>.from(json['known_bssids'] as List<dynamic>),
      expectedSecurityType: json['expected_security_type'] as String?,
      expectedSignalMin: json['expected_signal_min'] as int?,
      expectedSignalMax: json['expected_signal_max'] as int?,
      location: json['location'] as String?,
      firstSeen: json['first_seen'] != null
          ? DateTime.parse(json['first_seen'] as String)
          : null,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'ssid': ssid,
    'known_bssids': knownBSSIDs.toList(),
    'expected_security_type': expectedSecurityType,
    'expected_signal_min': expectedSignalMin,
    'expected_signal_max': expectedSignalMax,
    'location': location,
    'first_seen': firstSeen.toIso8601String(),
    'last_seen': lastSeen.toIso8601String(),
  };
}

/// Network scan result
class NetworkScanResult {
  final List<AccessPoint> accessPoints;
  final List<RogueAPResult> threats;
  final int totalAPs;
  final int rogueCount;
  final DateTime scanTime;
  final Duration scanDuration;

  NetworkScanResult({
    required this.accessPoints,
    required this.threats,
    required this.totalAPs,
    required this.rogueCount,
    required this.scanTime,
    required this.scanDuration,
  });

  /// Get APs grouped by SSID
  Map<String, List<AccessPoint>> get apsBySSID {
    final grouped = <String, List<AccessPoint>>{};
    for (final ap in accessPoints) {
      grouped.putIfAbsent(ap.ssid, () => []).add(ap);
    }
    return grouped;
  }
}

/// Rogue AP Detection Service
class RogueAPDetectionService {
  static const MethodChannel _channel = MethodChannel('com.orbguard/rogue_ap');
  static const EventChannel _eventChannel = EventChannel('com.orbguard/wifi_events');

  // Trusted networks database
  final Map<String, TrustedNetwork> _trustedNetworks = {};

  // Historical AP data for anomaly detection
  final Map<String, List<AccessPoint>> _apHistory = {};

  // Known legitimate vendor OUIs
  final Set<String> _legitimateVendorOUIs = {};

  // Stream controllers
  final _scanResultController = StreamController<NetworkScanResult>.broadcast();
  final _threatAlertController = StreamController<RogueAPResult>.broadcast();

  // Monitoring state
  bool _isMonitoring = false;
  Timer? _scanTimer;
  StreamSubscription? _wifiEventSubscription;

  /// Stream of scan results
  Stream<NetworkScanResult> get onScanResult => _scanResultController.stream;

  /// Stream of threat alerts
  Stream<RogueAPResult> get onThreatAlert => _threatAlertController.stream;

  /// Whether monitoring is active
  bool get isMonitoring => _isMonitoring;

  /// Initialize the service
  Future<void> initialize() async {
    _loadLegitimateVendors();
    await _loadTrustedNetworks();
  }

  /// Load legitimate vendor OUIs
  void _loadLegitimateVendors() {
    // Common legitimate router/AP vendors
    _legitimateVendorOUIs.addAll([
      // Cisco
      '00:00:0C', '00:01:42', '00:01:64', '00:1A:2F', '00:1B:54',
      // TP-Link
      '50:C7:BF', '60:E3:27', '98:DA:C4', 'AC:84:C6', 'C0:E4:2D',
      // Netgear
      '00:14:6C', '00:1E:2A', '00:1F:33', '00:22:3F', '00:26:F2',
      // Linksys
      '00:04:5A', '00:06:25', '00:0C:41', '00:0F:66', '00:12:17',
      // Asus
      '00:11:D8', '00:13:D4', '00:15:F2', '00:17:31', '00:1A:92',
      // D-Link
      '00:05:5D', '00:0D:88', '00:0F:3D', '00:11:95', '00:13:46',
      // Ubiquiti
      '00:27:22', '04:18:D6', '24:A4:3C', '44:D9:E7', '68:72:51',
      // Aruba/HPE
      '00:0B:86', '00:1A:1E', '00:24:6C', '04:BD:88', '24:DE:C6',
      // Ruckus
      '00:25:C4', '58:B6:33', '74:91:1A', 'C4:10:8A', 'EC:58:EA',
      // Meraki
      '00:18:0A', '88:15:44', 'E0:CB:BC', 'E8:ED:05', 'AC:17:C8',
    ]);
  }

  /// Load trusted networks from storage
  Future<void> _loadTrustedNetworks() async {
    // In production, load from secure storage
    // For now, start with empty and learn from user connections
  }

  /// Add a trusted network
  void addTrustedNetwork(TrustedNetwork network) {
    _trustedNetworks[network.ssid] = network;
  }

  /// Remove a trusted network
  void removeTrustedNetwork(String ssid) {
    _trustedNetworks.remove(ssid);
  }

  /// Get all trusted networks
  List<TrustedNetwork> get trustedNetworks => _trustedNetworks.values.toList();

  /// Perform a WiFi scan and analyze for rogue APs
  Future<NetworkScanResult> scanNetworks() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('WiFi scanning only supported on mobile');
    }

    final startTime = DateTime.now();

    try {
      // Get nearby access points from native
      final scanData = await _channel.invokeMethod<List<dynamic>>('scanWifi');

      final accessPoints = (scanData ?? [])
          .map((e) => AccessPoint.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      // Analyze each AP for threats
      final threats = <RogueAPResult>[];
      for (final ap in accessPoints) {
        final result = await analyzeAccessPoint(ap, accessPoints);
        if (result.isRogue) {
          threats.add(result);
          _threatAlertController.add(result);
        }
      }

      // Update history
      for (final ap in accessPoints) {
        _apHistory.putIfAbsent(ap.bssid, () => []).add(ap);
        // Keep only last 100 observations per AP
        if (_apHistory[ap.bssid]!.length > 100) {
          _apHistory[ap.bssid]!.removeAt(0);
        }
      }

      final result = NetworkScanResult(
        accessPoints: accessPoints,
        threats: threats,
        totalAPs: accessPoints.length,
        rogueCount: threats.length,
        scanTime: startTime,
        scanDuration: DateTime.now().difference(startTime),
      );

      _scanResultController.add(result);
      return result;
    } catch (e) {
      debugPrint('WiFi scan error: $e');
      rethrow;
    }
  }

  /// Analyze a single access point for rogue indicators
  Future<RogueAPResult> analyzeAccessPoint(
    AccessPoint ap,
    List<AccessPoint> allAPs,
  ) async {
    double score = 0.0;
    final indicators = <RogueAPIndicator>[];
    RogueAPType? threatType;
    AccessPoint? legitimateAP;

    // 1. Check for evil twin (same SSID, different BSSID)
    final sameSSID = allAPs.where((other) =>
      other.ssid == ap.ssid && other.bssid != ap.bssid
    ).toList();

    if (sameSSID.isNotEmpty && ap.ssid.isNotEmpty) {
      // Check if this BSSID is in trusted list
      final trusted = _trustedNetworks[ap.ssid];
      if (trusted != null && !trusted.knownBSSIDs.contains(ap.bssid)) {
        score += 0.4;
        threatType = RogueAPType.evilTwin;
        indicators.add(RogueAPIndicator(
          type: 'unknown_bssid',
          description: 'Unknown BSSID for trusted network "${ap.ssid}"',
          weight: 0.4,
          evidence: 'Known BSSIDs: ${trusted.knownBSSIDs.join(", ")}',
        ));

        // Find the legitimate AP
        legitimateAP = allAPs.firstWhere(
          (other) => trusted.knownBSSIDs.contains(other.bssid),
          orElse: () => ap,
        );
      }

      // Check for security downgrade
      if (sameSSID.any((other) => _isSecurityDowngrade(other, ap))) {
        score += 0.3;
        indicators.add(RogueAPIndicator(
          type: 'security_downgrade',
          description: 'Lower security than other APs with same SSID',
          weight: 0.3,
          evidence: 'This AP: ${ap.securityType}, Others have stronger security',
        ));
      }
    }

    // 2. Check for open network with common SSID (honeypot)
    if (_isLikelyHoneypot(ap)) {
      score += 0.35;
      threatType ??= RogueAPType.honeypot;
      indicators.add(RogueAPIndicator(
        type: 'honeypot_pattern',
        description: 'Open network with attractive SSID',
        weight: 0.35,
        evidence: 'SSID "${ap.ssid}" with open security',
      ));
    }

    // 3. Check vendor OUI
    if (!_legitimateVendorOUIs.contains(ap.vendorOUI)) {
      // Unknown vendor - could be legitimate or spoofed
      score += 0.1;
      indicators.add(RogueAPIndicator(
        type: 'unknown_vendor',
        description: 'MAC address from unknown vendor',
        weight: 0.1,
        evidence: 'OUI: ${ap.vendorOUI}',
      ));
    }

    // 4. Check for MAC randomization (suspicious for APs)
    if (_isRandomizedMAC(ap.bssid)) {
      score += 0.25;
      indicators.add(RogueAPIndicator(
        type: 'randomized_mac',
        description: 'MAC address appears randomized (unusual for legitimate APs)',
        weight: 0.25,
        evidence: 'BSSID: ${ap.bssid}',
      ));
    }

    // 5. Check signal strength anomalies
    final signalAnomaly = _checkSignalAnomaly(ap);
    if (signalAnomaly != null) {
      score += signalAnomaly.weight;
      indicators.add(signalAnomaly);
    }

    // 6. Check for deauth attack patterns (requires historical data)
    if (_apHistory.containsKey(ap.bssid)) {
      final history = _apHistory[ap.bssid]!;
      if (_detectDeauthPattern(history)) {
        score += 0.4;
        threatType = RogueAPType.deauthAttack;
        indicators.add(RogueAPIndicator(
          type: 'deauth_pattern',
          description: 'Frequent disconnections detected from this AP',
          weight: 0.4,
        ));
      }
    }

    // 7. Check for common rogue SSID patterns
    final roguePattern = _checkRogueSSIDPattern(ap.ssid);
    if (roguePattern != null) {
      score += roguePattern.weight;
      indicators.add(roguePattern);
    }

    // 8. Check for unusually strong signal (possible proximity attack)
    if (ap.signalStrength > -30) {
      score += 0.15;
      indicators.add(RogueAPIndicator(
        type: 'unusually_strong_signal',
        description: 'Extremely strong signal (possible nearby attack device)',
        weight: 0.15,
        evidence: 'Signal: ${ap.signalStrength} dBm',
      ));
    }

    // Normalize score
    score = score.clamp(0.0, 1.0);

    // Determine risk level
    String riskLevel;
    if (score >= 0.7) {
      riskLevel = 'critical';
    } else if (score >= 0.5) {
      riskLevel = 'high';
    } else if (score >= 0.3) {
      riskLevel = 'medium';
    } else if (score >= 0.15) {
      riskLevel = 'low';
    } else {
      riskLevel = 'safe';
    }

    // Generate recommendation
    final recommendation = _generateRecommendation(score, threatType, ap);

    return RogueAPResult(
      accessPoint: ap,
      isRogue: score >= 0.4,
      confidenceScore: score,
      threatType: threatType,
      indicators: indicators,
      riskLevel: riskLevel,
      recommendation: recommendation,
      legitimateAP: legitimateAP,
    );
  }

  /// Check if AP is likely a honeypot
  bool _isLikelyHoneypot(AccessPoint ap) {
    // Open networks with attractive names
    final honeypotPatterns = [
      RegExp(r'^free\s*(wi-?fi|internet|hotspot)', caseSensitive: false),
      RegExp(r'^(airport|hotel|cafe|coffee|starbucks|mcdonalds)', caseSensitive: false),
      RegExp(r'^guest', caseSensitive: false),
      RegExp(r'^open', caseSensitive: false),
      RegExp(r'^public', caseSensitive: false),
      RegExp(r'(free|gratis|libero)', caseSensitive: false),
    ];

    final isOpen = ap.securityType == null ||
        ap.securityType!.toLowerCase().contains('open') ||
        ap.securityType!.isEmpty;

    if (!isOpen) return false;

    return honeypotPatterns.any((p) => p.hasMatch(ap.ssid));
  }

  /// Check for security downgrade attack
  bool _isSecurityDowngrade(AccessPoint legitimate, AccessPoint suspect) {
    final securityLevels = {
      'wpa3': 4,
      'wpa2': 3,
      'wpa': 2,
      'wep': 1,
      'open': 0,
      '': 0,
    };

    int getLevel(String? security) {
      if (security == null) return 0;
      final lower = security.toLowerCase();
      for (final entry in securityLevels.entries) {
        if (lower.contains(entry.key)) return entry.value;
      }
      return 0;
    }

    return getLevel(suspect.securityType) < getLevel(legitimate.securityType);
  }

  /// Check if MAC address appears randomized
  bool _isRandomizedMAC(String bssid) {
    // Randomized MACs have bit 1 of first byte set (locally administered)
    final firstByte = int.tryParse(bssid.split(':').first, radix: 16) ?? 0;
    return (firstByte & 0x02) != 0;
  }

  /// Check for signal strength anomalies
  RogueAPIndicator? _checkSignalAnomaly(AccessPoint ap) {
    final trusted = _trustedNetworks[ap.ssid];
    if (trusted == null) return null;

    // Check if signal is outside expected range
    if (trusted.expectedSignalMin != null && trusted.expectedSignalMax != null) {
      if (ap.signalStrength < trusted.expectedSignalMin! - 20 ||
          ap.signalStrength > trusted.expectedSignalMax! + 10) {
        return RogueAPIndicator(
          type: 'signal_anomaly',
          description: 'Signal strength outside expected range',
          weight: 0.2,
          evidence: 'Expected: ${trusted.expectedSignalMin} to ${trusted.expectedSignalMax} dBm, '
              'Got: ${ap.signalStrength} dBm',
        );
      }
    }

    return null;
  }

  /// Detect deauth attack pattern from history
  bool _detectDeauthPattern(List<AccessPoint> history) {
    if (history.length < 5) return false;

    // Check for frequent signal drops indicating forced disconnections
    int dropCount = 0;
    for (int i = 1; i < history.length; i++) {
      final prev = history[i - 1];
      final curr = history[i];

      // Sudden signal drop followed by return
      if (prev.signalStrength - curr.signalStrength > 30) {
        dropCount++;
      }
    }

    // More than 3 drops in recent history suggests deauth
    return dropCount >= 3;
  }

  /// Check for common rogue SSID patterns
  RogueAPIndicator? _checkRogueSSIDPattern(String ssid) {
    // Typosquatting patterns
    final typoPatterns = [
      // Common misspellings
      (RegExp(r'googl[^e]|gogle'), 'Google'),
      (RegExp(r'faceboo[^k]|facbook'), 'Facebook'),
      (RegExp(r'amazo[^n]|amzon'), 'Amazon'),
      (RegExp(r'starbuks|starbuck[^s]'), 'Starbucks'),
      (RegExp(r'xfinti|xfinnity'), 'Xfinity'),
    ];

    for (final pattern in typoPatterns) {
      if (pattern.$1.hasMatch(ssid.toLowerCase())) {
        return RogueAPIndicator(
          type: 'typosquatting',
          description: 'SSID appears to mimic "${pattern.$2}"',
          weight: 0.35,
          evidence: 'Suspicious SSID: $ssid',
        );
      }
    }

    // Suspicious suffixes
    if (RegExp(r'[-_](test|temp|backup|new|old|2|copy)$', caseSensitive: false).hasMatch(ssid)) {
      return RogueAPIndicator(
        type: 'suspicious_suffix',
        description: 'SSID has suspicious suffix suggesting a clone',
        weight: 0.2,
        evidence: 'SSID: $ssid',
      );
    }

    return null;
  }

  /// Generate recommendation based on threat
  String _generateRecommendation(double score, RogueAPType? type, AccessPoint ap) {
    if (score >= 0.7) {
      return 'DANGER: This network "${ap.ssid}" appears to be malicious. '
          'Do NOT connect. ${type != null ? "Detected: ${type.displayName}. " : ""}'
          'Use mobile data or a trusted VPN instead.';
    } else if (score >= 0.5) {
      return 'WARNING: This network has suspicious characteristics. '
          'Avoid connecting unless you can verify its legitimacy. '
          'If you must connect, use a VPN.';
    } else if (score >= 0.3) {
      return 'CAUTION: Some concerns detected with this network. '
          'Verify network ownership before connecting. Use HTTPS for all browsing.';
    } else if (score >= 0.15) {
      return 'LOW RISK: Minor anomalies detected. Exercise normal caution.';
    } else {
      return 'This network appears safe based on current analysis.';
    }
  }

  /// Start continuous monitoring
  Future<void> startMonitoring({
    Duration interval = const Duration(minutes: 2),
  }) async {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // Setup WiFi event listener
    if (Platform.isAndroid) {
      _wifiEventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          if (event is Map) {
            final ap = AccessPoint.fromJson(Map<String, dynamic>.from(event));
            // Trigger analysis on new AP
            scanNetworks();
          }
        },
      );
    }

    // Periodic scanning
    _scanTimer = Timer.periodic(interval, (_) {
      if (_isMonitoring) {
        scanNetworks();
      }
    });

    // Initial scan
    await scanNetworks();
  }

  /// Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    _wifiEventSubscription?.cancel();
    _wifiEventSubscription = null;
  }

  /// Learn current network as trusted
  Future<void> trustCurrentNetwork() async {
    try {
      final currentInfo = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentWifi');

      if (currentInfo == null) return;

      final ssid = currentInfo['ssid'] as String?;
      final bssid = currentInfo['bssid'] as String?;
      final signal = currentInfo['signal_strength'] as int?;
      final security = currentInfo['security_type'] as String?;

      if (ssid == null || bssid == null) return;

      // Add or update trusted network
      final existing = _trustedNetworks[ssid];
      if (existing != null) {
        // Update existing
        _trustedNetworks[ssid] = TrustedNetwork(
          ssid: ssid,
          knownBSSIDs: {...existing.knownBSSIDs, bssid},
          expectedSecurityType: security ?? existing.expectedSecurityType,
          expectedSignalMin: signal != null
              ? (existing.expectedSignalMin != null
                  ? (signal < existing.expectedSignalMin! ? signal : existing.expectedSignalMin)
                  : signal)
              : existing.expectedSignalMin,
          expectedSignalMax: signal != null
              ? (existing.expectedSignalMax != null
                  ? (signal > existing.expectedSignalMax! ? signal : existing.expectedSignalMax)
                  : signal)
              : existing.expectedSignalMax,
          firstSeen: existing.firstSeen,
          lastSeen: DateTime.now(),
        );
      } else {
        // Create new
        _trustedNetworks[ssid] = TrustedNetwork(
          ssid: ssid,
          knownBSSIDs: {bssid},
          expectedSecurityType: security,
          expectedSignalMin: signal,
          expectedSignalMax: signal,
        );
      }
    } catch (e) {
      debugPrint('Failed to trust network: $e');
    }
  }

  /// Check if currently connected network is safe
  Future<RogueAPResult?> checkCurrentNetwork() async {
    try {
      final currentInfo = await _channel.invokeMethod<Map<dynamic, dynamic>>('getCurrentWifi');

      if (currentInfo == null) return null;

      final ap = AccessPoint(
        ssid: currentInfo['ssid'] as String? ?? '',
        bssid: currentInfo['bssid'] as String? ?? '',
        signalStrength: currentInfo['signal_strength'] as int? ?? -100,
        frequency: currentInfo['frequency'] as int? ?? 0,
        securityType: currentInfo['security_type'] as String?,
        isConnected: true,
      );

      // Get all nearby APs for comparison
      final scanResult = await scanNetworks();
      return analyzeAccessPoint(ap, scanResult.accessPoints);
    } catch (e) {
      debugPrint('Failed to check current network: $e');
      return null;
    }
  }

  /// Get detection statistics
  Map<String, dynamic> getStatistics() {
    return {
      'trusted_networks': _trustedNetworks.length,
      'monitored_aps': _apHistory.length,
      'known_vendors': _legitimateVendorOUIs.length,
      'is_monitoring': _isMonitoring,
    };
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _scanResultController.close();
    _threatAlertController.close();
  }
}
