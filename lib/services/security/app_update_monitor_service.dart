/// App Update Monitoring Service
///
/// Monitors app updates for security changes:
/// - Permission change detection
/// - SDK/library updates tracking
/// - Security regression detection
/// - Malicious update detection
/// - Update recommendation engine
/// - Version vulnerability correlation

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// App update information
class AppUpdate {
  final String packageName;
  final String appName;
  final String currentVersion;
  final String newVersion;
  final DateTime availableSince;
  final UpdateType type;
  final List<PermissionChange> permissionChanges;
  final List<String> releaseNotes;
  final SecurityAssessment securityAssessment;
  final UpdateRecommendation recommendation;

  AppUpdate({
    required this.packageName,
    required this.appName,
    required this.currentVersion,
    required this.newVersion,
    required this.availableSince,
    required this.type,
    required this.permissionChanges,
    required this.releaseNotes,
    required this.securityAssessment,
    required this.recommendation,
  });

  bool get hasPermissionChanges => permissionChanges.isNotEmpty;
  bool get hasNewDangerousPermissions => permissionChanges.any(
    (c) => c.changeType == PermissionChangeType.added && c.isDangerous
  );
}

/// Update types
enum UpdateType {
  major('Major', 'Significant changes'),
  minor('Minor', 'New features'),
  patch('Patch', 'Bug fixes'),
  security('Security', 'Security update'),
  unknown('Unknown', 'Unknown update type');

  final String displayName;
  final String description;
  const UpdateType(this.displayName, this.description);
}

/// Permission change in update
class PermissionChange {
  final String permission;
  final String permissionLabel;
  final PermissionChangeType changeType;
  final bool isDangerous;
  final String? description;
  final RiskLevel riskLevel;

  PermissionChange({
    required this.permission,
    required this.permissionLabel,
    required this.changeType,
    required this.isDangerous,
    this.description,
    required this.riskLevel,
  });
}

/// Permission change types
enum PermissionChangeType {
  added,
  removed,
  modified,
}

/// Risk levels
enum RiskLevel {
  critical('Critical', 'Immediate attention required'),
  high('High', 'Significant security concern'),
  medium('Medium', 'Moderate concern'),
  low('Low', 'Minor concern'),
  safe('Safe', 'No security concerns');

  final String displayName;
  final String description;
  const RiskLevel(this.displayName, this.description);
}

/// Security assessment of an update
class SecurityAssessment {
  final double securityScore; // 0-100
  final List<SecurityConcern> concerns;
  final List<SecurityImprovement> improvements;
  final bool isSafeToUpdate;
  final String summary;

  SecurityAssessment({
    required this.securityScore,
    required this.concerns,
    required this.improvements,
    required this.isSafeToUpdate,
    required this.summary,
  });

  String get riskLevel {
    if (securityScore >= 80) return 'Safe';
    if (securityScore >= 60) return 'Low Risk';
    if (securityScore >= 40) return 'Medium Risk';
    if (securityScore >= 20) return 'High Risk';
    return 'Critical Risk';
  }
}

/// Security concern in update
class SecurityConcern {
  final String id;
  final String title;
  final String description;
  final RiskLevel severity;
  final String? mitigation;

  SecurityConcern({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    this.mitigation,
  });
}

/// Security improvement in update
class SecurityImprovement {
  final String id;
  final String title;
  final String description;
  final String? cveFixed;

  SecurityImprovement({
    required this.id,
    required this.title,
    required this.description,
    this.cveFixed,
  });
}

/// Update recommendation
enum UpdateRecommendation {
  updateImmediately('Update Immediately', 'Critical security update', true),
  updateRecommended('Update Recommended', 'Beneficial update', true),
  updateWithCaution('Update with Caution', 'Review changes before updating', false),
  holdUpdate('Hold Update', 'Security concerns detected', false),
  doNotUpdate('Do Not Update', 'Significant security regression', false);

  final String displayName;
  final String description;
  final bool shouldUpdate;
  const UpdateRecommendation(this.displayName, this.description, this.shouldUpdate);
}

