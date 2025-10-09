// cloud_threat_intelligence.dart
// Location: lib/intelligence/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================================
// THREAT INTELLIGENCE API CLIENT
// ============================================================================

class ThreatIntelligenceAPI {
  final Dio _dio;
  final String baseUrl;

  // You can use your own API or public threat intelligence feeds
  ThreatIntelligenceAPI({String? apiUrl, String? apiKey})
    : baseUrl = apiUrl ?? 'https://api.yourdomain.com/threat-intelligence',
      _dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            if (apiKey != null) 'Authorization': 'Bearer $apiKey',
          },
        ),
      );

  /// Fetch latest indicators of compromise from multiple sources
  Future<ThreatIntelligenceData> fetchLatestIoCs() async {
    try {
      // Fetch from multiple sources and merge
      final results = await Future.wait([
        _fetchPegasusIoCs(),
        _fetchCommunityIoCs(),
        _fetchPublicFeeds(),
      ]);

      // Merge all sources
      return _mergeIntelligence(results);
    } catch (e) {
      print('Error fetching threat intelligence: $e');
      rethrow;
    }
  }

  /// Fetch Pegasus-specific indicators
  Future<ThreatIntelligenceData> _fetchPegasusIoCs() async {
    try {
      final response = await _dio.get('$baseUrl/pegasus');
      return ThreatIntelligenceData.fromJson(response.data);
    } catch (e) {
      print('Error fetching Pegasus IoCs: $e');
      return ThreatIntelligenceData.empty();
    }
  }

  /// Fetch community-reported indicators
  Future<ThreatIntelligenceData> _fetchCommunityIoCs() async {
    try {
      final response = await _dio.get('$baseUrl/community');
      return ThreatIntelligenceData.fromJson(response.data);
    } catch (e) {
      print('Error fetching community IoCs: $e');
      return ThreatIntelligenceData.empty();
    }
  }

  /// Fetch from public threat intelligence feeds
  Future<ThreatIntelligenceData> _fetchPublicFeeds() async {
    try {
      // Integrate with public feeds like:
      // - Abuse.ch
      // - OpenPhish
      // - URLhaus
      // - Citizen Lab reports

      final feeds = <String, String>{
        'abuse_ch': 'https://urlhaus-api.abuse.ch/v1/urls/recent/',
        'openphish': 'https://openphish.com/feed.txt',
        // Add more feeds
      };

      final allData = ThreatIntelligenceData.empty();

      for (final entry in feeds.entries) {
        try {
          final response = await _dio.get(entry.value);
          final feedData = _parseFeed(entry.key, response.data);
          allData.merge(feedData);
        } catch (e) {
          print('Error fetching ${entry.key}: $e');
        }
      }

      return allData;
    } catch (e) {
      print('Error fetching public feeds: $e');
      return ThreatIntelligenceData.empty();
    }
  }

  ThreatIntelligenceData _parseFeed(String source, dynamic data) {
    // Parse different feed formats
    // Implementation depends on feed format
    return ThreatIntelligenceData.empty();
  }

  ThreatIntelligenceData _mergeIntelligence(
    List<ThreatIntelligenceData> sources,
  ) {
    final merged = ThreatIntelligenceData.empty();
    for (final source in sources) {
      merged.merge(source);
    }
    return merged;
  }

  /// Report a new threat to community database
  Future<bool> reportThreat(ThreatReport report) async {
    try {
      final response = await _dio.post(
        '$baseUrl/report',
        data: report.toJson(),
      );
      return response.statusCode == 200;
    } catch (e) {
      print('Error reporting threat: $e');
      return false;
    }
  }

  /// Query if specific indicator is malicious
  Future<bool> checkIndicator(String indicator, IndicatorType type) async {
    try {
      final response = await _dio.get(
        '$baseUrl/check',
        queryParameters: {
          'indicator': indicator,
          'type': type.toString().split('.').last,
        },
      );
      return response.data['isMalicious'] ?? false;
    } catch (e) {
      print('Error checking indicator: $e');
      return false;
    }
  }
}

// ============================================================================
// THREAT INTELLIGENCE DATA MODEL
// ============================================================================

class ThreatIntelligenceData {
  final Map<String, IndicatorOfCompromise> domains;
  final Map<String, IndicatorOfCompromise> ips;
  final Map<String, IndicatorOfCompromise> fileHashes;
  final Map<String, IndicatorOfCompromise> processNames;
  final Map<String, IndicatorOfCompromise> certificates;
  final Map<String, IndicatorOfCompromise> packageNames;
  final DateTime lastUpdated;
  final int version;

