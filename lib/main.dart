// lib/main.dart - Complete with Special Permissions Integration
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'screens/scan_results_screen.dart';
import 'screens/permission_setup_screen.dart';
import 'screens/elevated_access_setup_screen.dart';
import 'screens/scanning_screen.dart';
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
  const AntiSpywareApp({super.key});

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
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const platform = MethodChannel('com.orb.guard/system');

  bool _isScanning = false;
  bool _hasRootAccess = false;
  String _deviceInfo = '';
  String _accessLevel = 'Standard';
  String _accessMethod = 'Standard';
  final List<ThreatDetection> _threats = [];
  ScanProgress _scanProgress = ScanProgress();
  double _detectionCapability = 0.0;
  bool _permissionsChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh permissions when app returns to foreground
    if (state == AppLifecycleState.resumed) {
      _refreshPermissions();
    }
  }

  Future<void> _refreshPermissions() async {
    await specialPermissions.checkPermissions();
    await _calculateDetectionCapability();
    setState(() {});
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
    double capability = 25.0;

    // Add capability based on granted permissions (45% total)
    if (await Permission.phone.isGranted) capability += 5;
    if (await Permission.sms.isGranted) capability += 10;
    if (await Permission.location.isGranted) capability += 5;

    // Storage - check via native method for Android 11+
    try {
      final storageResult = await platform.invokeMethod('checkStoragePermission');
      if (storageResult['hasPermission'] == true) capability += 10;
    } catch (e) {
      if (await Permission.storage.isGranted) capability += 10;
    }

    // Special permissions (25% total)
    if (specialPermissions.hasUsageStats) capability += 15;
    if (specialPermissions.hasAccessibility) capability += 10;

    // Enhanced/Root access (15% total)
    if (_hasRootAccess) {
      capability += 15;
    } else if (_accessMethod == 'Shell' || _accessMethod == 'AppProcess') {
      capability += 10;
    }

    setState(() {
      _detectionCapability = capability.clamp(0, 100);
    });
  }

  // Track scan metadata for results display
  int _lastScanItemsScanned = 0;
  Duration _lastScanDuration = Duration.zero;

  Future<void> _startScan({bool deepScan = false}) async {
    // Check if we have enough permissions
    if (_detectionCapability < 50) {
      _showPermissionWarning();
      return;
    }

    // Navigate to scanning screen
    final scanResult = await Navigator.push<ScanResult>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ScanningScreen(
          onScan: () => _performScan(deepScan: deepScan),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );

    if (scanResult != null && scanResult.threats.isNotEmpty) {
      print('[OrbGuard] Received ${scanResult.threats.length} threats from scan');
      setState(() {
        _threats.clear();
        for (var t in scanResult.threats) {
          final converted = ThreatDetection.fromJson(t);
          print('[OrbGuard] Converted: ${converted.name} (${converted.severity})');
          _threats.add(converted);
        }
        _lastScanItemsScanned = scanResult.itemsScanned;
        _lastScanDuration = scanResult.scanDuration;
      });
      print('[OrbGuard] Showing results with ${_threats.length} threats');
      _showScanResults();
    } else if (scanResult != null) {
      // Scan completed with no threats
      print('[OrbGuard] Scan completed with no threats');
      setState(() {
        _lastScanItemsScanned = scanResult.itemsScanned;
        _lastScanDuration = scanResult.scanDuration;
      });
      _showNoThreatsDialog();
    }
  }

  Future<List<Map<String, dynamic>>> _performScan({bool deepScan = false}) async {
    List<Map<String, dynamic>> allThreats = [];

    try {
      await platform.invokeMethod('initializeScan', {
        'deepScan': deepScan || _hasRootAccess,
        'hasRoot': _hasRootAccess,
      });
    } catch (e) {
      print('Initialize scan error: $e');
    }

    // Run native scans
    try {
      final result = await platform.invokeMethod('scanNetwork');
      if (result['threats'] != null) {
        for (var threat in result['threats']) {
          allThreats.add(Map<String, dynamic>.from(threat));
        }
      }
    } catch (e) {
      print('Network scan error: $e');
    }

    try {
      final result = await platform.invokeMethod('scanProcesses');
      if (result['threats'] != null) {
        for (var threat in result['threats']) {
          allThreats.add(Map<String, dynamic>.from(threat));
        }
      }
    } catch (e) {
      print('Process scan error: $e');
    }

    try {
      final result = await platform.invokeMethod('scanFileSystem');
      if (result['threats'] != null) {
        for (var threat in result['threats']) {
          allThreats.add(Map<String, dynamic>.from(threat));
        }
      }
    } catch (e) {
      print('File system scan error: $e');
    }

    try {
      final result = await platform.invokeMethod('scanDatabases');
      if (result['threats'] != null) {
        for (var threat in result['threats']) {
          allThreats.add(Map<String, dynamic>.from(threat));
        }
      }
    } catch (e) {
      print('Database scan error: $e');
    }

    try {
      final result = await platform.invokeMethod('scanMemory');
      if (result['threats'] != null) {
        for (var threat in result['threats']) {
          allThreats.add(Map<String, dynamic>.from(threat));
        }
      }
    } catch (e) {
      print('Memory scan error: $e');
    }

    // Advanced detection modules
    try {
      final behavioral = await advancedDetection.runModule('behavioral');
      allThreats.addAll(behavioral);
    } catch (e) {
      print('Behavioral analysis error: $e');
    }

    try {
      final certs = await advancedDetection.runModule('certificate');
      allThreats.addAll(certs);
    } catch (e) {
      print('Certificate analysis error: $e');
    }

    try {
      final perms = await advancedDetection.runModule('permission');
      allThreats.addAll(perms);
    } catch (e) {
      print('Permission analysis error: $e');
    }

    try {
      final access = await advancedDetection.runModule('accessibility');
      allThreats.addAll(access);
    } catch (e) {
      print('Accessibility check error: $e');
    }

    try {
      final keyloggers = await advancedDetection.runModule('keylogger');
      allThreats.addAll(keyloggers);
    } catch (e) {
      print('Keylogger detection error: $e');
    }

    try {
      final location = await advancedDetection.runModule('location');
      allThreats.addAll(location);
    } catch (e) {
      print('Location stalker detection error: $e');
    }

    // Debug: Log scan results
    print('[OrbGuard] Scan complete: ${allThreats.length} threats detected');
    for (var threat in allThreats) {
      print('[OrbGuard] Threat: ${threat['name']} (${threat['severity']})');
    }

    return allThreats;
  }

  void _showNoThreatsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1D1E33),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withOpacity(0.2),
              ),
              child: const Icon(
                Icons.verified_user,
                size: 48,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'All Clear!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'No threats were detected on your device. Your device appears to be secure.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Great!'),
              ),
            ),
          ],
        ),
      ),
    );
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
        builder: (context) => ScanResultsScreen(
          threats: _threats,
          itemsScanned: _lastScanItemsScanned,
          scanDuration: _lastScanDuration,
        ),
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
            _buildDetectionCapabilityCard(),
            const SizedBox(height: 16),
            _buildScanButton(),
            const SizedBox(height: 16),
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

  Widget _buildDetectionCapabilityCard() {
    Color capabilityColor = _detectionCapability >= 80
        ? Colors.green
        : _detectionCapability >= 50
            ? Colors.orange
            : Colors.red;

    return Card(
      color: const Color(0xFF1D1E33),
      child: InkWell(
        onTap: _navigateToPermissionSetup,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        _detectionCapability >= 80
                            ? Icons.verified_user
                            : _detectionCapability >= 50
                                ? Icons.shield
                                : Icons.warning,
                        color: capabilityColor,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Detection Capability',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Text(
                    '${_detectionCapability.round()}%',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: capabilityColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: _detectionCapability / 100,
                  backgroundColor: Colors.grey[800],
                  color: capabilityColor,
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 12),
              // Status breakdown
              _buildCapabilityBreakdown(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _detectionCapability >= 80
                        ? 'Full protection active'
                        : 'Tap to configure permissions',
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey[600], size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCapabilityBreakdown() {
    return FutureBuilder<List<_CapabilityItem>>(
      future: _getCapabilityItems(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final items = snapshot.data!;

        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: items.map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: item.enabled
                    ? Colors.green.withAlpha(30)
                    : Colors.grey.withAlpha(30),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: item.enabled
                      ? Colors.green.withAlpha(100)
                      : Colors.grey.withAlpha(50),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item.enabled ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 14,
                    color: item.enabled ? Colors.green : Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 11,
                      color: item.enabled ? Colors.green[300] : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<List<_CapabilityItem>> _getCapabilityItems() async {
    bool hasStorage = false;
    try {
      final storageResult = await platform.invokeMethod('checkStoragePermission');
      hasStorage = storageResult['hasPermission'] == true;
    } catch (e) {
      hasStorage = await Permission.storage.isGranted;
    }

    final hasEnhanced = _hasRootAccess || _accessMethod == 'Shell' || _accessMethod == 'AppProcess';
    final enhancedLabel = _hasRootAccess ? 'Root' : (_accessMethod == 'Shell' ? 'Shell' : 'Enhanced');

    return [
      _CapabilityItem('Storage', hasStorage),
      _CapabilityItem('SMS', await Permission.sms.isGranted),
      _CapabilityItem('Phone', await Permission.phone.isGranted),
      _CapabilityItem('Location', await Permission.location.isGranted),
      _CapabilityItem('Usage', specialPermissions.hasUsageStats),
      _CapabilityItem('Accessibility', specialPermissions.hasAccessibility),
      _CapabilityItem(enhancedLabel, hasEnhanced),
    ];
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

class _CapabilityItem {
  final String name;
  final bool enabled;

  _CapabilityItem(this.name, this.enabled);
}
