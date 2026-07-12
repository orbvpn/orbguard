/// Breach Monitoring Service
///
/// Integrates multiple breach databases:
/// - Have I Been Pwned (HIBP)
/// - LeakCheck
/// - Intelligence X (IntelX)
///
/// Provides comprehensive breach monitoring for emails, passwords, and domains.

import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// Breach source
enum BreachSource {
  hibp('Have I Been Pwned'),
  leakCheck('LeakCheck'),
  intelX('Intelligence X');

  final String displayName;
  const BreachSource(this.displayName);
}

/// Breach data class type
enum DataClassType {
  email('Email'),
  password('Password'),
  passwordHash('Password Hash'),
  username('Username'),
  name('Name'),
  phone('Phone'),
  address('Address'),
  ip('IP Address'),
  dateOfBirth('Date of Birth'),
  creditCard('Credit Card'),
  ssn('SSN'),
  other('Other');

  final String displayName;
  const DataClassType(this.displayName);
}

/// Individual breach record
class BreachRecord {
  final String id;
  final String name;
  final String? domain;
  final DateTime? breachDate;
  final DateTime? addedDate;
  final int? pwnCount;
  final List<String> dataClasses;
  final String? description;
  final bool isVerified;
  final bool isSensitive;
  final bool isSpamList;
  final BreachSource source;

  BreachRecord({
    required this.id,
    required this.name,
    this.domain,
    this.breachDate,
    this.addedDate,
    this.pwnCount,
    this.dataClasses = const [],
    this.description,
    this.isVerified = false,
    this.isSensitive = false,
    this.isSpamList = false,
    required this.source,
  });

