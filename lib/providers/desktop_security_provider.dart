/// Desktop Security Provider
/// Unified provider for Windows, macOS, and Linux persistence scanning
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/security/macos_persistence_scanner_service.dart';
import '../services/security/windows_persistence_scanner_service.dart';
import '../services/security/linux_persistence_scanner_service.dart';

/// Unified persistence item for all platforms
class DesktopPersistenceItem {
  final String id;
  final String name;
  final String path;
  final String? command;
  final String type;
  final String typeDisplayName;
  final DesktopItemRisk risk;
  final String signingStatus;
  final String? publisher;
  final String? description;
  final String? owner;
  final String? permissions;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool isEnabled;
  final List<String> indicators;
  final Map<String, dynamic>? metadata;

  DesktopPersistenceItem({
    required this.id,
    required this.name,
    required this.path,
    this.command,
    required this.type,
    required this.typeDisplayName,
    required this.risk,
    this.signingStatus = 'Unknown',
    this.publisher,
    this.description,
    this.owner,
    this.permissions,
    this.createdAt,
    this.modifiedAt,
    this.isEnabled = true,
    this.indicators = const [],
    this.metadata,
  });
}

/// Unified risk level
enum DesktopItemRisk {
  safe('Safe', 'Known legitimate software', 0),
  low('Low', 'Uncommon but likely safe', 1),
  medium('Medium', 'Potentially unwanted', 2),
  high('High', 'Suspicious characteristics', 3),
  critical('Critical', 'Known malware indicators', 4);

  final String displayName;
  final String description;
  final int level;

  const DesktopItemRisk(this.displayName, this.description, this.level);
}

/// Desktop scan result
class DesktopScanResult {
  final String platform;
  final DateTime scannedAt;
  final Duration scanDuration;
  final int totalItems;
  final int criticalItems;
  final int highRiskItems;
  final int mediumRiskItems;
  final int safeItems;
  final List<DesktopPersistenceItem> items;
  final List<String> errors;

  DesktopScanResult({
    required this.platform,
    required this.scannedAt,
    required this.scanDuration,
    required this.totalItems,
    required this.criticalItems,
    required this.highRiskItems,
    required this.mediumRiskItems,
    required this.safeItems,
    required this.items,
    this.errors = const [],
  });

  int get riskScore {
    if (totalItems == 0) return 100;
    final weighted = (criticalItems * 25) + (highRiskItems * 10) + (mediumRiskItems * 3);
    return (100 - weighted).clamp(0, 100);
  }

  String get riskGrade {
    final score = riskScore;
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 60) return 'D';
    return 'F';
  }
}

/// Desktop Security Provider
class DesktopSecurityProvider extends ChangeNotifier {
  // Platform scanners
  final MacOSPersistenceScannerService _macosScanner = MacOSPersistenceScannerService();
  final WindowsPersistenceScannerService _windowsScanner = WindowsPersistenceScannerService.instance;
  final LinuxPersistenceScannerService _linuxScanner = LinuxPersistenceScannerService.instance;

  // State
  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;
  String _currentPhase = '';
  double _scanProgress = 0.0;
  DesktopScanResult? _lastScanResult;
  List<DesktopPersistenceItem> _items = [];

  // Getters
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get error => _error;
  String get currentPhase => _currentPhase;
  double get scanProgress => _scanProgress;
  DesktopScanResult? get lastScanResult => _lastScanResult;
  List<DesktopPersistenceItem> get items => _items;

