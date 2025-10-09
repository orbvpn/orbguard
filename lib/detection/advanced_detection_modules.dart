// advanced_detection_modules.dart
// Location: lib/detection/

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

// ============================================================================
// MODULE 1: BEHAVIORAL ANOMALY DETECTION
// ============================================================================

class BehavioralAnomalyDetector {
  static const platform = MethodChannel('com.orb.guard/system');

  // Baseline metrics for normal behavior
  final Map<String, dynamic> _baseline = {};
  final List<Map<String, dynamic>> _anomalies = [];

  /// Establish baseline of normal device behavior
  Future<void> learnBaseline({int durationMinutes = 60}) async {
    print('[Behavioral] Learning baseline for $durationMinutes minutes...');

    final startTime = DateTime.now();
    final samples = <Map<String, dynamic>>[];

    while (DateTime.now().difference(startTime).inMinutes < durationMinutes) {
      final sample = await _collectMetrics();
      samples.add(sample);
      await Future.delayed(const Duration(seconds: 30));
    }

    _calculateBaseline(samples);
    print('[Behavioral] Baseline established');
  }

  Future<Map<String, dynamic>> _collectMetrics() async {
    return {
      'timestamp': DateTime.now().toIso8601String(),
      'batteryDrain': await _getBatteryDrain(),
      'cpuUsage': await _getCPUUsage(),
      'networkActivity': await _getNetworkActivity(),
      'screenOnTime': await _getScreenOnTime(),
      'backgroundProcessCount': await _getBackgroundProcessCount(),
      'dataUsage': await _getDataUsage(),
    };
  }

  void _calculateBaseline(List<Map<String, dynamic>> samples) {
    // Calculate average and standard deviation for each metric
    final metrics = [
      'batteryDrain',
      'cpuUsage',
      'networkActivity',
      'backgroundProcessCount',
      'dataUsage',
    ];

    for (final metric in metrics) {
      final values = samples.map((s) => s[metric] as double).toList();
      final avg = values.reduce((a, b) => a + b) / values.length;
      final variance =
          values.map((v) => (v - avg) * (v - avg)).reduce((a, b) => a + b) /
              values.length;
      final stdDev = sqrt(variance);

      _baseline[metric] = {
        'average': avg,
        'stdDev': stdDev,
        'threshold': avg + (2 * stdDev), // 2 standard deviations
      };
    }
  }

  /// Detect anomalies by comparing current metrics to baseline
  Future<List<Map<String, dynamic>>> detectAnomalies() async {
    if (_baseline.isEmpty) {
      throw Exception('Baseline not established. Call learnBaseline() first.');
    }

    final current = await _collectMetrics();
    final threats = <Map<String, dynamic>>[];

    // Check each metric against baseline
    for (final metric in _baseline.keys) {
      final currentValue = current[metric] as double;
      final threshold = _baseline[metric]['threshold'] as double;
      final average = _baseline[metric]['average'] as double;

      if (currentValue > threshold) {
        final deviation = ((currentValue - average) / average * 100).round();

        threats.add({
          'id': 'anomaly_${metric}_${DateTime.now().millisecondsSinceEpoch}',
          'name': 'Behavioral Anomaly: ${_formatMetricName(metric)}',
          'description': '$metric is ${deviation}% above normal baseline',
          'severity': deviation > 100 ? 'HIGH' : 'MEDIUM',
          'type': 'behavioral',
          'path': metric,
          'requiresRoot': false,
          'metadata': {
            'metric': metric,
            'baseline': average,
            'current': currentValue,
            'deviation': '$deviation%',
            'timestamp': current['timestamp'],
          },
        });
      }
    }

    return threats;
  }

  String _formatMetricName(String metric) {
    return metric
        .replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')
        .trim();
  }