  factory BreachRecord.fromHIBP(Map<String, dynamic> json) {
    return BreachRecord(
      id: json['Name'] as String,
      name: json['Title'] as String? ?? json['Name'] as String,
      domain: json['Domain'] as String?,
      breachDate: json['BreachDate'] != null
          ? DateTime.tryParse(json['BreachDate'] as String)
          : null,
      addedDate: json['AddedDate'] != null
          ? DateTime.tryParse(json['AddedDate'] as String)
          : null,
      pwnCount: json['PwnCount'] as int?,
      dataClasses: (json['DataClasses'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      description: json['Description'] as String?,
      isVerified: json['IsVerified'] as bool? ?? false,
      isSensitive: json['IsSensitive'] as bool? ?? false,
      isSpamList: json['IsSpamList'] as bool? ?? false,
      source: BreachSource.hibp,
    );
  }

  factory BreachRecord.fromLeakCheck(Map<String, dynamic> json) {
    return BreachRecord(
      id: json['name'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Unknown Breach',
      domain: json['domain'] as String?,
      breachDate: json['date'] != null
          ? DateTime.tryParse(json['date'].toString())
          : null,
      dataClasses: (json['fields'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      source: BreachSource.leakCheck,
    );
  }

  factory BreachRecord.fromIntelX(Map<String, dynamic> json) {
    return BreachRecord(
      id: json['systemid'] as String? ?? json['storageid'] as String? ?? 'unknown',
      name: json['name'] as String? ?? 'Intelligence X Record',
      domain: json['bucket'] as String?,
      addedDate: json['date'] != null
          ? DateTime.tryParse(json['date'] as String)
          : null,
      description: json['description'] as String?,
      source: BreachSource.intelX,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'domain': domain,
        'breach_date': breachDate?.toIso8601String(),
        'added_date': addedDate?.toIso8601String(),
        'pwn_count': pwnCount,
        'data_classes': dataClasses,
        'description': description,
        'is_verified': isVerified,
        'is_sensitive': isSensitive,
        'is_spam_list': isSpamList,
        'source': source.name,
      };
}

/// Password check result
class PasswordCheckResult {
  final bool isCompromised;
  final int occurrences;
  final BreachSource source;
  final DateTime checkedAt;

  PasswordCheckResult({
    required this.isCompromised,
    required this.occurrences,
    required this.source,
    required this.checkedAt,
  });

  String get severityText {
    if (!isCompromised) return 'Safe';
    if (occurrences > 1000000) return 'Extremely Compromised';
    if (occurrences > 100000) return 'Highly Compromised';
    if (occurrences > 10000) return 'Compromised';
    if (occurrences > 1000) return 'Moderately Exposed';
    return 'Exposed';
  }
}

/// Breach check result
class BreachCheckResult {
  final String query;
  final bool isBreached;
  final List<BreachRecord> breaches;
  final DateTime checkedAt;
  final Map<BreachSource, int> sourceBreachCounts;
  final int totalExposures;

  BreachCheckResult({
    required this.query,
    required this.isBreached,
    required this.breaches,
    required this.checkedAt,
    required this.sourceBreachCounts,
    required this.totalExposures,
  });
}

/// Breach Monitoring Service
class BreachMonitoringService {
  // API Keys
  static const String _hibpApiKey = '153d2cd2165c4841b7f7bcea1e89f702';
  static const String _leakCheckApiKey = '0a81d813291df7d42c881f3495fb28cd1fa3becd';
  static const String _intelXApiKey = '312e04bf-8fb0-4f09-b36e-34c8dc0c7a5a';

  // API Endpoints
  static const String _hibpBaseUrl = 'https://haveibeenpwned.com/api/v3';
  static const String _hibpPasswordUrl = 'https://api.pwnedpasswords.com/range';
  static const String _leakCheckUrl = 'https://leakcheck.io/api/public';
  static const String _intelXUrl = 'https://2.intelx.io';

  final http.Client _client;
  final Map<String, BreachCheckResult> _cache = {};
  final Duration _cacheDuration = const Duration(hours: 1);

  BreachMonitoringService({http.Client? client}) : _client = client ?? http.Client();

  /// Check email across all breach databases
  Future<BreachCheckResult> checkEmail(String email) async {
    final cacheKey = 'email:${email.toLowerCase()}';

    // Check cache
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey]!;
      if (DateTime.now().difference(cached.checkedAt) < _cacheDuration) {
        return cached;
      }
    }

    final allBreaches = <BreachRecord>[];
    final sourceCounts = <BreachSource, int>{};

    // Check HIBP
    try {
      final hibpBreaches = await _checkHIBP(email);
      allBreaches.addAll(hibpBreaches);
      sourceCounts[BreachSource.hibp] = hibpBreaches.length;
    } catch (e) {
      print('HIBP check failed: $e');
      sourceCounts[BreachSource.hibp] = 0;
    }

    // Check LeakCheck
    try {
      final leakCheckBreaches = await _checkLeakCheck(email);
      allBreaches.addAll(leakCheckBreaches);
      sourceCounts[BreachSource.leakCheck] = leakCheckBreaches.length;
    } catch (e) {
      print('LeakCheck check failed: $e');
      sourceCounts[BreachSource.leakCheck] = 0;
    }

    // Check IntelX
    try {
      final intelXBreaches = await _checkIntelX(email);
      allBreaches.addAll(intelXBreaches);
      sourceCounts[BreachSource.intelX] = intelXBreaches.length;
    } catch (e) {
      print('IntelX check failed: $e');
      sourceCounts[BreachSource.intelX] = 0;
    }

    final result = BreachCheckResult(
      query: email,
      isBreached: allBreaches.isNotEmpty,
      breaches: allBreaches,
      checkedAt: DateTime.now(),
      sourceBreachCounts: sourceCounts,
      totalExposures: allBreaches.length,
    );

    _cache[cacheKey] = result;
    return result;
  }

  /// Check password using k-anonymity (HIBP)
  Future<PasswordCheckResult> checkPassword(String password) async {
    try {
      // Hash the password with SHA-1
      final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
      final prefix = hash.substring(0, 5);
      final suffix = hash.substring(5);

      // Query HIBP with the prefix (k-anonymity)
      final response = await _client.get(
        Uri.parse('$_hibpPasswordUrl/$prefix'),
        headers: {
          'User-Agent': 'OrbGuard-Security-App',
        },
      );

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        for (final line in lines) {
          final parts = line.trim().split(':');
          if (parts.length == 2 && parts[0].toUpperCase() == suffix) {
            final count = int.tryParse(parts[1]) ?? 0;
            return PasswordCheckResult(
              isCompromised: true,
              occurrences: count,
              source: BreachSource.hibp,
              checkedAt: DateTime.now(),
            );
          }
        }
      }

      return PasswordCheckResult(
        isCompromised: false,
        occurrences: 0,
        source: BreachSource.hibp,
        checkedAt: DateTime.now(),
      );
    } catch (e) {
      print('Password check failed: $e');
      rethrow;
    }
  }

  /// Check domain for breaches (HIBP)
  Future<List<BreachRecord>> checkDomain(String domain) async {
    try {
      final response = await _client.get(
        Uri.parse('$_hibpBaseUrl/breaches?domain=$domain'),
        headers: {
          'hibp-api-key': _hibpApiKey,
          'User-Agent': 'OrbGuard-Security-App',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((b) => BreachRecord.fromHIBP(b)).toList();
      } else if (response.statusCode == 404) {
        return [];
      }

      throw Exception('Domain check failed: ${response.statusCode}');
    } catch (e) {
      print('Domain check failed: $e');
      rethrow;
    }
  }

  /// Get all known breaches (HIBP)
  Future<List<BreachRecord>> getAllBreaches() async {
    try {
      final response = await _client.get(
        Uri.parse('$_hibpBaseUrl/breaches'),
        headers: {
          'User-Agent': 'OrbGuard-Security-App',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((b) => BreachRecord.fromHIBP(b)).toList();
      }

      throw Exception('Failed to fetch breaches: ${response.statusCode}');
    } catch (e) {
      print('Failed to get all breaches: $e');
      rethrow;
    }
  }

  /// Check email with HIBP
  Future<List<BreachRecord>> _checkHIBP(String email) async {
    final response = await _client.get(
      Uri.parse('$_hibpBaseUrl/breachedaccount/${Uri.encodeComponent(email)}?truncateResponse=false'),
      headers: {
        'hibp-api-key': _hibpApiKey,
        'User-Agent': 'OrbGuard-Security-App',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((b) => BreachRecord.fromHIBP(b)).toList();
    } else if (response.statusCode == 404) {
      // No breaches found
      return [];
    } else if (response.statusCode == 401) {
      throw Exception('HIBP API key invalid');
    } else if (response.statusCode == 429) {
      throw Exception('HIBP rate limit exceeded');
    }

    throw Exception('HIBP check failed: ${response.statusCode}');
  }

  /// Check email with LeakCheck
  Future<List<BreachRecord>> _checkLeakCheck(String email) async {
    final response = await _client.get(
      Uri.parse('$_leakCheckUrl?check=${Uri.encodeComponent(email)}'),
      headers: {
        'X-API-Key': _leakCheckApiKey,
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['success'] == true && data['found'] > 0) {
        final List<dynamic> sources = data['sources'] ?? [];
        return sources.map((s) => BreachRecord.fromLeakCheck(s)).toList();
      }
      return [];
    } else if (response.statusCode == 404) {
      return [];
    } else if (response.statusCode == 401) {
      throw Exception('LeakCheck API key invalid');
    }

    throw Exception('LeakCheck check failed: ${response.statusCode}');
  }

  /// Check email with IntelX
  Future<List<BreachRecord>> _checkIntelX(String email) async {
    // First, create a search
    final searchResponse = await _client.post(
      Uri.parse('$_intelXUrl/intelligent/search'),
      headers: {
        'x-key': _intelXApiKey,
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'term': email,
        'buckets': [],
        'lookuplevel': 0,
        'maxresults': 100,
        'timeout': 5,
        'datefrom': '',
        'dateto': '',
        'sort': 4,
        'media': 0,
        'terminate': [],
      }),
    );

    if (searchResponse.statusCode != 200) {
      if (searchResponse.statusCode == 401) {
        throw Exception('IntelX API key invalid');
      }
      throw Exception('IntelX search failed: ${searchResponse.statusCode}');
    }

    final searchData = json.decode(searchResponse.body);
    final searchId = searchData['id'];

    if (searchId == null) {
      return [];
    }

    // Wait a bit for results
    await Future.delayed(const Duration(seconds: 2));

    // Get results
    final resultResponse = await _client.get(
      Uri.parse('$_intelXUrl/intelligent/search/result?id=$searchId'),
      headers: {
        'x-key': _intelXApiKey,
      },
    );

    if (resultResponse.statusCode == 200) {
      final resultData = json.decode(resultResponse.body);
      final List<dynamic> records = resultData['records'] ?? [];
      return records.map((r) => BreachRecord.fromIntelX(r)).toList();
    }

    return [];
  }

  /// Get breach statistics
  Future<BreachStats> getStats() async {
    try {
      final breaches = await getAllBreaches();

      int totalAccounts = 0;
      int totalBreaches = breaches.length;
      final dataClassCounts = <String, int>{};
      final yearlyBreaches = <int, int>{};

      for (final breach in breaches) {
        totalAccounts += breach.pwnCount ?? 0;

        for (final dc in breach.dataClasses) {
          dataClassCounts[dc] = (dataClassCounts[dc] ?? 0) + 1;
        }

        if (breach.breachDate != null) {
          final year = breach.breachDate!.year;
          yearlyBreaches[year] = (yearlyBreaches[year] ?? 0) + 1;
        }
      }

      return BreachStats(
        totalBreaches: totalBreaches,
        totalAccounts: totalAccounts,
        dataClassCounts: dataClassCounts,
        yearlyBreaches: yearlyBreaches,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      print('Failed to get stats: $e');
      rethrow;
    }
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
  }

  /// Dispose resources
  void dispose() {
    _client.close();
  }
}

/// Breach statistics
class BreachStats {
  final int totalBreaches;
  final int totalAccounts;
  final Map<String, int> dataClassCounts;
  final Map<int, int> yearlyBreaches;
  final DateTime lastUpdated;

  BreachStats({
    required this.totalBreaches,
    required this.totalAccounts,
    required this.dataClassCounts,
    required this.yearlyBreaches,
    required this.lastUpdated,
  });

  String get formattedTotalAccounts {
    if (totalAccounts >= 1000000000) {
      return '${(totalAccounts / 1000000000).toStringAsFixed(1)}B';
    } else if (totalAccounts >= 1000000) {
      return '${(totalAccounts / 1000000).toStringAsFixed(1)}M';
    } else if (totalAccounts >= 1000) {
      return '${(totalAccounts / 1000).toStringAsFixed(1)}K';
    }
    return totalAccounts.toString();
  }

  List<MapEntry<String, int>> get topDataClasses {
    final sorted = dataClassCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(10).toList();
  }
}