  String get currentPlatform {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  bool get isDesktopPlatform =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  int get criticalCount => _items.where((i) => i.risk == DesktopItemRisk.critical).length;
  int get highRiskCount => _items.where((i) => i.risk == DesktopItemRisk.high).length;
  int get mediumRiskCount => _items.where((i) => i.risk == DesktopItemRisk.medium).length;
  int get lowRiskCount => _items.where((i) => i.risk == DesktopItemRisk.low).length;
  int get safeCount => _items.where((i) => i.risk == DesktopItemRisk.safe).length;

  /// Initialize provider
  Future<void> init() async {
    if (!isDesktopPlatform) {
      _error = 'Desktop scanning not available on mobile platforms';
      return;
    }

    _isLoading = true;
    notifyListeners();

    // Load any cached results
    await _loadCachedResults();

    _isLoading = false;
    notifyListeners();
  }

  /// Run full persistence scan
  Future<DesktopScanResult> runFullScan() async {
    if (!isDesktopPlatform) {
      return DesktopScanResult(
        platform: 'Unknown',
        scannedAt: DateTime.now(),
        scanDuration: Duration.zero,
        totalItems: 0,
        criticalItems: 0,
        highRiskItems: 0,
        mediumRiskItems: 0,
        safeItems: 0,
        items: [],
        errors: ['Desktop scanning not available on this platform'],
      );
    }

    _isScanning = true;
    _scanProgress = 0.0;
    _error = null;
    _currentPhase = 'Initializing scan...';
    notifyListeners();

    final startTime = DateTime.now();
    final items = <DesktopPersistenceItem>[];
    final errors = <String>[];

    try {
      if (Platform.isMacOS) {
        final result = await _macosScanner.runFullScan(
          onProgress: (phase, progress) {
            _currentPhase = phase;
            _scanProgress = progress;
            notifyListeners();
          },
        );
        items.addAll(_convertMacOSItems(result.items));
      } else if (Platform.isWindows) {
        final result = await _windowsScanner.runFullScan(
          onProgress: (phase, progress) {
            _currentPhase = phase;
            _scanProgress = progress;
            notifyListeners();
          },
        );
        items.addAll(_convertWindowsItems(result.items));
        errors.addAll(result.errors);
      } else if (Platform.isLinux) {
        final result = await _linuxScanner.runFullScan(
          onProgress: (phase, progress) {
            _currentPhase = phase;
            _scanProgress = progress;
            notifyListeners();
          },
        );
        items.addAll(_convertLinuxItems(result.items));
        errors.addAll(result.errors);
      }
    } catch (e) {
      errors.add('Scan error: $e');
    }

    final endTime = DateTime.now();

    // Sort by risk level (highest first)
    items.sort((a, b) => b.risk.level.compareTo(a.risk.level));

    _items = items;
    _lastScanResult = DesktopScanResult(
      platform: currentPlatform,
      scannedAt: startTime,
      scanDuration: endTime.difference(startTime),
      totalItems: items.length,
      criticalItems: items.where((i) => i.risk == DesktopItemRisk.critical).length,
      highRiskItems: items.where((i) => i.risk == DesktopItemRisk.high).length,
      mediumRiskItems: items.where((i) => i.risk == DesktopItemRisk.medium).length,
      safeItems: items.where((i) => i.risk == DesktopItemRisk.safe || i.risk == DesktopItemRisk.low).length,
      items: items,
      errors: errors,
    );

    _isScanning = false;
    _currentPhase = 'Scan complete';
    _scanProgress = 1.0;
    notifyListeners();

    return _lastScanResult!;
  }

  /// Quick scan (high-risk locations only)
  Future<DesktopScanResult> runQuickScan() async {
    // For quick scan, we'll filter to only critical and high risk items
    final result = await runFullScan();

    final filteredItems = result.items
        .where((i) => i.risk.level >= DesktopItemRisk.medium.level)
        .toList();

    return DesktopScanResult(
      platform: result.platform,
      scannedAt: result.scannedAt,
      scanDuration: result.scanDuration,
      totalItems: filteredItems.length,
      criticalItems: result.criticalItems,
      highRiskItems: result.highRiskItems,
      mediumRiskItems: result.mediumRiskItems,
      safeItems: 0,
      items: filteredItems,
      errors: result.errors,
    );
  }

  /// Filter items by risk level
  List<DesktopPersistenceItem> filterByRisk(DesktopItemRisk minRisk) {
    return _items.where((i) => i.risk.level >= minRisk.level).toList();
  }

  /// Filter items by type
  List<DesktopPersistenceItem> filterByType(String type) {
    return _items.where((i) => i.type == type).toList();
  }

  /// Get unique item types
  List<String> getItemTypes() {
    return _items.map((i) => i.typeDisplayName).toSet().toList()..sort();
  }

  /// Convert macOS items to unified format
  List<DesktopPersistenceItem> _convertMacOSItems(List<PersistenceItem> items) {
    return items.map((item) => DesktopPersistenceItem(
      id: item.id,
      name: item.name,
      path: item.path,
      command: item.executablePath,
      type: item.type.name,
      typeDisplayName: item.type.displayName,
      risk: _convertMacOSRisk(item.status),
      signingStatus: item.signingStatus.displayName,
      publisher: item.signingAuthority,
      description: item.bundleId,
      createdAt: item.createdDate,
      modifiedAt: item.modifiedDate,
      isEnabled: item.isEnabled,
      indicators: item.suspiciousIndicators,
      metadata: item.plistData,
    )).toList();
  }

  /// Convert Windows items to unified format
  List<DesktopPersistenceItem> _convertWindowsItems(List<WindowsPersistenceItem> items) {
    return items.map((item) => DesktopPersistenceItem(
      id: item.id,
      name: item.name,
      path: item.path,
      command: item.command,
      type: item.type.name,
      typeDisplayName: item.type.displayName,
      risk: _convertWindowsRisk(item.risk),
      signingStatus: item.signingStatus.displayName,
      publisher: item.publisher,
      description: item.description,
      createdAt: item.createdAt,
      modifiedAt: item.modifiedAt,
      isEnabled: item.isEnabled,
      indicators: item.indicators,
      metadata: item.metadata,
    )).toList();
  }

  /// Convert Linux items to unified format
  List<DesktopPersistenceItem> _convertLinuxItems(List<LinuxPersistenceItem> items) {
    return items.map((item) => DesktopPersistenceItem(
      id: item.id,
      name: item.name,
      path: item.path,
      command: item.command,
      type: item.type.name,
      typeDisplayName: item.type.displayName,
      risk: _convertLinuxRisk(item.risk),
      owner: item.owner,
      permissions: item.permissions,
      description: item.description,
      createdAt: item.createdAt,
      modifiedAt: item.modifiedAt,
      isEnabled: item.isEnabled,
      indicators: item.indicators,
      metadata: item.metadata,
    )).toList();
  }

  /// Convert macOS risk level
  DesktopItemRisk _convertMacOSRisk(ItemStatus status) {
    switch (status) {
      case ItemStatus.legitimate:
        return DesktopItemRisk.safe;
      case ItemStatus.unknown:
        return DesktopItemRisk.low;
      case ItemStatus.suspicious:
        return DesktopItemRisk.high;
      case ItemStatus.malicious:
        return DesktopItemRisk.critical;
    }
  }

  /// Convert Windows risk level
  DesktopItemRisk _convertWindowsRisk(WindowsItemRisk risk) {
    switch (risk) {
      case WindowsItemRisk.safe:
        return DesktopItemRisk.safe;
      case WindowsItemRisk.low:
        return DesktopItemRisk.low;
      case WindowsItemRisk.medium:
        return DesktopItemRisk.medium;
      case WindowsItemRisk.high:
        return DesktopItemRisk.high;
      case WindowsItemRisk.critical:
        return DesktopItemRisk.critical;
    }
  }

  /// Convert Linux risk level
  DesktopItemRisk _convertLinuxRisk(LinuxItemRisk risk) {
    switch (risk) {
      case LinuxItemRisk.safe:
        return DesktopItemRisk.safe;
      case LinuxItemRisk.low:
        return DesktopItemRisk.low;
      case LinuxItemRisk.medium:
        return DesktopItemRisk.medium;
      case LinuxItemRisk.high:
        return DesktopItemRisk.high;
      case LinuxItemRisk.critical:
        return DesktopItemRisk.critical;
    }
  }

  /// Load cached scan results
  Future<void> _loadCachedResults() async {
    // TODO: Implement caching with shared_preferences or similar
  }

  /// Export scan results
  Map<String, dynamic> exportResults() {
    if (_lastScanResult == null) return {};

    return {
      'platform': _lastScanResult!.platform,
      'scanned_at': _lastScanResult!.scannedAt.toIso8601String(),
      'scan_duration_ms': _lastScanResult!.scanDuration.inMilliseconds,
      'risk_score': _lastScanResult!.riskScore,
      'risk_grade': _lastScanResult!.riskGrade,
      'summary': {
        'total': _lastScanResult!.totalItems,
        'critical': _lastScanResult!.criticalItems,
        'high': _lastScanResult!.highRiskItems,
        'medium': _lastScanResult!.mediumRiskItems,
        'safe': _lastScanResult!.safeItems,
      },
      'items': _items.map((i) => {
        'id': i.id,
        'name': i.name,
        'path': i.path,
        'command': i.command,
        'type': i.type,
        'risk': i.risk.name,
        'signing_status': i.signingStatus,
        'indicators': i.indicators,
      }).toList(),
      'errors': _lastScanResult!.errors,
    };
  }
}
