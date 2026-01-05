/// URL Classifier
/// On-device ML classifier for URL threat detection
library url_classifier;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// URL classification result
class UrlClassificationResult {
  final String label;
  final double confidence;
  final Map<String, double> probabilities;
  final List<String> indicators;
  final Duration latency;
  final bool usedFallback;

  UrlClassificationResult({
    required this.label,
    required this.confidence,
    required this.probabilities,
    this.indicators = const [],
    required this.latency,
    this.usedFallback = false,
  });

  bool get isMalicious => label == 'malicious' && confidence > 0.7;
  bool get isPhishing => label == 'phishing' && confidence > 0.7;
  bool get isSuspicious =>
      label == 'suspicious' ||
      ((label == 'malicious' || label == 'phishing') && confidence < 0.7);
  bool get isSafe => label == 'safe';

  double get maliciousProbability => probabilities['malicious'] ?? 0.0;
  double get phishingProbability => probabilities['phishing'] ?? 0.0;
  double get suspiciousProbability => probabilities['suspicious'] ?? 0.0;
  double get safeProbability => probabilities['safe'] ?? 1.0;
}

/// URL Classifier - Threat detection using on-device ML
class UrlClassifier {
  static const String _modelPath = 'assets/models/url_threat.tflite';

  // Model state
  bool _isModelLoaded = false;
  String _modelVersion = '1.0.0-heuristic';

  // Statistics
  int _classificationCount = 0;
  int _totalLatencyMs = 0;

  // Cache
  final Map<String, UrlClassificationResult> _cache = {};

  // Suspicious TLDs
  static const List<String> _suspiciousTlds = [
    '.tk', '.ml', '.ga', '.cf', '.gq', '.top', '.xyz', '.work',
    '.click', '.link', '.info', '.biz', '.online', '.site', '.live',
  ];

  // Trusted TLDs (reduce score)
  static const List<String> _trustedTlds = [
    '.gov', '.edu', '.mil', '.org',
  ];

  // Brand impersonation patterns
  static const List<String> _impersonationPatterns = [
    'paypa1', 'paypai', 'pay-pal', 'amaz0n', 'amazom', 'amazon-',
    'faceb00k', 'g00gle', 'googie', 'micros0ft', 'appie', 'app1e',
    'netf1ix', 'netfllx', 'bankofamerica', 'wellsfarg0', 'chasebank',
  ];

  // Suspicious URL patterns
  static const List<String> _suspiciousPatterns = [
    'login', 'signin', 'account', 'verify', 'update', 'confirm',
    'secure', 'security', 'password', 'credential', 'banking',
  ];

  // Getters
  bool get isModelLoaded => _isModelLoaded;
  String get modelVersion => _modelVersion;
  int get classificationCount => _classificationCount;
  Duration get averageLatency => _classificationCount > 0
      ? Duration(milliseconds: _totalLatencyMs ~/ _classificationCount)
      : Duration.zero;

  /// Load the TensorFlow Lite model
  Future<void> loadModel() async {
    try {
      // TODO: Load actual TFLite model when available
      _isModelLoaded = true;
      _modelVersion = '1.0.0-heuristic';
      debugPrint('UrlClassifier: Using heuristic fallback');
    } catch (e) {
      debugPrint('UrlClassifier: Failed to load model: $e');
      _isModelLoaded = false;
    }
  }

  /// Classify a URL
  Future<UrlClassificationResult> classify(String url) async {
    final stopwatch = Stopwatch()..start();

    // Check cache
    final cacheKey = url.hashCode.toString();
    if (_cache.containsKey(cacheKey)) {
      stopwatch.stop();
      return _cache[cacheKey]!;
    }

    try {
      final result = _classifyHeuristic(url);
      stopwatch.stop();

      final finalResult = UrlClassificationResult(
        label: result['label'] as String,
        confidence: result['confidence'] as double,
        probabilities: result['probabilities'] as Map<String, double>,
        indicators: result['indicators'] as List<String>,
        latency: stopwatch.elapsed,
        usedFallback: true,
      );

      // Update stats
      _classificationCount++;
      _totalLatencyMs += stopwatch.elapsedMilliseconds;

      // Cache result
      _cache[cacheKey] = finalResult;

      return finalResult;
    } catch (e) {
      stopwatch.stop();
      debugPrint('UrlClassifier: Error classifying: $e');
      return UrlClassificationResult(
        label: 'safe',
        confidence: 0.5,
        probabilities: {
          'safe': 0.5,
          'suspicious': 0.2,
          'phishing': 0.15,
          'malicious': 0.15
        },
        latency: stopwatch.elapsed,
        usedFallback: true,
      );
    }
  }