/// App version history
class AppVersionHistory {
  final String packageName;
  final List<VersionRecord> versions;

  AppVersionHistory({
    required this.packageName,
    required this.versions,
  });

  VersionRecord? get currentVersion =>
      versions.isNotEmpty ? versions.last : null;
}

/// Version record
class VersionRecord {
  final String version;
  final DateTime installedAt;
  final List<String> permissions;
  final int sdkCount;
  final double securityScore;

  VersionRecord({
    required this.version,
    required this.installedAt,
    required this.permissions,
    required this.sdkCount,
    required this.securityScore,
  });
}

/// App Update Monitor Service
class AppUpdateMonitorService {
  static const MethodChannel _channel = MethodChannel('com.orbguard/app_update');

  // Tracked apps
  final Map<String, AppVersionHistory> _appHistory = {};

  // Pending updates
  final List<AppUpdate> _pendingUpdates = [];

  // Dangerous permissions list
  static const List<String> _dangerousPermissions = [
    'android.permission.READ_SMS',
    'android.permission.SEND_SMS',
    'android.permission.RECEIVE_SMS',
    'android.permission.READ_CONTACTS',
    'android.permission.WRITE_CONTACTS',
    'android.permission.READ_CALL_LOG',
    'android.permission.WRITE_CALL_LOG',
    'android.permission.CAMERA',
    'android.permission.RECORD_AUDIO',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.READ_EXTERNAL_STORAGE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.READ_CALENDAR',
    'android.permission.WRITE_CALENDAR',
    'android.permission.BODY_SENSORS',
    'android.permission.PROCESS_OUTGOING_CALLS',
    'android.permission.READ_PHONE_STATE',
    'android.permission.CALL_PHONE',
    'android.permission.BIND_ACCESSIBILITY_SERVICE',
    'android.permission.BIND_DEVICE_ADMIN',
    'android.permission.SYSTEM_ALERT_WINDOW',
  ];

  // Stream controllers
  final _updateController = StreamController<AppUpdate>.broadcast();
  final _alertController = StreamController<UpdateAlert>.broadcast();

  // Update check timer
  Timer? _checkTimer;

  /// Stream of app updates
  Stream<AppUpdate> get onUpdate => _updateController.stream;

  /// Stream of update alerts
  Stream<UpdateAlert> get onAlert => _alertController.stream;

  /// Initialize the service
  Future<void> initialize() async {
    await _loadAppHistory();
  }

  /// Load app history from storage
  Future<void> _loadAppHistory() async {
    if (!Platform.isAndroid) return;

    try {
      final apps = await _channel.invokeMethod<List<dynamic>>('getInstalledApps');

      for (final app in (apps ?? [])) {
        final appMap = Map<String, dynamic>.from(app as Map);
        final packageName = appMap['package_name'] as String;

        _appHistory[packageName] = AppVersionHistory(
          packageName: packageName,
          versions: [
            VersionRecord(
              version: appMap['version'] as String? ?? 'Unknown',
              installedAt: DateTime.now(),
              permissions: (appMap['permissions'] as List<dynamic>?)?.cast<String>() ?? [],
              sdkCount: (appMap['sdk_count'] as int?) ?? 0,
              securityScore: 75.0,
            ),
          ],
        );
      }
    } catch (e) {
      debugPrint('Failed to load app history: $e');
    }
  }

