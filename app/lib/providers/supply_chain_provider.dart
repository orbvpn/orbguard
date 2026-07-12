/// Supply Chain Provider
/// State management for supply chain vulnerability monitoring

import 'package:flutter/foundation.dart';

import '../services/security/supply_chain_monitor_service.dart';

class SupplyChainProvider extends ChangeNotifier {
  final SupplyChainMonitorService _service = SupplyChainMonitorService();

  // State
  List<DependencyScanResult> _scanResults = [];
  DependencyScanResult? _currentAppScan;
  Map<String, List<ThirdPartyLibrary>> _librariesByCategory = {};

  // Loading states
  bool _isLoading = false;
  bool _isScanning = false;
  double _scanProgress = 0.0;
  String _scanStatus = '';

  // Error state
  String? _error;

  // Getters
  List<DependencyScanResult> get scanResults => _scanResults;
  DependencyScanResult? get currentAppScan => _currentAppScan;
  Map<String, List<ThirdPartyLibrary>> get librariesByCategory => _librariesByCategory;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  double get scanProgress => _scanProgress;
  String get scanStatus => _scanStatus;
  String? get error => _error;

  // Computed getters
  int get totalAppsScanned => _scanResults.length;
  int get appsWithVulnerabilities =>
      _scanResults.where((r) => r.vulnerabilities.isNotEmpty).length;
  int get totalVulnerabilities =>
      _scanResults.fold(0, (sum, r) => sum + r.vulnerabilities.length);
  int get criticalVulnerabilities => _scanResults.fold(
      0,
      (sum, r) =>
          sum + r.vulnerabilities.where((v) => v.cvssScore >= 9.0).length);
  int get totalTrackers =>
      _scanResults.fold(0, (sum, r) => sum + r.trackerCount);

  List<Vulnerability> get allVulnerabilities {
    final vulns = <Vulnerability>[];
    for (final result in _scanResults) {
      vulns.addAll(result.vulnerabilities);
    }
    vulns.sort((a, b) => b.cvssScore.compareTo(a.cvssScore));
    return vulns;
  }

  List<ThirdPartyLibrary> get highRiskLibraries {
    final libs = <ThirdPartyLibrary>[];
    for (final result in _scanResults) {
      libs.addAll(result.highRiskLibraries);
    }
    return libs;
  }

  /// Initialize the provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.initialize();
      // Listen to scan results
      _service.onScanResult.listen((result) {
        _scanResults.add(result);
        _updateLibraryCategories();
        notifyListeners();
      });

      // Listen to vulnerability alerts
      _service.onVulnerabilityAlert.listen((vuln) {
        // Handle critical vulnerability alert
        debugPrint('Critical vulnerability found: ${vuln.cveId}');
      });
    } catch (e) {
      _error = 'Failed to initialize supply chain monitor';
      debugPrint('Error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Scan a specific app
  Future<DependencyScanResult?> scanApp(String packageName) async {
    if (_isScanning) return null;

    _isScanning = true;
    _scanProgress = 0.0;
    _scanStatus = 'Scanning $packageName...';
    _error = null;
    notifyListeners();

    try {
      _scanProgress = 0.2;
      _scanStatus = 'Analyzing dependencies...';
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 200));

      _scanProgress = 0.5;
      _scanStatus = 'Checking vulnerabilities...';
      notifyListeners();

      final result = await _service.scanApp(packageName);
      _currentAppScan = result;

      _scanProgress = 0.8;
      _scanStatus = 'Analyzing trackers...';
      notifyListeners();
      await Future.delayed(const Duration(milliseconds: 200));

      _scanProgress = 1.0;
      _scanStatus = 'Complete';
      notifyListeners();

      return result;
    } catch (e) {
      _error = 'Scan failed: $e';
      notifyListeners();
      return null;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Scan all installed apps
  Future<void> scanAllApps({bool userAppsOnly = true}) async {
    if (_isScanning) return;

    _isScanning = true;
    _scanProgress = 0.0;
    _scanStatus = 'Starting full scan...';
    _scanResults.clear();
    _error = null;
    notifyListeners();

    try {
      final results = await _service.scanAllApps(userAppsOnly: userAppsOnly);
      _scanResults = results;
      _updateLibraryCategories();

      _scanProgress = 1.0;
      _scanStatus = 'Scan complete';
    } catch (e) {
      _error = 'Scan failed: $e';
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Update library categories mapping
  void _updateLibraryCategories() {
    _librariesByCategory.clear();

    for (final result in _scanResults) {
      for (final lib in result.libraries) {
        final categoryName = lib.category.displayName;
        _librariesByCategory[categoryName] ??= [];
        _librariesByCategory[categoryName]!.add(lib);
      }
    }
  }

  /// Get scan result for specific app
  DependencyScanResult? getScanResult(String packageName) {
    return _scanResults
        .where((r) => r.appPackage == packageName)
        .firstOrNull;
  }

  /// Get risk level color
  static int getRiskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.critical:
        return 0xFFFF1744;
      case RiskLevel.high:
        return 0xFFFF5722;
      case RiskLevel.medium:
        return 0xFFFF9800;
      case RiskLevel.low:
        return 0xFFFFEB3B;
      case RiskLevel.safe:
        return 0xFF4CAF50;
    }
  }

  /// Get category icon
  static String getCategoryIcon(LibraryCategory category) {
    switch (category) {
      case LibraryCategory.analytics:
        return 'analytics';
      case LibraryCategory.advertising:
        return 'campaign';
      case LibraryCategory.crashReporting:
        return 'bug_report';
      case LibraryCategory.authentication:
        return 'fingerprint';
      case LibraryCategory.payment:
        return 'payment';
      case LibraryCategory.socialMedia:
        return 'share';
      case LibraryCategory.cloud:
        return 'cloud';
      case LibraryCategory.database:
        return 'storage';
      case LibraryCategory.networking:
        return 'wifi';
      case LibraryCategory.security:
        return 'security';
      case LibraryCategory.ui:
        return 'palette';
      case LibraryCategory.utility:
        return 'build';
      case LibraryCategory.malicious:
        return 'dangerous';
      case LibraryCategory.unknown:
        return 'help_outline';
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Clear current app scan
  void clearCurrentScan() {
    _currentAppScan = null;
    notifyListeners();
  }

  /// Dispose
  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }
}
