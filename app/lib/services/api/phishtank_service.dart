/// PhishTank Service
///
/// Integration with PhishTank API for verified phishing URLs:
/// - URL checking against PhishTank database
/// - Phishing submission
/// - Database updates
/// - Vote verification

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// PhishTank check result
enum PhishTankResult {
  phishing('Phishing', 'Verified phishing site'),
  notPhishing('Not Phishing', 'Not a known phishing site'),
  unknown('Unknown', 'Not in database'),
  error('Error', 'Check failed');

  final String displayName;
  final String description;

  const PhishTankResult(this.displayName, this.description);
}

/// PhishTank phish details
class PhishDetails {
  final int phishId;
  final String url;
  final DateTime submissionTime;
  final DateTime? verifiedTime;
  final bool isVerified;
  final bool isOnline;
  final String? target;
  final String? detailsUrl;

  PhishDetails({
    required this.phishId,
    required this.url,
    required this.submissionTime,
    this.verifiedTime,
    required this.isVerified,
    required this.isOnline,
    this.target,
    this.detailsUrl,
  });

  factory PhishDetails.fromJson(Map<String, dynamic> json) {
    final results = json['results'] as Map<String, dynamic>? ?? json;

    return PhishDetails(
      phishId: int.tryParse(results['phish_id']?.toString() ?? '0') ?? 0,
      url: results['url'] as String? ?? '',
      submissionTime: results['submission_time'] != null
          ? DateTime.parse(results['submission_time'] as String)
          : DateTime.now(),
      verifiedTime: results['verified_at'] != null
          ? DateTime.tryParse(results['verified_at'] as String)
          : null,
      isVerified: results['verified'] == 'yes' || results['verified'] == true,
      isOnline: results['online'] == 'yes' || results['online'] == true,
      target: results['target'] as String?,
      detailsUrl: results['phish_detail_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'phish_id': phishId,
    'url': url,
    'submission_time': submissionTime.toIso8601String(),
    'verified_time': verifiedTime?.toIso8601String(),
    'is_verified': isVerified,
    'is_online': isOnline,
    'target': target,
    'details_url': detailsUrl,
  };
}

/// PhishTank check response
class PhishTankCheckResponse {
  final String url;
  final PhishTankResult result;
  final PhishDetails? details;
  final DateTime checkedAt;
  final bool fromCache;
  final String? errorMessage;

  PhishTankCheckResponse({
    required this.url,
    required this.result,
    this.details,
    required this.checkedAt,
    this.fromCache = false,
    this.errorMessage,
  });

  bool get isPhishing => result == PhishTankResult.phishing;
  bool get isVerified => details?.isVerified ?? false;
}

/// PhishTank database entry
class PhishTankEntry {
  final int phishId;
  final String url;
  final String urlHash;
  final DateTime addedAt;
  final String? target;

  PhishTankEntry({
    required this.phishId,
    required this.url,
    required this.urlHash,
    required this.addedAt,
    this.target,
  });

  factory PhishTankEntry.fromCsvLine(String line) {
    final parts = line.split(',');
    if (parts.length < 3) {
      throw FormatException('Invalid CSV line');
    }

    return PhishTankEntry(
      phishId: int.parse(parts[0]),
      url: parts[1],
      urlHash: parts[2],
      addedAt: parts.length > 3 ? DateTime.parse(parts[3]) : DateTime.now(),
      target: parts.length > 4 ? parts[4] : null,
    );
  }
}

/// PhishTank Service
class PhishTankService {
  final String? _apiKey;
  final http.Client _httpClient;

  static const _baseUrl = 'https://checkurl.phishtank.com/checkurl/';
  static const _databaseUrl = 'http://data.phishtank.com/data/online-valid.json';

  final Map<String, PhishTankCheckResponse> _cache = {};
  final Set<String> _localDatabase = {};

  DateTime? _lastDatabaseUpdate;
  Timer? _updateTimer;

  PhishTankService({
    String? apiKey,
    http.Client? httpClient,
  })  : _apiKey = apiKey,
        _httpClient = httpClient ?? http.Client();

  /// Check a URL against PhishTank
  Future<PhishTankCheckResponse> checkUrl(String url) async {
    // Normalize URL
    final normalizedUrl = _normalizeUrl(url);
    final urlHash = sha256.convert(utf8.encode(normalizedUrl)).toString();

    // Check cache first
    final cached = _cache[urlHash];
    if (cached != null &&
        DateTime.now().difference(cached.checkedAt).inMinutes < 60) {
      return PhishTankCheckResponse(
        url: url,
        result: cached.result,
        details: cached.details,
        checkedAt: cached.checkedAt,
        fromCache: true,
      );
    }

    // Check local database
    if (_localDatabase.contains(urlHash)) {
      final response = PhishTankCheckResponse(
        url: url,
        result: PhishTankResult.phishing,
        checkedAt: DateTime.now(),
      );
      _cache[urlHash] = response;
      return response;
    }

    // Query PhishTank API
    try {
      final response = await _queryApi(normalizedUrl);
      _cache[urlHash] = response;
      return response;
    } catch (e) {
      return PhishTankCheckResponse(
        url: url,
        result: PhishTankResult.error,
        checkedAt: DateTime.now(),
        errorMessage: e.toString(),
      );
    }
  }

  /// Query PhishTank API
  Future<PhishTankCheckResponse> _queryApi(String url) async {
    final body = {
      'url': url,
      'format': 'json',
    };

    if (_apiKey != null) {
      body['app_key'] = _apiKey!;
    }

    final response = await _httpClient.post(
      Uri.parse(_baseUrl),
      body: body,
      headers: {
        'User-Agent': 'OrbGuard/1.0',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final meta = data['meta'] as Map<String, dynamic>? ?? {};
      final results = data['results'] as Map<String, dynamic>? ?? {};

      if (meta['status'] == 'success') {
        final inDatabase = results['in_database'] == true;

        if (inDatabase) {
          final isValid = results['valid'] == true;

          if (isValid) {
            return PhishTankCheckResponse(
              url: url,
              result: PhishTankResult.phishing,
              details: PhishDetails.fromJson(results),
              checkedAt: DateTime.now(),
            );
          } else {
            return PhishTankCheckResponse(
              url: url,
              result: PhishTankResult.notPhishing,
              checkedAt: DateTime.now(),
            );
          }
        } else {
          return PhishTankCheckResponse(
            url: url,
            result: PhishTankResult.unknown,
            checkedAt: DateTime.now(),
          );
        }
      }
    }

    return PhishTankCheckResponse(
      url: url,
      result: PhishTankResult.error,
      checkedAt: DateTime.now(),
      errorMessage: 'API returned status ${response.statusCode}',
    );
  }

  /// Check multiple URLs
  Future<Map<String, PhishTankCheckResponse>> checkUrls(List<String> urls) async {
    final results = <String, PhishTankCheckResponse>{};

    // Check cache and local database first
    final unchecked = <String>[];
    for (final url in urls) {
      final normalizedUrl = _normalizeUrl(url);
      final urlHash = sha256.convert(utf8.encode(normalizedUrl)).toString();

      final cached = _cache[urlHash];
      if (cached != null &&
          DateTime.now().difference(cached.checkedAt).inMinutes < 60) {
        results[url] = PhishTankCheckResponse(
          url: url,
          result: cached.result,
          details: cached.details,
          checkedAt: cached.checkedAt,
          fromCache: true,
        );
      } else if (_localDatabase.contains(urlHash)) {
        results[url] = PhishTankCheckResponse(
          url: url,
          result: PhishTankResult.phishing,
          checkedAt: DateTime.now(),
        );
      } else {
        unchecked.add(url);
      }
    }

    // Query API for uncached URLs (with rate limiting)
    for (final url in unchecked) {
      try {
        results[url] = await checkUrl(url);
        // Rate limit: 1 request per second
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        results[url] = PhishTankCheckResponse(
          url: url,
          result: PhishTankResult.error,
          checkedAt: DateTime.now(),
          errorMessage: e.toString(),
        );
      }
    }

    return results;
  }

  /// Update local database from PhishTank
  Future<void> updateDatabase() async {
    try {
      final response = await _httpClient.get(
        Uri.parse(_databaseUrl),
        headers: {
          'User-Agent': 'OrbGuard/1.0',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;

        _localDatabase.clear();

        for (final entry in data) {
          if (entry is Map<String, dynamic>) {
            final url = entry['url'] as String?;
            if (url != null) {
              final normalizedUrl = _normalizeUrl(url);
              final urlHash = sha256.convert(utf8.encode(normalizedUrl)).toString();
              _localDatabase.add(urlHash);
            }
          }
        }

        _lastDatabaseUpdate = DateTime.now();
        print('PhishTank database updated: ${_localDatabase.length} entries');
      }
    } catch (e) {
      print('Failed to update PhishTank database: $e');
    }
  }

  /// Start periodic database updates
  void startPeriodicUpdates({Duration interval = const Duration(hours: 1)}) {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(interval, (_) => updateDatabase());

    // Initial update
    updateDatabase();
  }

  /// Stop periodic updates
  void stopPeriodicUpdates() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  /// Normalize URL for consistent checking
  String _normalizeUrl(String url) {
    var normalized = url.trim().toLowerCase();

    // Add scheme if missing
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }

    // Remove trailing slash
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }

    // Remove fragment
    final fragmentIndex = normalized.indexOf('#');
    if (fragmentIndex >= 0) {
      normalized = normalized.substring(0, fragmentIndex);
    }

    return normalized;
  }

  /// Submit a phishing URL to PhishTank
  Future<bool> submitPhish(String url, {String? comments}) async {
    // PhishTank submission requires authentication and web interface
    // This is a placeholder for the API integration
    print('PhishTank submission would require web interface: $url');
    return false;
  }

  /// Get database statistics
  Map<String, dynamic> getStats() {
    return {
      'database_entries': _localDatabase.length,
      'cache_entries': _cache.length,
      'last_update': _lastDatabaseUpdate?.toIso8601String(),
      'has_api_key': _apiKey != null,
    };
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
  }

  /// Dispose resources
  void dispose() {
    stopPeriodicUpdates();
    _httpClient.close();
  }
}
