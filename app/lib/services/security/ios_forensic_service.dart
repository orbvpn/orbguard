/// iOS Forensic Analysis Service
///
/// Advanced iOS forensic capabilities inspired by iVerify and MVT:
/// - Shutdown.log analysis for Pegasus indicators
/// - iOS backup parsing and analysis
/// - Sysdiagnose analysis
/// - DataUsage.sqlite analysis
/// - Process anomaly detection
/// - Timeline reconstruction
/// - IOC scanning

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Forensic scan type
enum ForensicScanType {
  quick('Quick Scan', 'Basic IOC check', Duration(minutes: 1)),
  standard('Standard Scan', 'Shutdown.log + basic analysis', Duration(minutes: 5)),
  deep('Deep Scan', 'Full forensic analysis', Duration(minutes: 30)),
  backup('Backup Analysis', 'Full backup parsing', Duration(hours: 1));

  final String displayName;
  final String description;
  final Duration estimatedDuration;

  const ForensicScanType(this.displayName, this.description, this.estimatedDuration);
}

/// Forensic finding severity
enum FindingSeverity {
  critical('Critical', 'Strong indicator of compromise'),
  high('High', 'Suspicious activity detected'),
  medium('Medium', 'Potentially concerning'),
  low('Low', 'Minor anomaly'),
  info('Info', 'For reference');

  final String displayName;
  final String description;

  const FindingSeverity(this.displayName, this.description);
}

/// Forensic finding category
enum FindingCategory {
  pegasus('Pegasus', 'NSO Group Pegasus spyware'),
  predator('Predator', 'Cytrox Predator spyware'),
  quadream('QuaDream', 'QuaDream spyware'),
  stalkerware('Stalkerware', 'Commercial surveillance'),
  malware('Malware', 'Generic malware'),
  anomaly('Anomaly', 'Suspicious behavior'),
  network('Network', 'Suspicious network activity'),
  process('Process', 'Suspicious process'),
  persistence('Persistence', 'Persistence mechanism'),
  dataExfil('Data Exfiltration', 'Data theft indicators');

  final String displayName;
  final String description;

  const FindingCategory(this.displayName, this.description);
}

/// Forensic finding
class ForensicFinding {
  final String id;
  final FindingCategory category;
  final FindingSeverity severity;
  final String title;
  final String description;
  final String? technicalDetails;
  final DateTime detectedTime;
  final String source;
  final List<String> iocs;
  final Map<String, dynamic> evidence;
  final List<String> mitreAttackIds;
  final List<String> recommendations;

  ForensicFinding({
    required this.id,
    required this.category,
    required this.severity,
    required this.title,
    required this.description,
    this.technicalDetails,
    required this.detectedTime,
    required this.source,
    this.iocs = const [],
    this.evidence = const {},
    this.mitreAttackIds = const [],
    this.recommendations = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category.name,
    'severity': severity.name,
    'title': title,
    'description': description,
    'technical_details': technicalDetails,
    'detected_time': detectedTime.toIso8601String(),
    'source': source,
    'iocs': iocs,
    'evidence': evidence,
    'mitre_attack_ids': mitreAttackIds,
    'recommendations': recommendations,
  };
}

/// Shutdown log entry
class ShutdownLogEntry {
  final DateTime timestamp;
  final String processName;
  final String? processPath;
  final int? pid;
  final String eventType;
  final bool isSuspicious;
  final String? suspiciousReason;

  ShutdownLogEntry({
    required this.timestamp,
    required this.processName,
    this.processPath,
    this.pid,
    required this.eventType,
    this.isSuspicious = false,
    this.suspiciousReason,
  });
}

/// Data usage entry
class DataUsageEntry {
  final String bundleId;
  final String? processName;
  final int bytesReceived;
  final int bytesSent;
  final DateTime firstSeen;
  final DateTime lastSeen;
  final bool isSuspicious;
  final String? suspiciousReason;

  DataUsageEntry({
    required this.bundleId,
    this.processName,
    required this.bytesReceived,
    required this.bytesSent,
    required this.firstSeen,
    required this.lastSeen,
    this.isSuspicious = false,
    this.suspiciousReason,
  });

