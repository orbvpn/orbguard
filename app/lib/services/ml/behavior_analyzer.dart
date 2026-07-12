/// Behavior Analyzer
/// On-device ML analyzer for behavioral anomaly detection
library behavior_analyzer;

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Behavior features for analysis
class BehaviorFeatures {
  final int cpuUsage;
  final int memoryUsage;
  final int networkBytesSent;
  final int networkBytesReceived;
  final int batteryDrain;
  final int wakeLockCount;
  final int backgroundActivityCount;
  final int permissionRequestCount;
  final int sensorAccessCount;
  final int locationAccessCount;
  final int cameraAccessCount;
  final int microphoneAccessCount;
  final int contactAccessCount;
  final int storageAccessCount;
  final Duration sessionDuration;

  BehaviorFeatures({
    this.cpuUsage = 0,
    this.memoryUsage = 0,
    this.networkBytesSent = 0,
    this.networkBytesReceived = 0,
    this.batteryDrain = 0,
    this.wakeLockCount = 0,
    this.backgroundActivityCount = 0,
    this.permissionRequestCount = 0,
    this.sensorAccessCount = 0,
    this.locationAccessCount = 0,
    this.cameraAccessCount = 0,
    this.microphoneAccessCount = 0,
    this.contactAccessCount = 0,
    this.storageAccessCount = 0,
    this.sessionDuration = Duration.zero,
  });

  /// Convert to feature vector for ML model
  List<double> toVector() {
    return [
      cpuUsage / 100.0,
      memoryUsage / 100.0,
      math.log(1 + networkBytesSent.toDouble()) / 20.0,
      math.log(1 + networkBytesReceived.toDouble()) / 20.0,
      batteryDrain / 100.0,
      wakeLockCount / 10.0,
      backgroundActivityCount / 50.0,
      permissionRequestCount / 20.0,
      sensorAccessCount / 100.0,
      locationAccessCount / 50.0,
      cameraAccessCount / 20.0,
      microphoneAccessCount / 20.0,
      contactAccessCount / 10.0,
      storageAccessCount / 100.0,
      sessionDuration.inMinutes / 60.0,
    ].map((v) => v.clamp(0.0, 1.0)).toList();
  }
}

/// Behavior analysis result
class BehaviorAnalysisResult {
  final String label;
  final double anomalyScore;
  final List<String> anomalies;
  final Map<String, double> featureScores;
  final Duration latency;
  final bool usedFallback;

  BehaviorAnalysisResult({
    required this.label,
    required this.anomalyScore,
    this.anomalies = const [],
    this.featureScores = const {},
    required this.latency,
    this.usedFallback = false,
  });

  bool get isAnomaly => label == 'anomaly' && anomalyScore > 0.7;
  bool get isSuspicious => anomalyScore > 0.4 && anomalyScore <= 0.7;
  bool get isNormal => label == 'normal' && anomalyScore <= 0.4;
}

/// Behavior Analyzer - Anomaly detection using on-device ML
class BehaviorAnalyzer {
  static const String _modelPath = 'assets/models/behavior_anomaly.tflite';

  // Model state
  bool _isModelLoaded = false;
  String _modelVersion = '1.0.0-heuristic';

  // Statistics
  int _analysisCount = 0;
  int _totalLatencyMs = 0;

  // Baseline stats (learned from normal behavior)
  final Map<String, _BaselineStats> _baselines = {};

  // Thresholds for anomaly detection
  static const _thresholds = {
    'cpuUsage': 80.0, // %
    'memoryUsage': 85.0, // %
    'batteryDrain': 20.0, // % per hour
    'wakeLockCount': 5.0,
    'backgroundActivityCount': 30.0,
    'locationAccessCount': 20.0,
    'cameraAccessCount': 10.0,
    'microphoneAccessCount': 10.0,
    'contactAccessCount': 5.0,
  };

  // Getters
  bool get isModelLoaded => _isModelLoaded;
  String get modelVersion => _modelVersion;
  int get analysisCount => _analysisCount;
  Duration get averageLatency => _analysisCount > 0
      ? Duration(milliseconds: _totalLatencyMs ~/ _analysisCount)
      : Duration.zero;