  ThreatIntelligenceData({
    required this.domains,
    required this.ips,
    required this.fileHashes,
    required this.processNames,
    required this.certificates,
    required this.packageNames,
    required this.lastUpdated,
    required this.version,
  });

  factory ThreatIntelligenceData.empty() {
    return ThreatIntelligenceData(
      domains: {},
      ips: {},
      fileHashes: {},
      processNames: {},
      certificates: {},
      packageNames: {},
      lastUpdated: DateTime.now(),
      version: 0,
    );
  }

  factory ThreatIntelligenceData.fromJson(Map<String, dynamic> json) {
    return ThreatIntelligenceData(
      domains: _parseIndicators(json['domains']),
      ips: _parseIndicators(json['ips']),
      fileHashes: _parseIndicators(json['file_hashes']),
      processNames: _parseIndicators(json['process_names']),
      certificates: _parseIndicators(json['certificates']),
      packageNames: _parseIndicators(json['package_names']),
      lastUpdated: DateTime.parse(
        json['last_updated'] ?? DateTime.now().toIso8601String(),
      ),
      version: json['version'] ?? 0,
    );
  }

  static Map<String, IndicatorOfCompromise> _parseIndicators(dynamic data) {
    if (data == null) return {};
    final map = data as Map<String, dynamic>;
    return map.map(
      (key, value) => MapEntry(key, IndicatorOfCompromise.fromJson(value)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'domains': domains.map((k, v) => MapEntry(k, v.toJson())),
      'ips': ips.map((k, v) => MapEntry(k, v.toJson())),
      'file_hashes': fileHashes.map((k, v) => MapEntry(k, v.toJson())),
      'process_names': processNames.map((k, v) => MapEntry(k, v.toJson())),
      'certificates': certificates.map((k, v) => MapEntry(k, v.toJson())),
      'package_names': packageNames.map((k, v) => MapEntry(k, v.toJson())),
      'last_updated': lastUpdated.toIso8601String(),
      'version': version,
    };
  }

  void merge(ThreatIntelligenceData other) {
    domains.addAll(other.domains);
    ips.addAll(other.ips);
    fileHashes.addAll(other.fileHashes);
    processNames.addAll(other.processNames);
    certificates.addAll(other.certificates);
    packageNames.addAll(other.packageNames);
  }

  int get totalIndicators =>
      domains.length +
      ips.length +
      fileHashes.length +
      processNames.length +
      certificates.length +
      packageNames.length;
}

// ============================================================================
// INDICATOR OF COMPROMISE MODEL
// ============================================================================

class IndicatorOfCompromise {
  final String value;
  final IndicatorType type;
  final ThreatSeverity severity;
  final String description;
  final List<String> tags;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final int reportCount;
  final List<String> sources;
  final Map<String, dynamic> metadata;

  IndicatorOfCompromise({
    required this.value,
    required this.type,
    required this.severity,
    required this.description,
    required this.tags,
    required this.firstSeen,
    required this.lastSeen,
    required this.reportCount,
    required this.sources,
    required this.metadata,
  });

  factory IndicatorOfCompromise.fromJson(Map<String, dynamic> json) {
    return IndicatorOfCompromise(
      value: json['value'] ?? '',
      type: IndicatorType.values.firstWhere(
        (e) => e.toString() == 'IndicatorType.${json['type']}',
        orElse: () => IndicatorType.domain,
      ),
      severity: ThreatSeverity.values.firstWhere(
        (e) => e.toString() == 'ThreatSeverity.${json['severity']}',
        orElse: () => ThreatSeverity.medium,
      ),
      description: json['description'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      firstSeen: DateTime.parse(
        json['first_seen'] ?? DateTime.now().toIso8601String(),
      ),
      lastSeen: DateTime.parse(
        json['last_seen'] ?? DateTime.now().toIso8601String(),
      ),
      reportCount: json['report_count'] ?? 1,
      sources: List<String>.from(json['sources'] ?? []),
      metadata: json['metadata'] ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'value': value,
      'type': type.toString().split('.').last,
      'severity': severity.toString().split('.').last,
      'description': description,
      'tags': tags,
      'first_seen': firstSeen.toIso8601String(),
      'last_seen': lastSeen.toIso8601String(),
      'report_count': reportCount,
      'sources': sources,
      'metadata': metadata,
    };
  }
}

enum IndicatorType {
  domain,
  ip,
  fileHash,
  processName,
  certificate,
  packageName,
}

enum ThreatSeverity { critical, high, medium, low, info }

// ============================================================================
// LOCAL INTELLIGENCE CACHE
// ============================================================================

class LocalIntelligenceCache {
  static const String _cacheFileName = 'threat_intelligence_cache.json';
  static const String _lastUpdateKey = 'threat_intel_last_update';

