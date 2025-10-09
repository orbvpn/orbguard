// lib/detection/enhanced_behavioral_detector.dart
// Enhanced behavioral analysis using Usage Stats permission

import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';

class EnhancedBehavioralDetector {
  static const platform = MethodChannel('com.orb.guard/system');

  // Baseline thresholds for anomaly detection
  static const double ANOMALY_THRESHOLD = 2.0; // Standard deviations
  static const int MIN_BASELINE_SAMPLES = 20;

  // Baseline data
  final Map<String, BaselineMetrics> _appBaselines = {};
  final Map<String, List<double>> _historicalData = {};
  bool _baselineEstablished = false;

  /// Establish baseline from historical usage data
  Future<void> establishBaseline() async {
    print('[Behavioral] Establishing baseline from historical data...');

    try {
      // Get usage data for last 7 days
      final usageStats = await _getUsageStats(hours: 24 * 7);

      if (usageStats.isEmpty) {
        print(
            '[Behavioral] No usage data available. Ensure Usage Stats permission is granted.');
        return;
      }

      // Process historical data
      for (final stat in usageStats) {
        final packageName = stat['packageName'] as String;
        final foregroundTime = stat['totalTimeInForeground'] as int;

        if (!_historicalData.containsKey(packageName)) {
          _historicalData[packageName] = [];
        }

        // Convert to hours
        final hours = foregroundTime / (1000 * 60 * 60);
        _historicalData[packageName]!.add(hours);
      }

      // Calculate baselines
      for (final entry in _historicalData.entries) {
        if (entry.value.length >= MIN_BASELINE_SAMPLES) {
          _appBaselines[entry.key] = _calculateBaseline(entry.value);
        }
      }

      _baselineEstablished = true;
      print(
          '[Behavioral] Baseline established for ${_appBaselines.length} apps');
    } catch (e) {
      print('[Behavioral] Error establishing baseline: $e');
    }
  }

  BaselineMetrics _calculateBaseline(List<double> values) {
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    final stdDev = sqrt(variance);

    return BaselineMetrics(
      mean: mean,
      stdDev: stdDev,
      min: values.reduce((a, b) => a < b ? a : b),
      max: values.reduce((a, b) => a > b ? a : b),
      sampleCount: values.length,
    );
  }

  /// Detect behavioral anomalies in current app usage
  Future<List<Map<String, dynamic>>> detectBehavioralAnomalies() async {
    final threats = <Map<String, dynamic>>[];

    if (!_baselineEstablished) {
      print(
          '[Behavioral] Baseline not established. Run establishBaseline() first.');
      return threats;
    }

    try {
      // Get current usage (last 24 hours)
      final currentUsage = await _getUsageStats(hours: 24);

      for (final stat in currentUsage) {
        final packageName = stat['packageName'] as String;
        final appName = stat['appName'] as String;
        final foregroundTime = stat['totalTimeInForeground'] as int;

        // Skip if no baseline for this app
        if (!_appBaselines.containsKey(packageName)) continue;

        final baseline = _appBaselines[packageName]!;
        final currentHours = foregroundTime / (1000 * 60 * 60);

        // Check for anomaly
        final deviation =
            (currentHours - baseline.mean).abs() / baseline.stdDev;

        if (deviation > ANOMALY_THRESHOLD) {
          final percentChange =
              ((currentHours - baseline.mean) / baseline.mean * 100).round();

          String severity;
          if (deviation > 4.0) {
            severity = 'CRITICAL';
          } else if (deviation > 3.0) {
            severity = 'HIGH';
          } else {
            severity = 'MEDIUM';
          }

          threats.add({
            'id':
                'behavior_${packageName}_${DateTime.now().millisecondsSinceEpoch}',
            'name': 'Behavioral Anomaly: $appName',
            'description':
                'App usage is ${percentChange > 0 ? "$percentChange%" : "${percentChange.abs()}%"} ${percentChange > 0 ? "above" : "below"} normal',
            'severity': severity,
            'type': 'behavioral',
            'path': packageName,
            'requiresRoot': false,
            'metadata': {
              'packageName': packageName,
              'currentUsage': currentHours.toStringAsFixed(2),
              'normalUsage': baseline.mean.toStringAsFixed(2),
              'deviation': deviation.toStringAsFixed(2),
              'percentChange': '$percentChange%',
              'stdDeviations': deviation.toStringAsFixed(1),
            },
          });
        }
      }

      // Detect apps running excessively in background
      threats.addAll(await _detectBackgroundAbuse());

      // Detect unusual network usage patterns
      threats.addAll(await _detectNetworkAnomalies());
    } catch (e) {
      print('[Behavioral] Error detecting anomalies: $e');
    }

    return threats;
  }

