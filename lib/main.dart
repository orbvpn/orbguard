// lib/main.dart - Complete with Special Permissions Integration
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'screens/scan_results_screen.dart';
import 'screens/permission_setup_screen.dart';
import 'permissions/special_permissions_manager.dart';
import 'detection/advanced_detection_modules.dart';
import 'intelligence/cloud_threat_intelligence.dart';

// Global instances
late ThreatIntelligenceManager threatIntel;
late AdvancedDetectionManager advancedDetection;
late SpecialPermissionsManager specialPermissions;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize threat intelligence
  threatIntel = ThreatIntelligenceManager(
    apiUrl: 'http://localhost:8080/api/v1/intelligence',
    apiKey: 'secret123',
  );

  await threatIntel.initialize();

  // Start auto-updates
  final autoUpdater = ThreatIntelligenceAutoUpdater(threatIntel);
  autoUpdater.startAutoUpdate();

  // Initialize advanced detection
  advancedDetection = AdvancedDetectionManager();

  // Initialize special permissions manager
  specialPermissions = SpecialPermissionsManager();
  await specialPermissions.checkPermissions();

  runApp(const AntiSpywareApp());
}

class AntiSpywareApp extends StatelessWidget {
  const AntiSpywareApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OrbGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E21),
        primaryColor: const Color(0xFF1D1E33),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00D9FF),
          secondary: Color(0xFFFF006E),
          error: Color(0xFFFF006E),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const platform = MethodChannel('com.orb.guard/system');

  bool _isScanning = false;
  bool _hasRootAccess = false;
  String _deviceInfo = '';
  String _accessLevel = 'Standard';
  String _accessMethod = 'Standard';
  List<ThreatDetection> _threats = [];
  ScanProgress _scanProgress = ScanProgress();
  double _detectionCapability = 0.0;
  bool _permissionsChecked = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkDeviceInfo();
    await _checkSystemAccess();
    await _checkAllPermissions();
    await _calculateDetectionCapability();
  }

  Future<void> _checkDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String info = '';

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      info = 'Android ${androidInfo.version.release}\n'
          'Model: ${androidInfo.model}\n'
          'Security Patch: ${androidInfo.version.securityPatch ?? "Unknown"}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      info = 'iOS ${iosInfo.systemVersion}\n'
          'Model: ${iosInfo.model}\n'
          'Device: ${iosInfo.name}';
    }

    setState(() {
      _deviceInfo = info;
    });
  }

  Future<void> _checkSystemAccess() async {
    try {
      final result = await platform.invokeMethod('checkRootAccess');
      setState(() {
        _hasRootAccess = result['hasRoot'] ?? false;
        _accessLevel = result['accessLevel'] ?? 'Standard';
        _accessMethod = result['method'] ?? 'Standard';
      });

      if (_accessMethod != 'Standard') {
        print('[OrbGuard] Access method detected: $_accessMethod');
      }
    } catch (e) {
      setState(() {
        _accessLevel = 'Standard';
        _accessMethod = 'Standard';
      });
    }
  }

  Future<void> _checkAllPermissions() async {
    await specialPermissions.checkPermissions();
    setState(() {
      _permissionsChecked = true;
    });
  }

  Future<void> _calculateDetectionCapability() async {
    // Base capability from standard APIs
    double capability = 30.0;

    // Add capability based on granted permissions
    if (await Permission.phone.isGranted) capability += 5;
    if (await Permission.sms.isGranted) capability += 5;
    if (await Permission.contacts.isGranted) capability += 5;
    if (await Permission.location.isGranted) capability += 5;
    if (await Permission.storage.isGranted) capability += 10;

    // Special permissions
    if (specialPermissions.hasUsageStats) capability += 15;
    if (specialPermissions.hasAccessibility) capability += 10;

    // Root/elevated access
    if (_hasRootAccess) capability += 15;

    setState(() {
      _detectionCapability = capability.clamp(0, 100);
    });
  }

  Future<void> _startScan({bool deepScan = false}) async {
    // Check if we have enough permissions
    if (_detectionCapability < 50) {
      _showPermissionWarning();
      return;
    }

    setState(() {
      _isScanning = true;
      _threats.clear();
      _scanProgress = ScanProgress();
    });

    try {
      await platform.invokeMethod('initializeScan', {
        'deepScan': deepScan || _hasRootAccess,
        'hasRoot': _hasRootAccess,
      });

      // Run all scan phases
      await _runScanPhase('Network Analysis', _scanNetwork);
      await _runScanPhase('Process Inspection', _scanProcesses);
      await _runScanPhase('File System Check', _scanFileSystem);
      await _runScanPhase('Database Analysis', _scanDatabases);
      await _runScanPhase('Memory Analysis', _scanMemory);

      // Advanced detection modules
      await _runScanPhase('Behavioral Analysis', () async {
        try {
          final behavioral = await advancedDetection.runModule('behavioral');
          _addThreats(behavioral);
        } catch (e) {
          print('Behavioral analysis error: $e');
        }
      });

      await _runScanPhase('Certificate Analysis', () async {
        try {
          final certs = await advancedDetection.runModule('certificate');
          _addThreats(certs);
        } catch (e) {
          print('Certificate analysis error: $e');
        }
      });

      await _runScanPhase('Permission Analysis', () async {
        try {
          final perms = await advancedDetection.runModule('permission');
          _addThreats(perms);
        } catch (e) {
          print('Permission analysis error: $e');
        }
      });

      await _runScanPhase('Accessibility Check', () async {
        try {
          final access = await advancedDetection.runModule('accessibility');
          _addThreats(access);
        } catch (e) {
          print('Accessibility check error: $e');
        }
      });

      await _runScanPhase('Keylogger Detection', () async {
        try {
          final keyloggers = await advancedDetection.runModule('keylogger');
          _addThreats(keyloggers);
        } catch (e) {
          print('Keylogger detection error: $e');
        }
      });

      await _runScanPhase('Location Stalker', () async {
        try {
          final location = await advancedDetection.runModule('location');
          _addThreats(location);
        } catch (e) {
          print('Location stalker detection error: $e');
        }
      });

      // Cloud intelligence matching
      await _runScanPhase('Cloud Intelligence', _matchCloudIntelligence);

      setState(() {
        _isScanning = false;
      });

      _showScanResults();
    } catch (e) {
      setState(() {
        _isScanning = false;
      });
      _showError('Scan failed: $e');
    }
  }

  Future<void> _runScanPhase(
    String phase,
    Future<void> Function() scanFunc,
  ) async {
    setState(() {
      _scanProgress.currentPhase = phase;
    });
    await scanFunc();
  }

  Future<void> _scanNetwork() async {
    try {
      final result = await platform.invokeMethod('scanNetwork');
      final threats = _parseThreatData(result['threats']);
      setState(() {
        _threats.addAll(threats);
        _scanProgress.networkComplete = true;
      });
    } catch (e) {
      print('Network scan error: $e');
      setState(() {
        _scanProgress.networkComplete = true;
      });
    }
  }

  Future<void> _scanProcesses() async {
    try {
      final result = await platform.invokeMethod('scanProcesses');
      final threats = _parseThreatData(result['threats']);
      setState(() {
        _threats.addAll(threats);
        _scanProgress.processComplete = true;
      });
    } catch (e) {
      print('Process scan error: $e');
      setState(() {
        _scanProgress.processComplete = true;
      });
    }
  }

  Future<void> _scanFileSystem() async {
    try {
      final result = await platform.invokeMethod('scanFileSystem');
      final threats = _parseThreatData(result['threats']);
      setState(() {
        _threats.addAll(threats);
        _scanProgress.fileSystemComplete = true;
      });
    } catch (e) {
      print('File system scan error: $e');
      setState(() {
        _scanProgress.fileSystemComplete = true;
      });
    }
  }

  Future<void> _scanDatabases() async {
    try {
      final result = await platform.invokeMethod('scanDatabases');
      final threats = _parseThreatData(result['threats']);
      setState(() {
        _threats.addAll(threats);
        _scanProgress.databaseComplete = true;
      });
    } catch (e) {
      print('Database scan error: $e');
      setState(() {
        _scanProgress.databaseComplete = true;
      });
    }
  }

  Future<void> _scanMemory() async {
    try {
      final result = await platform.invokeMethod('scanMemory');
      final threats = _parseThreatData(result['threats']);
      setState(() {
        _threats.addAll(threats);
        _scanProgress.memoryComplete = true;
      });
    } catch (e) {
      print('Memory scan error: $e');
      setState(() {
        _scanProgress.memoryComplete = true;
      });
    }
  }

  void _addThreats(List<Map<String, dynamic>> threats) {
    setState(() {
      _threats.addAll(threats.map((t) => ThreatDetection.fromJson(t)));
    });
  }

  Future<void> _matchCloudIntelligence() async {
    for (final threat in _threats) {
      bool isKnown = false;

      switch (threat.type) {
        case 'network':
          isKnown = threatIntel.isDomainMalicious(threat.path);
          break;
        case 'process':
          isKnown = threatIntel.isProcessMalicious(threat.path);
          break;
        case 'package':
          isKnown = threatIntel.isPackageMalicious(threat.path);
          break;
      }

      if (isKnown) {
        threat.severity = 'CRITICAL';
        final details = threatIntel.getIndicatorDetails(
          threat.path,
          _mapToIndicatorType(threat.type),
        );

        if (details != null) {
          threat.metadata.addAll({
            'verifiedByCloudIntel': true,
            'sources': details.sources,
            'reportCount': details.reportCount,
            'tags': details.tags,
          });
        }
      }
    }

    setState(() {
      _scanProgress.iocComplete = true;
    });
  }

  IndicatorType _mapToIndicatorType(String type) {
    switch (type) {
      case 'network':
        return IndicatorType.domain;
      case 'process':
        return IndicatorType.processName;
      case 'package':
        return IndicatorType.packageName;
      default:
        return IndicatorType.domain;
    }
  }

  List<ThreatDetection> _parseThreatData(dynamic data) {
    if (data == null) return [];
    List<ThreatDetection> threats = [];
    for (var item in data) {
      threats.add(ThreatDetection.fromJson(item));
    }
    return threats;
  }

  void _showScanResults() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanResultsScreen(threats: _threats),
      ),
    );
  }

  void _showPermissionWarning() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Limited Detection'),
        content: Text(
          'Current detection capability: ${_detectionCapability.round()}%\n\n'
          'For comprehensive scanning, please grant additional permissions.\n\n'
          'Would you like to set up permissions now?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToPermissionSetup();
            },
            child: const Text('Setup Permissions'),
          ),
        ],
      ),
    );
  }

  void _navigateToPermissionSetup() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PermissionSetupScreen(),
      ),
    );

    if (result == true) {
      await _checkAllPermissions();
      await _calculateDetectionCapability();
      setState(() {});
    }
  }

  Future<void> _removeThreat(ThreatDetection threat) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Threat'),
        content: Text(
          'Are you sure you want to remove:\n\n'
          '${threat.name}\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await _executeRemoval(threat);
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Future<void> _executeRemoval(ThreatDetection threat) async {
    try {
      final result = await platform.invokeMethod('removeThreat', {
        'id': threat.id,
        'type': threat.type,
        'path': threat.path,
        'requiresRoot': threat.requiresRoot,
      });

      if (result['success']) {
        setState(() {
          _threats.remove(threat);
        });
        _showSuccess('Threat removed successfully');
      } else {
        _showError('Failed to remove threat');
      }
    } catch (e) {
      _showError('Removal failed: $e');
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OrbGuard - Spyware Defense'),
        elevation: 0,
        actions: [
          // Permission setup button
          IconButton(
            icon: Icon(
              Icons.security,
              color: _detectionCapability >= 80
                  ? Colors.green
                  : _detectionCapability >= 50
                      ? Colors.orange
                      : Colors.red,
            ),
            onPressed: _navigateToPermissionSetup,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showAboutDialog(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Detection capability banner
            if (_permissionsChecked && _detectionCapability < 80)
              _buildCapabilityBanner(),
            _buildStatusCard(),
            const SizedBox(height: 16),
            _buildDeviceInfoCard(),
            const SizedBox(height: 16),
            _buildAccessLevelCard(),
            const SizedBox(height: 16),
            _buildDetectionCapabilityCard(),
            const SizedBox(height: 16),
            _buildScanButton(),
            const SizedBox(height: 16),
            if (_isScanning) _buildScanProgress(),
            if (_threats.isNotEmpty) _buildThreatsSummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilityBanner() {
    Color bannerColor = _detectionCapability >= 50 ? Colors.orange : Colors.red;

    return Card(
      color: bannerColor.withOpacity(0.2),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.warning, color: bannerColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Detection capability at ${_detectionCapability.round()}%. Grant permissions for full protection.',
                style: TextStyle(color: bannerColor),
              ),
            ),
            TextButton(
              onPressed: _navigateToPermissionSetup,
              child: const Text('Setup'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final criticalThreats =
        _threats.where((t) => t.severity == 'CRITICAL').length;
    final highThreats = _threats.where((t) => t.severity == 'HIGH').length;

    Color statusColor = Colors.green;
    String statusText = 'Protected';
    IconData statusIcon = Icons.shield;

    if (criticalThreats > 0) {
      statusColor = Colors.red;
      statusText = 'Critical Threats Detected';
      statusIcon = Icons.error;
    } else if (highThreats > 0) {
      statusColor = Colors.orange;
      statusText = 'Threats Detected';
      statusIcon = Icons.warning;
    }

    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(statusIcon, size: 64, color: statusColor),
            const SizedBox(height: 12),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            if (_threats.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildThreatCount('Critical', criticalThreats, Colors.red),
                  _buildThreatCount('High', highThreats, Colors.orange),
                  _buildThreatCount(
                    'Medium',
                    _threats.where((t) => t.severity == 'MEDIUM').length,
                    Colors.yellow,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThreatCount(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Device Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(_deviceInfo, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessLevelCard() {
    Color chipColor = Colors.blue;
    String description = '';

    switch (_accessLevel) {
      case 'Root':
        chipColor = Colors.green;
        description = '✓ Root access detected\n'
            '✓ Full system privileges\n'
            '✓ Deep scanning enabled\n'
            '✓ Advanced threat removal';
        break;
      case 'Shell':
        chipColor = Colors.cyan;
        description = '✓ Shell access enabled (Shizuku method)\n'
            '✓ Elevated privileges active\n'
            '✓ Deep scanning available\n'
            '✓ System file access granted';
        break;
      case 'AppProcess':
        chipColor = Colors.orange;
        description = '✓ System service access\n'
            '✓ Enhanced scanning enabled\n'
            '✓ Process inspection active\n'
            '✓ Network monitoring enhanced';
        break;
      default:
        chipColor = Colors.blue;
        description = '✓ Standard protection active\n'
            '✓ Behavioral analysis enabled\n'
            '✓ Network monitoring active\n'
            '✓ App scanning enabled';
    }

    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'System Access Level',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Chip(
                  label: Text(_accessLevel),
                  backgroundColor: chipColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(description, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildDetectionCapabilityCard() {
    Color capabilityColor = _detectionCapability >= 80
        ? Colors.green
        : _detectionCapability >= 50
            ? Colors.orange
            : Colors.red;

    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Detection Capability',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_detectionCapability.round()}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: capabilityColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _detectionCapability / 100,
              backgroundColor: Colors.grey[800],
              color: capabilityColor,
              minHeight: 10,
            ),
            const SizedBox(height: 8),
            Text(
              _detectionCapability >= 80
                  ? '✓ Full protection active'
                  : _detectionCapability >= 50
                      ? '⚠️ Partial protection - grant more permissions'
                      : '❌ Limited protection - setup required',
              style: TextStyle(fontSize: 12, color: capabilityColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return ElevatedButton.icon(
      onPressed: _isScanning ? null : () => _startScan(),
      icon: Icon(_isScanning ? Icons.hourglass_empty : Icons.search, size: 32),
      label: Text(
        _isScanning ? 'Scanning...' : 'Start Security Scan',
        style: const TextStyle(fontSize: 20),
      ),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.all(20),
        backgroundColor: const Color(0xFF00D9FF),
        foregroundColor: Colors.black,
      ),
    );
  }

  Widget _buildScanProgress() {
    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Scanning: ${_scanProgress.currentPhase}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildProgressItem(
                'Network Analysis', _scanProgress.networkComplete),
            _buildProgressItem(
                'Process Inspection', _scanProgress.processComplete),
            _buildProgressItem(
                'File System Check', _scanProgress.fileSystemComplete),
            _buildProgressItem(
                'Database Analysis', _scanProgress.databaseComplete),
            _buildProgressItem('Memory Analysis', _scanProgress.memoryComplete),
            _buildProgressItem(
                'Advanced Detection', _scanProgress.advancedComplete),
            _buildProgressItem('Cloud Intelligence', _scanProgress.iocComplete),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressItem(String label, bool complete) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            complete ? Icons.check_circle : Icons.hourglass_empty,
            color: complete ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildThreatsSummary() {
    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detected Threats',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...(_threats.take(3).map((threat) => ListTile(
                  leading: Icon(
                    Icons.error,
                    color: threat.severity == 'CRITICAL'
                        ? Colors.red
                        : threat.severity == 'HIGH'
                            ? Colors.orange
                            : Colors.yellow,
                  ),
                  title: Text(threat.name),
                  subtitle: Text(threat.description),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeThreat(threat),
                  ),
                ))),
            if (_threats.length > 3)
              TextButton(
                onPressed: _showScanResults,
                child: Text('View All ${_threats.length} Threats'),
              ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About OrbGuard'),
        content: const Text(
          'OrbGuard - Advanced Spyware Defense\n\n'
          'Detects and removes sophisticated threats including Pegasus using multiple access methods:\n\n'
          '• Root Access (if available)\n'
          '• Shell Access (Shizuku method integrated)\n'
          '• System Services (app_process)\n'
          '• Standard APIs\n\n'
          '✓ No external apps required\n'
          '✓ All scanning happens locally\n'
          '✓ No data sent to servers\n'
          '✓ Automatic privilege escalation\n'
          '✓ Cloud threat intelligence\n'
          '✓ Special permissions for enhanced detection\n\n'
          'Your privacy and security are our priority.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// Data Models
class ThreatDetection {
  final String id;
  String name;
  String description;
  String severity;
  final String type;
  final String path;
  final bool requiresRoot;
  final Map<String, dynamic> metadata;

  ThreatDetection({
    required this.id,
    required this.name,
    required this.description,
    required this.severity,
    required this.type,
    required this.path,
    required this.requiresRoot,
    required this.metadata,
  });

  factory ThreatDetection.fromJson(Map<String, dynamic> json) {
    return ThreatDetection(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      severity: json['severity'] ?? 'MEDIUM',
      type: json['type'] ?? '',
      path: json['path'] ?? '',
      requiresRoot: json['requiresRoot'] ?? false,
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'severity': severity,
      'type': type,
      'path': path,
      'requiresRoot': requiresRoot,
      'metadata': metadata,
    };
  }
}

class ScanProgress {
  String currentPhase = '';
  bool networkComplete = false;
  bool processComplete = false;
  bool fileSystemComplete = false;
  bool databaseComplete = false;
  bool memoryComplete = false;
  bool advancedComplete = false;
  bool iocComplete = false;
}
