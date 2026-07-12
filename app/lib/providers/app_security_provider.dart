/// App Security Provider
/// State management for app security and privacy analysis

import 'package:flutter/foundation.dart';

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

  double get riskScore => result?.riskScore ?? 0.0;
  String get riskLevel => result?.riskLevel ?? 'unknown';
  String get privacyGrade => result?.privacyGrade ?? 'U';
  bool get isHighRisk => riskScore > 0.7 || (result?.isKnownMalware ?? false);
  bool get isMediumRisk => riskScore > 0.4 && !isHighRisk;
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

  /// Load installed apps from device
  Future<void> loadApps() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get list of installed apps from API (previously submitted/analyzed)
      final appsData = await _api.getInstalledApps();

      _apps.clear();
      for (final appJson in appsData) {
        final app = InstalledApp(
          packageName: appJson['package_name'] as String? ?? '',
          appName: appJson['app_name'] as String? ?? 'Unknown',
          version: appJson['version'] as String? ?? '0.0.0',
          iconPath: appJson['icon_path'] as String?,
          permissions: (appJson['permissions'] as List<dynamic>?)?.cast<String>() ?? [],
          installSource: appJson['install_source'] as String? ?? 'unknown',
          installTime: appJson['install_time'] != null
              ? DateTime.parse(appJson['install_time'] as String)
              : DateTime.now(),
          updateTime: appJson['update_time'] != null
              ? DateTime.parse(appJson['update_time'] as String)
              : null,
          apkSize: appJson['apk_size'] as int?,
        );

        // Check if there's an analysis result
        AppAnalysisResult? result;
        if (appJson['analysis_result'] != null) {
          result = AppAnalysisResult.fromJson(appJson['analysis_result'] as Map<String, dynamic>);
        }

        _apps.add(AnalyzedApp(app: app, result: result));
      }

      _updateStats();
    } catch (e) {
      _error = 'Failed to load apps: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Scan all apps
  Future<void> scanAllApps() async {
    if (_isScanning) return;

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
        version: app.app.version,
        permissions: app.app.permissions,
        installSource: app.app.installSource,
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
    _selectedApp = _apps.firstWhere(
      (a) => a.app.packageName == packageName,
      orElse: () => _apps.first,
    );
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