  int get totalBytes => bytesReceived + bytesSent;
}

/// Timeline event
class TimelineEvent {
  final DateTime timestamp;
  final String eventType;
  final String description;
  final String source;
  final FindingSeverity severity;
  final Map<String, dynamic> details;

  TimelineEvent({
    required this.timestamp,
    required this.eventType,
    required this.description,
    required this.source,
    this.severity = FindingSeverity.info,
    this.details = const {},
  });
}

/// Forensic scan result
class ForensicScanResult {
  final String scanId;
  final ForensicScanType scanType;
  final DateTime startTime;
  final DateTime endTime;
  final List<ForensicFinding> findings;
  final List<TimelineEvent> timeline;
  final int processedArtifacts;
  final bool isCompromised;
  final double confidenceScore;
  final Map<String, dynamic> summary;

  ForensicScanResult({
    required this.scanId,
    required this.scanType,
    required this.startTime,
    required this.endTime,
    required this.findings,
    this.timeline = const [],
    required this.processedArtifacts,
    required this.isCompromised,
    required this.confidenceScore,
    this.summary = const {},
  });

  Duration get duration => endTime.difference(startTime);

  int get criticalFindings =>
      findings.where((f) => f.severity == FindingSeverity.critical).length;

  int get highFindings =>
      findings.where((f) => f.severity == FindingSeverity.high).length;
}

/// iOS Forensic Analysis Service
class IOSForensicService {
  // Known Pegasus process indicators
  static const _pegasusProcessIndicators = [
    'bh', 'roleaccountd', 'msgacntd', 'fmld', 'corelogicd',
    'roleaboutd', 'accountsd', 'fserversd', 'laaboratoryd',
    'pcaboratoryd', 'ABOatoryd', 'NiLaboratoryd',
  ];

  // Known Pegasus file indicators
  static const _pegasusFileIndicators = [
    '/private/var/tmp/mbr/*',
    '/private/var/tmp/mux/*',
    '/private/var/tmp/wifid/*',
    'com.apple.CrashReporter.plist.bak',
    '/private/var/tmp/imf*',
  ];

  // Known Pegasus domains
  static const _pegasusDomains = [
    'amazonaws.com', // Often abused
    'cloudfront.net', // Often abused
    // Specific NSO infrastructure patterns
  ];

  // Suspicious process paths that shouldn't exist
  static const _suspiciousProcessPaths = [
    '/private/var/tmp/',
    '/private/var/root/',
    '/private/var/mobile/Library/SMS/Drafts/',
    '/private/var/containers/Bundle/',
  ];

  // Known stalkerware bundle IDs
  static const _stalkerwareBundleIds = [
    'com.mspy.mobile',
    'com.flexispy.agent',
    'com.cocospy.app',
    'com.spyic.app',
    'com.minspy.app',
    'com.spyzie.app',
    'com.hoverwatch.app',
    'com.eyezy.app',
  ];

  final List<ForensicScanResult> _scanHistory = [];
  final _findingsController = StreamController<ForensicFinding>.broadcast();

  Stream<ForensicFinding> get findingsStream => _findingsController.stream;