  /// Heuristic-based classification
  Map<String, dynamic> _classifyHeuristic(String url) {
    final lowerUrl = url.toLowerCase();
    final indicators = <String>[];
    double threatScore = 0.0;
    bool isPhishingLikely = false;

    // Parse URL
    Uri? uri;
    try {
      uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    } catch (e) {
      indicators.add('Invalid URL format');
      threatScore += 0.3;
    }

    if (uri != null) {
      final host = uri.host.toLowerCase();
      final path = uri.path.toLowerCase();

      // Check for IP address
      if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host)) {
        indicators.add('IP address instead of domain');
        threatScore += 0.4;
      }

      // Check TLD
      for (final tld in _suspiciousTlds) {
        if (host.endsWith(tld)) {
          indicators.add('Suspicious TLD: $tld');
          threatScore += 0.15;
          break;
        }
      }

      for (final tld in _trustedTlds) {
        if (host.endsWith(tld)) {
          threatScore -= 0.2;
          break;
        }
      }

      // Check for brand impersonation
      for (final pattern in _impersonationPatterns) {
        if (host.contains(pattern)) {
          indicators.add('Possible brand impersonation: $pattern');
          threatScore += 0.5;
          isPhishingLikely = true;
          break;
        }
      }

      // Check for excessive subdomains
      final subdomainCount = host.split('.').length - 2;
      if (subdomainCount > 2) {
        indicators.add('Excessive subdomains ($subdomainCount)');
        threatScore += 0.1 * (subdomainCount - 2);
      }

      // Check for suspicious keywords in path
      int suspiciousCount = 0;
      for (final pattern in _suspiciousPatterns) {
        if (path.contains(pattern) || host.contains(pattern)) {
          suspiciousCount++;
        }
      }
      if (suspiciousCount > 0) {
        indicators.add('Suspicious keywords ($suspiciousCount matches)');
        threatScore += 0.1 * suspiciousCount.clamp(1, 3);
        if (suspiciousCount >= 2) isPhishingLikely = true;
      }

      // Check for long random strings
      if (RegExp(r'[a-zA-Z0-9]{20,}').hasMatch(host)) {
        indicators.add('Long random string in domain');
        threatScore += 0.2;
      }

      // Check for non-standard ports
      if (uri.hasPort && uri.port != 80 && uri.port != 443) {
        indicators.add('Non-standard port: ${uri.port}');
        threatScore += 0.15;
      }

      // Check for URL shorteners
      final shorteners = ['bit.ly', 'tinyurl', 't.co', 'goo.gl', 'ow.ly', 'is.gd'];
      for (final shortener in shorteners) {
        if (host.contains(shortener)) {
          indicators.add('URL shortener detected');
          threatScore += 0.1;
          break;
        }
      }

      // Check HTTPS
      if (uri.scheme != 'https') {
        indicators.add('Not using HTTPS');
        threatScore += 0.1;
      }

      // Check for homograph attacks (mixed scripts)
      if (RegExp(r'[^\x00-\x7F]').hasMatch(host)) {
        indicators.add('Non-ASCII characters in domain');
        threatScore += 0.3;
      }

      // Check for excessive hyphens
      final hyphenCount = '-'.allMatches(host).length;
      if (hyphenCount > 2) {
        indicators.add('Excessive hyphens in domain');
        threatScore += 0.1;
      }
    }

    // Normalize score
    threatScore = threatScore.clamp(0.0, 1.0);

    // Determine label
    String label;
    double confidence;
    Map<String, double> probabilities;

    if (threatScore > 0.6) {
      label = isPhishingLikely ? 'phishing' : 'malicious';
      confidence = threatScore;
      probabilities = {
        'malicious': isPhishingLikely ? threatScore * 0.3 : threatScore * 0.7,
        'phishing': isPhishingLikely ? threatScore * 0.7 : threatScore * 0.3,
        'suspicious': (1 - threatScore) * 0.5,
        'safe': (1 - threatScore) * 0.5,
      };
    } else if (threatScore > 0.3) {
      label = 'suspicious';
      confidence = 0.5 + threatScore * 0.3;
      probabilities = {
        'malicious': threatScore * 0.3,
        'phishing': threatScore * 0.3,
        'suspicious': 0.5,
        'safe': 1 - threatScore - 0.3,
      };
    } else {
      label = 'safe';
      confidence = 1 - threatScore;
      probabilities = {
        'malicious': threatScore * 0.25,
        'phishing': threatScore * 0.25,
        'suspicious': threatScore * 0.5,
        'safe': 1 - threatScore,
      };
    }

    return {
      'label': label,
      'confidence': confidence,
      'probabilities': probabilities,
      'indicators': indicators,
    };
  }

  /// Clear the cache
  void clearCache() {
    _cache.clear();
  }

  /// Dispose resources
  void dispose() {
    _cache.clear();
    _isModelLoaded = false;
  }
}
