/// Desktop Security Provider
/// Unified provider for Windows, macOS, and Linux persistence scanning
library;

import 'dart:convert';
import 'dart:io';
import '../utils/platform_info.dart';
import '../services/security/desktop_scan_config.dart';

import 'package:flutter/foundation.dart';

import '../services/api/orbguard_api_client.dart';
import '../services/security/desktop_host_collector.dart';
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

/// Quarantined item with metadata
class QuarantinedItem {
  final String fileName;
  final String originalPath;
  final String name;
  final String type;
  final DateTime? quarantinedAt;
  final bool isService;
  final bool isRegistry;
  final bool isTask;

  /// Path to the `reg export` backup taken before a registry value was
  /// deleted; enables automatic registry restore via `reg import`.
  final String? registryBackupPath;

  QuarantinedItem({
    required this.fileName,
    required this.originalPath,
    required this.name,
    required this.type,
    this.quarantinedAt,
    this.isService = false,
    this.isRegistry = false,
    this.isTask = false,
    this.registryBackupPath,
  });

  bool get canAutoRestore =>
      originalPath.isNotEmpty &&
      (!isRegistry || (registryBackupPath != null && registryBackupPath!.isNotEmpty));
}

/// Observed state of the OS host firewall.
enum HostFirewallState {
  enabled,
  disabled,

  /// The firewall tool exists but its state could not be read (e.g. needs
  /// elevation). Never rendered as "protected".
  unknown,

  /// No supported firewall tooling found on this host.
  unavailable,
}

/// Real OS firewall status read from the platform firewall tooling.
class HostFirewallStatus {
  final HostFirewallState state;

  /// Honest human-readable detail (per-profile states, raw tool summary or
  /// the exact failure).
  final String detail;

  /// Exactly which command produced this status.
  final String source;

  const HostFirewallStatus({
    required this.state,
    required this.detail,
    required this.source,
  });
}

/// Result of an OS firewall mutation (toggle, quick action, local rule).
class FirewallActionResult {
  final bool success;

  /// The user dismissed the admin/polkit/UAC prompt.
  final bool cancelled;

  /// The OS refused the operation for lack of privileges (and no elevation
  /// path succeeded).
  final bool permissionDenied;

  /// The operation is not supported by this platform's firewall tooling.
  final bool unsupported;

  /// Honest detail: stdout/stderr of the real command, or why it could not
  /// run.
  final String message;

  const FirewallActionResult({
    required this.success,
    this.cancelled = false,
    this.permissionDenied = false,
    this.unsupported = false,
    required this.message,
  });
}

/// Desktop Security Provider
class DesktopSecurityProvider extends ChangeNotifier {
  // Platform scanners
  final MacOSPersistenceScannerService _macosScanner = MacOSPersistenceScannerService();
  final WindowsPersistenceScannerService _windowsScanner = WindowsPersistenceScannerService.instance;
  final LinuxPersistenceScannerService _linuxScanner = LinuxPersistenceScannerService.instance;

  // Backend API client (used ONLY for value-based lookups the backend can
  // genuinely answer for this device: VirusTotal hash/IP enrichment).
  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  // State
  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;
  String _currentPhase = '';
  double _scanProgress = 0.0;
  DesktopScanResult? _lastScanResult;
  List<DesktopPersistenceItem> _items = [];

  // Host firewall state (real OS firewall, read via platform tooling)
  HostFirewallStatus? _hostFirewallStatus;

  // Host-local network connection collection
  List<Map<String, dynamic>> _hostNetworkConnections = [];
  List<String> _hostNetworkErrors = [];
  String _hostNetworkSource = '';
  DateTime? _hostNetworkCollectedAt;
  bool _isCollectingNetwork = false;

  // Host-local browser extension collection
  Map<String, dynamic>? _hostBrowserScan;
  bool _isCollectingBrowser = false;

  // Local code-signing verification
  List<Map<String, dynamic>> _localSignedApps = [];
  String? _codeSigningUnavailableReason;
  bool _isVerifyingCodeSigning = false;

  // Getters
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  String? get error => _error;
  String get currentPhase => _currentPhase;
  double get scanProgress => _scanProgress;
  DesktopScanResult? get lastScanResult => _lastScanResult;
  List<DesktopPersistenceItem> get items => _items;

  HostFirewallStatus? get hostFirewallStatus => _hostFirewallStatus;
  List<Map<String, dynamic>> get hostNetworkConnections => _hostNetworkConnections;
  List<String> get hostNetworkErrors => _hostNetworkErrors;
  String get hostNetworkSource => _hostNetworkSource;
  DateTime? get hostNetworkCollectedAt => _hostNetworkCollectedAt;
  bool get isCollectingNetwork => _isCollectingNetwork;
  Map<String, dynamic>? get hostBrowserScan => _hostBrowserScan;
  bool get isCollectingBrowser => _isCollectingBrowser;
  List<Map<String, dynamic>> get localSignedApps => _localSignedApps;
  String? get codeSigningUnavailableReason => _codeSigningUnavailableReason;
  bool get isVerifyingCodeSigning => _isVerifyingCodeSigning;

  String get currentPlatform {
    if (PlatformInfo.isMacOS) return 'macOS';
    if (PlatformInfo.isWindows) return 'Windows';
    if (PlatformInfo.isLinux) return 'Linux';
    return 'Unknown';
  }