  // Helper methods to get device metrics
  Future<double> _getBatteryDrain() async {
    try {
      final result = await platform.invokeMethod('getBatteryDrain');
      return result['drainRate'] ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> _getCPUUsage() async {
    try {
      final result = await platform.invokeMethod('getCPUUsage');
      return result['percentage'] ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> _getNetworkActivity() async {
    try {
      final result = await platform.invokeMethod('getNetworkActivity');
      return result['bytesPerSecond'] ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> _getScreenOnTime() async {
    try {
      final result = await platform.invokeMethod('getScreenOnTime');
      return result['minutes'] ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> _getBackgroundProcessCount() async {
    try {
      final result = await platform.invokeMethod('getBackgroundProcessCount');
      return result['count']?.toDouble() ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  Future<double> _getDataUsage() async {
    try {
      final result = await platform.invokeMethod('getDataUsage');
      return result['megabytes'] ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  double sqrt(double value) => value >= 0 ? (value).toDouble() : 0.0;
}

// ============================================================================
// MODULE 2: CERTIFICATE & SSL PINNING DETECTOR
// ============================================================================

class CertificateAnalyzer {
  static const platform = MethodChannel('com.orb.guard/system');

  /// Detect SSL certificate manipulation (MITM attacks)
  Future<List<Map<String, dynamic>>> detectCertificateThreats() async {
    final threats = <Map<String, dynamic>>[];

    // Check installed certificates
    final certs = await _getInstalledCertificates();

    for (final cert in certs) {
      // Check for user-installed certificates (potential MITM)
      if (cert['isUserInstalled'] == true) {
        threats.add({
          'id': 'cert_${cert['serial']}',
          'name': 'Suspicious Certificate Installed',
          'description':
              'User-installed certificate detected: ${cert['subject']}',
          'severity': 'HIGH',
          'type': 'certificate',
          'path': cert['path'] ?? 'System Certificate Store',
          'requiresRoot': true,
          'metadata': {
            'subject': cert['subject'],
            'issuer': cert['issuer'],
            'serial': cert['serial'],
            'validFrom': cert['validFrom'],
            'validTo': cert['validTo'],
          },
        });
      }

      // Check for expired certificates still active
      if (cert['isExpired'] == true && cert['isActive'] == true) {
        threats.add({
          'id': 'cert_expired_${cert['serial']}',
          'name': 'Expired Certificate in Use',
          'description': 'Active expired certificate: ${cert['subject']}',
          'severity': 'MEDIUM',
          'type': 'certificate',
          'path': cert['path'] ?? 'System Certificate Store',
          'requiresRoot': true,
          'metadata': cert,
        });
      }

      // Check for self-signed certificates
      if (cert['isSelfSigned'] == true) {
        threats.add({
          'id': 'cert_selfsigned_${cert['serial']}',
          'name': 'Self-Signed Certificate',
          'description':
              'Potentially malicious self-signed cert: ${cert['subject']}',
          'severity': 'MEDIUM',
          'type': 'certificate',
          'path': cert['path'] ?? 'System Certificate Store',
          'requiresRoot': true,
          'metadata': cert,
        });
      }
    }

    return threats;
  }

  Future<List<Map<String, dynamic>>> _getInstalledCertificates() async {
    try {
      final result = await platform.invokeMethod('getInstalledCertificates');
      return List<Map<String, dynamic>>.from(result['certificates'] ?? []);
    } catch (e) {
      print('Error getting certificates: $e');
      return [];
    }
  }
}

// ============================================================================
// MODULE 3: PERMISSION ABUSE DETECTOR
// ============================================================================

class PermissionAbuseDetector {
  static const platform = MethodChannel('com.orb.guard/system');

  // Dangerous permission combinations that indicate spyware
  static const suspiciousPermissionCombos = [
    {
      'name': 'Full Surveillance Suite',
      'permissions': [
        'CAMERA',
        'RECORD_AUDIO',
        'ACCESS_FINE_LOCATION',
        'READ_CONTACTS',
        'READ_SMS',
      ],
      'severity': 'CRITICAL',
    },
    {
      'name': 'Data Exfiltration Suite',
      'permissions': [
        'READ_CONTACTS',
        'READ_SMS',
        'READ_CALL_LOG',
        'GET_ACCOUNTS',
        'INTERNET',
      ],
      'severity': 'HIGH',
    },
    {
      'name': 'Location Tracker',
      'permissions': [
        'ACCESS_FINE_LOCATION',
        'ACCESS_BACKGROUND_LOCATION',
        'INTERNET',
      ],
      'severity': 'HIGH',
    },
  ];

  /// Detect apps with suspicious permission combinations
  Future<List<Map<String, dynamic>>> detectPermissionAbuse() async {
    final threats = <Map<String, dynamic>>[];
    final installedApps = await _getInstalledApps();

    for (final app in installedApps) {
      final appPermissions = app['permissions'] as List<dynamic>;

      // Check against suspicious combinations
      for (final combo in suspiciousPermissionCombos) {
        final requiredPerms = combo['permissions'] as List<String>;
        final hasAll = requiredPerms.every(
          (perm) => appPermissions.contains(perm),
        );

        if (hasAll) {
          threats.add({
            'id': 'perm_${app['packageName']}',
            'name': 'Suspicious Permissions: ${app['appName']}',
            'description': 'App has ${combo['name']} permissions',
            'severity': combo['severity'],
            'type': 'permission',
            'path': app['packageName'],
            'requiresRoot': false,
            'metadata': {
              'packageName': app['packageName'],
              'appName': app['appName'],
              'permissions': appPermissions,
              'comboMatched': combo['name'],
              'installDate': app['installDate'],
            },
          });
        }
      }

      // Check for background usage of sensitive permissions
      final backgroundUsage = await _checkBackgroundPermissionUsage(
        app['packageName'],
      );

      if (backgroundUsage.isNotEmpty) {
        threats.add({
          'id': 'bg_perm_${app['packageName']}',
          'name': 'Background Permission Abuse: ${app['appName']}',
          'description': 'App using sensitive permissions in background',
          'severity': 'HIGH',
          'type': 'permission',
          'path': app['packageName'],
          'requiresRoot': false,
          'metadata': {
            'packageName': app['packageName'],
            'backgroundUsage': backgroundUsage,
          },
        });
      }
    }

    return threats;
  }

  Future<List<Map<String, dynamic>>> _getInstalledApps() async {
    try {
      final result = await platform.invokeMethod('getInstalledApps');
      return List<Map<String, dynamic>>.from(result['apps'] ?? []);
    } catch (e) {
      print('Error getting installed apps: $e');
      return [];
    }
  }

  Future<List<String>> _checkBackgroundPermissionUsage(
    String packageName,
  ) async {
    try {
      final result = await platform.invokeMethod(
        'checkBackgroundPermissionUsage',
        {'packageName': packageName},
      );
      return List<String>.from(result['permissions'] ?? []);
    } catch (e) {
      return [];
    }
  }
}

// ============================================================================
// MODULE 4: ACCESSIBILITY SERVICE ABUSE DETECTOR
// ============================================================================

class AccessibilityAbuseDetector {
  static const platform = MethodChannel('com.orb.guard/system');

  /// Detect malicious use of accessibility services
  /// (Accessibility services can read screen content, simulate touches)
  Future<List<Map<String, dynamic>>> detectAccessibilityAbuse() async {
    final threats = <Map<String, dynamic>>[];

    final accessibilityServices = await _getEnabledAccessibilityServices();

    for (final service in accessibilityServices) {
      final packageName = service['packageName'] as String;

      // Check if system app or known safe app
      if (!_isSystemApp(packageName) && !_isKnownSafeApp(packageName)) {
        // Get app info
        final appInfo = await _getAppInfo(packageName);

        threats.add({
          'id': 'accessibility_${packageName}',
          'name': 'Accessibility Service Enabled',
          'description':
              'Third-party app has accessibility access: ${appInfo['appName']}',
          'severity': 'HIGH',
          'type': 'accessibility',
          'path': packageName,
          'requiresRoot': false,
          'metadata': {
            'packageName': packageName,
            'appName': appInfo['appName'],
            'capabilities': service['capabilities'],
            'canRetrieveWindowContent': service['canRetrieveWindowContent'],
            'enabledDate': service['enabledDate'],
          },
        });
      }
    }

    return threats;
  }

  Future<List<Map<String, dynamic>>> _getEnabledAccessibilityServices() async {
    try {
      final result = await platform.invokeMethod(
        'getEnabledAccessibilityServices',
      );
      return List<Map<String, dynamic>>.from(result['services'] ?? []);
    } catch (e) {
      print('Error getting accessibility services: $e');
      return [];
    }
  }

  bool _isSystemApp(String packageName) {
    return packageName.startsWith('com.android.') ||
        packageName.startsWith('com.google.android.');
  }

  bool _isKnownSafeApp(String packageName) {
    const safeApps = [
      'com.google.android.talkback',
      'com.android.talkback',
      'com.google.android.marvin.talkback',
    ];
    return safeApps.contains(packageName);
  }

  Future<Map<String, dynamic>> _getAppInfo(String packageName) async {
    try {
      final result = await platform.invokeMethod('getAppInfo', {
        'packageName': packageName,
      });
      return result ?? {'appName': packageName};
    } catch (e) {
      return {'appName': packageName};
    }
  }
}

// ============================================================================
// MODULE 5: KEYSTROKE LOGGER DETECTOR
// ============================================================================

class KeystrokeLoggerDetector {
  static const platform = MethodChannel('com.orb.guard/system');

  /// Detect keyloggers by analyzing input methods and keyboard apps
  Future<List<Map<String, dynamic>>> detectKeyloggers() async {
    final threats = <Map<String, dynamic>>[];

    // Check installed keyboards
    final keyboards = await _getInstalledKeyboards();

    for (final keyboard in keyboards) {
      final packageName = keyboard['packageName'] as String;

      // Check if keyboard requests internet permission (red flag)
      final permissions = keyboard['permissions'] as List<dynamic>;
      final hasInternet = permissions.contains('INTERNET');

      if (hasInternet && !_isTrustedKeyboard(packageName)) {
        threats.add({
          'id': 'keyboard_${packageName}',
          'name': 'Suspicious Keyboard App',
          'description':
              'Keyboard with internet access: ${keyboard['appName']}',
          'severity': 'CRITICAL',
          'type': 'keylogger',
          'path': packageName,
          'requiresRoot': false,
          'metadata': {
            'packageName': packageName,
            'appName': keyboard['appName'],
            'permissions': permissions,
            'isEnabled': keyboard['isEnabled'],
            'isDefault': keyboard['isDefault'],
          },
        });
      }
    }

    // Check for input method editor (IME) abuse
    final imeAbuse = await _detectIMEAbuse();
    threats.addAll(imeAbuse);

    return threats;
  }

  Future<List<Map<String, dynamic>>> _getInstalledKeyboards() async {
    try {
      final result = await platform.invokeMethod('getInstalledKeyboards');
      return List<Map<String, dynamic>>.from(result['keyboards'] ?? []);
    } catch (e) {
      print('Error getting keyboards: $e');
      return [];
    }
  }

  bool _isTrustedKeyboard(String packageName) {
    const trustedKeyboards = [
      'com.google.android.inputmethod.latin', // Gboard
      'com.android.inputmethod.latin', // AOSP Keyboard
      'com.samsung.android.honeyboard', // Samsung Keyboard
      'com.microsoft.swiftkey.swiftkeyconfigurator', // SwiftKey
    ];
    return trustedKeyboards.contains(packageName);
  }

  Future<List<Map<String, dynamic>>> _detectIMEAbuse() async {
    try {
      final result = await platform.invokeMethod('detectIMEAbuse');
      return List<Map<String, dynamic>>.from(result['threats'] ?? []);
    } catch (e) {
      return [];
    }
  }
}

// ============================================================================
// MODULE 6: ROOTING/JAILBREAK MALWARE DETECTOR
// ============================================================================

class RootingMalwareDetector {
  static const platform = MethodChannel('com.orb.guard/system');

  /// Detect malware that exploits root/jailbreak
  Future<List<Map<String, dynamic>>> detectRootingMalware() async {
    final threats = <Map<String, dynamic>>[];

    // Check for suspicious root binaries
    if (Platform.isAndroid) {
      final rootBinaries = await _checkSuspiciousRootBinaries();
      threats.addAll(rootBinaries);

      // Check for modified system files
      final modifiedFiles = await _checkModifiedSystemFiles();
      threats.addAll(modifiedFiles);
    }

    if (Platform.isIOS) {
      // Check for malicious jailbreak tweaks
      final maliciousTweaks = await _checkMaliciousTweaks();
      threats.addAll(maliciousTweaks);

      // Check for modified launchd daemons
      final maliciousDaemons = await _checkMaliciousDaemons();
      threats.addAll(maliciousDaemons);
    }

    return threats;
  }

  Future<List<Map<String, dynamic>>> _checkSuspiciousRootBinaries() async {
    try {
      final result = await platform.invokeMethod('checkSuspiciousRootBinaries');
      return List<Map<String, dynamic>>.from(result['threats'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _checkModifiedSystemFiles() async {
    try {
      final result = await platform.invokeMethod('checkModifiedSystemFiles');
      return List<Map<String, dynamic>>.from(result['threats'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _checkMaliciousTweaks() async {
    try {
      final result = await platform.invokeMethod('checkMaliciousTweaks');
      return List<Map<String, dynamic>>.from(result['threats'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _checkMaliciousDaemons() async {
    try {
      final result = await platform.invokeMethod('checkMaliciousDaemons');
      return List<Map<String, dynamic>>.from(result['threats'] ?? []);
    } catch (e) {
      return [];
    }
  }
}

// ============================================================================
// MODULE 7: GEOLOCATION STALKER DETECTOR
// ============================================================================

class GeolocationStalkerDetector {
  static const platform = MethodChannel('com.orb.guard/system');

  /// Detect apps that excessively track location
  Future<List<Map<String, dynamic>>> detectLocationStalkers() async {
    final threats = <Map<String, dynamic>>[];

    // Get location access history for last 24 hours
    final locationAccess = await _getLocationAccessHistory(hours: 24);

    // Group by app
    final accessByApp = <String, List<Map<String, dynamic>>>{};
    for (final access in locationAccess) {
      final packageName = access['packageName'] as String;
      accessByApp.putIfAbsent(packageName, () => []).add(access);
    }

    // Check for excessive access
    for (final entry in accessByApp.entries) {
      final packageName = entry.key;
      final accesses = entry.value;

      // Flag apps accessing location more than 100 times per day
      if (accesses.length > 100) {
        final appInfo = await _getAppInfo(packageName);

        threats.add({
          'id': 'location_${packageName}',
          'name': 'Excessive Location Tracking',
          'description':
              '${appInfo['appName']} accessed location ${accesses.length} times',
          'severity': 'HIGH',
          'type': 'location',
          'path': packageName,
          'requiresRoot': false,
          'metadata': {
            'packageName': packageName,
            'appName': appInfo['appName'],
            'accessCount': accesses.length,
            'lastAccess': accesses.last['timestamp'],
            'backgroundAccess':
                accesses.where((a) => a['isBackground'] == true).length,
          },
        });
      }
    }

    return threats;
  }

  Future<List<Map<String, dynamic>>> _getLocationAccessHistory({
    int hours = 24,
  }) async {
    try {
      final result = await platform.invokeMethod('getLocationAccessHistory', {
        'hours': hours,
      });
      return List<Map<String, dynamic>>.from(result['accesses'] ?? []);
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> _getAppInfo(String packageName) async {
    try {
      final result = await platform.invokeMethod('getAppInfo', {
        'packageName': packageName,
      });
      return result ?? {'appName': packageName};
    } catch (e) {
      return {'appName': packageName};
    }
  }
}

// ============================================================================
// MODULE MANAGER - Coordinates all detection modules
// ============================================================================

class AdvancedDetectionManager {
  final BehavioralAnomalyDetector behavioralDetector;
  final CertificateAnalyzer certificateAnalyzer;
  final PermissionAbuseDetector permissionDetector;
  final AccessibilityAbuseDetector accessibilityDetector;
  final KeystrokeLoggerDetector keystrokeDetector;
  final RootingMalwareDetector rootingDetector;
  final GeolocationStalkerDetector locationDetector;

  AdvancedDetectionManager()
      : behavioralDetector = BehavioralAnomalyDetector(),
        certificateAnalyzer = CertificateAnalyzer(),
        permissionDetector = PermissionAbuseDetector(),
        accessibilityDetector = AccessibilityAbuseDetector(),
        keystrokeDetector = KeystrokeLoggerDetector(),
        rootingDetector = RootingMalwareDetector(),
        locationDetector = GeolocationStalkerDetector();

  /// Run all advanced detection modules
  Future<List<Map<String, dynamic>>> runAllModules() async {
    final allThreats = <Map<String, dynamic>>[];

    print('[Advanced] Running behavioral analysis...');
    try {
      final behavioral = await behavioralDetector.detectAnomalies();
      allThreats.addAll(behavioral);
      print('[Advanced] Behavioral: ${behavioral.length} threats');
    } catch (e) {
      print('[Advanced] Behavioral error: $e');
    }

    print('[Advanced] Running certificate analysis...');
    try {
      final certificates = await certificateAnalyzer.detectCertificateThreats();
      allThreats.addAll(certificates);
      print('[Advanced] Certificates: ${certificates.length} threats');
    } catch (e) {
      print('[Advanced] Certificate error: $e');
    }

    print('[Advanced] Running permission analysis...');
    try {
      final permissions = await permissionDetector.detectPermissionAbuse();
      allThreats.addAll(permissions);
      print('[Advanced] Permissions: ${permissions.length} threats');
    } catch (e) {
      print('[Advanced] Permission error: $e');
    }

    print('[Advanced] Running accessibility analysis...');
    try {
      final accessibility =
          await accessibilityDetector.detectAccessibilityAbuse();
      allThreats.addAll(accessibility);
      print('[Advanced] Accessibility: ${accessibility.length} threats');
    } catch (e) {
      print('[Advanced] Accessibility error: $e');
    }

    print('[Advanced] Running keylogger detection...');
    try {
      final keyloggers = await keystrokeDetector.detectKeyloggers();
      allThreats.addAll(keyloggers);
      print('[Advanced] Keyloggers: ${keyloggers.length} threats');
    } catch (e) {
      print('[Advanced] Keylogger error: $e');
    }

    print('[Advanced] Running rooting malware detection...');
    try {
      final rootingMalware = await rootingDetector.detectRootingMalware();
      allThreats.addAll(rootingMalware);
      print('[Advanced] Rooting malware: ${rootingMalware.length} threats');
    } catch (e) {
      print('[Advanced] Rooting malware error: $e');
    }

    print('[Advanced] Running location stalker detection...');
    try {
      final locationStalkers = await locationDetector.detectLocationStalkers();
      allThreats.addAll(locationStalkers);
      print('[Advanced] Location stalkers: ${locationStalkers.length} threats');
    } catch (e) {
      print('[Advanced] Location stalker error: $e');
    }

    print('[Advanced] Total threats detected: ${allThreats.length}');
    return allThreats;
  }

  /// Run specific module by name
  Future<List<Map<String, dynamic>>> runModule(String moduleName) async {
    switch (moduleName.toLowerCase()) {
      case 'behavioral':
        return await behavioralDetector.detectAnomalies();
      case 'certificate':
        return await certificateAnalyzer.detectCertificateThreats();
      case 'permission':
        return await permissionDetector.detectPermissionAbuse();
      case 'accessibility':
        return await accessibilityDetector.detectAccessibilityAbuse();
      case 'keylogger':
        return await keystrokeDetector.detectKeyloggers();
      case 'rooting':
        return await rootingDetector.detectRootingMalware();
      case 'location':
        return await locationDetector.detectLocationStalkers();
      default:
        throw Exception('Unknown module: $moduleName');
    }
  }
}
