/// Safe Browsing API Service
///
/// Integration with Google Safe Browsing API:
/// - URL threat checking
/// - Malware detection
/// - Social engineering detection
/// - Unwanted software detection
/// - Real-time updates

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Threat type from Safe Browsing
enum SafeBrowsingThreatType {
  malware('MALWARE', 'Malicious software'),
  socialEngineering('SOCIAL_ENGINEERING', 'Phishing/Deceptive content'),
  unwantedSoftware('UNWANTED_SOFTWARE', 'Potentially harmful'),
  potentiallyHarmful('POTENTIALLY_HARMFUL_APPLICATION', 'Dangerous app'),
  threatTypeUnspecified('THREAT_TYPE_UNSPECIFIED', 'Unknown threat');

  final String apiValue;
  final String description;

  const SafeBrowsingThreatType(this.apiValue, this.description);
}

/// Platform type
enum SafeBrowsingPlatform {
  anyPlatform('ANY_PLATFORM'),
  android('ANDROID'),
  ios('IOS'),
  windows('WINDOWS'),
  linux('LINUX'),
  osx('OSX'),
  chrome('CHROME'),
  allPlatforms('ALL_PLATFORMS');

  final String apiValue;

  const SafeBrowsingPlatform(this.apiValue);
}

/// Threat entry type
enum ThreatEntryType {
  url('URL'),
  executable('EXECUTABLE'),
  ipRange('IP_RANGE'),
  threatEntryTypeUnspecified('THREAT_ENTRY_TYPE_UNSPECIFIED');

  final String apiValue;

  const ThreatEntryType(this.apiValue);
}

/// Safe Browsing threat match
class ThreatMatch {
  final SafeBrowsingThreatType threatType;
  final SafeBrowsingPlatform platform;
  final ThreatEntryType threatEntryType;
  final String url;
  final String? cacheDuration;
  final Map<String, dynamic>? threatEntryMetadata;

  ThreatMatch({
    required this.threatType,
    required this.platform,
    required this.threatEntryType,
    required this.url,
    this.cacheDuration,
    this.threatEntryMetadata,
  });

  factory ThreatMatch.fromJson(Map<String, dynamic> json) {
    return ThreatMatch(
      threatType: SafeBrowsingThreatType.values.firstWhere(
        (t) => t.apiValue == json['threatType'],
        orElse: () => SafeBrowsingThreatType.threatTypeUnspecified,
      ),
      platform: SafeBrowsingPlatform.values.firstWhere(
        (p) => p.apiValue == json['platformType'],
        orElse: () => SafeBrowsingPlatform.anyPlatform,
      ),
      threatEntryType: ThreatEntryType.values.firstWhere(
        (t) => t.apiValue == json['threatEntryType'],
        orElse: () => ThreatEntryType.threatEntryTypeUnspecified,
      ),
      url: json['threat']?['url'] as String? ?? '',
      cacheDuration: json['cacheDuration'] as String?,
      threatEntryMetadata: json['threatEntryMetadata'] as Map<String, dynamic>?,
    );
  }
}

/// URL check result
class URLCheckResult {
  final String url;
  final bool isSafe;
  final List<ThreatMatch> threats;
  final DateTime checkTime;
  final bool fromCache;
  final String? error;

  URLCheckResult({
    required this.url,
    required this.isSafe,
    this.threats = const [],
    required this.checkTime,
    this.fromCache = false,
    this.error,
  });

  bool get hasMalware =>
      threats.any((t) => t.threatType == SafeBrowsingThreatType.malware);

  bool get hasPhishing =>
      threats.any((t) => t.threatType == SafeBrowsingThreatType.socialEngineering);

  bool get hasUnwantedSoftware =>
      threats.any((t) => t.threatType == SafeBrowsingThreatType.unwantedSoftware);

  String get threatSummary {
    if (isSafe) return 'Safe';
    return threats.map((t) => t.threatType.description).join(', ');
  }
}

/// Local threat list entry
class LocalThreatEntry {
  final String hashPrefix;
  final SafeBrowsingThreatType threatType;
  final DateTime addedTime;
  final DateTime? expiresTime;

