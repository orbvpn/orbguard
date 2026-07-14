// App Security Provider
// State management for app security and privacy analysis

import '../utils/platform_info.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api/orbguard_api_client.dart';
import '../models/api/url_reputation.dart';

/// Installed app info (from device)
class InstalledApp {
  final String packageName;
  final String appName;
  final String version;
  final String? iconPath;
  final List<String> permissions;
  final String installSource;
  final DateTime installTime;
  final DateTime? updateTime;
  final int? apkSize;

  /// SDK/library package prefixes detected inside the app, when available.
  /// Forwarded to the backend analyzer for tracker detection.
  final List<String>? detectedLibraries;

  InstalledApp({
    required this.packageName,
    required this.appName,
    required this.version,
    this.iconPath,
    required this.permissions,
    required this.installSource,
    required this.installTime,
    this.updateTime,
    this.apkSize,
    this.detectedLibraries,
  });

  bool get isSideloaded =>
      installSource != 'com.android.vending' &&
      installSource != 'com.apple.appstore';
}

/// App with analysis result
class AnalyzedApp {
  final InstalledApp app;
  final AppAnalysisResult? result;
  final bool isPending;
  final String? error;

  AnalyzedApp({
    required this.app,
    this.result,
    this.isPending = false,
    this.error,
  });

  AnalyzedApp copyWith({
    InstalledApp? app,
    AppAnalysisResult? result,
    bool? isPending,
    String? error,
  }) {
    return AnalyzedApp(
      app: app ?? this.app,
      result: result ?? this.result,
      isPending: isPending ?? this.isPending,
      error: error ?? this.error,
    );
  }

  /// Risk score normalized to 0.0-1.0 (the backend emits 0-100).
  double get riskScore => ((result?.riskScore ?? 0.0) / 100.0).clamp(0.0, 1.0);
  String get riskLevel => result?.riskLevel ?? 'unknown';
  String get privacyGrade => result?.privacyGrade ?? 'U';
  bool get isHighRisk =>
      riskScore >= 0.7 ||
      riskLevel == 'critical' ||
      riskLevel == 'high' ||
      (result?.isKnownMalware ?? false);
  bool get isMediumRisk =>
      !isHighRisk && (riskScore >= 0.4 || riskLevel == 'medium');
}

/// App security stats
class AppSecurityStats {
  final int totalApps;
  final int analyzedApps;
  final int highRiskApps;
  final int mediumRiskApps;
  final int lowRiskApps;
  final int sideloadedApps;
  final int malwareDetected;
  final int trackersFound;
  final int dangerousPermissions;

  AppSecurityStats({
    this.totalApps = 0,
    this.analyzedApps = 0,
    this.highRiskApps = 0,
    this.mediumRiskApps = 0,
    this.lowRiskApps = 0,
    this.sideloadedApps = 0,
    this.malwareDetected = 0,
    this.trackersFound = 0,
    this.dangerousPermissions = 0,
  });
}

/// Sort options for app list
enum AppSortOption {
  name,
  riskScore,
  installDate,
  privacyGrade;

  String get displayName {
    switch (this) {
      case AppSortOption.name:
        return 'Name';
      case AppSortOption.riskScore:
        return 'Risk Score';
      case AppSortOption.installDate:
        return 'Install Date';
      case AppSortOption.privacyGrade:
        return 'Privacy Grade';
    }
  }
}

/// Filter options for app list
enum AppFilterOption {
  all,
  highRisk,
  sideloaded,
  hasTrackers,
  dangerousPermissions;

  String get displayName {
    switch (this) {
      case AppFilterOption.all:
        return 'All Apps';
      case AppFilterOption.highRisk:
        return 'High Risk';
      case AppFilterOption.sideloaded:
        return 'Sideloaded';
      case AppFilterOption.hasTrackers:
        return 'Has Trackers';
      case AppFilterOption.dangerousPermissions:
        return 'Dangerous Permissions';
    }
  }
}

/// App Security Provider
class AppSecurityProvider extends ChangeNotifier {
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  /// Native system channel (android/.../MainActivity.kt) exposing the
  /// on-device package inventory via the "getInstalledApps" method.
  static const MethodChannel _systemChannel =
      MethodChannel('com.orb.guard/system');

  // State
  final List<AnalyzedApp> _apps = [];
  AppSecurityStats _stats = AppSecurityStats();
  AppSortOption _sortOption = AppSortOption.riskScore;
  AppFilterOption _filterOption = AppFilterOption.all;
  AnalyzedApp? _selectedApp;

  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;
  double _scanProgress = 0.0;

  // Getters
  List<AnalyzedApp> get apps => _getFilteredAndSortedApps();
  List<AnalyzedApp> get allApps => List.unmodifiable(_apps);
  AppSecurityStats get stats => _stats;
  AppSortOption get sortOption => _sortOption;
  AppFilterOption get filterOption => _filterOption;
  AnalyzedApp? get selectedApp => _selectedApp;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get error => _error;
  double get scanProgress => _scanProgress;

  /// High risk apps
  List<AnalyzedApp> get highRiskApps =>
      _apps.where((a) => a.isHighRisk).toList();

