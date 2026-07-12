/// SMS Classifier
/// On-device ML classifier for SMS phishing detection
library sms_classifier;

import 'dart:async';
import 'package:flutter/foundation.dart';

/// SMS classification result
class SmsClassificationResult {
  final String label;
  final double confidence;
  final Map<String, double> probabilities;
  final List<String> indicators;
  final Duration latency;
  final bool usedFallback;

  SmsClassificationResult({
    required this.label,
    required this.confidence,
    required this.probabilities,
    this.indicators = const [],
    required this.latency,
    this.usedFallback = false,
  });

  bool get isPhishing => label == 'phishing' && confidence > 0.7;
  bool get isSuspicious => label == 'suspicious' || (label == 'phishing' && confidence < 0.7);
  bool get isSafe => label == 'safe';

  double get phishingProbability => probabilities['phishing'] ?? 0.0;
  double get suspiciousProbability => probabilities['suspicious'] ?? 0.0;
  double get safeProbability => probabilities['safe'] ?? 1.0;
}

/// SMS Classifier - Phishing detection using on-device ML
class SmsClassifier {
  static const String _modelPath = 'assets/models/sms_phishing.tflite';
  static const String _vocabPath = 'assets/models/sms_vocab.txt';

  // Model state
  bool _isModelLoaded = false;
  String _modelVersion = '1.0.0-heuristic';

  // Statistics
  int _classificationCount = 0;
  int _totalLatencyMs = 0;

  // Cache
  final Map<String, SmsClassificationResult> _cache = {};

  // Phishing indicators (heuristic fallback)
  static const List<String> _urgencyWords = [
    'urgent', 'immediately', 'now', 'hurry', 'quick', 'fast',
    'limited time', 'expires', 'act now', 'don\'t wait',
  ];

  static const List<String> _financialWords = [
    'bank', 'account', 'credit', 'debit', 'payment', 'transfer',
    'verify', 'confirm', 'suspend', 'blocked', 'unauthorized',
    'refund', 'tax', 'irs', 'social security', 'ssn',
  ];

  static const List<String> _rewardWords = [
    'winner', 'won', 'prize', 'congratulations', 'selected',
    'lucky', 'reward', 'gift', 'free', 'claim',
  ];

  static const List<String> _threatWords = [
    'suspended', 'blocked', 'disabled', 'cancelled', 'terminated',
    'legal action', 'arrest', 'warrant', 'police', 'fraud',
  ];

