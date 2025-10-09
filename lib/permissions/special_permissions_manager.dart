// lib/permissions/special_permissions_manager.dart
// Handles Usage Stats and Accessibility permissions

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

class SpecialPermissionsManager {
  static const platform = MethodChannel('com.orb.guard/system');

  // Permission status
  bool _hasUsageStats = false;
  bool _hasAccessibility = false;

  bool get hasUsageStats => _hasUsageStats;
  bool get hasAccessibility => _hasAccessibility;
  bool get hasAllSpecialPermissions => _hasUsageStats && _hasAccessibility;

  /// Check all special permissions status
  Future<void> checkPermissions() async {
    if (Platform.isAndroid) {
      _hasUsageStats = await checkUsageStatsPermission();
      _hasAccessibility = await checkAccessibilityPermission();
    } else if (Platform.isIOS) {
      // iOS doesn't have these exact permissions
      // We check for equivalent capabilities
      _hasUsageStats = false; // Not available on iOS
      _hasAccessibility = false; // Limited on iOS
    }
  }

  /// Check if Usage Stats permission is granted
  Future<bool> checkUsageStatsPermission() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await platform.invokeMethod('checkUsageStatsPermission');
      return result['hasPermission'] ?? false;
    } catch (e) {
      print('Error checking usage stats permission: $e');
      return false;
    }
  }

  /// Check if Accessibility permission is granted
  Future<bool> checkAccessibilityPermission() async {
    if (!Platform.isAndroid) return false;

    try {
      final result =
          await platform.invokeMethod('checkAccessibilityPermission');
      return result['hasPermission'] ?? false;
    } catch (e) {
      print('Error checking accessibility permission: $e');
      return false;
    }
  }

  /// Request Usage Stats permission (opens Settings)
  Future<bool> requestUsageStatsPermission() async {
    if (!Platform.isAndroid) return false;

    try {
      await platform.invokeMethod('requestUsageStatsPermission');
      // Wait a bit for user to potentially grant permission
      await Future.delayed(const Duration(seconds: 1));
      // Check again after returning
      return await checkUsageStatsPermission();
    } catch (e) {
      print('Error requesting usage stats permission: $e');
      return false;
    }
  }

  /// Request Accessibility permission (opens Settings)
  Future<bool> requestAccessibilityPermission() async {
    if (!Platform.isAndroid) return false;

    try {
      await platform.invokeMethod('requestAccessibilityPermission');
      await Future.delayed(const Duration(seconds: 1));
      return await checkAccessibilityPermission();
    } catch (e) {
      print('Error requesting accessibility permission: $e');
      return false;
    }
  }

  /// Show permission rationale dialog
  Future<bool?> showPermissionRationale(
    BuildContext context,
    SpecialPermissionType type,
  ) async {
    String title;
    String description;
    List<String> capabilities;

    switch (type) {
      case SpecialPermissionType.usageStats:
        title = 'Usage Access Permission';
        description =
            'OrbGuard needs Usage Access to detect abnormal app behavior and suspicious activity patterns.';
        capabilities = [
          '✓ Detect apps running excessively in background',
          '✓ Identify unusual battery drain patterns',
          '✓ Monitor suspicious data usage',
          '✓ Track screen-on time anomalies',
          '✓ Detect behavioral deviations from baseline',
        ];
        break;

      case SpecialPermissionType.accessibility:
        title = 'Accessibility Detection';
        description =
            'OrbGuard needs to check for malicious accessibility services that could be used for spyware.';
        capabilities = [
          '✓ Detect unauthorized accessibility services',
          '✓ Identify keylogger attempts',
          '✓ Find screen capture malware',
          '✓ Detect click injection attacks',
          '✓ Monitor for overlay attacks',
        ];
        break;
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.security, color: Color(0xFF00D9FF)),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                description,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'This enables:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...capabilities.map(
                (cap) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(cap, style: const TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'OrbGuard only uses this to detect threats. Your data stays on your device.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D9FF),
              foregroundColor: Colors.black,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Get missing permissions list
  List<SpecialPermissionType> getMissingPermissions() {
    final missing = <SpecialPermissionType>[];
    if (!_hasUsageStats) missing.add(SpecialPermissionType.usageStats);
    if (!_hasAccessibility) missing.add(SpecialPermissionType.accessibility);
    return missing;
  }
}

enum SpecialPermissionType {
  usageStats,
  accessibility,
}

// Permission request screen
class SpecialPermissionsScreen extends StatefulWidget {
  final SpecialPermissionsManager permissionManager;

  const SpecialPermissionsScreen({
    Key? key,
    required this.permissionManager,
  }) : super(key: key);

  @override
  State<SpecialPermissionsScreen> createState() =>
      _SpecialPermissionsScreenState();
}

class _SpecialPermissionsScreenState extends State<SpecialPermissionsScreen> {
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() => _isChecking = true);
    await widget.permissionManager.checkPermissions();
    setState(() => _isChecking = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enhanced Detection Setup'),
        elevation: 0,
      ),
      body: _isChecking
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Card(
                  color: Color(0xFF1D1E33),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.security,
                                color: Color(0xFF00D9FF), size: 32),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Enhanced Threat Detection',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Text(
                          'For comprehensive spyware detection, OrbGuard needs additional permissions to analyze behavioral patterns and detect malicious accessibility services.',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Usage Stats Permission
                _buildPermissionCard(
                  type: SpecialPermissionType.usageStats,
                  title: 'Usage Access',
                  description: 'Monitor app behavior and detect anomalies',
                  icon: Icons.analytics,
                  isGranted: widget.permissionManager.hasUsageStats,
                  benefits: [
                    'Detect background spyware activity',
                    'Identify unusual battery drain',
                    'Monitor suspicious data usage',
                    'Track behavioral anomalies',
                  ],
                ),

                const SizedBox(height: 16),

                // Accessibility Permission
                _buildPermissionCard(
                  type: SpecialPermissionType.accessibility,
                  title: 'Accessibility Detection',
                  description: 'Scan for malicious accessibility services',
                  icon: Icons.accessibility,
                  isGranted: widget.permissionManager.hasAccessibility,
                  benefits: [
                    'Detect keylogger attempts',
                    'Find screen capture malware',
                    'Identify overlay attacks',
                    'Block click injection',
                  ],
                ),

                const SizedBox(height: 24),

                // Action buttons
                if (!widget.permissionManager.hasAllSpecialPermissions) ...[
                  ElevatedButton.icon(
                    onPressed: _requestAllPermissions,
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Grant All Permissions'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00D9FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    widget.permissionManager.hasAllSpecialPermissions
                        ? 'Continue'
                        : 'Skip for Now',
                  ),
                ),

                const SizedBox(height: 16),

                // Privacy note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.privacy_tip,
                              color: Colors.green, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Privacy First',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• All analysis happens on your device\n'
                        '• No personal data is collected\n'
                        '• No data sent to external servers\n'
                        '• Permissions used only for threat detection',
                        style: TextStyle(fontSize: 12, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPermissionCard({
    required SpecialPermissionType type,
    required String title,
    required String description,
    required IconData icon,
    required bool isGranted,
    required List<String> benefits,
  }) {
    return Card(
      color: const Color(0xFF1D1E33),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isGranted
                        ? Colors.green.withOpacity(0.2)
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isGranted ? Colors.green : Colors.orange,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isGranted ? Icons.check_circle : Icons.warning,
                  color: isGranted ? Colors.green : Colors.orange,
                  size: 28,
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Enables:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            ...benefits.map(
              (benefit) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check,
                      size: 16,
                      color: Color(0xFF00D9FF),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        benefit,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isGranted) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () => _requestPermission(type),
                icon: const Icon(Icons.settings),
                label: const Text('Grant Permission'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _requestPermission(SpecialPermissionType type) async {
    // Show rationale first
    final shouldRequest =
        await widget.permissionManager.showPermissionRationale(
      context,
      type,
    );

    if (shouldRequest != true) return;

    // Request the permission
    bool granted = false;

    switch (type) {
      case SpecialPermissionType.usageStats:
        granted = await widget.permissionManager.requestUsageStatsPermission();
        break;
      case SpecialPermissionType.accessibility:
        granted =
            await widget.permissionManager.requestAccessibilityPermission();
        break;
    }

    // Refresh UI
    await _checkPermissions();

    if (granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permission granted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _requestAllPermissions() async {
    final missing = widget.permissionManager.getMissingPermissions();

    for (final type in missing) {
      await _requestPermission(type);
      // Small delay between requests
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}