  /// Check for updates for all tracked apps
  Future<List<AppUpdate>> checkForUpdates() async {
    final updates = <AppUpdate>[];

    if (!Platform.isAndroid) return updates;

    try {
      final updateData = await _channel.invokeMethod<List<dynamic>>('checkUpdates');

      for (final update in (updateData ?? [])) {
        final updateMap = Map<String, dynamic>.from(update as Map);
        final appUpdate = await _analyzeUpdate(updateMap);

        if (appUpdate != null) {
          updates.add(appUpdate);
          _pendingUpdates.add(appUpdate);
          _updateController.add(appUpdate);

          // Check for alerts
          if (appUpdate.hasNewDangerousPermissions) {
            _alertController.add(UpdateAlert(
              packageName: appUpdate.packageName,
              appName: appUpdate.appName,
              type: AlertType.newDangerousPermission,
              message: 'Update adds new dangerous permissions',
              severity: RiskLevel.high,
            ));
          }

          if (!appUpdate.securityAssessment.isSafeToUpdate) {
            _alertController.add(UpdateAlert(
              packageName: appUpdate.packageName,
              appName: appUpdate.appName,
              type: AlertType.securityRegression,
              message: appUpdate.securityAssessment.summary,
              severity: RiskLevel.critical,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
    }

    return updates;
  }

  /// Analyze a single update
  Future<AppUpdate?> _analyzeUpdate(Map<String, dynamic> updateData) async {
    final packageName = updateData['package_name'] as String;
    final appName = updateData['app_name'] as String? ?? packageName;
    final currentVersion = updateData['current_version'] as String;
    final newVersion = updateData['new_version'] as String;
    final currentPermissions = (updateData['current_permissions'] as List<dynamic>?)?.cast<String>() ?? [];
    final newPermissions = (updateData['new_permissions'] as List<dynamic>?)?.cast<String>() ?? [];

    // Analyze permission changes
    final permissionChanges = _analyzePermissionChanges(currentPermissions, newPermissions);

    // Determine update type
    final updateType = _determineUpdateType(currentVersion, newVersion);

    // Perform security assessment
    final securityAssessment = _assessUpdateSecurity(
      packageName,
      currentPermissions,
      newPermissions,
      updateType,
    );

    // Generate recommendation
    final recommendation = _generateRecommendation(
      permissionChanges,
      securityAssessment,
      updateType,
    );

    return AppUpdate(
      packageName: packageName,
      appName: appName,
      currentVersion: currentVersion,
      newVersion: newVersion,
      availableSince: DateTime.now(),
      type: updateType,
      permissionChanges: permissionChanges,
      releaseNotes: (updateData['release_notes'] as List<dynamic>?)?.cast<String>() ?? [],
      securityAssessment: securityAssessment,
      recommendation: recommendation,
    );
  }

  /// Analyze permission changes between versions
  List<PermissionChange> _analyzePermissionChanges(
    List<String> currentPermissions,
    List<String> newPermissions,
  ) {
    final changes = <PermissionChange>[];

    // Find added permissions
    for (final permission in newPermissions) {
      if (!currentPermissions.contains(permission)) {
        final isDangerous = _dangerousPermissions.contains(permission);
        changes.add(PermissionChange(
          permission: permission,
          permissionLabel: _getPermissionLabel(permission),
          changeType: PermissionChangeType.added,
          isDangerous: isDangerous,
          description: 'This permission was added in the update',
          riskLevel: isDangerous ? RiskLevel.high : RiskLevel.low,
        ));
      }
    }

    // Find removed permissions
    for (final permission in currentPermissions) {
      if (!newPermissions.contains(permission)) {
        changes.add(PermissionChange(
          permission: permission,
          permissionLabel: _getPermissionLabel(permission),
          changeType: PermissionChangeType.removed,
          isDangerous: _dangerousPermissions.contains(permission),
          description: 'This permission was removed in the update',
          riskLevel: RiskLevel.safe,
        ));
      }
    }

    return changes;
  }

  /// Get human-readable permission label
  String _getPermissionLabel(String permission) {
    final labels = {
      'android.permission.READ_SMS': 'Read SMS Messages',
      'android.permission.SEND_SMS': 'Send SMS Messages',
      'android.permission.READ_CONTACTS': 'Read Contacts',
      'android.permission.CAMERA': 'Access Camera',
      'android.permission.RECORD_AUDIO': 'Record Audio',
      'android.permission.ACCESS_FINE_LOCATION': 'Precise Location',
      'android.permission.ACCESS_COARSE_LOCATION': 'Approximate Location',
      'android.permission.READ_EXTERNAL_STORAGE': 'Read Storage',
      'android.permission.WRITE_EXTERNAL_STORAGE': 'Write Storage',
      'android.permission.BIND_ACCESSIBILITY_SERVICE': 'Accessibility Service',
      'android.permission.BIND_DEVICE_ADMIN': 'Device Admin',
      'android.permission.SYSTEM_ALERT_WINDOW': 'Draw Over Other Apps',
    };

    return labels[permission] ?? permission.split('.').last;
  }

  /// Determine update type from version strings
  UpdateType _determineUpdateType(String current, String newVersion) {
    try {
      final currentParts = current.split('.').map(int.parse).toList();
      final newParts = newVersion.split('.').map(int.parse).toList();

      while (currentParts.length < 3) currentParts.add(0);
      while (newParts.length < 3) newParts.add(0);

      if (newParts[0] > currentParts[0]) return UpdateType.major;
      if (newParts[1] > currentParts[1]) return UpdateType.minor;
      if (newParts[2] > currentParts[2]) return UpdateType.patch;

      return UpdateType.unknown;
    } catch (e) {
      return UpdateType.unknown;
    }
  }

  /// Assess security of the update
  SecurityAssessment _assessUpdateSecurity(
    String packageName,
    List<String> currentPermissions,
    List<String> newPermissions,
    UpdateType updateType,
  ) {
    double score = 80.0;
    final concerns = <SecurityConcern>[];
    final improvements = <SecurityImprovement>[];

    // Check for new dangerous permissions
    final newDangerous = newPermissions.where(
      (p) => _dangerousPermissions.contains(p) && !currentPermissions.contains(p)
    ).toList();

    for (final permission in newDangerous) {
      score -= 15;
      concerns.add(SecurityConcern(
        id: 'new_perm_${permission.hashCode}',
        title: 'New Dangerous Permission',
        description: 'Update requests "${_getPermissionLabel(permission)}"',
        severity: RiskLevel.high,
        mitigation: 'Review if this permission is necessary for app functionality',
      ));
    }

    // Check for removed permissions (positive)
    final removedDangerous = currentPermissions.where(
      (p) => _dangerousPermissions.contains(p) && !newPermissions.contains(p)
    ).toList();

    for (final permission in removedDangerous) {
      score += 5;
      improvements.add(SecurityImprovement(
        id: 'removed_perm_${permission.hashCode}',
        title: 'Permission Removed',
        description: 'Update removes "${_getPermissionLabel(permission)}"',
      ));
    }

    // Security updates are positive
    if (updateType == UpdateType.security) {
      score += 10;
      improvements.add(SecurityImprovement(
        id: 'security_update',
        title: 'Security Update',
        description: 'This update includes security fixes',
      ));
    }

    // Check for accessibility service (very risky)
    if (newDangerous.contains('android.permission.BIND_ACCESSIBILITY_SERVICE') &&
        !currentPermissions.contains('android.permission.BIND_ACCESSIBILITY_SERVICE')) {
      score -= 30;
      concerns.add(SecurityConcern(
        id: 'accessibility_service',
        title: 'Accessibility Service Added',
        description: 'Update adds accessibility service which can monitor all screen content',
        severity: RiskLevel.critical,
        mitigation: 'Only allow if app explicitly requires screen reading functionality',
      ));
    }

    // Check for device admin
    if (newDangerous.contains('android.permission.BIND_DEVICE_ADMIN') &&
        !currentPermissions.contains('android.permission.BIND_DEVICE_ADMIN')) {
      score -= 25;
      concerns.add(SecurityConcern(
        id: 'device_admin',
        title: 'Device Admin Added',
        description: 'Update requests device administrator privileges',
        severity: RiskLevel.critical,
        mitigation: 'Only allow for enterprise/MDM apps',
      ));
    }

    score = score.clamp(0.0, 100.0);

    return SecurityAssessment(
      securityScore: score,
      concerns: concerns,
      improvements: improvements,
      isSafeToUpdate: score >= 50 && !concerns.any((c) => c.severity == RiskLevel.critical),
      summary: _generateSecuritySummary(score, concerns, improvements),
    );
  }

  /// Generate security summary
  String _generateSecuritySummary(
    double score,
    List<SecurityConcern> concerns,
    List<SecurityImprovement> improvements,
  ) {
    if (score >= 80) {
      return improvements.isNotEmpty
          ? 'Safe update with ${improvements.length} security improvement(s)'
          : 'Safe update with no significant changes';
    } else if (score >= 50) {
      return 'Update has ${concerns.length} concern(s) to review';
    } else {
      return 'Update has significant security concerns - review carefully';
    }
  }

  /// Generate update recommendation
  UpdateRecommendation _generateRecommendation(
    List<PermissionChange> permissionChanges,
    SecurityAssessment assessment,
    UpdateType type,
  ) {
    // Critical security concerns
    if (assessment.concerns.any((c) => c.severity == RiskLevel.critical)) {
      return UpdateRecommendation.doNotUpdate;
    }

    // Security update - always recommend
    if (type == UpdateType.security) {
      return UpdateRecommendation.updateImmediately;
    }

    // New dangerous permissions
    if (permissionChanges.any((c) =>
        c.changeType == PermissionChangeType.added && c.isDangerous)) {
      return UpdateRecommendation.updateWithCaution;
    }

    // Good security score
    if (assessment.securityScore >= 70) {
      return UpdateRecommendation.updateRecommended;
    }

    // Moderate score
    if (assessment.securityScore >= 50) {
      return UpdateRecommendation.updateWithCaution;
    }

    return UpdateRecommendation.holdUpdate;
  }

  /// Start automatic update checking
  void startAutoCheck({Duration interval = const Duration(hours: 12)}) {
    stopAutoCheck();

    _checkTimer = Timer.periodic(interval, (_) {
      checkForUpdates();
    });

    // Initial check
    checkForUpdates();
  }

  /// Stop automatic update checking
  void stopAutoCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Get pending updates
  List<AppUpdate> getPendingUpdates({UpdateRecommendation? recommendation}) {
    var updates = _pendingUpdates.toList();

    if (recommendation != null) {
      updates = updates.where((u) => u.recommendation == recommendation).toList();
    }

    return updates..sort((a, b) =>
        a.recommendation.index.compareTo(b.recommendation.index)
    );
  }

  /// Get app version history
  AppVersionHistory? getAppHistory(String packageName) => _appHistory[packageName];

  /// Record that an update was installed
  void recordUpdateInstalled(String packageName, String newVersion, List<String> newPermissions) {
    final history = _appHistory[packageName];
    if (history != null) {
      history.versions.add(VersionRecord(
        version: newVersion,
        installedAt: DateTime.now(),
        permissions: newPermissions,
        sdkCount: 0,
        securityScore: 75.0,
      ));
    }

    // Remove from pending
    _pendingUpdates.removeWhere((u) => u.packageName == packageName);
  }

  /// Get service statistics
  Map<String, dynamic> getStatistics() {
    return {
      'tracked_apps': _appHistory.length,
      'pending_updates': _pendingUpdates.length,
      'updates_with_concerns': _pendingUpdates.where(
        (u) => u.securityAssessment.concerns.isNotEmpty
      ).length,
      'is_auto_checking': _checkTimer != null,
    };
  }

  /// Dispose resources
  void dispose() {
    stopAutoCheck();
    _updateController.close();
    _alertController.close();
  }
}

/// Update alert
class UpdateAlert {
  final String packageName;
  final String appName;
  final AlertType type;
  final String message;
  final RiskLevel severity;
  final DateTime timestamp;

  UpdateAlert({
    required this.packageName,
    required this.appName,
    required this.type,
    required this.message,
    required this.severity,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Alert types
enum AlertType {
  newDangerousPermission,
  securityRegression,
  suspiciousUpdate,
  trackerAdded,
  sdkVulnerability,
}