  /// Load the TensorFlow Lite model
  Future<void> loadModel() async {
    try {
      // TODO: Load actual TFLite model when available
      _isModelLoaded = true;
      _modelVersion = '1.0.0-heuristic';
      debugPrint('BehaviorAnalyzer: Using heuristic fallback');
    } catch (e) {
      debugPrint('BehaviorAnalyzer: Failed to load model: $e');
      _isModelLoaded = false;
    }
  }

  /// Analyze behavior features
  Future<BehaviorAnalysisResult> analyze(BehaviorFeatures features) async {
    final stopwatch = Stopwatch()..start();

    try {
      final result = _analyzeHeuristic(features);
      stopwatch.stop();

      final finalResult = BehaviorAnalysisResult(
        label: result['label'] as String,
        anomalyScore: result['anomalyScore'] as double,
        anomalies: result['anomalies'] as List<String>,
        featureScores: result['featureScores'] as Map<String, double>,
        latency: stopwatch.elapsed,
        usedFallback: true,
      );

      // Update stats
      _analysisCount++;
      _totalLatencyMs += stopwatch.elapsedMilliseconds;

      // Update baselines
      _updateBaselines(features);

      return finalResult;
    } catch (e) {
      stopwatch.stop();
      debugPrint('BehaviorAnalyzer: Error analyzing: $e');
      return BehaviorAnalysisResult(
        label: 'normal',
        anomalyScore: 0.0,
        latency: stopwatch.elapsed,
        usedFallback: true,
      );
    }
  }