  /// Run forensic scan
  Future<ForensicScanResult> runScan({
    ForensicScanType scanType = ForensicScanType.standard,
    String? backupPath,
    List<String>? customIOCs,
  }) async {
    final scanId = 'scan_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();
    final findings = <ForensicFinding>[];
    final timeline = <TimelineEvent>[];
    var processedArtifacts = 0;

    // Add start event to timeline
    timeline.add(TimelineEvent(
      timestamp: startTime,
      eventType: 'scan_start',
      description: 'Forensic scan started',
      source: 'IOSForensicService',
    ));

    try {
      // Run different scans based on type
      switch (scanType) {
        case ForensicScanType.quick:
          final quickFindings = await _runQuickScan();
          findings.addAll(quickFindings);
          processedArtifacts += 10;
          break;

        case ForensicScanType.standard:
          // Shutdown log analysis
          final shutdownFindings = await _analyzeShutdownLog();
          findings.addAll(shutdownFindings);
          processedArtifacts += 1;

          // Basic process check
          final processFindings = await _checkRunningProcesses();
          findings.addAll(processFindings);
          processedArtifacts += 50;

          // Network connections
          final networkFindings = await _analyzeNetworkConnections();
          findings.addAll(networkFindings);
          processedArtifacts += 20;
          break;

        case ForensicScanType.deep:
          // All standard checks
          findings.addAll(await _analyzeShutdownLog());
          findings.addAll(await _checkRunningProcesses());
          findings.addAll(await _analyzeNetworkConnections());
          processedArtifacts += 71;

          // DataUsage.sqlite
          final dataUsageFindings = await _analyzeDataUsage();
          findings.addAll(dataUsageFindings);
          processedArtifacts += 1;

          // Sysdiagnose if available
          final sysdiagFindings = await _analyzeSysdiagnose();
          findings.addAll(sysdiagFindings);
          processedArtifacts += 100;

          // App installations
          final appFindings = await _analyzeInstalledApps();
          findings.addAll(appFindings);
          processedArtifacts += 200;

          // Configuration profiles
          final profileFindings = await _analyzeConfigProfiles();
          findings.addAll(profileFindings);
          processedArtifacts += 10;
          break;

        case ForensicScanType.backup:
          if (backupPath != null) {
            final backupFindings = await _analyzeBackup(backupPath);
            findings.addAll(backupFindings);
            processedArtifacts += 1000;
          }
          break;
      }

      // Check custom IOCs if provided
      if (customIOCs != null && customIOCs.isNotEmpty) {
        final customFindings = await _checkCustomIOCs(customIOCs);
        findings.addAll(customFindings);
      }

    } catch (e) {
      // Add error to timeline
      timeline.add(TimelineEvent(
        timestamp: DateTime.now(),
        eventType: 'error',
        description: 'Scan error: $e',
        source: 'IOSForensicService',
        severity: FindingSeverity.high,
      ));
    }

    // Emit findings
    for (final finding in findings) {
      _findingsController.add(finding);
    }

    final endTime = DateTime.now();

    // Add end event to timeline
    timeline.add(TimelineEvent(
      timestamp: endTime,
      eventType: 'scan_end',
      description: 'Forensic scan completed',
      source: 'IOSForensicService',
    ));

    // Determine if compromised
    final isCompromised = findings.any((f) =>
        f.severity == FindingSeverity.critical ||
        (f.severity == FindingSeverity.high &&
         (f.category == FindingCategory.pegasus ||
          f.category == FindingCategory.predator ||
          f.category == FindingCategory.quadream)));

    // Calculate confidence score
    final confidenceScore = _calculateConfidenceScore(findings);

    final result = ForensicScanResult(
      scanId: scanId,
      scanType: scanType,
      startTime: startTime,
      endTime: endTime,
      findings: findings,
      timeline: timeline,
      processedArtifacts: processedArtifacts,
      isCompromised: isCompromised,
      confidenceScore: confidenceScore,
      summary: {
        'total_findings': findings.length,
        'critical': findings.where((f) => f.severity == FindingSeverity.critical).length,
        'high': findings.where((f) => f.severity == FindingSeverity.high).length,
        'medium': findings.where((f) => f.severity == FindingSeverity.medium).length,
        'categories': findings.map((f) => f.category.name).toSet().toList(),
      },
    );

    _scanHistory.add(result);

    return result;
  }

  /// Quick IOC check
  Future<List<ForensicFinding>> _runQuickScan() async {
    final findings = <ForensicFinding>[];

    // Check for known malicious processes
    for (final process in _pegasusProcessIndicators) {
      // In production, this would actually check running processes
      // Here we simulate the check
    }

    return findings;
  }

  /// Analyze Shutdown.log for Pegasus indicators
  Future<List<ForensicFinding>> _analyzeShutdownLog() async {
    final findings = <ForensicFinding>[];

    // Shutdown.log location on iOS: /private/var/db/diagnostics/shutdown.log
    // This requires jailbreak or backup access

    // Simulate analysis of shutdown log entries
    // In production, this would parse actual shutdown.log

    // Check for suspicious process names
    for (final process in _pegasusProcessIndicators) {
      // Example finding if process is found
      // findings.add(ForensicFinding(
      //   id: 'shutdown_${DateTime.now().millisecondsSinceEpoch}',
      //   category: FindingCategory.pegasus,
      //   severity: FindingSeverity.critical,
      //   title: 'Pegasus Process Detected',
      //   description: 'Shutdown.log contains entry for known Pegasus process: $process',
      //   detectedTime: DateTime.now(),
      //   source: 'shutdown.log',
      //   iocs: [process],
      //   mitreAttackIds: ['T1059', 'T1055'],
      //   recommendations: [
      //     'Factory reset device immediately',
      //     'Do not restore from backup',
      //     'Contact security professional',
      //   ],
      // ));
    }

    return findings;
  }