  /// Detect apps with excessive background activity
  Future<List<Map<String, dynamic>>> _detectBackgroundAbuse() async {
    final threats = <Map<String, dynamic>>[];

    try {
      final usageStats = await _getUsageStats(hours: 24);

      for (final stat in usageStats) {
        final packageName = stat['packageName'] as String;
        final appName = stat['appName'] as String;
        final foregroundTime = stat['totalTimeInForeground'] as int;
        final lastUsed = stat['lastTimeUsed'] as int;

        // Calculate how long ago the app was used
        final hoursSinceLastUse =
            (DateTime.now().millisecondsSinceEpoch - lastUsed) /
                (1000 * 60 * 60);

        // If app has significant foreground time but wasn't recently used,
        // it might be running in background
        if (foregroundTime > 1000 * 60 * 60 && hoursSinceLastUse > 6) {
          threats.add({
            'id': 'bg_abuse_$packageName',
            'name': 'Suspicious Background Activity: $appName',
            'description':
                'App showing activity without recent user interaction',
            'severity': 'HIGH',
            'type': 'background_abuse',
            'path': packageName,
            'requiresRoot': false,
            'metadata': {
              'packageName': packageName,
              'hoursSinceLastUse': hoursSinceLastUse.toStringAsFixed(1),
              'totalTimeInForeground':
                  (foregroundTime / (1000 * 60 * 60)).toStringAsFixed(2),
            },
          });
        }
      }
    } catch (e) {
      print('[Behavioral] Error detecting background abuse: $e');
    }

    return threats;
  }

  /// Detect unusual network usage patterns
  Future<List<Map<String, dynamic>>> _detectNetworkAnomalies() async {
    final threats = <Map<String, dynamic>>[];

    try {
      final networkStats = await _getNetworkUsageStats(hours: 24);

      for (final stat in networkStats) {
        final type = stat['type'] as String;
        final rxBytes = stat['rxBytes'] as int;
        final txBytes = stat['txBytes'] as int;

        final totalMB = (rxBytes + txBytes) / (1024 * 1024);

        // Flag if more than 1GB transferred in 24 hours
        // (Potential data exfiltration)
        if (totalMB > 1024) {
          threats.add({
            'id': 'network_high_$type',
            'name': 'High Network Usage Detected',
            'description':
                '${totalMB.toStringAsFixed(0)} MB transferred over $type in 24h',
            'severity': 'MEDIUM',
            'type': 'network_anomaly',
            'path': type,
            'requiresRoot': false,
            'metadata': {
              'networkType': type,
              'totalMB': totalMB.toStringAsFixed(2),
              'rxMB': (rxBytes / (1024 * 1024)).toStringAsFixed(2),
              'txMB': (txBytes / (1024 * 1024)).toStringAsFixed(2),
            },
          });
        }
      }
    } catch (e) {
      print('[Behavioral] Error detecting network anomalies: $e');
    }

    return threats;
  }

  /// Get usage statistics
  Future<List<Map<String, dynamic>>> _getUsageStats({int hours = 24}) async {
    try {
      final result = await platform.invokeMethod('getUsageStats', {
        'hours': hours,
      });

      final stats = result['stats'] as List<dynamic>?;
      if (stats == null) return [];

      return stats.map((s) => Map<String, dynamic>.from(s)).toList();
    } catch (e) {
      print('[Behavioral] Error getting usage stats: $e');
      return [];
    }
  }

  /// Get network usage statistics
  Future<List<Map<String, dynamic>>> _getNetworkUsageStats(
      {int hours = 24}) async {
    try {
      final result = await platform.invokeMethod('getNetworkUsageStats', {
        'hours': hours,
      });

      final stats = result['stats'] as List<dynamic>?;
      if (stats == null) return [];

      return stats.map((s) => Map<String, dynamic>.from(s)).toList();
    } catch (e) {
      print('[Behavioral] Error getting network stats: $e');
      return [];
    }
  }

  /// Generate behavioral analysis report
  Future<Map<String, dynamic>> generateBehavioralReport() async {
    final report = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'baselineEstablished': _baselineEstablished,
      'trackedApps': _appBaselines.length,
      'anomalies': <Map<String, dynamic>>[],
      'summary': <String, dynamic>{},
    };

    if (_baselineEstablished) {
      final anomalies = await detectBehavioralAnomalies();
      report['anomalies'] = anomalies;

      report['summary'] = {
        'totalAnomalies': anomalies.length,
        'critical': anomalies.where((a) => a['severity'] == 'CRITICAL').length,
        'high': anomalies.where((a) => a['severity'] == 'HIGH').length,
        'medium': anomalies.where((a) => a['severity'] == 'MEDIUM').length,
      };
    }

    return report;
  }
}

class BaselineMetrics {
  final double mean;
  final double stdDev;
  final double min;
  final double max;
  final int sampleCount;

  BaselineMetrics({
    required this.mean,
    required this.stdDev,
    required this.min,
    required this.max,
    required this.sampleCount,
  });

  double get lowerBound => mean - (2 * stdDev);
  double get upperBound => mean + (2 * stdDev);

  bool isAnomaly(double value) {
    return value < lowerBound || value > upperBound;
  }
}

// Usage Example:
/*
final detector = EnhancedBehavioralDetector();

// First, establish baseline (do this once or periodically)
await detector.establishBaseline();

// Then detect anomalies
final threats = await detector.detectBehavioralAnomalies();

// Or generate full report
final report = await detector.generateBehavioralReport();
*/