  static const List<String> _actionWords = [
    'click', 'tap', 'call', 'reply', 'text', 'send',
    'verify', 'confirm', 'update', 'login', 'sign in',
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
      // For now, use heuristic-based classification
      _isModelLoaded = true;
      _modelVersion = '1.0.0-heuristic';
      debugPrint('SmsClassifier: Using heuristic fallback');
    } catch (e) {
      debugPrint('SmsClassifier: Failed to load model: $e');
      _isModelLoaded = false;
    }
  }

  /// Classify an SMS message
  Future<SmsClassificationResult> classify(String content, {String? sender}) async {
    final stopwatch = Stopwatch()..start();

    // Check cache
    final cacheKey = '${sender ?? ''}_${content.hashCode}';
    if (_cache.containsKey(cacheKey)) {
      stopwatch.stop();
      return _cache[cacheKey]!;
    }

    try {
      final result = _classifyHeuristic(content, sender);
      stopwatch.stop();

      final finalResult = SmsClassificationResult(
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
      debugPrint('SmsClassifier: Error classifying: $e');
      return SmsClassificationResult(
        label: 'safe',
        confidence: 0.5,
        probabilities: {'safe': 0.5, 'suspicious': 0.25, 'phishing': 0.25},
        latency: stopwatch.elapsed,
        usedFallback: true,
      );
    }
  }

  /// Heuristic-based classification
  Map<String, dynamic> _classifyHeuristic(String content, String? sender) {
    final lowerContent = content.toLowerCase();
    final indicators = <String>[];
    double phishingScore = 0.0;

    // Check for URLs
    final urlPattern = RegExp(r'https?://[^\s]+|www\.[^\s]+|[^\s]+\.[a-z]{2,}[^\s]*');
    final hasUrl = urlPattern.hasMatch(content);
    if (hasUrl) {
      indicators.add('Contains URL');
      phishingScore += 0.15;

      // Check for suspicious URL patterns
      if (content.contains('bit.ly') ||
          content.contains('tinyurl') ||
          content.contains('t.co') ||
          RegExp(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}').hasMatch(content)) {
        indicators.add('Suspicious URL shortener or IP');
        phishingScore += 0.2;
      }
    }

    // Check for urgency
    int urgencyCount = 0;
    for (final word in _urgencyWords) {
      if (lowerContent.contains(word)) {
        urgencyCount++;
      }
    }
    if (urgencyCount > 0) {
      indicators.add('Urgency language ($urgencyCount matches)');
      phishingScore += 0.1 * urgencyCount.clamp(1, 3);
    }

    // Check for financial terms
    int financialCount = 0;
    for (final word in _financialWords) {
      if (lowerContent.contains(word)) {
        financialCount++;
      }
    }
    if (financialCount > 0) {
      indicators.add('Financial terms ($financialCount matches)');
      phishingScore += 0.1 * financialCount.clamp(1, 3);
    }

    // Check for reward/prize language
    int rewardCount = 0;
    for (final word in _rewardWords) {
      if (lowerContent.contains(word)) {
        rewardCount++;
      }
    }
    if (rewardCount > 0) {
      indicators.add('Reward/prize language ($rewardCount matches)');
      phishingScore += 0.15 * rewardCount.clamp(1, 2);
    }

    // Check for threats
    int threatCount = 0;
    for (final word in _threatWords) {
      if (lowerContent.contains(word)) {
        threatCount++;
      }
    }
    if (threatCount > 0) {
      indicators.add('Threatening language ($threatCount matches)');
      phishingScore += 0.15 * threatCount.clamp(1, 2);
    }

    // Check for action requests
    int actionCount = 0;
    for (final word in _actionWords) {
      if (lowerContent.contains(word)) {
        actionCount++;
      }
    }
    if (actionCount > 0 && hasUrl) {
      indicators.add('Call-to-action with link');
      phishingScore += 0.1;
    }

    // Check sender patterns
    if (sender != null) {
      // Alphanumeric sender (common in legitimate but also spam)
      if (RegExp(r'^[A-Z][a-zA-Z]+$').hasMatch(sender)) {
        indicators.add('Alphanumeric sender');
        phishingScore += 0.05;
      }
      // Short code
      if (RegExp(r'^\d{4,6}$').hasMatch(sender)) {
        // Short codes can be legitimate
        phishingScore -= 0.05;
      }
    }

    // Check for excessive punctuation
    final exclamations = '!'.allMatches(content).length;
    if (exclamations > 2) {
      indicators.add('Excessive punctuation');
      phishingScore += 0.05;
    }

    // Check for ALL CAPS
    final capsRatio = content.replaceAll(RegExp(r'[^A-Z]'), '').length /
        content.replaceAll(RegExp(r'[^a-zA-Z]'), '').length.clamp(1, 1000);
    if (capsRatio > 0.5) {
      indicators.add('Excessive capitalization');
      phishingScore += 0.1;
    }

    // Normalize score
    phishingScore = phishingScore.clamp(0.0, 1.0);

    // Determine label
    String label;
    double confidence;
    Map<String, double> probabilities;

    if (phishingScore > 0.6) {
      label = 'phishing';
      confidence = phishingScore;
      probabilities = {
        'phishing': phishingScore,
        'suspicious': (1 - phishingScore) * 0.7,
        'safe': (1 - phishingScore) * 0.3,
      };
    } else if (phishingScore > 0.3) {
      label = 'suspicious';
      confidence = 0.5 + phishingScore * 0.3;
      probabilities = {
        'phishing': phishingScore * 0.8,
        'suspicious': 0.5,
        'safe': 1 - phishingScore - 0.3,
      };
    } else {
      label = 'safe';
      confidence = 1 - phishingScore;
      probabilities = {
        'phishing': phishingScore * 0.5,
        'suspicious': phishingScore * 0.5,
        'safe': 1 - phishingScore,
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