  LocalThreatEntry({
    required this.hashPrefix,
    required this.threatType,
    required this.addedTime,
    this.expiresTime,
  });

  bool get isExpired =>
      expiresTime != null && DateTime.now().isAfter(expiresTime!);
}

/// Safe Browsing API Service
class SafeBrowsingService {
  final String _apiKey;
  final String _clientId;
  final String _clientVersion;

  static const _baseUrl = 'https://safebrowsing.googleapis.com/v4';

  final http.Client _httpClient;
  final Map<String, URLCheckResult> _cache = {};
  final Map<String, LocalThreatEntry> _localDatabase = {};

  Timer? _updateTimer;
  String? _clientState;

  SafeBrowsingService({
    required String apiKey,
    String clientId = 'orbguard',
    String clientVersion = '1.0.0',
    http.Client? httpClient,
  })  : _apiKey = apiKey,
        _clientId = clientId,
        _clientVersion = clientVersion,
        _httpClient = httpClient ?? http.Client();

  /// Check a single URL
  Future<URLCheckResult> checkUrl(String url) async {
    // Check cache first
    final cached = _getCachedResult(url);
    if (cached != null) {
      return URLCheckResult(
        url: url,
        isSafe: cached.isSafe,
        threats: cached.threats,
        checkTime: DateTime.now(),
        fromCache: true,
      );
    }

    // Check local database (Update API)
    final localMatch = await _checkLocalDatabase(url);
    if (localMatch != null) {
      // Need to verify with full hash
      final verified = await _verifyWithFullHashes(url, localMatch);
      if (verified != null) {
        _cacheResult(url, verified);
        return verified;
      }
    }

    // Fall back to Lookup API
    return await _lookupUrl(url);
  }

  /// Check multiple URLs
  Future<Map<String, URLCheckResult>> checkUrls(List<String> urls) async {
    final results = <String, URLCheckResult>{};
    final uncachedUrls = <String>[];

    // Check cache first
    for (final url in urls) {
      final cached = _getCachedResult(url);
      if (cached != null) {
        results[url] = URLCheckResult(
          url: url,
          isSafe: cached.isSafe,
          threats: cached.threats,
          checkTime: DateTime.now(),
          fromCache: true,
        );
      } else {
        uncachedUrls.add(url);
      }
    }

    // Batch check uncached URLs
    if (uncachedUrls.isNotEmpty) {
      final batchResults = await _lookupUrls(uncachedUrls);
      results.addAll(batchResults);
    }

    return results;
  }

  /// Lookup URL using Lookup API
  Future<URLCheckResult> _lookupUrl(String url) async {
    final results = await _lookupUrls([url]);
    return results[url] ?? URLCheckResult(
      url: url,
      isSafe: true,
      checkTime: DateTime.now(),
    );
  }