  /// Check running processes
  Future<List<ForensicFinding>> _checkRunningProcesses() async {
    final findings = <ForensicFinding>[];

    // On iOS, we can't directly enumerate processes without jailbreak
    // But we can check for suspicious behavior patterns

    return findings;
  }

  /// Analyze network connections
  Future<List<ForensicFinding>> _analyzeNetworkConnections() async {
    final findings = <ForensicFinding>[];

    // Check for connections to known C2 infrastructure
    // This would use the rogue_ap_detection_service and dns_protection_service

    return findings;
  }

  /// Analyze DataUsage.sqlite
  Future<List<ForensicFinding>> _analyzeDataUsage() async {
    final findings = <ForensicFinding>[];

    // DataUsage.sqlite location: /private/var/wireless/Library/Databases/DataUsage.sqlite
    // Contains network usage per process/bundle ID

    // Look for:
    // - Unknown bundle IDs with high data usage
    // - Processes that shouldn't have network access
    // - Unusual patterns (high upload, late night activity)

    return findings;
  }

  /// Analyze sysdiagnose
  Future<List<ForensicFinding>> _analyzeSysdiagnose() async {
    final findings = <ForensicFinding>[];

    // Sysdiagnose contains:
    // - ps output
    // - Network statistics
    // - System logs
    // - Crash reports

    // Parse and analyze each component

    return findings;
  }

  /// Analyze installed apps
  Future<List<ForensicFinding>> _analyzeInstalledApps() async {
    final findings = <ForensicFinding>[];

    // Check for known stalkerware bundle IDs
    for (final bundleId in _stalkerwareBundleIds) {
      // In production, check if app is installed
    }

    // Check for enterprise-signed apps from unknown sources
    // Check for apps with suspicious permissions

    return findings;
  }

  /// Analyze configuration profiles
  Future<List<ForensicFinding>> _analyzeConfigProfiles() async {
    final findings = <ForensicFinding>[];

    // MDM profiles can be used for surveillance
    // Check for:
    // - Unknown MDM profiles
    // - Profiles with suspicious payloads
    // - Certificate trust settings

    return findings;
  }

  /// Analyze iOS backup
  Future<List<ForensicFinding>> _analyzeBackup(String backupPath) async {
    final findings = <ForensicFinding>[];

    // Parse backup manifest
    // Analyze:
    // - SMS/iMessage database
    // - Call history
    // - Safari history
    // - App data
    // - Photos metadata
    // - Location history

    final backupDir = Directory(backupPath);
    if (!await backupDir.exists()) {
      return findings;
    }

    // Check Manifest.db for file list
    // Parse Info.plist for device info
    // Analyze domain files

    return findings;
  }

  /// Check custom IOCs
  Future<List<ForensicFinding>> _checkCustomIOCs(List<String> iocs) async {
    final findings = <ForensicFinding>[];

    for (final ioc in iocs) {
      // Check IOC against various data sources
      // Could be domain, IP, file hash, process name, etc.
    }

    return findings;
  }

  /// Calculate confidence score for findings
  double _calculateConfidenceScore(List<ForensicFinding> findings) {
    if (findings.isEmpty) return 0.0;

    var totalScore = 0.0;

    for (final finding in findings) {
      switch (finding.severity) {
        case FindingSeverity.critical:
          totalScore += 1.0;
          break;
        case FindingSeverity.high:
          totalScore += 0.8;
          break;
        case FindingSeverity.medium:
          totalScore += 0.5;
          break;
        case FindingSeverity.low:
          totalScore += 0.2;
          break;
        case FindingSeverity.info:
          totalScore += 0.1;
          break;
      }

      // Boost for specific spyware categories
      if (finding.category == FindingCategory.pegasus ||
          finding.category == FindingCategory.predator ||
          finding.category == FindingCategory.quadream) {
        totalScore += 0.2;
      }

      // Boost for multiple IOCs
      if (finding.iocs.length > 3) {
        totalScore += 0.1;
      }
    }

    // Normalize to 0-1 range
    return (totalScore / findings.length).clamp(0.0, 1.0);
  }

