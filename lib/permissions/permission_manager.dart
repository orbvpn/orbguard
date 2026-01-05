// lib/permissions/permission_manager.dart
// Complete permission management system for OrbGuard

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

// ============================================================================
// PERMISSION MANAGER - Handles all app permissions
// ============================================================================

class PermissionManager {
  static const platform = MethodChannel('com.orb.guard/system');

  // Permission groups with explanations
  static const Map<String, PermissionGroup> permissionGroups = {
    'essential': PermissionGroup(
      name: 'Essential Permissions',
      description: 'Required for basic threat detection',
      icon: Icons.security,
      permissions: [
        PermissionInfo(
          permission: Permission.storage,
          name: 'Storage Access',
          reason: 'Scan files for malware and suspicious modifications',
          impact: 'Enables file system threat detection',
        ),
        PermissionInfo(
          permission: Permission.phone,
          name: 'Phone State',
          reason: 'Monitor device for suspicious system modifications',
          impact: 'Detects system-level threats',
        ),
      ],
    ),
    'advanced': PermissionGroup(
      name: 'Advanced Detection',
      description: 'Enables deep threat analysis',
      icon: Icons.search,
      permissions: [
        PermissionInfo(
          permission: Permission.sms,
          name: 'SMS Access',
          reason: 'Detect SMS-based exploits (Pegasus uses SMS)',
          impact: 'Critical for zero-click exploit detection',
        ),
        PermissionInfo(
          permission: Permission.phone,
          name: 'Call Logs',
          reason: 'Identify suspicious call patterns',
          impact: 'Detects communication monitoring malware',
        ),
        PermissionInfo(
          permission: Permission.location,
          name: 'Location',
          reason: 'Detect location stalking behavior',
          impact: 'Identifies location-tracking spyware',
        ),
      ],
    ),
    'special': PermissionGroup(
      name: 'Special Permissions',
      description: 'Requires manual activation in Settings',
      icon: Icons.settings,
      permissions: [], // Handled separately
    ),
  };

  // Current permission states
  final Map<Permission, PermissionStatus> _permissionStates = {};
  bool _hasUsageStats = false;
  bool _hasAccessibility = false;
  bool _hasRootAccess = false;
  String _accessMethod = 'Standard';

  // ============================================================================
  // PERMISSION STATUS CHECKING
  // ============================================================================

  /// Check all permission statuses
  Future<PermissionScanResult> checkAllPermissions() async {
    final result = PermissionScanResult();

    // Check standard permissions
    for (final group in permissionGroups.values) {
      for (final permInfo in group.permissions) {
        // For storage, use native check on Android 11+
        if (permInfo.permission == Permission.storage && Platform.isAndroid) {
          final hasStorage = await _checkStoragePermission();
          if (hasStorage) {
            result.granted.add(permInfo.name);
            _permissionStates[permInfo.permission] = PermissionStatus.granted;
          } else {
            result.denied.add(permInfo.name);
            _permissionStates[permInfo.permission] = PermissionStatus.denied;
          }
        } else {
          final status = await permInfo.permission.status;
          _permissionStates[permInfo.permission] = status;

          if (status.isGranted) {
            result.granted.add(permInfo.name);
          } else if (status.isDenied) {
            result.denied.add(permInfo.name);
          } else if (status.isPermanentlyDenied) {
            result.permanentlyDenied.add(permInfo.name);
          }
        }
      }
    }

    // Check special permissions
    _hasUsageStats = await _checkUsageStatsPermission();
    _hasAccessibility = await _checkAccessibilityPermission();

    if (_hasUsageStats) result.granted.add('Usage Stats');
    if (_hasAccessibility) result.granted.add('Accessibility');

    // Check root/shell access
    await _checkSystemAccess();
    if (_hasRootAccess) {
      result.granted.add('Root Access');
    } else if (_accessMethod == 'Shell' || _accessMethod == 'AppProcess') {
      result.granted.add('Enhanced Access');
    }

    // Calculate detection capability
    result.detectionCapability = _calculateDetectionCapability();

    return result;
  }