  Future<void> saveIntelligence(ThreatIntelligenceData data) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_cacheFileName');

      await file.writeAsString(jsonEncode(data.toJson()));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastUpdateKey, DateTime.now().toIso8601String());

      print('[Cache] Saved ${data.totalIndicators} indicators');
    } catch (e) {
      print('[Cache] Error saving intelligence: $e');
    }
  }

  Future<ThreatIntelligenceData?> loadIntelligence() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_cacheFileName');

      if (!await file.exists()) {
        return null;
      }

      final contents = await file.readAsString();
      final json = jsonDecode(contents) as Map<String, dynamic>;

      return ThreatIntelligenceData.fromJson(json);
    } catch (e) {
      print('[Cache] Error loading intelligence: $e');
      return null;
    }
  }

  Future<DateTime?> getLastUpdateTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getString(_lastUpdateKey);

      if (timestamp == null) return null;
      return DateTime.parse(timestamp);
    } catch (e) {
      return null;
    }
  }

  Future<bool> needsUpdate({Duration maxAge = const Duration(days: 1)}) async {
    final lastUpdate = await getLastUpdateTime();

    if (lastUpdate == null) return true;

    return DateTime.now().difference(lastUpdate) > maxAge;
  }

  Future<void> clearCache() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_cacheFileName');

      if (await file.exists()) {
        await file.delete();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastUpdateKey);
    } catch (e) {
      print('[Cache] Error clearing cache: $e');
    }
  }
}

// ============================================================================
// THREAT INTELLIGENCE MANAGER
// ============================================================================

class ThreatIntelligenceManager {
  final ThreatIntelligenceAPI api;
  final LocalIntelligenceCache cache;
  ThreatIntelligenceData? _currentIntelligence;

  ThreatIntelligenceManager({String? apiUrl, String? apiKey})
    : api = ThreatIntelligenceAPI(apiUrl: apiUrl, apiKey: apiKey),
      cache = LocalIntelligenceCache();

  /// Initialize - load from cache or fetch from cloud
  Future<void> initialize() async {
    print('[ThreatIntel] Initializing...');

    // Try to load from cache first
    _currentIntelligence = await cache.loadIntelligence();

    if (_currentIntelligence != null) {
      print(
        '[ThreatIntel] Loaded ${_currentIntelligence!.totalIndicators} indicators from cache',
      );
    }

    // Check if needs update
    if (await cache.needsUpdate()) {
      print('[ThreatIntel] Cache outdated, fetching updates...');
      await updateIntelligence();
    }
  }

  /// Fetch latest intelligence from cloud and update cache
  Future<void> updateIntelligence() async {
    try {
      print('[ThreatIntel] Fetching latest intelligence...');

      final newIntelligence = await api.fetchLatestIoCs();

      // Merge with existing if available
      if (_currentIntelligence != null) {
        _currentIntelligence!.merge(newIntelligence);
      } else {
        _currentIntelligence = newIntelligence;
      }

      // Save to cache
      await cache.saveIntelligence(_currentIntelligence!);

      print(
        '[ThreatIntel] Updated with ${_currentIntelligence!.totalIndicators} indicators',
      );
    } catch (e) {
      print('[ThreatIntel] Error updating intelligence: $e');
    }
  }

  /// Check if a domain is malicious
  bool isDomainMalicious(String domain) {
    if (_currentIntelligence == null) return false;

    // Direct match
    if (_currentIntelligence!.domains.containsKey(domain)) {
      return true;
    }

    // Substring match for wildcards
    for (final maliciousDomain in _currentIntelligence!.domains.keys) {
      if (domain.contains(maliciousDomain) ||
          maliciousDomain.contains(domain)) {
        return true;
      }
    }

    return false;
  }

  /// Check if an IP is malicious
  bool isIPMalicious(String ip) {
    if (_currentIntelligence == null) return false;
    return _currentIntelligence!.ips.containsKey(ip);
  }

  /// Check if a file hash is malicious
  bool isFileHashMalicious(String hash) {
    if (_currentIntelligence == null) return false;
    return _currentIntelligence!.fileHashes.containsKey(hash);
  }

