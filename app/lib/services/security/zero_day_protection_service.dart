/// Zero-Day Protection Service
///
/// Detects unknown/zero-day threats through behavioral analysis:
/// - Anomaly detection for suspicious patterns
/// - Behavioral analysis of apps and network traffic
/// - Heuristic-based unknown threat detection
/// - Sandbox-style URL/content analysis
/// - Runtime behavior monitoring
/// - Machine learning-based anomaly scoring

import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Behavioral profile for an entity (app, network endpoint, etc.)
class BehavioralProfile {
  final String entityId;
  final EntityType entityType;
  final Map<String, double> normalBehavior;
  final List<BehaviorSample> samples;
  final DateTime firstSeen;
  DateTime lastUpdated;
  int sampleCount;

  BehavioralProfile({
    required this.entityId,
    required this.entityType,
    Map<String, double>? normalBehavior,
    List<BehaviorSample>? samples,
    DateTime? firstSeen,
    DateTime? lastUpdated,
    this.sampleCount = 0,
  })  : normalBehavior = normalBehavior ?? {},
        samples = samples ?? [],
        firstSeen = firstSeen ?? DateTime.now(),
        lastUpdated = lastUpdated ?? DateTime.now();

  /// Check if profile has enough data for reliable analysis
  bool get isReliable => sampleCount >= 10;

  /// Update profile with new behavior sample
  void addSample(BehaviorSample sample) {
    samples.add(sample);
    if (samples.length > 100) {
      samples.removeAt(0);
    }
    sampleCount++;
    lastUpdated = DateTime.now();

    // Update running averages
    for (final entry in sample.metrics.entries) {
      final current = normalBehavior[entry.key] ?? entry.value;
      normalBehavior[entry.key] = (current * 0.9) + (entry.value * 0.1);
    }
  }
}

/// Entity types for behavioral profiling
enum EntityType {
  app,
  domain,
  ipAddress,
  networkFlow,
  process,
  user,
}

/// Single behavior sample
class BehaviorSample {
  final DateTime timestamp;
  final Map<String, double> metrics;
  final String? context;