  /// Check system access level (Root/Shell/Standard)
  Future<void> _checkSystemAccess() async {
    try {
      final result = await platform.invokeMethod('checkRootAccess');
      _hasRootAccess = result['hasRoot'] ?? false;
      _accessMethod = result['method'] ?? 'Standard';
    } catch (e) {
      _hasRootAccess = false;
      _accessMethod = 'Standard';
    }
  }

  /// Calculate detection capability percentage
  /// Uses same formula as main.dart for consistency
  int _calculateDetectionCapability() {
    // Base capability from standard APIs
    int capability = 25;

    // Standard permissions (30% total)
    if (_permissionStates[Permission.phone]?.isGranted ?? false) {
      capability += 5;
    }
    if (_permissionStates[Permission.sms]?.isGranted ?? false) {
      capability += 10;
    }
    if (_permissionStates[Permission.location]?.isGranted ?? false) {
      capability += 5;
    }
    if (_permissionStates[Permission.storage]?.isGranted ?? false) {
      capability += 10;
    }

    // Special permissions (25% total)
    if (_hasUsageStats) capability += 15;
    if (_hasAccessibility) capability += 10;

    // Enhanced/Root access (15% total)
    if (_hasRootAccess) {
      capability += 15;
    } else if (_accessMethod == 'Shell' || _accessMethod == 'AppProcess') {
      capability += 10;
    }

    return capability.clamp(0, 100);
  }

  // ============================================================================
  // PERMISSION REQUESTING
  // ============================================================================

  /// Request all essential permissions at once
  Future<Map<Permission, PermissionStatus>>
      requestEssentialPermissions() async {
    final results = <Permission, PermissionStatus>{};

    // Request storage permission via native method (Android 11+)
    if (Platform.isAndroid) {
      await requestStoragePermission();
      final hasStorage = await _checkStoragePermission();
      results[Permission.storage] = hasStorage
          ? PermissionStatus.granted
          : PermissionStatus.denied;
    }

    // Request phone permission
    final phoneStatus = await Permission.phone.request();
    results[Permission.phone] = phoneStatus;

    return results;
  }

  /// Request advanced permissions
  Future<Map<Permission, PermissionStatus>> requestAdvancedPermissions() async {
    final permissions = [
      Permission.sms,
      Permission.location,
      Permission.phone,
    ];

    // Request location with explanation
    if (Platform.isAndroid) {
      // Android 10+ requires background location separately
      final locationStatus = await Permission.location.request();

      if (locationStatus.isGranted) {
        await Permission.locationAlways.request();
      }
    }

    return await permissions.request();
  }