  bool get isDesktopPlatform =>
      PlatformInfo.isMacOS || PlatformInfo.isWindows || PlatformInfo.isLinux;

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
      final cfg = await DesktopScanConfig.load();
      if (PlatformInfo.isMacOS) {
        final result = await _macosScanner.runFullScan(
          config: cfg,
          onProgress: (phase, progress) {
            _currentPhase = phase;
            _scanProgress = progress;
            notifyListeners();
          },
        );
        items.addAll(_convertMacOSItems(result.items));
      } else if (PlatformInfo.isWindows) {
        final result = await _windowsScanner.runFullScan(
          config: cfg,
          onProgress: (phase, progress) {
            _currentPhase = phase;
            _scanProgress = progress;
            notifyListeners();
          },
        );
        items.addAll(_convertWindowsItems(result.items));
        errors.addAll(result.errors);
      } else if (PlatformInfo.isLinux) {
        final result = await _linuxScanner.runFullScan(
          config: cfg,
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

    // Save results to cache
    await _saveCachedResults();

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
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        final content = await cacheFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;

        // Check if cache is still valid (less than 1 hour old)
        final cachedAt = DateTime.parse(json['cached_at'] as String);
        if (DateTime.now().difference(cachedAt).inHours < 1) {
          _items = (json['items'] as List).map((item) => DesktopPersistenceItem(
            id: item['id'] as String,
            name: item['name'] as String,
            path: item['path'] as String,
            command: item['command'] as String?,
            type: item['type'] as String,
            typeDisplayName: item['type_display_name'] as String,
            risk: DesktopItemRisk.values.firstWhere(
              (r) => r.name == item['risk'],
              orElse: () => DesktopItemRisk.low,
            ),
            signingStatus: item['signing_status'] as String? ?? 'Unknown',
            indicators: (item['indicators'] as List?)?.cast<String>() ?? [],
          )).toList();
          notifyListeners();
        }
      }
    } catch (e) {
      // Cache load failed, will run fresh scan
    }
  }

  /// Save scan results to cache
  Future<void> _saveCachedResults() async {
    try {
      final cacheFile = await _getCacheFile();
      final json = {
        'cached_at': DateTime.now().toIso8601String(),
        'platform': currentPlatform,
        'items': _items.map((i) => {
          'id': i.id,
          'name': i.name,
          'path': i.path,
          'command': i.command,
          'type': i.type,
          'type_display_name': i.typeDisplayName,
          'risk': i.risk.name,
          'signing_status': i.signingStatus,
          'indicators': i.indicators,
        }).toList(),
      };
      await cacheFile.writeAsString(jsonEncode(json));
    } catch (e) {
      // Cache save failed, ignore
    }
  }

  /// Get cache file path
  Future<File> _getCacheFile() async {
    final home = PlatformInfo.environment['HOME'] ?? PlatformInfo.environment['USERPROFILE'] ?? '';
    final cacheDir = Directory('$home/.orbguard/cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return File('${cacheDir.path}/persistence_scan_cache.json');
  }

  /// Clear cached results
  Future<void> clearCache() async {
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        await cacheFile.delete();
      }
      _items.clear();
      _lastScanResult = null;
      notifyListeners();
    } catch (e) {
      // Ignore
    }
  }

  /// Disable/quarantine a persistence item
  Future<bool> disableItem(DesktopPersistenceItem item) async {
    try {
      if (PlatformInfo.isMacOS) {
        return await _disableMacOSItem(item);
      } else if (PlatformInfo.isLinux) {
        return await _disableLinuxItem(item);
      } else if (PlatformInfo.isWindows) {
        return await _disableWindowsItem(item);
      }
    } catch (e) {
      _error = 'Failed to disable item: $e';
      notifyListeners();
    }
    return false;
  }

  /// Moves a file into quarantine. Uses rename when possible and falls back
  /// to copy+delete (cross-volume), surfacing the real failure otherwise.
  Future<bool> _moveFileToQuarantine(String path, String quarantinePath) async {
    final file = File(path);
    try {
      await file.rename(quarantinePath);
      return true;
    } on FileSystemException {
      try {
        await file.copy(quarantinePath);
        await file.delete();
        return true;
      } on FileSystemException catch (e) {
        _error =
            'Failed to quarantine $path: ${e.osError?.message ?? e.message}. '
            'System-owned locations require elevated privileges.';
        notifyListeners();
        return false;
      }
    }
  }

  /// Disable macOS persistence item: unload, then move-to-quarantine BEFORE
  /// anything is deleted so the item can always be restored.
  Future<bool> _disableMacOSItem(DesktopPersistenceItem item) async {
    final path = item.path;

    // For LaunchAgents/Daemons, unload and move to quarantine
    if (path.contains('LaunchAgents') || path.contains('LaunchDaemons')) {
      // Unload the service. A non-zero exit is non-fatal (the job may simply
      // not be loaded) but is recorded for transparency.
      final unload = await Process.run('launchctl', ['unload', path]);
      if (unload.exitCode != 0) {
        debugPrint(
            'launchctl unload $path exited ${unload.exitCode}: ${unload.stderr}');
      }

      // Move to quarantine (backup-before-disable)
      final quarantineDir = await _getQuarantineDir();
      final fileName = path.split('/').last;
      final quarantinePath = '${quarantineDir.path}/$fileName';

      if (!await _moveFileToQuarantine(path, quarantinePath)) return false;

      // Save quarantine metadata for automatic restore
      await _saveQuarantineMetadata(fileName, path, item);

      // Update local state
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For login items, use osascript to remove
    if (item.type.contains('loginItem')) {
      final result = await Process.run('osascript', [
        '-e', 'tell application "System Events" to delete login item "${item.name}"'
      ]);
      if (result.exitCode != 0) {
        _error =
            'Failed to remove login item "${item.name}": ${(result.stderr as String).trim()}';
        notifyListeners();
        return false;
      }
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    _error = 'Quarantine is not supported for item type "${item.typeDisplayName}"';
    notifyListeners();
    return false;
  }

  /// Disable Linux persistence item with move-to-quarantine before delete.
  Future<bool> _disableLinuxItem(DesktopPersistenceItem item) async {
    final path = item.path;

    // For systemd services, disable them (user scope first, then system)
    if (item.type.contains('systemd')) {
      final serviceName = path.split('/').last;
      var result =
          await Process.run('systemctl', ['--user', 'disable', serviceName]);
      if (result.exitCode != 0) {
        // Not a user unit — try the system scope (works when the unit is
        // enabled for the current user or polkit allows it).
        result = await Process.run('systemctl', ['disable', serviceName]);
      }
      if (result.exitCode != 0) {
        _error =
            'systemctl disable $serviceName failed (exit ${result.exitCode}): '
            '${(result.stderr as String).trim()}';
        notifyListeners();
        return false;
      }
      // Save metadata for systemd services too
      await _saveQuarantineMetadata(serviceName, path, item, isService: true);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For other items, move to quarantine (backup-before-disable)
    final quarantineDir = await _getQuarantineDir();
    final fileName = path.split('/').last;
    final quarantinePath = '${quarantineDir.path}/$fileName';

    if (!await _moveFileToQuarantine(path, quarantinePath)) return false;
    // Save quarantine metadata for automatic restore
    await _saveQuarantineMetadata(fileName, path, item);
    _items.removeWhere((i) => i.id == item.id);
    notifyListeners();
    return true;
  }

  /// Disable Windows persistence item.
  ///
  /// Registry values are backed up with `reg export` BEFORE `reg delete` so
  /// they can be restored automatically with `reg import`. Every command's
  /// exit code is checked; nothing is reported as quarantined unless the
  /// command actually succeeded.
  Future<bool> _disableWindowsItem(DesktopPersistenceItem item) async {
    // For registry items, back up the key then delete the value
    if (item.type.contains('registry')) {
      final parts = item.path.split('\\');
      final keyPath = parts.sublist(0, parts.length - 1).join('\\');

      // 1. Backup: reg export of the containing key.
      final quarantineDir = await _getQuarantineDir();
      final safeName = item.name.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final backupPath =
          '${quarantineDir.path}\\registry_${safeName}_${DateTime.now().millisecondsSinceEpoch}.reg';
      final export = await Process.run(
        'reg', ['export', keyPath, backupPath, '/y'],
        runInShell: true,
      );
      if (export.exitCode != 0) {
        _error =
            'Registry backup failed for $keyPath (exit ${export.exitCode}): '
            '${(export.stderr as String).trim()}. Value was NOT deleted.';
        notifyListeners();
        return false;
      }

      // 2. Delete the value only after the backup exists.
      final del = await Process.run(
        'reg', ['delete', keyPath, '/v', item.name, '/f'],
        runInShell: true,
      );
      if (del.exitCode != 0) {
        _error =
            'reg delete failed for $keyPath\\${item.name} (exit ${del.exitCode}): '
            '${(del.stderr as String).trim()}';
        notifyListeners();
        return false;
      }

      // Save metadata for registry restore (with the backup location)
      await _saveQuarantineMetadata(
        item.name,
        item.path,
        item,
        isRegistry: true,
        registryBackupPath: backupPath,
        registryKeyPath: keyPath,
      );
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For scheduled tasks, disable them
    if (item.type.contains('scheduledTask')) {
      final result = await Process.run(
        'schtasks', ['/Change', '/TN', item.name, '/Disable'],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        _error =
            'schtasks /Disable failed for "${item.name}" (exit ${result.exitCode}): '
            '${(result.stderr as String).trim()}';
        notifyListeners();
        return false;
      }
      // Save metadata for task restore
      await _saveQuarantineMetadata(item.name, item.path, item, isTask: true);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For services, disable them
    if (item.type.contains('service')) {
      final result = await Process.run(
        'sc', ['config', item.name, 'start=', 'disabled'],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        _error =
            'sc config failed for "${item.name}" (exit ${result.exitCode}): '
            '${(result.stdout as String).trim()} ${(result.stderr as String).trim()}. '
            'Disabling services usually requires running OrbGuard as Administrator.';
        notifyListeners();
        return false;
      }
      // Save metadata for service restore
      await _saveQuarantineMetadata(item.name, item.path, item, isService: true);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    _error = 'Quarantine is not supported for item type "${item.typeDisplayName}"';
    notifyListeners();
    return false;
  }

  /// Get quarantine directory
  Future<Directory> _getQuarantineDir() async {
    final home = PlatformInfo.environment['HOME'] ?? PlatformInfo.environment['USERPROFILE'] ?? '';
    final quarantineDir = Directory('$home/.orbguard/quarantine');
    if (!await quarantineDir.exists()) {
      await quarantineDir.create(recursive: true);
    }
    return quarantineDir;
  }

  /// Get quarantine metadata file
  Future<File> _getQuarantineMetadataFile() async {
    final quarantineDir = await _getQuarantineDir();
    return File('${quarantineDir.path}/.metadata.json');
  }

  /// Save quarantine metadata for automatic restore
  Future<void> _saveQuarantineMetadata(
    String fileName,
    String originalPath,
    DesktopPersistenceItem item, {
    bool isService = false,
    bool isRegistry = false,
    bool isTask = false,
    String? registryBackupPath,
    String? registryKeyPath,
  }) async {
    try {
      final metadataFile = await _getQuarantineMetadataFile();
      Map<String, dynamic> metadata = {};

      // Load existing metadata
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        metadata = jsonDecode(content) as Map<String, dynamic>;
      }

      // Add new entry
      metadata[fileName] = {
        'original_path': originalPath,
        'name': item.name,
        'type': item.type,
        'type_display_name': item.typeDisplayName,
        'quarantined_at': DateTime.now().toIso8601String(),
        'is_service': isService,
        'is_registry': isRegistry,
        'is_task': isTask,
        if (registryBackupPath != null) 'registry_backup': registryBackupPath,
        if (registryKeyPath != null) 'registry_key': registryKeyPath,
        'platform': currentPlatform,
        'command': item.command,
        'risk': item.risk.name,
      };

      await metadataFile.writeAsString(jsonEncode(metadata));
    } catch (e) {
      // Metadata save failed, continue anyway
    }
  }

  /// Load quarantine metadata
  Future<Map<String, dynamic>> _loadQuarantineMetadata() async {
    try {
      final metadataFile = await _getQuarantineMetadataFile();
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      // Ignore
    }
    return {};
  }

  /// Delete quarantine metadata entry
  Future<void> _deleteQuarantineMetadata(String fileName) async {
    try {
      final metadataFile = await _getQuarantineMetadataFile();
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final metadata = jsonDecode(content) as Map<String, dynamic>;
        metadata.remove(fileName);
        await metadataFile.writeAsString(jsonEncode(metadata));
      }
    } catch (e) {
      // Ignore
    }
  }

  /// Restore a quarantined item (automatic path lookup)
  Future<bool> restoreItem(String quarantinedFileName, [String? originalPath]) async {
    try {
      final quarantineDir = await _getQuarantineDir();
      final quarantinedFile = File('${quarantineDir.path}/$quarantinedFileName');

      // Load metadata to get original path if not provided
      String restorePath = originalPath ?? '';
      final metadata = await _loadQuarantineMetadata();
      final itemMeta = metadata[quarantinedFileName] as Map<String, dynamic>?;

      if (restorePath.isEmpty && itemMeta != null) {
        restorePath = itemMeta['original_path'] as String? ?? '';
      }

      if (restorePath.isEmpty) {
        _error = 'Original path not found. Cannot restore without path.';
        notifyListeners();
        return false;
      }

      // Handle different item types
      final isService = itemMeta?['is_service'] as bool? ?? false;
      final isRegistry = itemMeta?['is_registry'] as bool? ?? false;
      final isTask = itemMeta?['is_task'] as bool? ?? false;

      if (isService) {
        // Re-enable service
        ProcessResult? result;
        if (PlatformInfo.isLinux) {
          result = await Process.run(
              'systemctl', ['--user', 'enable', quarantinedFileName]);
          if (result.exitCode != 0) {
            result =
                await Process.run('systemctl', ['enable', quarantinedFileName]);
          }
        } else if (PlatformInfo.isWindows) {
          result = await Process.run(
              'sc', ['config', quarantinedFileName, 'start=', 'auto'],
              runInShell: true);
        }
        if (result == null || result.exitCode != 0) {
          _error = result == null
              ? 'Service restore is not supported on this platform'
              : 'Failed to re-enable service (exit ${result.exitCode}): '
                  '${(result.stderr as String).trim()}';
          notifyListeners();
          return false;
        }
        await _deleteQuarantineMetadata(quarantinedFileName);
        return true;
      }

      if (isTask && PlatformInfo.isWindows) {
        // Re-enable scheduled task
        final result = await Process.run(
            'schtasks', ['/Change', '/TN', quarantinedFileName, '/Enable'],
            runInShell: true);
        if (result.exitCode != 0) {
          _error =
              'Failed to re-enable task (exit ${result.exitCode}): '
              '${(result.stderr as String).trim()}';
          notifyListeners();
          return false;
        }
        await _deleteQuarantineMetadata(quarantinedFileName);
        return true;
      }

      if (isRegistry && PlatformInfo.isWindows) {
        // Restore the registry key from the reg export backup taken before
        // deletion.
        final backupPath = itemMeta?['registry_backup'] as String? ?? '';
        if (backupPath.isEmpty || !await File(backupPath).exists()) {
          _error =
              'No registry backup found for this item; it must be restored manually.';
          notifyListeners();
          return false;
        }
        final result = await Process.run(
            'reg', ['import', backupPath], runInShell: true);
        if (result.exitCode != 0) {
          _error =
              'reg import failed (exit ${result.exitCode}): '
              '${(result.stderr as String).trim()}';
          notifyListeners();
          return false;
        }
        // Keep the .reg backup file removal best-effort.
        try {
          await File(backupPath).delete();
        } catch (_) {}
        await _deleteQuarantineMetadata(quarantinedFileName);
        return true;
      }

      // File-based quarantine - move file back
      if (await quarantinedFile.exists()) {
        try {
          await quarantinedFile.rename(restorePath);
        } on FileSystemException {
          await quarantinedFile.copy(restorePath);
          await quarantinedFile.delete();
        }

        // Reload if it's a launch agent/daemon on macOS
        if (PlatformInfo.isMacOS && (restorePath.contains('LaunchAgents') || restorePath.contains('LaunchDaemons'))) {
          final load = await Process.run('launchctl', ['load', restorePath]);
          if (load.exitCode != 0) {
            debugPrint(
                'launchctl load $restorePath exited ${load.exitCode}: ${load.stderr}');
          }
        }

        await _deleteQuarantineMetadata(quarantinedFileName);
        return true;
      }
    } catch (e) {
      _error = 'Failed to restore item: $e';
      notifyListeners();
    }
    return false;
  }

  /// Get list of quarantined items with metadata.
  ///
  /// Includes metadata-only entries (disabled services/tasks and deleted
  /// registry values have no quarantine file) as well as quarantine files
  /// that lost their metadata. Registry `.reg` backups are attached to their
  /// owning entry instead of being listed as items.
  Future<List<QuarantinedItem>> getQuarantinedItems() async {
    final items = <QuarantinedItem>[];
    try {
      final quarantineDir = await _getQuarantineDir();
      final metadata = await _loadQuarantineMetadata();
      final registryBackups = metadata.values
          .whereType<Map<String, dynamic>>()
          .map((m) => m['registry_backup'] as String?)
          .whereType<String>()
          .toSet();

      // All metadata entries, file-backed or not.
      for (final entry in metadata.entries) {
        final itemMeta = entry.value as Map<String, dynamic>?;
        items.add(QuarantinedItem(
          fileName: entry.key,
          originalPath: itemMeta?['original_path'] as String? ?? '',
          name: itemMeta?['name'] as String? ?? entry.key,
          type: itemMeta?['type_display_name'] as String? ?? 'Unknown',
          quarantinedAt: itemMeta?['quarantined_at'] != null
              ? DateTime.tryParse(itemMeta!['quarantined_at'] as String)
              : null,
          isService: itemMeta?['is_service'] as bool? ?? false,
          isRegistry: itemMeta?['is_registry'] as bool? ?? false,
          isTask: itemMeta?['is_task'] as bool? ?? false,
          registryBackupPath: itemMeta?['registry_backup'] as String?,
        ));
      }

      // Orphan quarantine files without metadata.
      if (await quarantineDir.exists()) {
        await for (final entity in quarantineDir.list()) {
          if (entity is! File || entity.path.endsWith('.metadata.json')) {
            continue;
          }
          if (registryBackups.contains(entity.path)) continue;
          final fileName = entity.path.split(PlatformInfo.pathSeparator).last;
          if (metadata.containsKey(fileName)) continue;
          items.add(QuarantinedItem(
            fileName: fileName,
            originalPath: '',
            name: fileName,
            type: 'Unknown',
          ));
        }
      }
    } catch (e) {
      // Ignore
    }
    return items;
  }

  /// Delete a quarantined item permanently. Metadata-only entries (disabled
  /// services/tasks, deleted registry values) just drop their metadata —
  /// including the registry backup, which makes the deletion final.
  Future<bool> deleteQuarantinedItem(String fileName) async {
    try {
      final quarantineDir = await _getQuarantineDir();
      final metadata = await _loadQuarantineMetadata();
      final itemMeta = metadata[fileName] as Map<String, dynamic>?;

      final file = File('${quarantineDir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
      } else if (itemMeta == null) {
        _error = 'Quarantined item not found: $fileName';
        notifyListeners();
        return false;
      }

      // Remove the registry backup if this entry owned one.
      final backupPath = itemMeta?['registry_backup'] as String?;
      if (backupPath != null && backupPath.isNotEmpty) {
        final backup = File(backupPath);
        if (await backup.exists()) await backup.delete();
      }

      await _deleteQuarantineMetadata(fileName);
      return true;
    } catch (e) {
      _error = 'Failed to delete item: $e';
      notifyListeners();
    }
    return false;
  }

  // =========================================================================
  // Host firewall (W5.10) — real OS firewall state and control
  // =========================================================================

  static const _macFirewallTool = '/usr/libexec/ApplicationFirewall/socketfilterfw';

  /// Read the REAL OS firewall state from platform tooling.
  Future<HostFirewallStatus> refreshHostFirewallStatus() async {
    HostFirewallStatus status;
    if (PlatformInfo.isMacOS) {
      status = await _readMacFirewallStatus();
    } else if (PlatformInfo.isWindows) {
      status = await _readWindowsFirewallStatus();
    } else if (PlatformInfo.isLinux) {
      status = await _readLinuxFirewallStatus();
    } else {
      status = const HostFirewallStatus(
        state: HostFirewallState.unavailable,
        detail: 'Host firewall control is only available on desktop platforms',
        source: 'platform check',
      );
    }
    _hostFirewallStatus = status;
    notifyListeners();
    return status;
  }

  Future<HostFirewallStatus> _readMacFirewallStatus() async {
    try {
      final result = await Process.run(_macFirewallTool, ['--getglobalstate']);
      final out = ((result.stdout as String) + (result.stderr as String)).trim();
      if (result.exitCode != 0) {
        return HostFirewallStatus(
          state: HostFirewallState.unknown,
          detail: 'socketfilterfw exited ${result.exitCode}: $out',
          source: '$_macFirewallTool --getglobalstate',
        );
      }
      final lower = out.toLowerCase();
      if (lower.contains('enabled') || out.contains('State = 1') || out.contains('State = 2')) {
        return HostFirewallStatus(
          state: HostFirewallState.enabled,
          detail: out,
          source: '$_macFirewallTool --getglobalstate',
        );
      }
      if (lower.contains('disabled') || out.contains('State = 0')) {
        return HostFirewallStatus(
          state: HostFirewallState.disabled,
          detail: out,
          source: '$_macFirewallTool --getglobalstate',
        );
      }
      return HostFirewallStatus(
        state: HostFirewallState.unknown,
        detail: 'Unrecognized socketfilterfw output: $out',
        source: '$_macFirewallTool --getglobalstate',
      );
    } on ProcessException catch (e) {
      return HostFirewallStatus(
        state: HostFirewallState.unavailable,
        detail: 'socketfilterfw could not be executed: ${e.message}',
        source: _macFirewallTool,
      );
    }
  }

  Future<HostFirewallStatus> _readWindowsFirewallStatus() async {
    const source = 'netsh advfirewall show allprofiles';
    try {
      final result = await Process.run(
        'netsh', ['advfirewall', 'show', 'allprofiles'],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        return HostFirewallStatus(
          state: HostFirewallState.unknown,
          detail:
              'netsh exited ${result.exitCode}: ${((result.stdout as String) + (result.stderr as String)).trim()}',
          source: source,
        );
      }
      final lines = const LineSplitter().convert(result.stdout as String);
      String currentProfile = '';
      final profileStates = <String, bool>{};
      for (final line in lines) {
        final t = line.trim();
        final profileMatch = RegExp(r'^(\S+.*) Profile Settings:').firstMatch(t);
        if (profileMatch != null) {
          currentProfile = profileMatch.group(1)!;
          continue;
        }
        final stateMatch = RegExp(r'^State\s+(ON|OFF)$', caseSensitive: false)
            .firstMatch(t);
        if (stateMatch != null && currentProfile.isNotEmpty) {
          profileStates[currentProfile] =
              stateMatch.group(1)!.toUpperCase() == 'ON';
        }
      }
      if (profileStates.isEmpty) {
        return HostFirewallStatus(
          state: HostFirewallState.unknown,
          detail:
              'Could not parse profile states from netsh output (localized Windows?)',
          source: source,
        );
      }
      final detail = profileStates.entries
          .map((e) => '${e.key}: ${e.value ? 'ON' : 'OFF'}')
          .join(', ');
      final anyOn = profileStates.values.any((v) => v);
      return HostFirewallStatus(
        state: anyOn ? HostFirewallState.enabled : HostFirewallState.disabled,
        detail: detail,
        source: source,
      );
    } on ProcessException catch (e) {
      return HostFirewallStatus(
        state: HostFirewallState.unavailable,
        detail: 'netsh could not be executed: ${e.message}',
        source: source,
      );
    }
  }

  Future<HostFirewallStatus> _readLinuxFirewallStatus() async {
    // 1. ufw: ENABLED flag in /etc/ufw/ufw.conf is world-readable, so we can
    //    read real state without root.
    final ufwConf = File('/etc/ufw/ufw.conf');
    if (await ufwConf.exists()) {
      try {
        final content = await ufwConf.readAsString();
        final m = RegExp(r'^ENABLED\s*=\s*(\w+)', multiLine: true)
            .firstMatch(content);
        if (m != null) {
          final enabled = m.group(1)!.toLowerCase() == 'yes';
          return HostFirewallStatus(
            state: enabled ? HostFirewallState.enabled : HostFirewallState.disabled,
            detail: 'ufw ENABLED=${m.group(1)} (/etc/ufw/ufw.conf)',
            source: '/etc/ufw/ufw.conf',
          );
        }
      } on FileSystemException catch (e) {
        return HostFirewallStatus(
          state: HostFirewallState.unknown,
          detail: 'ufw installed but config unreadable: ${e.message}',
          source: '/etc/ufw/ufw.conf',
        );
      }
    }
    // 2. firewalld
    try {
      final result = await Process.run('firewall-cmd', ['--state']);
      final out = ((result.stdout as String) + (result.stderr as String)).trim();
      if (result.exitCode == 0 && out.contains('running')) {
        return HostFirewallStatus(
          state: HostFirewallState.enabled,
          detail: 'firewalld is running',
          source: 'firewall-cmd --state',
        );
      }
      return HostFirewallStatus(
        state: HostFirewallState.disabled,
        detail: 'firewalld: $out',
        source: 'firewall-cmd --state',
      );
    } on ProcessException {
      // Neither ufw nor firewalld present.
    }
    return const HostFirewallStatus(
      state: HostFirewallState.unavailable,
      detail: 'No supported firewall tooling found (looked for ufw, firewalld)',
      source: 'ufw/firewalld detection',
    );
  }

  /// Run a shell command with macOS admin elevation via osascript. Surfaces
  /// user cancellation of the password prompt honestly.
  Future<FirewallActionResult> _runMacAdminCommand(String command) async {
    final escaped = command.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    try {
      final result = await Process.run('osascript', [
        '-e',
        'do shell script "$escaped" with administrator privileges '
            'with prompt "OrbGuard needs administrator access to change firewall settings."',
      ]);
      final stderrStr = (result.stderr as String).trim();
      if (result.exitCode == 0) {
        return FirewallActionResult(
          success: true,
          message: (result.stdout as String).trim().isEmpty
              ? 'Command completed'
              : (result.stdout as String).trim(),
        );
      }
      if (stderrStr.contains('-128') ||
          stderrStr.toLowerCase().contains('user cancel')) {
        return const FirewallActionResult(
          success: false,
          cancelled: true,
          message: 'You cancelled the administrator password prompt — no changes were made.',
        );
      }
      return FirewallActionResult(
        success: false,
        permissionDenied: stderrStr.toLowerCase().contains('not allowed'),
        message: 'Command failed (exit ${result.exitCode}): $stderrStr',
      );
    } on ProcessException catch (e) {
      return FirewallActionResult(
        success: false,
        message: 'osascript could not be executed: ${e.message}',
      );
    }
  }

  /// Run netsh, retrying with a UAC elevation prompt when Windows refuses
  /// for lack of privileges. UAC declines are surfaced as cancellation.
  Future<FirewallActionResult> _runNetshElevated(List<String> args) async {
    try {
      final direct = await Process.run('netsh', args, runInShell: true);
      final out =
          ((direct.stdout as String) + (direct.stderr as String)).trim();
      if (direct.exitCode == 0) {
        return FirewallActionResult(
          success: true,
          message: out.isEmpty ? 'Command completed' : out,
        );
      }
      // Elevation needed — retry through UAC.
      final argList = args.map((a) => "'$a'").join(',');
      final ps = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          'try { Start-Process netsh -ArgumentList $argList -Verb RunAs -Wait -WindowStyle Hidden } '
              "catch { Write-Error \$_.Exception.Message; exit 1 }",
        ],
        runInShell: true,
      );
      final psErr = (ps.stderr as String).trim();
      if (ps.exitCode == 0) {
        return const FirewallActionResult(
          success: true,
          message: 'Command completed with administrator elevation',
        );
      }
      if (psErr.toLowerCase().contains('canceled by the user') ||
          psErr.toLowerCase().contains('cancelled by the user')) {
        return const FirewallActionResult(
          success: false,
          cancelled: true,
          message: 'You declined the User Account Control prompt — no changes were made.',
        );
      }
      return FirewallActionResult(
        success: false,
        permissionDenied: true,
        message: 'netsh failed without elevation ($out) and the elevated retry '
            'also failed: $psErr',
      );
    } on ProcessException catch (e) {
      return FirewallActionResult(
        success: false,
        message: 'netsh could not be executed: ${e.message}',
      );
    }
  }

  /// Run a command as root via pkexec (polkit GUI prompt). Exit code 126 is
  /// a dismissed prompt, 127 is an authorization failure.
  Future<FirewallActionResult> _runPkexec(List<String> args) async {
    try {
      final result = await Process.run('pkexec', args);
      final out =
          ((result.stdout as String) + (result.stderr as String)).trim();
      if (result.exitCode == 0) {
        return FirewallActionResult(
          success: true,
          message: out.isEmpty ? 'Command completed' : out,
        );
      }
      if (result.exitCode == 126) {
        return const FirewallActionResult(
          success: false,
          cancelled: true,
          message: 'You dismissed the authentication prompt — no changes were made.',
        );
      }
      if (result.exitCode == 127) {
        return FirewallActionResult(
          success: false,
          permissionDenied: true,
          message: 'Not authorized by polkit: $out',
        );
      }
      return FirewallActionResult(
        success: false,
        message: 'Command failed (exit ${result.exitCode}): $out',
      );
    } on ProcessException catch (e) {
      return FirewallActionResult(
        success: false,
        message:
            'pkexec is not available (${e.message}); cannot elevate to change firewall settings.',
      );
    }
  }

  /// Enable/disable the REAL OS firewall. Always re-reads state afterwards so
  /// the UI reflects what actually happened, not what was requested.
  Future<FirewallActionResult> setHostFirewallEnabled(bool enable) async {
    FirewallActionResult result;
    if (PlatformInfo.isMacOS) {
      result = await _runMacAdminCommand(
          '$_macFirewallTool --setglobalstate ${enable ? 'on' : 'off'}');
    } else if (PlatformInfo.isWindows) {
      result = await _runNetshElevated(
          ['advfirewall', 'set', 'allprofiles', 'state', enable ? 'on' : 'off']);
    } else if (PlatformInfo.isLinux) {
      result = await _setLinuxFirewallEnabled(enable);
    } else {
      result = const FirewallActionResult(
        success: false,
        unsupported: true,
        message: 'Host firewall control is only available on desktop platforms',
      );
    }
    await refreshHostFirewallStatus();
    return result;
  }

  Future<FirewallActionResult> _setLinuxFirewallEnabled(bool enable) async {
    if (await File('/usr/sbin/ufw').exists() ||
        await File('/usr/bin/ufw').exists()) {
      return _runPkexec(
          enable ? ['ufw', '--force', 'enable'] : ['ufw', 'disable']);
    }
    // firewalld fallback
    try {
      final probe = await Process.run('firewall-cmd', ['--version']);
      if (probe.exitCode == 0) {
        return _runPkexec(
            ['systemctl', enable ? 'start' : 'stop', 'firewalld']);
      }
    } on ProcessException {
      // fall through
    }
    return const FirewallActionResult(
      success: false,
      unsupported: true,
      message: 'No supported firewall tooling found (ufw or firewalld required)',
    );
  }

  /// Quick action: block all incoming connections.
  Future<FirewallActionResult> setBlockAllIncoming(bool enable) async {
    FirewallActionResult result;
    if (PlatformInfo.isMacOS) {
      result = await _runMacAdminCommand(
          '$_macFirewallTool --setblockall ${enable ? 'on' : 'off'}');
    } else if (PlatformInfo.isWindows) {
      result = await _runNetshElevated([
        'advfirewall', 'set', 'allprofiles', 'firewallpolicy',
        enable ? 'blockinboundalways,allowoutbound' : 'blockinbound,allowoutbound',
      ]);
    } else {
      result = const FirewallActionResult(
        success: false,
        unsupported: true,
        message:
            'ufw already denies unsolicited incoming traffic by default; a '
            'separate block-all override is not provided by ufw/firewalld.',
      );
    }
    await refreshHostFirewallStatus();
    return result;
  }

  /// Quick action: stealth mode (only macOS exposes a real toggle).
  Future<FirewallActionResult> setStealthMode(bool enable) async {
    if (PlatformInfo.isMacOS) {
      final result = await _runMacAdminCommand(
          '$_macFirewallTool --setstealthmode ${enable ? 'on' : 'off'}');
      await refreshHostFirewallStatus();
      return result;
    }
    return FirewallActionResult(
      success: false,
      unsupported: true,
      message: PlatformInfo.isWindows
          ? 'Windows Defender Firewall does not respond to unsolicited probes '
              'while enabled; there is no separate stealth toggle.'
          : 'Linux firewalls drop unsolicited probes when enabled; there is '
              'no separate stealth toggle.',
    );
  }

  /// Read macOS stealth mode state (no elevation needed).
  Future<bool?> getMacStealthMode() async {
    if (!PlatformInfo.isMacOS) return null;
    try {
      final result = await Process.run(_macFirewallTool, ['--getstealthmode']);
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String).toLowerCase();
      if (out.contains('enabled')) return true;
      if (out.contains('disabled')) return false;
      return null;
    } on ProcessException {
      return null;
    }
  }

  /// Create a rule in the LOCAL OS firewall.
  ///
  /// Windows: netsh advfirewall rule (full port/protocol/address support).
  /// Linux: ufw rule (port/protocol/address).
  /// macOS: the Application Firewall only supports per-application rules, so
  /// [appPath] is required and port-based parameters are rejected honestly.
  Future<FirewallActionResult> addLocalFirewallRule({
    required String name,
    required String action, // allow | block
    required String direction, // inbound | outbound
    String protocol = 'any', // tcp | udp | any
    String? port,
    String? remoteAddress,
    String? appPath,
  }) async {
    final isBlock = action.toLowerCase() == 'block';
    final isInbound = direction.toLowerCase() != 'outbound';

    if (PlatformInfo.isWindows) {
      final args = [
        'advfirewall', 'firewall', 'add', 'rule',
        'name=$name',
        'dir=${isInbound ? 'in' : 'out'}',
        'action=${isBlock ? 'block' : 'allow'}',
        if (protocol.toLowerCase() != 'any') 'protocol=${protocol.toUpperCase()}',
        if (port != null && port.isNotEmpty)
          isInbound ? 'localport=$port' : 'remoteport=$port',
        if (remoteAddress != null && remoteAddress.isNotEmpty)
          'remoteip=$remoteAddress',
        if (appPath != null && appPath.isNotEmpty) 'program=$appPath',
      ];
      // netsh requires a protocol when a port is specified.
      if (port != null && port.isNotEmpty && protocol.toLowerCase() == 'any') {
        return const FirewallActionResult(
          success: false,
          unsupported: true,
          message: 'Windows requires a protocol (TCP or UDP) for port-based rules.',
        );
      }
      return _runNetshElevated(args);
    }

    if (PlatformInfo.isLinux) {
      if ((port == null || port.isEmpty) &&
          (remoteAddress == null || remoteAddress.isEmpty)) {
        return const FirewallActionResult(
          success: false,
          unsupported: true,
          message: 'ufw rules need at least a port or a remote address.',
        );
      }
      final args = [
        'ufw',
        isBlock ? 'deny' : 'allow',
        isInbound ? 'in' : 'out',
        if (protocol.toLowerCase() != 'any') ...['proto', protocol.toLowerCase()],
        'from',
        (isInbound && remoteAddress != null && remoteAddress.isNotEmpty)
            ? remoteAddress
            : 'any',
        'to',
        (!isInbound && remoteAddress != null && remoteAddress.isNotEmpty)
            ? remoteAddress
            : 'any',
        if (port != null && port.isNotEmpty) ...['port', port],
        'comment', name,
      ];
      return _runPkexec(args);
    }

    if (PlatformInfo.isMacOS) {
      if (appPath == null || appPath.isEmpty) {
        return const FirewallActionResult(
          success: false,
          unsupported: true,
          message:
              'The macOS Application Firewall only supports per-application '
              'rules — provide an application path. Port/address rules need '
              'PF, which OrbGuard does not modify.',
        );
      }
      final escapedPath = appPath.replaceAll('"', '\\"');
      final verb = isBlock ? '--blockapp' : '--unblockapp';
      return _runMacAdminCommand(
          '$_macFirewallTool --add \\"$escapedPath\\" && $_macFirewallTool $verb \\"$escapedPath\\"');
    }

    return const FirewallActionResult(
      success: false,
      unsupported: true,
      message: 'Local firewall rules are only available on desktop platforms',
    );
  }

  /// Open the OS firewall settings UI.
  Future<FirewallActionResult> openSystemFirewallSettings() async {
    try {
      ProcessResult result;
      String what;
      if (PlatformInfo.isMacOS) {
        what = 'System Settings → Network → Firewall';
        result = await Process.run('open',
            ['x-apple.systempreferences:com.apple.preference.security?Firewall']);
      } else if (PlatformInfo.isWindows) {
        what = 'Windows Defender Firewall control panel';
        result = await Process.run('control', ['firewall.cpl'], runInShell: true);
      } else if (PlatformInfo.isLinux) {
        what = 'GUFW firewall settings';
        result = await Process.run('gufw', []);
      } else {
        return const FirewallActionResult(
          success: false,
          unsupported: true,
          message: 'Not available on this platform',
        );
      }
      if (result.exitCode == 0) {
        return FirewallActionResult(success: true, message: 'Opened $what');
      }
      return FirewallActionResult(
        success: false,
        message:
            'Could not open $what (exit ${result.exitCode}): ${(result.stderr as String).trim()}',
      );
    } on ProcessException catch (e) {
      return FirewallActionResult(
        success: false,
        message: 'Could not open firewall settings: ${e.message}',
      );
    }
  }

  // =========================================================================
  // Host-local network/browser collection (W5.11)
  //
  // The backend's desktop scanners run on the SERVER host, so collection
  // happens here on the device. The backend is used only for VirusTotal
  // value lookups (IP / hash), which genuinely operate on client-supplied
  // values. Risk analysis of collected data stays local until the backend
  // grows upload-accepting analyze endpoints (Wave 6).
  // =========================================================================

  /// Collect this device's active network connections and enrich public
  /// remote IPs via the backend VirusTotal lookup.
  Future<void> loadHostNetworkConnections({bool enrich = true}) async {
    if (!isDesktopPlatform) {
      _hostNetworkErrors = ['Host network collection is desktop-only'];
      notifyListeners();
      return;
    }
    _isCollectingNetwork = true;
    notifyListeners();

    HostCollection collection;
    if (PlatformInfo.isMacOS) {
      collection = await _macosScanner.collectNetworkConnections();
    } else if (PlatformInfo.isWindows) {
      collection = await _windowsScanner.collectNetworkConnections();
    } else {
      collection = await _linuxScanner.collectNetworkConnections();
    }

    _hostNetworkConnections = collection.items;
    _hostNetworkErrors = List.of(collection.errors);
    _hostNetworkSource = collection.source;
    _hostNetworkCollectedAt = DateTime.now();
    _isCollectingNetwork = false;
    notifyListeners();

    if (enrich && collection.items.isNotEmpty) {
      await _enrichConnectionsWithVirusTotal();
    }
  }

  /// VirusTotal enrichment of public remote IPs (capped to avoid hammering
  /// the backend's VT quota). Failures are recorded, never hidden.
  Future<void> _enrichConnectionsWithVirusTotal({int maxLookups = 8}) async {
    final uniqueIps = <String>{};
    for (final conn in _hostNetworkConnections) {
      final ip = conn['remote_address'] as String? ?? '';
      if (isPublicRoutableIp(ip)) uniqueIps.add(ip);
      if (uniqueIps.length >= maxLookups) break;
    }
    if (uniqueIps.isEmpty) return;

    var changed = false;
    for (final ip in uniqueIps) {
      try {
        final report = await _api.vtLookupIp(ip);
        final malicious = (report['malicious'] as num?)?.toInt() ?? 0;
        final isKnownBad =
            report['is_known_bad'] as bool? ?? (malicious > 0);
        final tags =
            (report['tags'] as List?)?.whereType<String>().toList() ?? const [];
        final country = report['country'] as String? ?? '';
        for (final conn in _hostNetworkConnections) {
          if (conn['remote_address'] == ip) {
            conn['is_known_bad'] = isKnownBad;
            if (tags.isNotEmpty) conn['threat_tags'] = tags;
            if (country.isNotEmpty) conn['remote_country'] = country;
            conn['vt_enriched'] = true;
            changed = true;
          }
        }
      } catch (e) {
        _hostNetworkErrors.add('VirusTotal enrichment unavailable for $ip: $e');
        changed = true;
        break; // backend VT is down/unconfigured — do not retry per-IP
      }
    }
    if (changed) notifyListeners();
  }

  /// Collect browser extensions from this device's browser profiles.
  /// Produces the same map shape the screen previously got from the backend:
  /// {extensions, total, high_risk, by_browser} plus source/errors.
  Future<void> loadHostBrowserExtensions() async {
    if (!isDesktopPlatform) {
      _hostBrowserScan = {
        'extensions': const <Map<String, dynamic>>[],
        'total': 0,
        'high_risk': 0,
        'by_browser': const <String, int>{},
        'errors': const ['Host browser collection is desktop-only'],
        'source': 'unavailable',
      };
      notifyListeners();
      return;
    }
    _isCollectingBrowser = true;
    notifyListeners();

    HostCollection collection;
    if (PlatformInfo.isMacOS) {
      collection = await _macosScanner.collectBrowserExtensions();
    } else if (PlatformInfo.isWindows) {
      collection = await _windowsScanner.collectBrowserExtensions();
    } else {
      collection = await _linuxScanner.collectBrowserExtensions();
    }

    final byBrowser = <String, int>{};
    var highRisk = 0;
    for (final ext in collection.items) {
      final browser = ext['browser'] as String? ?? 'Unknown';
      byBrowser[browser] = (byBrowser[browser] ?? 0) + 1;
      final risk = ext['risk_level'] as String? ?? 'low';
      if (risk == 'high' || risk == 'critical') highRisk++;
    }

    _hostBrowserScan = {
      'extensions': collection.items,
      'total': collection.items.length,
      'high_risk': highRisk,
      'by_browser': byBrowser,
      'errors': collection.errors,
      'source': collection.source,
      'collected_at': DateTime.now().toIso8601String(),
    };
    _isCollectingBrowser = false;
    notifyListeners();
  }

  // =========================================================================
  // Local code-signing verification (W5.10.4)
  //
  // The backend's POST /desktop/codesign/verify runs `codesign` on the
  // SERVER host, so it cannot verify files on this device. Verification is
  // done locally; the backend is used for VirusTotal HASH lookups, which
  // operate on a client-computed value.
  // =========================================================================

  /// Extracts a plausible executable path from a persistence command string.
  String? _extractExecutablePath(String? command) {
    if (command == null || command.isEmpty) return null;
    var c = command.trim();
    if (c.startsWith('"')) {
      final end = c.indexOf('"', 1);
      if (end > 1) return c.substring(1, end);
      return null;
    }
    final space = c.indexOf(' ');
    return space > 0 ? c.substring(0, space) : c;
  }

  /// Verify code signatures of executables referenced by the last
  /// persistence scan (plus /Applications bundles on macOS), LOCALLY.
  Future<void> verifyLocalCodeSigning({int maxItems = 50}) async {
    if (PlatformInfo.isLinux) {
      _codeSigningUnavailableReason =
          'Linux has no platform code-signing infrastructure for arbitrary '
          'executables (no Authenticode/codesign equivalent). Package '
          'signatures are verified by your package manager at install time.';
      _localSignedApps = [];
      notifyListeners();
      return;
    }
    if (!PlatformInfo.isMacOS && !PlatformInfo.isWindows) {
      _codeSigningUnavailableReason =
          'Local code-signing verification is desktop-only';
      _localSignedApps = [];
      notifyListeners();
      return;
    }

    _isVerifyingCodeSigning = true;
    _codeSigningUnavailableReason = null;
    notifyListeners();

    // Candidate set: executables referenced by persistence items, plus
    // installed app bundles on macOS.
    final candidates = <String>{};
    for (final item in _items) {
      final exe = _extractExecutablePath(item.command);
      if (exe == null) continue;
      final looksAbsolute = PlatformInfo.isWindows
          ? RegExp(r'^[A-Za-z]:[\\/]').hasMatch(exe)
          : exe.startsWith('/');
      if (looksAbsolute) candidates.add(exe);
    }
    if (PlatformInfo.isMacOS) {
      try {
        await for (final e in Directory('/Applications').list()) {
          if (e is Directory && e.path.endsWith('.app')) candidates.add(e.path);
          if (candidates.length >= maxItems) break;
        }
      } on FileSystemException {
        // /Applications unreadable — persistence-derived candidates remain.
      }
    }

    final results = <Map<String, dynamic>>[];
    for (final path in candidates.take(maxItems)) {
      if (PlatformInfo.isMacOS) {
        final r = await _verifyMacCodeSigning(path);
        if (r != null) results.add(r);
      } else {
        final r = await _verifyWindowsCodeSigning(path);
        if (r != null) results.add(r);
      }
    }

    results.sort((a, b) {
      final aRank = (a['is_signed'] == true ? (a['is_valid'] == true ? 2 : 1) : 0);
      final bRank = (b['is_signed'] == true ? (b['is_valid'] == true ? 2 : 1) : 0);
      return aRank.compareTo(bRank);
    });
    _localSignedApps = results;
    _isVerifyingCodeSigning = false;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _verifyMacCodeSigning(String path) async {
    if (!await File(path).exists() && !await Directory(path).exists()) {
      return null;
    }
    try {
      final info = await Process.run('codesign', ['-dv', '--verbose=2', path]);
      final detail = info.stderr as String; // codesign prints info to stderr
      final isSigned = info.exitCode == 0;
      String developer = '';
      String? teamId;
      String bundleId = '';
      if (isSigned) {
        final auth = RegExp(r'^Authority=(.+)$', multiLine: true).firstMatch(detail);
        developer = auth?.group(1) ?? '';
        teamId = RegExp(r'^TeamIdentifier=(.+)$', multiLine: true)
            .firstMatch(detail)
            ?.group(1);
        if (teamId == 'not set') teamId = null;
        bundleId = RegExp(r'^Identifier=(.+)$', multiLine: true)
                .firstMatch(detail)
                ?.group(1) ??
            '';
      }
      bool isValid = false;
      if (isSigned) {
        final verify =
            await Process.run('codesign', ['--verify', '--strict', path]);
        isValid = verify.exitCode == 0;
      }
      return {
        'name': path.split('/').last.replaceAll('.app', ''),
        'bundle_id': bundleId,
        'path': path,
        'is_signed': isSigned,
        'is_valid': isValid,
        'developer': developer,
        'team_id': teamId,
        'source': 'local',
      };
    } on ProcessException catch (e) {
      debugPrint('codesign unavailable for $path: ${e.message}');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _verifyWindowsCodeSigning(String path) async {
    if (!await File(path).exists()) return null;
    try {
      final escaped = path.replaceAll("'", "''");
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "Get-AuthenticodeSignature -LiteralPath '$escaped' | "
              "Select-Object @{n='Status';e={[int]\$_.Status}},StatusMessage,"
              "@{n='Subject';e={\$_.SignerCertificate.Subject}} | ConvertTo-Json -Compress",
        ],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        debugPrint(
            'Get-AuthenticodeSignature failed for $path: ${result.stderr}');
        return null;
      }
      final json = jsonDecode((result.stdout as String).trim())
          as Map<String, dynamic>;
      final status = (json['Status'] as num?)?.toInt() ?? 1;
      // SignatureStatus enum: 0=Valid, 2=NotSigned
      final isSigned = status != 2;
      final isValid = status == 0;
      String developer = '';
      final subject = json['Subject'] as String?;
      if (subject != null) {
        developer =
            RegExp(r'CN=([^,]+)').firstMatch(subject)?.group(1) ?? subject;
      }
      return {
        'name': path.split('\\').last,
        'bundle_id': '',
        'path': path,
        'is_signed': isSigned,
        'is_valid': isValid,
        'developer': developer,
        'team_id': null,
        'status_message': json['StatusMessage'],
        'source': 'local',
      };
    } on ProcessException catch (e) {
      debugPrint('powershell unavailable: ${e.message}');
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Compute the file's SHA-256 locally and look the hash up on VirusTotal
  /// via the backend (the only signing-related backend call that genuinely
  /// works for client files, since it operates on a client-computed value).
  Future<Map<String, dynamic>> lookupFileOnVirusTotal(String path) async {
    final hash = await _computeSha256(path);
    return _api.vtLookupHash(hash);
  }

  Future<String> _computeSha256(String path) async {
    ProcessResult result;
    if (PlatformInfo.isWindows) {
      result = await Process.run(
          'certutil', ['-hashfile', path, 'SHA256'],
          runInShell: true);
      if (result.exitCode != 0) {
        throw Exception(
            'certutil failed (exit ${result.exitCode}): ${(result.stderr as String).trim()}');
      }
      final lines = const LineSplitter()
          .convert(result.stdout as String)
          .map((l) => l.trim())
          .where((l) => RegExp(r'^[0-9a-fA-F\s]+$').hasMatch(l) && l.length >= 64)
          .toList();
      if (lines.isEmpty) throw Exception('certutil produced no hash output');
      return lines.first.replaceAll(RegExp(r'\s'), '').toLowerCase();
    }
    // macOS bundles: hash the main binary inside the bundle.
    var target = path;
    if (PlatformInfo.isMacOS && path.endsWith('.app')) {
      final name = path.split('/').last.replaceAll('.app', '');
      final mainBinary = File('$path/Contents/MacOS/$name');
      if (await mainBinary.exists()) target = mainBinary.path;
    }
    result = PlatformInfo.isMacOS
        ? await Process.run('shasum', ['-a', '256', target])
        : await Process.run('sha256sum', [target]);
    if (result.exitCode != 0) {
      throw Exception(
          'hash command failed (exit ${result.exitCode}): ${(result.stderr as String).trim()}');
    }
    final out = (result.stdout as String).trim();
    final m = RegExp(r'^([0-9a-fA-F]{64})').firstMatch(out);
    if (m == null) throw Exception('unexpected hash output: $out');
    return m.group(1)!.toLowerCase();
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