  /// Heuristic-based analysis
  Map<String, dynamic> _analyzeHeuristic(BehaviorFeatures features) {
    final anomalies = <String>[];
    final featureScores = <String, double>{};
    double totalScore = 0.0;
    int featureCount = 0;

    // Check CPU usage
    if (features.cpuUsage > _thresholds['cpuUsage']!) {
      final score = (features.cpuUsage - _thresholds['cpuUsage']!) / 20.0;
      anomalies.add('High CPU usage: ${features.cpuUsage}%');
      featureScores['cpuUsage'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['cpuUsage']!;
      featureCount++;
    }

    // Check memory usage
    if (features.memoryUsage > _thresholds['memoryUsage']!) {
      final score = (features.memoryUsage - _thresholds['memoryUsage']!) / 15.0;
      anomalies.add('High memory usage: ${features.memoryUsage}%');
      featureScores['memoryUsage'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['memoryUsage']!;
      featureCount++;
    }

    // Check battery drain
    if (features.batteryDrain > _thresholds['batteryDrain']!) {
      final score = (features.batteryDrain - _thresholds['batteryDrain']!) / 30.0;
      anomalies.add('Excessive battery drain: ${features.batteryDrain}%/hr');
      featureScores['batteryDrain'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['batteryDrain']!;
      featureCount++;
    }

    // Check wake locks
    if (features.wakeLockCount > _thresholds['wakeLockCount']!) {
      final score = (features.wakeLockCount - _thresholds['wakeLockCount']!) / 10.0;
      anomalies.add('Excessive wake locks: ${features.wakeLockCount}');
      featureScores['wakeLockCount'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['wakeLockCount']!;
      featureCount++;
    }

    // Check background activity
    if (features.backgroundActivityCount > _thresholds['backgroundActivityCount']!) {
      final score =
          (features.backgroundActivityCount - _thresholds['backgroundActivityCount']!) / 20.0;
      anomalies.add('High background activity: ${features.backgroundActivityCount}');
      featureScores['backgroundActivity'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['backgroundActivity']!;
      featureCount++;
    }

    // Check location access
    if (features.locationAccessCount > _thresholds['locationAccessCount']!) {
      final score =
          (features.locationAccessCount - _thresholds['locationAccessCount']!) / 30.0;
      anomalies.add('Frequent location access: ${features.locationAccessCount}');
      featureScores['locationAccess'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['locationAccess']!;
      featureCount++;
    }

    // Check camera access
    if (features.cameraAccessCount > _thresholds['cameraAccessCount']!) {
      final score = (features.cameraAccessCount - _thresholds['cameraAccessCount']!) / 10.0;
      anomalies.add('Suspicious camera access: ${features.cameraAccessCount}');
      featureScores['cameraAccess'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['cameraAccess']!;
      featureCount++;
    }

    // Check microphone access
    if (features.microphoneAccessCount > _thresholds['microphoneAccessCount']!) {
      final score =
          (features.microphoneAccessCount - _thresholds['microphoneAccessCount']!) / 10.0;
      anomalies.add('Suspicious microphone access: ${features.microphoneAccessCount}');
      featureScores['microphoneAccess'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['microphoneAccess']!;
      featureCount++;
    }

    // Check contact access
    if (features.contactAccessCount > _thresholds['contactAccessCount']!) {
      final score = (features.contactAccessCount - _thresholds['contactAccessCount']!) / 5.0;
      anomalies.add('Unusual contact access: ${features.contactAccessCount}');
      featureScores['contactAccess'] = score.clamp(0.0, 1.0);
      totalScore += featureScores['contactAccess']!;
      featureCount++;
    }

    // Check for data exfiltration patterns
    if (features.networkBytesSent > 10 * 1024 * 1024) {
      // 10MB sent
      final received = math.max(1, features.networkBytesReceived);
      final ratio = features.networkBytesSent / received;
      if (ratio > 2.0) {
        anomalies.add('Potential data exfiltration: high upload ratio');
        featureScores['dataExfiltration'] = (ratio / 5.0).clamp(0.0, 1.0);
        totalScore += featureScores['dataExfiltration']!;
        featureCount++;
      }
    }

    // Calculate anomaly score
    double anomalyScore = featureCount > 0 ? totalScore / featureCount : 0.0;

    // Boost score if multiple anomalies detected
    if (anomalies.length >= 3) {
      anomalyScore = (anomalyScore * 1.2).clamp(0.0, 1.0);
    }

    // Determine label
    String label;
    if (anomalyScore > 0.6) {
      label = 'anomaly';
    } else if (anomalyScore > 0.3) {
      label = 'suspicious';
    } else {
      label = 'normal';
    }

    return {
      'label': label,
      'anomalyScore': anomalyScore,
      'anomalies': anomalies,
      'featureScores': featureScores,
    };
  }

  /// Update baseline statistics
  void _updateBaselines(BehaviorFeatures features) {
    _updateBaseline('cpuUsage', features.cpuUsage.toDouble());
    _updateBaseline('memoryUsage', features.memoryUsage.toDouble());
    _updateBaseline('networkSent', features.networkBytesSent.toDouble());
    _updateBaseline('networkReceived', features.networkBytesReceived.toDouble());
  }

  void _updateBaseline(String feature, double value) {
    if (!_baselines.containsKey(feature)) {
      _baselines[feature] = _BaselineStats();
    }
    _baselines[feature]!.update(value);
  }

  /// Clear caches and baselines
  void clearCache() {
    _baselines.clear();
  }

  /// Dispose resources
  void dispose() {
    _baselines.clear();
    _isModelLoaded = false;
  }
}

/// Baseline statistics for anomaly detection
class _BaselineStats {
  double _sum = 0.0;
  double _sumSq = 0.0;
  int _count = 0;

  double get mean => _count > 0 ? _sum / _count : 0.0;

  double get variance {
    if (_count < 2) return 0.0;
    return (_sumSq / _count) - (mean * mean);
  }

  double get stdDev => math.sqrt(variance);

  void update(double value) {
    _sum += value;
    _sumSq += value * value;
    _count++;

    // Keep a rolling window
    if (_count > 100) {
      _sum *= 0.99;
      _sumSq *= 0.99;
      _count = 99;
    }
  }

  double zScore(double value) {
    if (stdDev == 0) return 0.0;
    return (value - mean) / stdDev;
  }
}