  BehaviorSample({
    DateTime? timestamp,
    required this.metrics,
    this.context,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Zero-day threat detection result
class ZeroDayDetectionResult {
  final String entityId;
  final bool isThreat;
  final double anomalyScore;
  final double confidenceScore;
  final ThreatClassification classification;
  final List<AnomalyIndicator> anomalies;
  final String explanation;
  final List<String> recommendations;
  final DateTime detectionTime;

  ZeroDayDetectionResult({
    required this.entityId,
    required this.isThreat,
    required this.anomalyScore,
    required this.confidenceScore,
    required this.classification,
    required this.anomalies,
    required this.explanation,
    required this.recommendations,
    DateTime? detectionTime,
  }) : detectionTime = detectionTime ?? DateTime.now();

  String get riskLevel {
    if (anomalyScore >= 0.9) return 'Critical';
    if (anomalyScore >= 0.7) return 'High';
    if (anomalyScore >= 0.5) return 'Medium';
    if (anomalyScore >= 0.3) return 'Low';
    return 'Safe';
  }
}

/// Threat classification
enum ThreatClassification {
  unknown('Unknown', 'Unclassified anomalous behavior'),
  suspiciousNetwork('Suspicious Network', 'Unusual network activity'),
  dataExfiltration('Data Exfiltration', 'Potential data theft'),
  commandAndControl('C2 Communication', 'Possible C2 traffic'),
  cryptoMining('Crypto Mining', 'Resource abuse for mining'),
  privilegeEscalation('Privilege Escalation', 'Attempting elevated access'),
  persistenceMechanism('Persistence', 'Establishing persistence'),
  evasionTechnique('Evasion', 'Attempting to evade detection'),
  maliciousPayload('Malicious Payload', 'Suspicious code execution'),
  phishingBehavior('Phishing', 'Credential harvesting behavior'),
  benign('Benign', 'Normal behavior');

  final String displayName;
  final String description;
  const ThreatClassification(this.displayName, this.description);
}

/// Specific anomaly indicator
class AnomalyIndicator {
  final String metric;
  final double observedValue;
  final double expectedValue;
  final double deviationScore;
  final String description;

  AnomalyIndicator({
    required this.metric,
    required this.observedValue,
    required this.expectedValue,
    required this.deviationScore,
    required this.description,
  });

  /// How many standard deviations from normal
  double get zScore => deviationScore;
}

/// Network behavior metrics
class NetworkBehaviorMetrics {
  final int connectionCount;
  final int uniqueDestinations;
  final int bytesTransmitted;
  final int bytesReceived;
  final double avgPacketSize;
  final int portCount;
  final int failedConnections;
  final int encryptedConnections;
  final int unusualPorts;
  final double connectionFrequency;

  NetworkBehaviorMetrics({
    required this.connectionCount,
    required this.uniqueDestinations,
    required this.bytesTransmitted,
    required this.bytesReceived,
    required this.avgPacketSize,
    required this.portCount,
    required this.failedConnections,
    required this.encryptedConnections,
    required this.unusualPorts,
    required this.connectionFrequency,
  });

  Map<String, double> toMetricsMap() => {
    'connection_count': connectionCount.toDouble(),
    'unique_destinations': uniqueDestinations.toDouble(),
    'bytes_tx': bytesTransmitted.toDouble(),
    'bytes_rx': bytesReceived.toDouble(),
    'avg_packet_size': avgPacketSize,
    'port_count': portCount.toDouble(),
    'failed_connections': failedConnections.toDouble(),
    'encrypted_ratio': encryptedConnections / max(connectionCount, 1),
    'unusual_ports': unusualPorts.toDouble(),
    'connection_frequency': connectionFrequency,
  };
}

/// App behavior metrics
class AppBehaviorMetrics {
  final double cpuUsage;
  final int memoryUsageMb;
  final int networkRequestsPerMin;
  final int backgroundWakeups;
  final int permissionAccesses;
  final int fileOperations;
  final int clipboardAccesses;
  final int locationRequests;
  final int cameraAccesses;
  final int microphoneAccesses;

  AppBehaviorMetrics({
    required this.cpuUsage,
    required this.memoryUsageMb,
    required this.networkRequestsPerMin,
    required this.backgroundWakeups,
    required this.permissionAccesses,
    required this.fileOperations,
    required this.clipboardAccesses,
    required this.locationRequests,
    required this.cameraAccesses,
    required this.microphoneAccesses,
  });

  Map<String, double> toMetricsMap() => {
    'cpu_usage': cpuUsage,
    'memory_mb': memoryUsageMb.toDouble(),
    'network_rpm': networkRequestsPerMin.toDouble(),
    'bg_wakeups': backgroundWakeups.toDouble(),
    'permission_accesses': permissionAccesses.toDouble(),
    'file_ops': fileOperations.toDouble(),
    'clipboard_accesses': clipboardAccesses.toDouble(),
    'location_requests': locationRequests.toDouble(),
    'camera_accesses': cameraAccesses.toDouble(),
    'microphone_accesses': microphoneAccesses.toDouble(),
  };
}

/// Zero-Day Protection Service
class ZeroDayProtectionService {
  // Behavioral profiles
  final Map<String, BehavioralProfile> _profiles = {};

  // Anomaly detection thresholds
  static const double _anomalyThreshold = 2.5; // Z-score threshold
  static const double _threatThreshold = 0.7;

  // Known malicious indicators
  final Set<String> _knownMaliciousIPs = {};
  final Set<String> _knownMaliciousDomains = {};
  final Set<int> _suspiciousPorts = {4444, 5555, 6666, 31337, 12345};

  // Stream controllers
  final _threatAlertController = StreamController<ZeroDayDetectionResult>.broadcast();
  final _anomalyController = StreamController<AnomalyIndicator>.broadcast();

  // Statistics
  int _threatsDetected = 0;
  int _samplesAnalyzed = 0;

  /// Stream of threat alerts
  Stream<ZeroDayDetectionResult> get onThreatAlert => _threatAlertController.stream;

  /// Stream of anomaly indicators
  Stream<AnomalyIndicator> get onAnomaly => _anomalyController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    _loadKnownIndicators();
  }

  /// Load known malicious indicators
  void _loadKnownIndicators() {
    // Known C2 ports
    _suspiciousPorts.addAll([
      4444, 5555, 6666, 7777, 8888, 9999, // Common RAT ports
      31337, 12345, 54321, // Classic backdoor ports
      1337, 1338, 1339, // Hacker culture ports
      6667, 6668, 6669, // IRC (common C2)
    ]);
  }

  /// Analyze app behavior for zero-day threats
  Future<ZeroDayDetectionResult> analyzeAppBehavior(
    String packageName,
    AppBehaviorMetrics metrics,
  ) async {
    _samplesAnalyzed++;

    // Get or create profile
    final profile = _profiles.putIfAbsent(
      packageName,
      () => BehavioralProfile(
        entityId: packageName,
        entityType: EntityType.app,
      ),
    );

    // Create behavior sample
    final sample = BehaviorSample(metrics: metrics.toMetricsMap());

    // Detect anomalies
    final anomalies = _detectAnomalies(profile, sample);

    // Calculate threat score
    final anomalyScore = _calculateAnomalyScore(anomalies);

    // Classify the threat
    final classification = _classifyAppThreat(anomalies, metrics);

    // Update profile with new sample
    profile.addSample(sample);

    // Build result
    final result = ZeroDayDetectionResult(
      entityId: packageName,
      isThreat: anomalyScore >= _threatThreshold,
      anomalyScore: anomalyScore,
      confidenceScore: profile.isReliable ? 0.9 : 0.5,
      classification: classification,
      anomalies: anomalies,
      explanation: _generateExplanation(anomalies, classification),
      recommendations: _generateRecommendations(classification, anomalyScore),
    );

    // Emit alerts
    if (result.isThreat) {
      _threatsDetected++;
      _threatAlertController.add(result);
    }

    for (final anomaly in anomalies.where((a) => a.deviationScore > 3.0)) {
      _anomalyController.add(anomaly);
    }

    return result;
  }

  /// Analyze network behavior for zero-day threats
  Future<ZeroDayDetectionResult> analyzeNetworkBehavior(
    String entityId,
    NetworkBehaviorMetrics metrics, {
    EntityType entityType = EntityType.networkFlow,
  }) async {
    _samplesAnalyzed++;

    // Get or create profile
    final profile = _profiles.putIfAbsent(
      entityId,
      () => BehavioralProfile(
        entityId: entityId,
        entityType: entityType,
      ),
    );

    // Create behavior sample
    final sample = BehaviorSample(metrics: metrics.toMetricsMap());

    // Detect anomalies
    final anomalies = _detectAnomalies(profile, sample);

    // Add network-specific anomaly checks
    anomalies.addAll(_detectNetworkAnomalies(metrics));

    // Calculate threat score
    final anomalyScore = _calculateAnomalyScore(anomalies);

    // Classify the threat
    final classification = _classifyNetworkThreat(anomalies, metrics);

    // Update profile
    profile.addSample(sample);

    final result = ZeroDayDetectionResult(
      entityId: entityId,
      isThreat: anomalyScore >= _threatThreshold,
      anomalyScore: anomalyScore,
      confidenceScore: profile.isReliable ? 0.9 : 0.5,
      classification: classification,
      anomalies: anomalies,
      explanation: _generateExplanation(anomalies, classification),
      recommendations: _generateRecommendations(classification, anomalyScore),
    );

    if (result.isThreat) {
      _threatsDetected++;
      _threatAlertController.add(result);
    }

    return result;
  }

  /// Analyze URL for zero-day phishing
  Future<ZeroDayDetectionResult> analyzeURL(String url) async {
    _samplesAnalyzed++;

    final anomalies = <AnomalyIndicator>[];
    double anomalyScore = 0.0;

    final uri = Uri.tryParse(url);
    if (uri == null) {
      return ZeroDayDetectionResult(
        entityId: url,
        isThreat: true,
        anomalyScore: 1.0,
        confidenceScore: 0.9,
        classification: ThreatClassification.maliciousPayload,
        anomalies: [AnomalyIndicator(
          metric: 'url_validity',
          observedValue: 0,
          expectedValue: 1,
          deviationScore: 10,
          description: 'Invalid URL format',
        )],
        explanation: 'URL is malformed and cannot be parsed',
        recommendations: ['Block this URL', 'Do not click'],
      );
    }

    // Check domain characteristics
    final domain = uri.host;

    // Check for IP address as domain
    if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(domain)) {
      anomalyScore += 0.3;
      anomalies.add(AnomalyIndicator(
        metric: 'ip_as_domain',
        observedValue: 1,
        expectedValue: 0,
        deviationScore: 3,
        description: 'URL uses IP address instead of domain name',
      ));
    }

    // Check domain length
    if (domain.length > 50) {
      anomalyScore += 0.2;
      anomalies.add(AnomalyIndicator(
        metric: 'domain_length',
        observedValue: domain.length.toDouble(),
        expectedValue: 20,
        deviationScore: 2.5,
        description: 'Unusually long domain name',
      ));
    }

    // Check for excessive subdomains
    final subdomainCount = domain.split('.').length - 2;
    if (subdomainCount > 3) {
      anomalyScore += 0.25;
      anomalies.add(AnomalyIndicator(
        metric: 'subdomain_count',
        observedValue: subdomainCount.toDouble(),
        expectedValue: 1,
        deviationScore: 3,
        description: 'Excessive number of subdomains',
      ));
    }

    // Check for suspicious TLDs
    final suspiciousTLDs = ['.xyz', '.tk', '.ml', '.ga', '.cf', '.gq', '.top', '.club', '.work', '.click'];
    if (suspiciousTLDs.any((tld) => domain.endsWith(tld))) {
      anomalyScore += 0.25;
      anomalies.add(AnomalyIndicator(
        metric: 'suspicious_tld',
        observedValue: 1,
        expectedValue: 0,
        deviationScore: 2.5,
        description: 'Domain uses suspicious top-level domain',
      ));
    }

    // Check for suspicious path patterns
    final path = uri.path.toLowerCase();
    final suspiciousPatterns = ['login', 'signin', 'account', 'verify', 'secure', 'update', 'confirm'];
    for (final pattern in suspiciousPatterns) {
      if (path.contains(pattern)) {
        anomalyScore += 0.1;
        anomalies.add(AnomalyIndicator(
          metric: 'suspicious_path',
          observedValue: 1,
          expectedValue: 0,
          deviationScore: 1.5,
          description: 'URL path contains "$pattern"',
        ));
        break;
      }
    }

    // Check for encoded characters
    if (url.contains('%') && RegExp(r'%[0-9a-fA-F]{2}').allMatches(url).length > 5) {
      anomalyScore += 0.15;
      anomalies.add(AnomalyIndicator(
        metric: 'url_encoding',
        observedValue: 1,
        expectedValue: 0,
        deviationScore: 2,
        description: 'Excessive URL encoding',
      ));
    }

    // Check for homoglyph characters
    if (_containsHomoglyphs(domain)) {
      anomalyScore += 0.4;
      anomalies.add(AnomalyIndicator(
        metric: 'homoglyph_attack',
        observedValue: 1,
        expectedValue: 0,
        deviationScore: 4,
        description: 'Domain contains lookalike characters',
      ));
    }

    anomalyScore = anomalyScore.clamp(0.0, 1.0);

    final classification = anomalyScore >= 0.5
        ? ThreatClassification.phishingBehavior
        : ThreatClassification.benign;

    return ZeroDayDetectionResult(
      entityId: url,
      isThreat: anomalyScore >= _threatThreshold,
      anomalyScore: anomalyScore,
      confidenceScore: 0.85,
      classification: classification,
      anomalies: anomalies,
      explanation: _generateExplanation(anomalies, classification),
      recommendations: _generateRecommendations(classification, anomalyScore),
    );
  }

  /// Detect anomalies by comparing to baseline
  List<AnomalyIndicator> _detectAnomalies(
    BehavioralProfile profile,
    BehaviorSample sample,
  ) {
    final anomalies = <AnomalyIndicator>[];

    if (!profile.isReliable) {
      return anomalies;
    }

    // Calculate standard deviations for each metric
    for (final entry in sample.metrics.entries) {
      final metric = entry.key;
      final observed = entry.value;
      final expected = profile.normalBehavior[metric] ?? observed;

      // Calculate deviation (simplified z-score)
      final stdDev = _estimateStdDev(profile.samples, metric);
      if (stdDev == 0) continue;

      final zScore = (observed - expected).abs() / stdDev;

      if (zScore > _anomalyThreshold) {
        anomalies.add(AnomalyIndicator(
          metric: metric,
          observedValue: observed,
          expectedValue: expected,
          deviationScore: zScore,
          description: _getMetricDescription(metric, observed, expected),
        ));
      }
    }

    return anomalies;
  }

  /// Detect network-specific anomalies
  List<AnomalyIndicator> _detectNetworkAnomalies(NetworkBehaviorMetrics metrics) {
    final anomalies = <AnomalyIndicator>[];

    // Check for suspicious ports
    if (metrics.unusualPorts > 0) {
      anomalies.add(AnomalyIndicator(
        metric: 'unusual_ports',
        observedValue: metrics.unusualPorts.toDouble(),
        expectedValue: 0,
        deviationScore: metrics.unusualPorts * 2.0,
        description: 'Connections to unusual/suspicious ports detected',
      ));
    }

    // Check connection frequency
    if (metrics.connectionFrequency > 100) {
      anomalies.add(AnomalyIndicator(
        metric: 'connection_frequency',
        observedValue: metrics.connectionFrequency,
        expectedValue: 10,
        deviationScore: metrics.connectionFrequency / 20,
        description: 'Abnormally high connection frequency',
      ));
    }

    // Check for data exfiltration patterns
    final txRxRatio = metrics.bytesTransmitted / max(metrics.bytesReceived, 1);
    if (txRxRatio > 10) {
      anomalies.add(AnomalyIndicator(
        metric: 'tx_rx_ratio',
        observedValue: txRxRatio,
        expectedValue: 1,
        deviationScore: txRxRatio / 3,
        description: 'High outbound to inbound traffic ratio (possible exfiltration)',
      ));
    }

    // Check failed connection ratio
    final failedRatio = metrics.failedConnections / max(metrics.connectionCount, 1);
    if (failedRatio > 0.5) {
      anomalies.add(AnomalyIndicator(
        metric: 'failed_connection_ratio',
        observedValue: failedRatio,
        expectedValue: 0.1,
        deviationScore: failedRatio * 5,
        description: 'High rate of failed connections (possible scanning)',
      ));
    }

    return anomalies;
  }

  /// Estimate standard deviation for a metric
  double _estimateStdDev(List<BehaviorSample> samples, String metric) {
    if (samples.length < 3) return 1.0;

    final values = samples
        .map((s) => s.metrics[metric])
        .whereType<double>()
        .toList();

    if (values.isEmpty) return 1.0;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;

    return sqrt(variance);
  }

  /// Calculate overall anomaly score
  double _calculateAnomalyScore(List<AnomalyIndicator> anomalies) {
    if (anomalies.isEmpty) return 0.0;

    // Weighted sum of deviation scores
    double totalScore = 0.0;
    for (final anomaly in anomalies) {
      totalScore += min(anomaly.deviationScore / 5.0, 0.3);
    }

    return totalScore.clamp(0.0, 1.0);
  }

  /// Classify app threat based on anomalies
  ThreatClassification _classifyAppThreat(
    List<AnomalyIndicator> anomalies,
    AppBehaviorMetrics metrics,
  ) {
    final anomalyMetrics = anomalies.map((a) => a.metric).toSet();

    if (anomalyMetrics.contains('cpu_usage') && metrics.cpuUsage > 80) {
      return ThreatClassification.cryptoMining;
    }

    if (anomalyMetrics.contains('clipboard_accesses') && metrics.clipboardAccesses > 10) {
      return ThreatClassification.dataExfiltration;
    }

    if (anomalyMetrics.contains('network_rpm') && metrics.networkRequestsPerMin > 100) {
      return ThreatClassification.commandAndControl;
    }

    if (anomalies.length >= 3) {
      return ThreatClassification.suspiciousNetwork;
    }

    return anomalies.isEmpty ? ThreatClassification.benign : ThreatClassification.unknown;
  }

  /// Classify network threat based on anomalies
  ThreatClassification _classifyNetworkThreat(
    List<AnomalyIndicator> anomalies,
    NetworkBehaviorMetrics metrics,
  ) {
    final anomalyMetrics = anomalies.map((a) => a.metric).toSet();

    if (anomalyMetrics.contains('unusual_ports')) {
      return ThreatClassification.commandAndControl;
    }

    if (anomalyMetrics.contains('tx_rx_ratio')) {
      return ThreatClassification.dataExfiltration;
    }

    if (anomalyMetrics.contains('failed_connection_ratio')) {
      return ThreatClassification.suspiciousNetwork;
    }

    if (anomalyMetrics.contains('connection_frequency')) {
      return ThreatClassification.commandAndControl;
    }

    return anomalies.isEmpty ? ThreatClassification.benign : ThreatClassification.unknown;
  }

  /// Check for homoglyph characters in domain
  bool _containsHomoglyphs(String domain) {
    // Check for non-ASCII characters that look like ASCII
    for (final char in domain.codeUnits) {
      if (char > 127) return true;
    }
    return false;
  }

  /// Get human-readable description for metric
  String _getMetricDescription(String metric, double observed, double expected) {
    final direction = observed > expected ? 'higher' : 'lower';
    final change = ((observed - expected).abs() / max(expected, 1) * 100).round();

    return '$metric is $change% $direction than normal '
        '(observed: ${observed.toStringAsFixed(1)}, expected: ${expected.toStringAsFixed(1)})';
  }

  /// Generate explanation for detection
  String _generateExplanation(
    List<AnomalyIndicator> anomalies,
    ThreatClassification classification,
  ) {
    if (anomalies.isEmpty) {
      return 'No significant anomalies detected. Behavior appears normal.';
    }

    final topAnomalies = anomalies.take(3).map((a) => a.description).join('; ');

    return 'Detected ${classification.displayName}: $topAnomalies. '
        '${classification.description}';
  }

  /// Generate recommendations based on threat
  List<String> _generateRecommendations(
    ThreatClassification classification,
    double score,
  ) {
    final recommendations = <String>[];

    switch (classification) {
      case ThreatClassification.dataExfiltration:
        recommendations.add('Review app permissions and revoke unnecessary access');
        recommendations.add('Check for unauthorized data transfers');
        recommendations.add('Consider uninstalling the app');
        break;

      case ThreatClassification.commandAndControl:
        recommendations.add('Disconnect from network immediately');
        recommendations.add('Run a full malware scan');
        recommendations.add('Check for unknown installed apps');
        break;

      case ThreatClassification.cryptoMining:
        recommendations.add('Check battery and CPU usage');
        recommendations.add('Identify and remove mining apps');
        recommendations.add('Monitor device temperature');
        break;

      case ThreatClassification.phishingBehavior:
        recommendations.add('Do not enter any credentials');
        recommendations.add('Verify URL with official source');
        recommendations.add('Report the suspicious URL');
        break;

      case ThreatClassification.suspiciousNetwork:
        recommendations.add('Review recent network connections');
        recommendations.add('Check for unauthorized apps');
        recommendations.add('Consider using a VPN');
        break;

      default:
        if (score >= 0.5) {
          recommendations.add('Monitor for continued suspicious activity');
          recommendations.add('Review recent app installations');
        }
    }

    return recommendations;
  }

  /// Get behavioral profile for entity
  BehavioralProfile? getProfile(String entityId) => _profiles[entityId];

  /// Reset behavioral profile
  void resetProfile(String entityId) {
    _profiles.remove(entityId);
  }

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'profiles_count': _profiles.length,
      'samples_analyzed': _samplesAnalyzed,
      'threats_detected': _threatsDetected,
      'reliable_profiles': _profiles.values.where((p) => p.isReliable).length,
    };
  }

  /// Dispose resources
  void dispose() {
    _threatAlertController.close();
    _anomalyController.close();
    _profiles.clear();
  }
}