  /// Lookup multiple URLs using Lookup API
  Future<Map<String, URLCheckResult>> _lookupUrls(List<String> urls) async {
    final results = <String, URLCheckResult>{};

    try {
      final requestBody = {
        'client': {
          'clientId': _clientId,
          'clientVersion': _clientVersion,
        },
        'threatInfo': {
          'threatTypes': [
            SafeBrowsingThreatType.malware.apiValue,
            SafeBrowsingThreatType.socialEngineering.apiValue,
            SafeBrowsingThreatType.unwantedSoftware.apiValue,
            SafeBrowsingThreatType.potentiallyHarmful.apiValue,
          ],
          'platformTypes': [
            SafeBrowsingPlatform.anyPlatform.apiValue,
          ],
          'threatEntryTypes': [
            ThreatEntryType.url.apiValue,
          ],
          'threatEntries': urls.map((url) => {'url': url}).toList(),
        },
      };

      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/threatMatches:find?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final matches = (data['matches'] as List<dynamic>?)
            ?.map((m) => ThreatMatch.fromJson(m as Map<String, dynamic>))
            .toList() ?? [];

        // Group matches by URL
        final matchesByUrl = <String, List<ThreatMatch>>{};
        for (final match in matches) {
          matchesByUrl.putIfAbsent(match.url, () => []).add(match);
        }

        // Create results for all URLs
        for (final url in urls) {
          final urlMatches = matchesByUrl[url] ?? [];
          final result = URLCheckResult(
            url: url,
            isSafe: urlMatches.isEmpty,
            threats: urlMatches,
            checkTime: DateTime.now(),
          );
          results[url] = result;
          _cacheResult(url, result);
        }
      } else {
        // API error - assume safe but log error
        for (final url in urls) {
          results[url] = URLCheckResult(
            url: url,
            isSafe: true,
            checkTime: DateTime.now(),
            error: 'API error: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      // Network error - assume safe but log error
      for (final url in urls) {
        results[url] = URLCheckResult(
          url: url,
          isSafe: true,
          checkTime: DateTime.now(),
          error: 'Network error: $e',
        );
      }
    }

    return results;
  }

  /// Check URL against local database
  Future<LocalThreatEntry?> _checkLocalDatabase(String url) async {
    // Calculate hash prefix
    final hash = sha256.convert(utf8.encode(_canonicalizeUrl(url)));
    final hashPrefix = hash.toString().substring(0, 8); // 4-byte prefix

    final entry = _localDatabase[hashPrefix];
    if (entry != null && !entry.isExpired) {
      return entry;
    }
    return null;
  }

  /// Verify potential match with full hashes
  Future<URLCheckResult?> _verifyWithFullHashes(
    String url,
    LocalThreatEntry localMatch,
  ) async {
    try {
      final hash = sha256.convert(utf8.encode(_canonicalizeUrl(url)));
      final hashPrefix = hash.toString().substring(0, 8);

      final requestBody = {
        'client': {
          'clientId': _clientId,
          'clientVersion': _clientVersion,
        },
        'threatInfo': {
          'threatTypes': [localMatch.threatType.apiValue],
          'platformTypes': [SafeBrowsingPlatform.anyPlatform.apiValue],
          'threatEntryTypes': [ThreatEntryType.url.apiValue],
        },
        'clientStates': _clientState != null ? [_clientState] : [],
        'threatEntries': [
          {'hash': hashPrefix},
        ],
      };

      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/fullHashes:find?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final matches = (data['matches'] as List<dynamic>?)
            ?.map((m) => ThreatMatch.fromJson(m as Map<String, dynamic>))
            .toList() ?? [];

        if (matches.isNotEmpty) {
          return URLCheckResult(
            url: url,
            isSafe: false,
            threats: matches,
            checkTime: DateTime.now(),
          );
        }
      }
    } catch (e) {
      // Verification failed - fall back to lookup
    }
    return null;
  }

  /// Update local database
  Future<void> updateLocalDatabase() async {
    try {
      final requestBody = {
        'client': {
          'clientId': _clientId,
          'clientVersion': _clientVersion,
        },
        'listUpdateRequests': [
          {
            'threatType': SafeBrowsingThreatType.malware.apiValue,
            'platformType': SafeBrowsingPlatform.anyPlatform.apiValue,
            'threatEntryType': ThreatEntryType.url.apiValue,
            'state': _clientState ?? '',
            'constraints': {
              'maxUpdateEntries': 2048,
              'maxDatabaseEntries': 4096,
              'region': 'US',
              'supportedCompressions': ['RAW'],
            },
          },
          {
            'threatType': SafeBrowsingThreatType.socialEngineering.apiValue,
            'platformType': SafeBrowsingPlatform.anyPlatform.apiValue,
            'threatEntryType': ThreatEntryType.url.apiValue,
            'state': _clientState ?? '',
            'constraints': {
              'maxUpdateEntries': 2048,
              'maxDatabaseEntries': 4096,
              'region': 'US',
              'supportedCompressions': ['RAW'],
            },
          },
        ],
      };

      final response = await _httpClient.post(
        Uri.parse('$_baseUrl/threatListUpdates:fetch?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final listUpdates = data['listUpdateResponses'] as List<dynamic>? ?? [];

        for (final update in listUpdates) {
          final updateMap = update as Map<String, dynamic>;
          final responseType = updateMap['responseType'] as String?;
          final newClientState = updateMap['newClientState'] as String?;
          final additions = updateMap['additions'] as List<dynamic>? ?? [];
          final removals = updateMap['removals'] as List<dynamic>? ?? [];

          // Handle full update
          if (responseType == 'FULL_UPDATE') {
            _localDatabase.clear();
          }

          // Process additions
          final threatType = SafeBrowsingThreatType.values.firstWhere(
            (t) => t.apiValue == updateMap['threatType'],
            orElse: () => SafeBrowsingThreatType.threatTypeUnspecified,
          );

          for (final addition in additions) {
            final additionMap = addition as Map<String, dynamic>;
            final rawHashes = additionMap['rawHashes'] as Map<String, dynamic>?;
            if (rawHashes != null) {
              final prefixSize = rawHashes['prefixSize'] as int? ?? 4;
              final rawData = rawHashes['rawHashes'] as String? ?? '';
              // Parse and add hash prefixes
              _parseAndAddHashes(rawData, prefixSize, threatType);
            }
          }

          // Process removals
          for (final removal in removals) {
            final removalMap = removal as Map<String, dynamic>;
            final rawIndices = removalMap['rawIndices'] as Map<String, dynamic>?;
            if (rawIndices != null) {
              final indices = rawIndices['indices'] as List<dynamic>? ?? [];
              // Remove by indices (would need to maintain index mapping)
            }
          }

          if (newClientState != null) {
            _clientState = newClientState;
          }
        }
      }
    } catch (e) {
      // Update failed
      print('Safe Browsing update failed: $e');
    }
  }

  void _parseAndAddHashes(String rawData, int prefixSize, SafeBrowsingThreatType threatType) {
    // Parse base64 encoded hash prefixes
    try {
      final bytes = base64Decode(rawData);
      for (var i = 0; i < bytes.length; i += prefixSize) {
        final prefix = bytes.sublist(i, i + prefixSize);
        final prefixHex = prefix.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        _localDatabase[prefixHex] = LocalThreatEntry(
          hashPrefix: prefixHex,
          threatType: threatType,
          addedTime: DateTime.now(),
          expiresTime: DateTime.now().add(const Duration(hours: 1)),
        );
      }
    } catch (e) {
      // Parse error
    }
  }

  /// Canonicalize URL for hashing
  String _canonicalizeUrl(String url) {
    var canonical = url.toLowerCase();

    // Remove fragment
    final fragmentIndex = canonical.indexOf('#');
    if (fragmentIndex >= 0) {
      canonical = canonical.substring(0, fragmentIndex);
    }

    // Ensure scheme
    if (!canonical.startsWith('http://') && !canonical.startsWith('https://')) {
      canonical = 'http://$canonical';
    }

    // Remove trailing slash
    if (canonical.endsWith('/')) {
      canonical = canonical.substring(0, canonical.length - 1);
    }

    return canonical;
  }

  /// Get cached result
  URLCheckResult? _getCachedResult(String url) {
    final cached = _cache[url];
    if (cached != null) {
      // Check if cache is still valid (5 minutes)
      if (DateTime.now().difference(cached.checkTime).inMinutes < 5) {
        return cached;
      }
      _cache.remove(url);
    }
    return null;
  }

  /// Cache result
  void _cacheResult(String url, URLCheckResult result) {
    _cache[url] = result;

    // Limit cache size
    if (_cache.length > 1000) {
      final oldestUrl = _cache.entries
          .reduce((a, b) =>
              a.value.checkTime.isBefore(b.value.checkTime) ? a : b)
          .key;
      _cache.remove(oldestUrl);
    }
  }

  /// Start periodic updates
  void startPeriodicUpdates({Duration interval = const Duration(minutes: 30)}) {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(interval, (_) => updateLocalDatabase());

    // Initial update
    updateLocalDatabase();
  }

  /// Stop periodic updates
  void stopPeriodicUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
  }

  /// Get cache stats
  Map<String, dynamic> getCacheStats() {
    return {
      'cached_urls': _cache.length,
      'local_database_entries': _localDatabase.length,
      'client_state': _clientState != null,
    };
  }

  /// Dispose resources
  void dispose() {
    stopPeriodicUpdates();
    _httpClient.close();
  }
}