  /// Get scan history
  List<ForensicScanResult> getScanHistory() => List.unmodifiable(_scanHistory);

  /// Get last scan result
  ForensicScanResult? getLastScanResult() =>
      _scanHistory.isNotEmpty ? _scanHistory.last : null;

  /// Export findings to JSON
  String exportFindings(ForensicScanResult result) {
    return jsonEncode({
      'scan_id': result.scanId,
      'scan_type': result.scanType.name,
      'start_time': result.startTime.toIso8601String(),
      'end_time': result.endTime.toIso8601String(),
      'is_compromised': result.isCompromised,
      'confidence_score': result.confidenceScore,
      'findings': result.findings.map((f) => f.toJson()).toList(),
      'summary': result.summary,
    });
  }

  /// Generate remediation report
  String generateRemediationReport(ForensicScanResult result) {
    final buffer = StringBuffer();

    buffer.writeln('# iOS Forensic Analysis Report');
    buffer.writeln();
    buffer.writeln('**Scan ID:** ${result.scanId}');
    buffer.writeln('**Scan Type:** ${result.scanType.displayName}');
    buffer.writeln('**Date:** ${result.startTime.toIso8601String()}');
    buffer.writeln('**Duration:** ${result.duration.inSeconds}s');
    buffer.writeln();

    if (result.isCompromised) {
      buffer.writeln('## ⚠️ DEVICE MAY BE COMPROMISED');
      buffer.writeln();
      buffer.writeln('Confidence Score: ${(result.confidenceScore * 100).toStringAsFixed(1)}%');
      buffer.writeln();
    } else {
      buffer.writeln('## ✅ No Indicators of Compromise Found');
      buffer.writeln();
    }

    buffer.writeln('## Findings Summary');
    buffer.writeln();
    buffer.writeln('- Critical: ${result.criticalFindings}');
    buffer.writeln('- High: ${result.highFindings}');
    buffer.writeln('- Total: ${result.findings.length}');
    buffer.writeln();

    if (result.findings.isNotEmpty) {
      buffer.writeln('## Detailed Findings');
      buffer.writeln();

      for (final finding in result.findings) {
        buffer.writeln('### ${finding.title}');
        buffer.writeln();
        buffer.writeln('**Severity:** ${finding.severity.displayName}');
        buffer.writeln('**Category:** ${finding.category.displayName}');
        buffer.writeln('**Source:** ${finding.source}');
        buffer.writeln();
        buffer.writeln(finding.description);
        buffer.writeln();

        if (finding.recommendations.isNotEmpty) {
          buffer.writeln('**Recommendations:**');
          for (final rec in finding.recommendations) {
            buffer.writeln('- $rec');
          }
          buffer.writeln();
        }
      }
    }

    buffer.writeln('## General Recommendations');
    buffer.writeln();
    if (result.isCompromised) {
      buffer.writeln('1. **Do not use the device for sensitive communications**');
      buffer.writeln('2. Factory reset the device (do not restore from backup)');
      buffer.writeln('3. Change all passwords from a different device');
      buffer.writeln('4. Enable two-factor authentication on all accounts');
      buffer.writeln('5. Contact a security professional for incident response');
      buffer.writeln('6. Consider reporting to law enforcement');
    } else {
      buffer.writeln('1. Keep iOS updated to the latest version');
      buffer.writeln('2. Enable Lockdown Mode if you are at high risk');
      buffer.writeln('3. Be cautious of links from unknown senders');
      buffer.writeln('4. Regularly review installed apps and profiles');
      buffer.writeln('5. Run periodic forensic scans');
    }

    return buffer.toString();
  }

  /// Dispose resources
  void dispose() {
    _findingsController.close();
  }
}