  /// Sideloaded apps
  List<AnalyzedApp> get sideloadedApps =>
      _apps.where((a) => a.app.isSideloaded).toList();

  /// Apps with trackers
  List<AnalyzedApp> get appsWithTrackers => _apps
      .where((a) => a.result != null && a.result!.detectedTrackers.isNotEmpty)
      .toList();

  /// Initialize provider
  Future<void> init() async {
    await loadApps();
  }

  /// Load installed apps from the device's native package inventory.
  ///
  /// Uses the "getInstalledApps" method on the com.orb.guard/system channel
  /// (implemented in MainActivity.kt). The response shape is
  /// { "apps": [{ packageName, appName, versionName, installerPackage,
  ///   firstInstallTime, lastUpdateTime, permissions, isSystemApp,
  ///   isUpdatedSystemApp, ... }] }.
  ///
  /// Pure (non-updated) system packages are excluded from the audit list;
  /// user-installed and updated system apps are kept. Analysis is performed
  /// on demand against the backend via POST /apps/analyze.
  Future<void> loadApps() async {
    _isLoading = true;
    notifyListeners();

    if (!PlatformInfo.isAndroid) {
      _apps.clear();
      _updateStats();
      _error =
          'The installed-app inventory is only available on Android devices.';
      _isLoading = false;
      notifyListeners();
      return;
    }

    try {
      final result = await _systemChannel
          .invokeMethod<Map<dynamic, dynamic>>('getInstalledApps');
      final appsData = (result?['apps'] as List<dynamic>?) ?? [];

      _apps.clear();
      for (final raw in appsData) {
        if (raw is! Map) continue;
        final appJson = Map<String, dynamic>.from(raw);

        final isSystemApp = appJson['isSystemApp'] as bool? ?? false;
        final isUpdatedSystemApp =
            appJson['isUpdatedSystemApp'] as bool? ?? false;
        if (isSystemApp && !isUpdatedSystemApp) continue;

        final packageName = appJson['packageName'] as String? ?? '';
        if (packageName.isEmpty) continue;

        final firstInstall = appJson['firstInstallTime'] as int?;
        final lastUpdate = appJson['lastUpdateTime'] as int?;

        final app = InstalledApp(
          packageName: packageName,
          appName: appJson['appName'] as String? ?? packageName,
          version: appJson['versionName'] as String? ?? 'Unknown',
          permissions:
              (appJson['permissions'] as List<dynamic>?)?.cast<String>() ?? [],
          installSource: appJson['installerPackage'] as String? ?? 'unknown',
          installTime: firstInstall != null
              ? DateTime.fromMillisecondsSinceEpoch(firstInstall)
              : DateTime.fromMillisecondsSinceEpoch(0),
          updateTime: lastUpdate != null
              ? DateTime.fromMillisecondsSinceEpoch(lastUpdate)
              : null,
        );

        _apps.add(AnalyzedApp(app: app));
      }

      _error = null;
      _updateStats();
    } on PlatformException catch (e) {
      _error = 'Failed to load installed apps: ${e.message ?? e.code}';
    } catch (e) {
      _error = 'Failed to load installed apps: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Scan all apps
  Future<void> scanAllApps() async {
    if (_isScanning) return;

    // Honor the App Security master toggle (Settings → prot_app). Fails open
    // (scans) when the preference is unreadable — an unreadable flag is not a
    // user opt-out.
    if (!await _isProtectionEnabledByUser()) return;

    _isScanning = true;
    _scanProgress = 0.0;
    notifyListeners();

    final appsToScan = _apps.where((a) => a.result == null).toList();
    final total = appsToScan.length;

    for (var i = 0; i < total; i++) {
      await analyzeApp(appsToScan[i].app.packageName);
      _scanProgress = (i + 1) / total;
      notifyListeners();
    }

    _isScanning = false;
    _updateStats();
    notifyListeners();
  }

  /// Reads the App Security master toggle (Settings → `prot_app`). Fails open
  /// (enabled) when preferences are unavailable.
  Future<bool> _isProtectionEnabledByUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('prot_app') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Analyze single app
  Future<AppAnalysisResult?> analyzeApp(String packageName) async {
    final index = _apps.indexWhere((a) => a.app.packageName == packageName);
    if (index < 0) return null;

    final app = _apps[index];
    _apps[index] = app.copyWith(isPending: true);
    notifyListeners();

    try {
      final request = AppAnalysisRequest(
        packageName: app.app.packageName,
        appName: app.app.appName,
        versionName: app.app.version,
        permissions: app.app.permissions
            .map((p) => AppPermissionInfo(
                  name: p,
                  isGranted: true,
                  isDangerous: AppPermissionInfo.isDangerousPermission(p),
                ))
            .toList(),
        installSource: app.app.installSource,
        detectedLibraries: app.app.detectedLibraries,
      );

      final result = await _api.analyzeApp(request);
      _apps[index] = app.copyWith(result: result, isPending: false);
      _updateStats();
      notifyListeners();
      return result;
    } catch (e) {
      _apps[index] = app.copyWith(
        isPending: false,
        error: 'Failed to analyze: $e',
      );
      notifyListeners();
      return null;
    }
  }

  /// Select app for detail view
  void selectApp(String packageName) {
    final index = _apps.indexWhere((a) => a.app.packageName == packageName);
    _selectedApp = index >= 0 ? _apps[index] : null;
    notifyListeners();
  }

  /// Clear selected app
  void clearSelectedApp() {
    _selectedApp = null;
    notifyListeners();
  }

  /// Set sort option
  void setSortOption(AppSortOption option) {
    _sortOption = option;
    notifyListeners();
  }

  /// Set filter option
  void setFilterOption(AppFilterOption option) {
    _filterOption = option;
    notifyListeners();
  }

  /// Get filtered and sorted apps
  List<AnalyzedApp> _getFilteredAndSortedApps() {
    var filtered = List<AnalyzedApp>.from(_apps);

    // Apply filter
    switch (_filterOption) {
      case AppFilterOption.all:
        break;
      case AppFilterOption.highRisk:
        filtered = filtered.where((a) => a.isHighRisk).toList();
        break;
      case AppFilterOption.sideloaded:
        filtered = filtered.where((a) => a.app.isSideloaded).toList();
        break;
      case AppFilterOption.hasTrackers:
        filtered = filtered
            .where((a) =>
                a.result != null && a.result!.detectedTrackers.isNotEmpty)
            .toList();
        break;
      case AppFilterOption.dangerousPermissions:
        filtered = filtered
            .where((a) =>
                a.result != null &&
                a.result!.permissionRisks.any((p) => p.isDangerous))
            .toList();
        break;
    }

    // Apply sort
    switch (_sortOption) {
      case AppSortOption.name:
        filtered.sort((a, b) => a.app.appName.compareTo(b.app.appName));
        break;
      case AppSortOption.riskScore:
        filtered.sort((a, b) => b.riskScore.compareTo(a.riskScore));
        break;
      case AppSortOption.installDate:
        filtered.sort((a, b) => b.app.installTime.compareTo(a.app.installTime));
        break;
      case AppSortOption.privacyGrade:
        filtered
            .sort((a, b) => a.privacyGrade.compareTo(b.privacyGrade));
        break;
    }

    return filtered;
  }

  /// Update stats
  void _updateStats() {
    int high = 0;
    int medium = 0;
    int low = 0;
    int analyzed = 0;
    int sideloaded = 0;
    int malware = 0;
    int trackers = 0;
    int dangerous = 0;

    for (final app in _apps) {
      if (app.app.isSideloaded) sideloaded++;

      if (app.result == null) continue;
      analyzed++;

      if (app.result!.isKnownMalware) malware++;
      trackers += app.result!.detectedTrackers.length;
      dangerous +=
          app.result!.permissionRisks.where((p) => p.isDangerous).length;

      if (app.isHighRisk) {
        high++;
      } else if (app.isMediumRisk) {
        medium++;
      } else {
        low++;
      }
    }

    _stats = AppSecurityStats(
      totalApps: _apps.length,
      analyzedApps: analyzed,
      highRiskApps: high,
      mediumRiskApps: medium,
      lowRiskApps: low,
      sideloadedApps: sideloaded,
      malwareDetected: malware,
      trackersFound: trackers,
      dangerousPermissions: dangerous,
    );
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Get privacy grade color
  static int getPrivacyGradeColor(String grade) {
    switch (grade.toUpperCase()) {
      case 'A':
      case 'A+':
        return 0xFF4CAF50;
      case 'B':
      case 'B+':
        return 0xFF8BC34A;
      case 'C':
        return 0xFFFFEB3B;
      case 'D':
        return 0xFFFF9800;
      case 'E':
      case 'F':
        return 0xFFF44336;
      default:
        return 0xFF9E9E9E;
    }
  }

  /// Get risk level color
  static int getRiskLevelColor(String level) {
    switch (level.toLowerCase()) {
      case 'critical':
        return 0xFFFF1744;
      case 'high':
        return 0xFFFF5722;
      case 'medium':
        return 0xFFFF9800;
      case 'low':
        return 0xFF4CAF50;
      default:
        return 0xFF9E9E9E;
    }
  }

  /// Get permission icon
  static String getPermissionIcon(String permission) {
    final lower = permission.toLowerCase();
    if (lower.contains('camera')) return 'camera';
    if (lower.contains('microphone') || lower.contains('record_audio')) {
      return 'mic';
    }
    if (lower.contains('location')) return 'location_on';
    if (lower.contains('contact')) return 'contacts';
    if (lower.contains('calendar')) return 'calendar_today';
    if (lower.contains('storage') || lower.contains('external')) {
      return 'folder';
    }
    if (lower.contains('sms')) return 'sms';
    if (lower.contains('phone') || lower.contains('call')) return 'phone';
    if (lower.contains('bluetooth')) return 'bluetooth';
    if (lower.contains('wifi') || lower.contains('network')) return 'wifi';
    if (lower.contains('notification')) return 'notifications';
    if (lower.contains('accessibility')) return 'accessibility';
    return 'security';
  }

}
