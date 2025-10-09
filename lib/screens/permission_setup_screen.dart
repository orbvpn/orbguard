// lib/screens/permission_setup_screen.dart
// Interactive permission setup with explanations

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../permissions/permission_manager.dart';

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({Key? key}) : super(key: key);

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  final PermissionManager _permissionManager = PermissionManager();
  PermissionScanResult? _scanResult;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isChecking = true);

    final result = await _permissionManager.checkAllPermissions();

    setState(() {
      _scanResult = result;
      _isChecking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permission Setup'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissions,
          ),
        ],
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : _scanResult == null
              ? const Center(child: Text('Loading...'))
              : _buildPermissionList(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildPermissionList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildDetectionCapabilityCard(),
        const SizedBox(height: 24),

        // Essential Permissions
        _buildGroupHeader('Essential Permissions', Icons.security),
        const Text(
          'Required for basic threat detection',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildPermissionCard(
          'Storage Access',
          'Scan files for malware and threats',
          Permission.storage,
          Icons.folder,
        ),
        _buildPermissionCard(
          'Phone State',
          'Monitor device for suspicious modifications',
          Permission.phone,
          Icons.phone_android,
        ),

        const SizedBox(height: 24),

        // Advanced Permissions
        _buildGroupHeader('Advanced Detection', Icons.search),
        const Text(
          'Enables deep threat analysis',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildPermissionCard(
          'SMS Access',
          'Detect SMS-based exploits (Pegasus)',
          Permission.sms,
          Icons.sms,
        ),
        _buildPermissionCard(
          'Location',
          'Detect location stalking behavior',
          Permission.location,
          Icons.location_on,
        ),

        const SizedBox(height: 24),

        // Special Permissions
        _buildGroupHeader('Special Permissions', Icons.settings),
        const Text(
          'Requires manual activation in Settings',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        _buildSpecialPermissionCard(
          'Usage Stats',
          'Monitor app behavior patterns',
          _scanResult!.granted.contains('Usage Stats'),
          () => _requestUsageStats(),
        ),
        _buildSpecialPermissionCard(
          'Accessibility',
          'Detect malicious accessibility services',
          _scanResult!.granted.contains('Accessibility'),
          () => _requestAccessibility(),
        ),

        const SizedBox(height: 80), // Space for bottom bar
      ],
    );
  }

  Widget _buildDetectionCapabilityCard() {
    final capability = _scanResult!.detectionCapability;
    Color color;
    String status;
    IconData icon;

    if (capability >= 80) {
      color = Colors.green;
      status = 'Excellent';
      icon = Icons.check_circle;
    } else if (capability >= 50) {
      color = Colors.orange;
      status = 'Good';
      icon = Icons.warning;
    } else {
      color = Colors.red;
      status = 'Limited';
      icon = Icons.error;
    }

    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Detection Capability',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        status,
                        style: TextStyle(color: color, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Text(
                  '$capability%',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: capability / 100,
                minHeight: 8,
                backgroundColor: Colors.grey[800],
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_scanResult!.granted.length} of ${_scanResult!.totalPermissions} permissions granted',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionCard(
    String name,
    String description,
    Permission permission,
    IconData icon,
  ) {
    return FutureBuilder<PermissionStatus>(
      future: permission.status,
      builder: (context, snapshot) {
        final isGranted = snapshot.data?.isGranted ?? false;
        final isDenied = snapshot.data?.isPermanentlyDenied ?? false;

        return Card(
          color: const Color(0xFF1D1E33),
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(icon, color: isGranted ? Colors.green : Colors.grey),
            title: Text(name),
            subtitle: Text(description, style: const TextStyle(fontSize: 12)),
            trailing: isGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : isDenied
                    ? const Icon(Icons.block, color: Colors.red)
                    : ElevatedButton(
                        onPressed: () => _requestPermission(permission, name),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text('Grant'),
                      ),
          ),
        );
      },
    );
  }

  Widget _buildSpecialPermissionCard(
    String name,
    String description,
    bool isGranted,
    VoidCallback onRequest,
  ) {
    return Card(
      color: const Color(0xFF1D1E33),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          Icons.settings,
          color: isGranted ? Colors.green : Colors.orange,
        ),
        title: Text(name),
        subtitle: Text(description, style: const TextStyle(fontSize: 12)),
        trailing: isGranted
            ? const Icon(Icons.check_circle, color: Colors.green)
            : ElevatedButton(
                onPressed: onRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: const Text('Enable'),
              ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final allEssential = _scanResult?.hasAllEssential ?? false;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1E33),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!allEssential)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Grant essential permissions to enable scanning',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed:
                      allEssential ? _grantAllRemaining : _grantEssential,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D9FF),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: Text(
                    allEssential ? 'Grant All Remaining' : 'Grant Essential',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
              if (allEssential) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.all(16),
                  ),
                  child: const Text('Continue'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // PERMISSION REQUEST HANDLERS
  // ============================================================================

  Future<void> _grantEssential() async {
    final results = await _permissionManager.requestEssentialPermissions();

    // Show results
    final granted = results.values.where((s) => s.isGranted).length;
    final total = results.length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Granted $granted of $total essential permissions'),
          backgroundColor: granted == total ? Colors.green : Colors.orange,
        ),
      );

      await _checkPermissions();
    }
  }

  Future<void> _grantAllRemaining() async {
    final results = await _permissionManager.requestAdvancedPermissions();

    final granted = results.values.where((s) => s.isGranted).length;
    final total = results.length;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Granted $granted of $total advanced permissions'),
          backgroundColor: granted == total ? Colors.green : Colors.orange,
        ),
      );

      await _checkPermissions();
    }
  }

  Future<void> _requestPermission(Permission permission, String name) async {
    final status = await _permissionManager.requestPermissionWithRationale(
      context: context,
      permission: permission,
      title: 'Grant $name',
      explanation: _getPermissionExplanation(permission),
      benefit: _getPermissionBenefit(permission),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status.isGranted ? '$name granted!' : '$name denied',
          ),
          backgroundColor: status.isGranted ? Colors.green : Colors.red,
        ),
      );

      await _checkPermissions();
    }
  }

  Future<void> _requestUsageStats() async {
    final success =
        await _permissionManager.requestUsageStatsPermission(context);
    if (success) {
      // Wait a bit for user to grant in Settings, then check again
      await Future.delayed(const Duration(seconds: 2));
      await _checkPermissions();
    }
  }

  Future<void> _requestAccessibility() async {
    final success =
        await _permissionManager.requestAccessibilityPermission(context);
    if (success) {
      await Future.delayed(const Duration(seconds: 2));
      await _checkPermissions();
    }
  }

  // ============================================================================
  // PERMISSION EXPLANATIONS
  // ============================================================================

  String _getPermissionExplanation(Permission permission) {
    final explanations = {
      Permission.storage:
          'OrbGuard needs to scan your files and installed apps to detect malware, suspicious modifications, and hidden threats.',
      Permission.phone:
          'This allows monitoring of device state to detect system-level compromises and root/jailbreak modifications.',
      Permission.sms:
          'Pegasus and similar spyware often use SMS-based zero-click exploits. This permission lets us scan SMS databases for exploit patterns.',
      Permission.location:
          'Location permission helps detect apps that excessively track your location, a common behavior of stalkerware.',
    };
    return explanations[permission] ??
        'This permission enhances threat detection capabilities.';
  }

  String _getPermissionBenefit(Permission permission) {
    final benefits = {
      Permission.storage:
          'Enables detection of malware files, hidden spyware, and suspicious app modifications',
      Permission.phone: 'Detects system compromises and security bypasses',
      Permission.sms:
          'Critical for detecting SMS-based zero-click exploits like those used by Pegasus',
      Permission.location:
          'Identifies location stalking and excessive tracking behavior',
    };
    return benefits[permission] ?? 'Enhances overall security monitoring';
  }
}
