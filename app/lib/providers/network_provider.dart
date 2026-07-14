// Network Provider
// State management for network security features

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api/url_reputation.dart';
import '../services/api/api_config.dart';
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

/// One canary domain resolved through the DEVICE's local resolver.
/// Hijack detection must use the local resolver: a server resolving canaries
/// proves nothing about the resolver this device actually uses.
class DnsCanaryResolution {
  final String canary;
  final List<String> resolvedIps;

  /// Set when the local lookup itself failed (no network, blocked resolver).
  /// A failed lookup is reported honestly instead of being sent as a clean
  /// empty answer set.
  final String? lookupError;

  DnsCanaryResolution({
    required this.canary,
    required this.resolvedIps,
    this.lookupError,
  });

  bool get succeeded => lookupError == null && resolvedIps.isNotEmpty;
}

/// What the backend's authoritative canary DNS server observed for the leak
/// check token this device resolved: the egress IP of whichever recursive
/// resolver actually performed the device's lookup.
class DnsLeakObservation {
  /// Source IP of the first canary query seen at the authoritative server.
  final String observedResolverIp;

  /// Every distinct resolver egress IP observed for the token.
  final List<String> observedResolverIps;

  /// True when an observed IP exactly equals the device's configured
  /// resolver. Public resolvers (1.1.1.1, 8.8.8.8) legitimately egress from
  /// provider ranges that differ from their anycast address, so `false` is
  /// informational, not proof of a leak by itself.
  final bool matchesConfiguredResolver;

  /// ASN of the observed resolver, when the backend recorded one.
  final int? resolverAsn;

  DnsLeakObservation({
    required this.observedResolverIp,
    required this.observedResolverIps,
    required this.matchesConfiguredResolver,
    this.resolverAsn,
  });

  static DnsLeakObservation? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final observed = json['observed_resolver_ip'] as String?;
    if (observed == null || observed.isEmpty) return null;
    return DnsLeakObservation(
      observedResolverIp: observed,
      observedResolverIps:
          (json['observed_resolver_ips'] as List<dynamic>? ?? const [])
              .map((e) => e.toString())
              .toList(growable: false),
      matchesConfiguredResolver:
          json['matches_configured_resolver'] as bool? ?? false,
      resolverAsn: (json['resolver_asn'] as num?)?.toInt(),
    );
  }
}

/// Result of a DNS security check (client-side canary resolution verified by
/// the backend against known-good answer sets and threat intelligence).
class DnsCheckResult {
  final bool isHijacked;
  final bool isSecure;
  final bool isEncrypted;
  final String? providerName;

  /// Backend status of the hijack check ("performed: ..." or
  /// "not_performed: ..."). Distinguishes "checked and clean" from
  /// "check never ran".
  final String hijackCheckStatus;

  /// Backend status of the leak check. When the backend advertises a
  /// controlled canary zone (GET /network/dns/leak-config) this device
  /// resolves a random {token}.{zone} and the backend reports
  /// "performed: ..." (query observed at its authoritative server) or
  /// "not_observed: ...". When no canary zone is deployed the status stays
  /// an explicit "unavailable: ..." — never a fabricated result.
  final String leakCheckStatus;

  /// Authoritative-server observation when [leakCheckPerformed]; null
  /// otherwise.
  final DnsLeakObservation? leakObservation;

  final String? hijackDescription;
  final double? hijackConfidence;
  final List<String> issues;

  /// What this device actually measured (including failed lookups).
  final List<DnsCanaryResolution> canaryResolutions;
  final String? resolverHint;
  final DateTime checkedAt;

  DnsCheckResult({
    required this.isHijacked,
    required this.isSecure,
    required this.isEncrypted,
    this.providerName,
    required this.hijackCheckStatus,
    required this.leakCheckStatus,
    this.leakObservation,
    this.hijackDescription,
    this.hijackConfidence,
    this.issues = const [],
    this.canaryResolutions = const [],
    this.resolverHint,
    required this.checkedAt,
  });