  /// Request single permission with explanation
  Future<PermissionStatus> requestPermissionWithRationale({
    required BuildContext context,
    required Permission permission,
    required String title,
    required String explanation,
    required String benefit,
  }) async {
    // Check current status
    final status = await permission.status;

    if (status.isGranted) {
      return status;
    }

    // If permanently denied, show settings dialog
    if (status.isPermanentlyDenied) {
      await _showSettingsDialog(context, title, explanation);
      return status;
    }

    // Show rationale dialog
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.security, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Why we need this permission:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(explanation),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.blue),
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grant Permission'),
          ),
        ],
      ),
    );

    if (shouldRequest ?? false) {
      return await permission.request();
    }

    return status;
  }

  // ============================================================================
  // SPECIAL PERMISSIONS
  // ============================================================================

  /// Check if Storage permission is granted (Android 11+ uses MANAGE_EXTERNAL_STORAGE)
  Future<bool> _checkStoragePermission() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await platform.invokeMethod('checkStoragePermission');
      return result['hasPermission'] ?? false;
    } catch (e) {
      // Fallback to standard permission check
      final status = await Permission.storage.status;
      return status.isGranted;
    }
  }

  /// Request storage permission (uses native method for Android 11+)
  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return false;

    try {
      await platform.invokeMethod('requestStoragePermission');
      return true;
    } catch (e) {
      print('Error requesting storage permission: $e');
      return false;
    }
  }

  /// Check if Usage Stats permission is granted
  Future<bool> _checkUsageStatsPermission() async {
    if (!Platform.isAndroid) return false;

    try {
      final result = await platform.invokeMethod('checkUsageStatsPermission');
      return result['hasPermission'] ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Check if Accessibility permission is granted
  Future<bool> _checkAccessibilityPermission() async {
    if (!Platform.isAndroid) return false;

    try {
      final result =
          await platform.invokeMethod('checkAccessibilityPermission');
      return result['hasPermission'] ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Request Usage Stats permission (navigates to Settings)
  Future<bool> requestUsageStatsPermission(BuildContext context) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Usage Stats'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This permission allows OrbGuard to:\n\n'
                '• Monitor app behavior patterns\n'
                '• Detect suspicious background activity\n'
                '• Identify data exfiltration attempts\n\n'
                'This is CRITICAL for detecting advanced threats like Pegasus.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You will be taken to Settings. Find "OrbGuard" and enable access.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpen ?? false) {
      try {
        await platform.invokeMethod('openUsageStatsSettings');
        return true;
      } catch (e) {
        print('Error opening usage stats settings: $e');
        return false;
      }
    }

    return false;
  }

  /// Request Accessibility permission (navigates to Settings)
  Future<bool> requestAccessibilityPermission(BuildContext context) async {
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Accessibility Service'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This permission allows OrbGuard to:\n\n'
                '• Detect malicious accessibility services\n'
                '• Monitor screen content for threats\n'
                '• Identify keylogger attempts\n\n'
                'This helps detect spyware that uses accessibility features.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'OrbGuard will NOT read your screen content. This permission is only used to detect malicious services.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (shouldOpen ?? false) {
      try {
        await platform.invokeMethod('openAccessibilitySettings');
        return true;
      } catch (e) {
        print('Error opening accessibility settings: $e');
        return false;
      }
    }

    return false;
  }

  // ============================================================================
  // UTILITY METHODS
  // ============================================================================

  /// Show settings dialog for permanently denied permissions
  Future<void> _showSettingsDialog(
    BuildContext context,
    String title,
    String explanation,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(explanation),
            const SizedBox(height: 16),
            const Text(
              'This permission was permanently denied. Please enable it manually in Settings.',
              style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Get human-readable permission name
  static String getPermissionName(Permission permission) {
    final permissionMap = {
      Permission.storage: 'Storage',
      Permission.phone: 'Phone',
      Permission.sms: 'SMS',
      Permission.location: 'Location',
      Permission.locationAlways: 'Background Location',
    };
    return permissionMap[permission] ?? permission.toString();
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

class PermissionGroup {
  final String name;
  final String description;
  final IconData icon;
  final List<PermissionInfo> permissions;

  const PermissionGroup({
    required this.name,
    required this.description,
    required this.icon,
    required this.permissions,
  });
}

class PermissionInfo {
  final Permission permission;
  final String name;
  final String reason;
  final String impact;

  const PermissionInfo({
    required this.permission,
    required this.name,
    required this.reason,
    required this.impact,
  });
}

class PermissionScanResult {
  final List<String> granted = [];
  final List<String> denied = [];
  final List<String> permanentlyDenied = [];
  int detectionCapability = 0;

  int get totalPermissions =>
      granted.length + denied.length + permanentlyDenied.length;

  bool get hasAllEssential =>
      granted.contains('Storage Access') && granted.contains('Phone State');

  bool get hasAllAdvanced =>
      granted.contains('SMS Access') && granted.contains('Location');

  bool get hasSpecialPermissions =>
      granted.contains('Usage Stats') || granted.contains('Accessibility');
}