  /// Check if a process name is malicious
  bool isProcessMalicious(String processName) {
    if (_currentIntelligence == null) return false;

    // Check exact match
    if (_currentIntelligence!.processNames.containsKey(processName)) {
      return true;
    }

    // Check partial match
    for (final maliciousProcess in _currentIntelligence!.processNames.keys) {
      if (processName.toLowerCase().contains(maliciousProcess.toLowerCase())) {
        return true;
      }
    }

    return false;
  }

  /// Check if a package name is malicious
  bool isPackageMalicious(String packageName) {
    if (_currentIntelligence == null) return false;
    return _currentIntelligence!.packageNames.containsKey(packageName);
  }

  /// Get indicator details
  IndicatorOfCompromise? getIndicatorDetails(String value, IndicatorType type) {
    if (_currentIntelligence == null) return null;

    switch (type) {
      case IndicatorType.domain:
        return _currentIntelligence!.domains[value];
      case IndicatorType.ip:
        return _currentIntelligence!.ips[value];
      case IndicatorType.fileHash:
        return _currentIntelligence!.fileHashes[value];
      case IndicatorType.processName:
        return _currentIntelligence!.processNames[value];
      case IndicatorType.certificate:
        return _currentIntelligence!.certificates[value];
      case IndicatorType.packageName:
        return _currentIntelligence!.packageNames[value];
    }
  }

  /// Report a threat to community database
  Future<bool> reportThreat({
    required String indicator,
    required IndicatorType type,
    required String description,
    List<String>? tags,
    Map<String, dynamic>? metadata,
  }) async {
    final report = ThreatReport(
      indicator: indicator,
      type: type,
      description: description,
      tags: tags ?? [],
      metadata: metadata ?? {},
      reportedAt: DateTime.now(),
      deviceInfo: await _getDeviceInfo(),
    );

    return await api.reportThreat(report);
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    // Anonymized device info for context
    return {
      'platform': Platform.operatingSystem,
      'version': Platform.operatingSystemVersion,
      // Don't include identifying info
    };
  }

  /// Get statistics about current intelligence
  Map<String, dynamic> getStatistics() {
    if (_currentIntelligence == null) {
      return {
        'total': 0,
        'domains': 0,
        'ips': 0,
        'fileHashes': 0,
        'processNames': 0,
        'certificates': 0,
        'packageNames': 0,
        'lastUpdated': null,
      };
    }

    return {
      'total': _currentIntelligence!.totalIndicators,
      'domains': _currentIntelligence!.domains.length,
      'ips': _currentIntelligence!.ips.length,
      'fileHashes': _currentIntelligence!.fileHashes.length,
      'processNames': _currentIntelligence!.processNames.length,
      'certificates': _currentIntelligence!.certificates.length,
      'packageNames': _currentIntelligence!.packageNames.length,
      'lastUpdated': _currentIntelligence!.lastUpdated.toIso8601String(),
      'version': _currentIntelligence!.version,
    };
  }
}

// ============================================================================
// THREAT REPORT MODEL
// ============================================================================

class ThreatReport {
  final String indicator;
  final IndicatorType type;
  final String description;
  final List<String> tags;
  final Map<String, dynamic> metadata;
  final DateTime reportedAt;
  final Map<String, dynamic> deviceInfo;

  ThreatReport({
    required this.indicator,
    required this.type,
    required this.description,
    required this.tags,
    required this.metadata,
    required this.reportedAt,
    required this.deviceInfo,
  });

  Map<String, dynamic> toJson() {
    return {
      'indicator': indicator,
      'type': type.toString().split('.').last,
      'description': description,
      'tags': tags,
      'metadata': metadata,
      'reported_at': reportedAt.toIso8601String(),
      'device_info': deviceInfo,
    };
  }
}

// ============================================================================
// AUTO-UPDATE SERVICE
// ============================================================================

class ThreatIntelligenceAutoUpdater {
  final ThreatIntelligenceManager manager;
  Timer? _updateTimer;

  ThreatIntelligenceAutoUpdater(this.manager);

  /// Start automatic updates
  void startAutoUpdate({Duration interval = const Duration(hours: 6)}) {
    print('[AutoUpdate] Starting with ${interval.inHours}h interval');

    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(interval, (timer) async {
      print('[AutoUpdate] Running scheduled update...');
      await manager.updateIntelligence();
    });
  }

  /// Stop automatic updates
  void stopAutoUpdate() {
    print('[AutoUpdate] Stopping');
    _updateTimer?.cancel();
    _updateTimer = null;
  }
}