  bool get hijackCheckPerformed => hijackCheckStatus.startsWith('performed');
  bool get leakCheckUnavailable => leakCheckStatus.startsWith('unavailable');
  bool get leakCheckPerformed => leakCheckStatus.startsWith('performed');
  bool get leakCheckNotObserved => leakCheckStatus.startsWith('not_observed');
}

/// Network security stats. Every field is derived from real scan/check
/// results — the app performs no on-device DNS or site blocking, so no
/// "blocked" counters exist here.
class NetworkSecurityStats {
  final int totalScans;
  final int threatsDetected;
  final int openNetworksFound;
  final int rogueApsDetected;

  NetworkSecurityStats({
    this.totalScans = 0,
    this.threatsDetected = 0,
    this.openNetworksFound = 0,
    this.rogueApsDetected = 0,
  });
}

/// Network Provider
class NetworkProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // Platform channel for native WiFi scanning
  static const _wifiChannel = MethodChannel('com.orb.guard/wifi');

  /// Master network-protection flag persisted by the Settings screen
  /// (ProtectionSettings → SettingsProvider, key `prot_network`).
  static const _kMasterProtectionKey = 'prot_network';
  SharedPreferences? _prefs;

  // State
  WifiNetwork? _currentNetwork;
  final List<WifiNetwork> _nearbyNetworks = [];

  /// Threats reported by the backend (GET /network/threats). Owned by
  /// [loadNetworkThreats]; never touched by local scans.
  final List<NetworkThreat> _remoteThreats = [];

  /// Threats derived on-device (local scan heuristics, WiFi audit of the
  /// current network, DNS hijack check). Owned by the scan/check methods;
  /// never touched by [loadNetworkThreats].
  final List<NetworkThreat> _localThreats = [];

  NetworkSecurityStats _stats = NetworkSecurityStats();

  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;

  // DNS security check state
  DnsCheckResult? _dnsCheckResult;
  bool _isCheckingDns = false;
  String? _dnsCheckError;

  // Getters
  WifiNetwork? get currentNetwork => _currentNetwork;
  List<WifiNetwork> get nearbyNetworks => List.unmodifiable(_nearbyNetworks);
  List<NetworkThreat> get threats =>
      List.unmodifiable([..._remoteThreats, ..._localThreats]);
  NetworkSecurityStats get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get error => _error;
  DnsCheckResult? get dnsCheckResult => _dnsCheckResult;
  bool get isCheckingDns => _isCheckingDns;
  String? get dnsCheckError => _dnsCheckError;

  /// True when the user turned network protection off in the app Settings
  /// (`prot_network`). While set, active scans and DNS checks are skipped.
  bool get protectionDisabledByUser => _protectionDisabledByUser;
  bool _protectionDisabledByUser = false;

  /// Reads the persisted Settings flag. Fails open (enabled) when
  /// preferences are unavailable — an unreadable setting is not a user
  /// opt-out.
  Future<bool> _isProtectionEnabledByUser() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('NetworkProvider: cannot read protection setting: $e');
    }
    final enabled = _prefs?.getBool(_kMasterProtectionKey) ?? true;
    _protectionDisabledByUser = !enabled;
    return enabled;
  }

  /// Active threats
  List<NetworkThreat> get activeThreats =>
      threats.where((t) => t.isActive).toList();

  /// Critical threats
  List<NetworkThreat> get criticalThreats =>
      threats.where((t) => t.isCritical && t.isActive).toList();

  /// Open (unsecured) networks nearby
  List<WifiNetwork> get openNetworks =>
      _nearbyNetworks.where((n) => !n.security.isSecure).toList();

  /// Is current network secure?
  bool get isCurrentNetworkSecure =>
      _currentNetwork?.security.isSecure ?? true;

  /// Initialize provider
  Future<void> init() async {
    await refreshNetworkInfo();
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
    if (!await _isProtectionEnabledByUser()) {
      _error = 'Network protection is disabled in Settings.';
      notifyListeners();
      return;
    }

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

      // Rebuild locally-derived threats from this scan, then append any
      // findings from the backend WiFi audit of the current network.
      _checkForThreats();
      if (_currentNetwork != null) {
        await _auditCurrentNetwork();
      }

      _updateStats(countScan: true);
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
          if (!_localThreats.any((t) => t.id == threatId)) {
            _localThreats.add(NetworkThreat(
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

      _remoteThreats.clear();
      for (final threatJson in threatsData) {
        _remoteThreats.add(NetworkThreat(
          id: threatJson['id'] as String? ?? '',
          type: threatJson['type'] as String? ?? 'unknown',
          title: threatJson['title'] as String? ?? 'Network Threat',
          description: threatJson['description'] as String? ?? '',
          severity: threatJson['severity'] as String? ?? 'medium',
          detectedAt: threatJson['detected_at'] != null
              ? DateTime.tryParse(threatJson['detected_at'] as String) ??
                  DateTime.now()
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

  // NOTE: device VPN connect/disconnect and DNS enable/disable were removed.
  // The backend never exposed those endpoints; VPN protection is provided by
  // the separate OrbVPN app, and secure DNS is configured at the OS level
  // (Android Private DNS / Apple DNS profiles).

  // ============================================
  // DNS SECURITY CHECK (client-side resolution)
  // ============================================

  /// Well-known canary hostnames with long-term-stable, vendor-operated
  /// answer sets the backend can verify:
  ///   one.one.one.one -> 1.1.1.1 / 1.0.0.1 (+IPv6), operated by Cloudflare
  ///   dns.google      -> 8.8.8.8 / 8.8.4.4 (+IPv6), operated by Google
  static const List<String> _dnsCanaries = ['one.one.one.one', 'dns.google'];

  /// Controlled leak-check canary zone advertised by the backend
  /// (GET /network/dns/leak-config). Cached for the provider's lifetime once
  /// fetched successfully; null while unknown, '' when the backend reports
  /// leak detection unavailable.
  String? _leakCanaryZone;

  /// Fetch (and cache) the leak-check canary zone. Failures are tolerated:
  /// the DNS check still runs, with the leak check reported by the backend
  /// as not performed.
  Future<String?> _getLeakCanaryZone() async {
    if (_leakCanaryZone != null) return _leakCanaryZone;
    try {
      final config = await _api.get<Map<String, dynamic>>(
        ApiEndpoints.networkDnsLeakConfig,
      );
      final available = config['leak_check_available'] as bool? ?? false;
      final zone = config['canary_zone'] as String? ?? '';
      _leakCanaryZone = available ? zone : '';
    } catch (e) {
      // Leave null so the next check retries the fetch.
      debugPrint('DNS check: leak canary config unavailable: $e');
    }
    final zone = _leakCanaryZone;
    return (zone == null || zone.isEmpty) ? null : zone;
  }

  /// Generate a crypto-secure random leak canary token: 32 lowercase hex
  /// characters (128 bits), a single valid DNS label.
  static String _generateLeakCanaryToken() {
    final rng = Random.secure();
    const hex = '0123456789abcdef';
    return String.fromCharCodes(
      List.generate(32, (_) => hex.codeUnitAt(rng.nextInt(16))),
    );
  }

  /// Run a DNS hijack check: resolve canary domains through this device's
  /// LOCAL resolver and submit the answers to the backend, which compares
  /// them against known-good answer sets and threat intelligence.
  ///
  /// Device identity for the backend audit trail is carried by the
  /// authenticated device api_key (the server's auth middleware resolves the
  /// device_id from it), so no device_id needs to be embedded in the body.
  Future<void> runDnsCheck() async {
    if (_isCheckingDns) return;
    if (!await _isProtectionEnabledByUser()) {
      _dnsCheckError = 'Network protection is disabled in Settings.';
      notifyListeners();
      return;
    }

    _isCheckingDns = true;
    _dnsCheckError = null;
    notifyListeners();

    try {
      // 1. Resolve each canary through the device's local resolver.
      final resolutions = <DnsCanaryResolution>[];
      for (final canary in _dnsCanaries) {
        try {
          final addresses = await InternetAddress.lookup(canary)
              .timeout(const Duration(seconds: 8));
          resolutions.add(DnsCanaryResolution(
            canary: canary,
            resolvedIps:
                addresses.map((a) => a.address).toList(growable: false),
          ));
        } on SocketException catch (e) {
          resolutions.add(DnsCanaryResolution(
            canary: canary,
            resolvedIps: const [],
            lookupError: e.message.isNotEmpty ? e.message : 'lookup failed',
          ));
        } on TimeoutException {
          resolutions.add(DnsCanaryResolution(
            canary: canary,
            resolvedIps: const [],
            lookupError: 'lookup timed out',
          ));
        }
      }

      // 2. Best-effort resolver hint from the native side. If the platform
      // does not expose the configured DNS servers, the hint is omitted —
      // never guessed.
      String? resolverHint;
      try {
        final servers =
            await _wifiChannel.invokeMethod<List<dynamic>>('getDnsServers');
        if (servers != null && servers.isNotEmpty) {
          resolverHint = servers.map((s) => s.toString()).join(',');
        }
      } on PlatformException catch (e) {
        debugPrint('DNS check: resolver hint unavailable: ${e.message}');
      } on MissingPluginException {
        debugPrint('DNS check: resolver hint unavailable (no native handler)');
      }

      final successful = resolutions.where((r) => r.succeeded).toList();
      if (successful.isEmpty && resolverHint == null) {
        // Nothing measurable: local resolution failed for every canary and
        // the resolver address is unknown. Report the failure explicitly
        // instead of submitting an empty check.
        final details = resolutions
            .map((r) => '${r.canary}: ${r.lookupError ?? 'no answers'}')
            .join('; ');
        _dnsCheckError =
            'DNS check could not run: local canary resolution failed ($details)';
        return;
      }

      // 3. Real leak check: when the backend advertises a controlled canary
      // zone, resolve a crypto-random {token}.{zone} through the LOCAL
      // resolver. The answer does not matter and lookup failure is tolerated
      // — what counts is which resolver IP contacts the backend's
      // authoritative canary server for the token. The token is submitted
      // either way: the absence of any query at the authoritative server is
      // itself signal (surfaced as "not_observed").
      String? leakCanaryToken;
      final leakZone = await _getLeakCanaryZone();
      if (leakZone != null) {
        leakCanaryToken = _generateLeakCanaryToken();
        try {
          await InternetAddress.lookup('$leakCanaryToken.$leakZone')
              .timeout(const Duration(seconds: 8));
        } on SocketException catch (e) {
          debugPrint(
              'DNS check: leak canary lookup failed (token still submitted): ${e.message}');
        } on TimeoutException {
          debugPrint(
              'DNS check: leak canary lookup timed out (token still submitted)');
        }
      }

      // 4. Submit the client-side measurements for verification.
      final response = await _api.post<Map<String, dynamic>>(
        ApiEndpoints.networkDnsCheck,
        data: {
          'current_dns':
              resolverHint == null ? '' : resolverHint.split(',').first,
          'check_hijack': true,
          'check_leaks': true,
          if (leakCanaryToken != null) 'leak_canary_token': leakCanaryToken,
          'client_resolutions': [
            for (final r in successful)
              {
                'canary': r.canary,
                'resolved_ips': r.resolvedIps,
                if (resolverHint != null) 'resolver_hint': resolverHint,
              },
          ],
        },
      );

      // 5. Parse the verified result.
      final issues = <String>[];
      for (final issue
          in (response['security_issues'] as List<dynamic>? ?? const [])) {
        final map = issue as Map<String, dynamic>;
        final title = map['title'] as String? ?? '';
        final description = map['description'] as String? ?? '';
        issues.add(title.isEmpty ? description : '$title: $description');
      }
      final provider = response['provider'] as Map<String, dynamic>?;
      final hijackDetails =
          response['hijack_details'] as Map<String, dynamic>?;

      // The check response also advertises the canary zone; refresh the
      // cache so a zone enabled after the leak-config fetch is picked up.
      final advertisedZone = response['leak_canary_zone'] as String?;
      if (advertisedZone != null && advertisedZone.isNotEmpty) {
        _leakCanaryZone = advertisedZone;
      }

      _dnsCheckResult = DnsCheckResult(
        isHijacked: response['is_hijacked'] as bool? ?? false,
        isSecure: response['is_secure'] as bool? ?? false,
        isEncrypted: response['is_encrypted'] as bool? ?? false,
        providerName: provider?['name'] as String?,
        hijackCheckStatus:
            response['hijack_check_status'] as String? ?? 'unknown',
        leakCheckStatus: response['leak_check_status'] as String? ?? 'unknown',
        leakObservation: DnsLeakObservation.fromJson(
            response['leak_observation'] as Map<String, dynamic>?),
        hijackDescription: hijackDetails?['description'] as String?,
        hijackConfidence: (hijackDetails?['confidence'] as num?)?.toDouble(),
        issues: issues,
        canaryResolutions: resolutions,
        resolverHint: resolverHint,
        checkedAt: DateTime.now(),
      );

      _syncDnsHijackThreat();
    } catch (e) {
      _dnsCheckError = 'DNS check failed: $e';
      debugPrint(_dnsCheckError);
    } finally {
      _isCheckingDns = false;
      notifyListeners();
    }
  }

  /// Keep the threats list in sync with the latest verified DNS check.
  void _syncDnsHijackThreat() {
    const threatId = 'dns_hijacking_local';
    _localThreats.removeWhere((t) => t.id == threatId);

    final result = _dnsCheckResult;
    if (result == null || !result.isHijacked) return;

    _localThreats.add(NetworkThreat(
      id: threatId,
      type: 'dns_hijacking',
      title: _getThreatTitle('dns_hijacking'),
      description: result.hijackDescription ??
          'The DNS resolver used by this device is rewriting answers for well-known domains.',
      severity: 'critical',
      detectedAt: result.checkedAt,
      recommendation: _getThreatRecommendation('dns_hijacking'),
    ));
  }

  /// Dismiss threat
  void dismissThreat(String id) {
    final removedLocal = _localThreats.any((t) => t.id == id);
    final removedRemote = _remoteThreats.any((t) => t.id == id);
    if (removedLocal) _localThreats.removeWhere((t) => t.id == id);
    if (removedRemote) _remoteThreats.removeWhere((t) => t.id == id);
    if (removedLocal || removedRemote) {
      _updateStats();
      notifyListeners();
    }
  }

  /// Rebuild locally-derived scan threats. Only touches [_localThreats];
  /// backend-reported threats are preserved. The DNS hijack finding (owned by
  /// [_syncDnsHijackThreat]) is re-applied after the rebuild.
  void _checkForThreats() {
    _localThreats.clear();

    // Check for open networks
    for (final network in _nearbyNetworks) {
      if (network.security == WifiSecurityLevel.open) {
        // Check for potential evil twin
        if (_nearbyNetworks.any((n) =>
            n.ssid == network.ssid &&
            n.bssid != network.bssid &&
            n.security.isSecure)) {
          _localThreats.add(NetworkThreat(
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
      _localThreats.add(NetworkThreat(
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

    // Re-apply the DNS hijack finding (cleared with the rest of the local
    // threats above) from the latest verified DNS check result.
    _syncDnsHijackThreat();
  }

  /// Update stats. [countScan] is true only when a real network scan
  /// completed, so the scan counter reflects actual scans rather than every
  /// state refresh.
  void _updateStats({bool countScan = false}) {
    final all = threats;
    _stats = NetworkSecurityStats(
      totalScans: _stats.totalScans + (countScan ? 1 : 0),
      threatsDetected: all.length,
      openNetworksFound: openNetworks.length,
      rogueApsDetected: all.where((t) => t.type == 'evil_twin').length,
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
