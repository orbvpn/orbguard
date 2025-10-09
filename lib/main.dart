// main.dart - Complete Anti-Spyware Defense System
// Platform: Flutter (iOS, Android, macOS, Windows)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  runApp(const AntiSpywareApp());
}

class AntiSpywareApp extends StatelessWidget {
  const AntiSpywareApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pegasus Defense',
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
  static const platform = MethodChannel('com.defense.antispyware/system');

  bool _isScanning = false;
  bool _hasRootAccess = false;
  String _deviceInfo = '';
  String _accessLevel = 'Limited';
  List<ThreatDetection> _threats = [];
  ScanProgress _scanProgress = ScanProgress();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _checkDeviceInfo();
    await _checkSystemAccess();
  }

  Future<void> _checkDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String info = '';

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      info =
          'Android ${androidInfo.version.release}\n'
          'Model: ${androidInfo.model}\n'
          'Security Patch: ${androidInfo.version.securityPatch ?? "Unknown"}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      info =
          'iOS ${iosInfo.systemVersion}\n'
          'Model: ${iosInfo.model}\n'
          'Device: ${iosInfo.name}';
    } else if (Platform.isMacOS) {
      final macInfo = await deviceInfo.macOsInfo;
      info =
          'macOS ${macInfo.osRelease}\n'
          'Model: ${macInfo.model}';
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      info =
          'Windows ${windowsInfo.displayVersion}\n'
          'Build: ${windowsInfo.buildNumber}';
    }

    setState(() {
      _deviceInfo = info;
    });
  }

  Future<void> _checkSystemAccess() async {
    try {
      // Check for elevated access
      final result = await platform.invokeMethod('checkRootAccess');
      setState(() {
        _hasRootAccess = result['hasRoot'] ?? false;
        _accessLevel = result['accessLevel'] ?? 'Limited';
      });
    } catch (e) {
      setState(() {
        _accessLevel = 'Limited';
      });
    }
  }

  Future<void> _requestSystemAccess() async {
    if (Platform.isAndroid) {
      await _requestAndroidAccess();
    } else if (Platform.isIOS) {
      await _requestIOSAccess();
    } else if (Platform.isMacOS || Platform.isWindows) {
      await _requestDesktopAccess();
    }
  }

  Future<void> _requestAndroidAccess() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enhanced System Access'),
        content: const Text(
          'For comprehensive scanning, this app needs:\n\n'
          '1. Root Access (optional but recommended)\n'
          '2. Accessibility Service\n'
          '3. Usage Access\n'
          '4. Device Admin Permission\n\n'
          'All data stays on your device. Would you like to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _enableAndroidPermissions();
            },
            child: const Text('Grant Access'),
          ),
        ],
      ),
    );
  }

  Future<void> _enableAndroidPermissions() async {
    // Request standard permissions first
    await Permission.storage.request();
    await Permission.phone.request();
    await Permission.sms.request();

    // Guide user to enable advanced permissions
    try {
      await platform.invokeMethod('requestAccessibilityService');
      await platform.invokeMethod('requestUsageAccess');
      await platform.invokeMethod('requestDeviceAdmin');

      // Check for root
      final hasRoot = await platform.invokeMethod('checkRootAccess');
      if (!hasRoot['hasRoot']) {
        _showRootInstructions();
      } else {
        await _checkSystemAccess();
      }
    } catch (e) {
      _showError('Failed to enable permissions: $e');
    }
  }

  Future<void> _requestIOSAccess() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('iOS System Access'),
        content: const Text(
          'iOS restricts deep system access by design.\n\n'
          'Options for enhanced scanning:\n\n'
          '1. ✅ Standard Scan (Available Now)\n'
          '   • Network monitoring\n'
          '   • Behavioral analysis\n'
          '   • Permission audit\n\n'
          '2. ⚡ Deep Scan (Requires Jailbreak)\n'
          '   • Full system file access\n'
          '   • Process inspection\n'
          '   • Root-level detection\n\n'
          'Note: Jailbreaking is YOUR choice and is legal on YOUR device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showJailbreakInstructions();
            },
            child: const Text('Jailbreak Guide'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startScan(deepScan: false);
            },
            child: const Text('Standard Scan'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestDesktopAccess() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Administrator Access Required'),
        content: Text(
          Platform.isMacOS
              ? 'This app needs administrator privileges to:\n\n'
                    '• Monitor system processes\n'
                    '• Scan system files\n'
                    '• Capture network traffic\n'
                    '• Remove detected threats\n\n'
                    'You will be prompted for your password.'
              : 'This app needs administrator privileges to:\n\n'
                    '• Monitor system processes\n'
                    '• Scan system files\n'
                    '• Analyze network traffic\n'
                    '• Remove detected threats\n\n'
                    'Please run as administrator or grant UAC permission.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _requestAdminPrivileges();
            },
            child: const Text('Request Access'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestAdminPrivileges() async {
    try {
      final result = await platform.invokeMethod('requestAdminAccess');
      if (result['granted']) {
        await _checkSystemAccess();
        _showSuccess('Administrator access granted');
      } else {
        _showError('Administrator access denied');
      }
    } catch (e) {
      _showError('Failed to request admin access: $e');
    }
  }

  void _showRootInstructions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RootInstructionsScreen()),
    );
  }

  void _showJailbreakInstructions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const JailbreakInstructionsScreen(),
      ),
    );
  }

  Future<void> _startScan({bool deepScan = false}) async {
    setState(() {
      _isScanning = true;
      _threats.clear();
      _scanProgress = ScanProgress();
    });

    try {
      // Initialize scan
      await platform.invokeMethod('initializeScan', {
        'deepScan': deepScan,
        'hasRoot': _hasRootAccess,
      });

      // Run scan phases
      await _runScanPhase('Network Analysis', _scanNetwork);
      await _runScanPhase('Process Inspection', _scanProcesses);
      await _runScanPhase('File System Check', _scanFileSystem);
      await _runScanPhase('Database Analysis', _scanDatabases);
      await _runScanPhase('Memory Analysis', _scanMemory);
      await _runScanPhase('IoC Matching', _matchIndicators);

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
    }
  }

  Future<void> _scanMemory() async {
    if (!_hasRootAccess) {
      setState(() {
        _scanProgress.memoryComplete = true;
      });
      return;
    }

    try {
      final result = await platform.invokeMethod('scanMemory');
      final threats = _parseThreatData(result['threats']);
      setState(() {
        _threats.addAll(threats);
        _scanProgress.memoryComplete = true;
      });
    } catch (e) {
      print('Memory scan error: $e');
    }
  }

  Future<void> _matchIndicators() async {
    try {
      await platform.invokeMethod('matchIndicators', {
        'threats': _threats.map((t) => t.toJson()).toList(),
      });
      setState(() {
        _scanProgress.iocComplete = true;
      });
    } catch (e) {
      print('IoC matching error: $e');
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
        _showError('Failed to remove threat: ${result['error']}');
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
        title: const Text('Pegasus Defense System'),
        elevation: 0,
        actions: [
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
            // Status Card
            _buildStatusCard(),
            const SizedBox(height: 16),

            // Device Info Card
            _buildDeviceInfoCard(),
            const SizedBox(height: 16),

            // Access Level Card
            _buildAccessLevelCard(),
            const SizedBox(height: 16),

            // Scan Button
            _buildScanButton(),
            const SizedBox(height: 16),

            // Scan Progress
            if (_isScanning) _buildScanProgress(),

            // Threats Summary
            if (_threats.isNotEmpty) _buildThreatsSummary(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final criticalThreats = _threats
        .where((t) => t.severity == 'CRITICAL')
        .length;
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
                  backgroundColor: _hasRootAccess
                      ? Colors.green
                      : Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _hasRootAccess
                  ? '✓ Full system access enabled\n✓ Deep scanning available\n✓ Threat removal enabled'
                  : '⚠ Limited access mode\n• Basic scanning available\n• Enable enhanced access for deep scan',
              style: const TextStyle(fontSize: 14),
            ),
            if (!_hasRootAccess) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _requestSystemAccess,
                icon: const Icon(Icons.security),
                label: const Text('Enable Enhanced Access'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScanButton() {
    return ElevatedButton.icon(
      onPressed: _isScanning
          ? null
          : () => _startScan(deepScan: _hasRootAccess),
      icon: const Icon(Icons.search, size: 32),
      label: Text(
        _isScanning ? 'Scanning...' : 'Start Scan',
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
              'Network Analysis',
              _scanProgress.networkComplete,
            ),
            _buildProgressItem(
              'Process Inspection',
              _scanProgress.processComplete,
            ),
            _buildProgressItem(
              'File System Check',
              _scanProgress.fileSystemComplete,
            ),
            _buildProgressItem(
              'Database Analysis',
              _scanProgress.databaseComplete,
            ),
            _buildProgressItem('Memory Analysis', _scanProgress.memoryComplete),
            _buildProgressItem('IoC Matching', _scanProgress.iocComplete),
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
            ...(_threats
                .take(3)
                .map(
                  (threat) => ListTile(
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
                  ),
                )),
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
        title: const Text('About'),
        content: const Text(
          'Pegasus Defense System\n\n'
          'A comprehensive anti-spyware tool that detects and removes '
          'sophisticated spyware including Pegasus.\n\n'
          'All scanning and analysis happens locally on your device. '
          'No data is sent to external servers.\n\n'
          'For best results, grant enhanced system access.',
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
  final String name;
  final String description;
  final String severity;
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
      metadata: json['metadata'] ?? {},
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
  bool iocComplete = false;
}

// Additional screens will be in separate files:
// - RootInstructionsScreen
// - JailbreakInstructionsScreen
// - ScanResultsScreen
