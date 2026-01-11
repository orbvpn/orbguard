/// Desktop Security Provider
/// Unified provider for Windows, macOS, and Linux persistence scanning
library;

import 'dart:convert';
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

  QuarantinedItem({
    required this.fileName,
    required this.originalPath,
    required this.name,
    required this.type,
    this.quarantinedAt,
    this.isService = false,
    this.isRegistry = false,
    this.isTask = false,
  });

  bool get canAutoRestore => originalPath.isNotEmpty && !isRegistry;
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
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
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
      if (Platform.isMacOS) {
        return await _disableMacOSItem(item);
      } else if (Platform.isLinux) {
        return await _disableLinuxItem(item);
      } else if (Platform.isWindows) {
        return await _disableWindowsItem(item);
      }
    } catch (e) {
      _error = 'Failed to disable item: $e';
      notifyListeners();
    }
    return false;
  }

  /// Disable macOS persistence item
  Future<bool> _disableMacOSItem(DesktopPersistenceItem item) async {
    final path = item.path;

    // For LaunchAgents/Daemons, unload and move to quarantine
    if (path.contains('LaunchAgents') || path.contains('LaunchDaemons')) {
      // Unload the service
      await Process.run('launchctl', ['unload', path]);

      // Move to quarantine
      final quarantineDir = await _getQuarantineDir();
      final fileName = path.split('/').last;
      final quarantinePath = '${quarantineDir.path}/$fileName';

      await File(path).rename(quarantinePath);

      // Save quarantine metadata for automatic restore
      await _saveQuarantineMetadata(fileName, path, item);

      // Update local state
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For login items, use osascript to remove
    if (item.type.contains('loginItem')) {
      await Process.run('osascript', [
        '-e', 'tell application "System Events" to delete login item "${item.name}"'
      ]);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    return false;
  }

  /// Disable Linux persistence item
  Future<bool> _disableLinuxItem(DesktopPersistenceItem item) async {
    final path = item.path;

    // For systemd services, disable them
    if (item.type.contains('systemd')) {
      final serviceName = path.split('/').last;
      await Process.run('systemctl', ['--user', 'disable', serviceName]);
      // Save metadata for systemd services too
      await _saveQuarantineMetadata(serviceName, path, item, isService: true);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For other items, move to quarantine
    final quarantineDir = await _getQuarantineDir();
    final fileName = path.split('/').last;
    final quarantinePath = '${quarantineDir.path}/$fileName';

    try {
      await File(path).rename(quarantinePath);
      // Save quarantine metadata for automatic restore
      await _saveQuarantineMetadata(fileName, path, item);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Disable Windows persistence item
  Future<bool> _disableWindowsItem(DesktopPersistenceItem item) async {
    // For registry items, delete the value
    if (item.type.contains('registry')) {
      final parts = item.path.split('\\');
      final keyPath = parts.sublist(0, parts.length - 1).join('\\');
      await Process.run('reg', ['delete', keyPath, '/v', item.name, '/f'], runInShell: true);
      // Save metadata for registry restore
      await _saveQuarantineMetadata(item.name, item.path, item, isRegistry: true);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For scheduled tasks, disable them
    if (item.type.contains('scheduledTask')) {
      await Process.run('schtasks', ['/Change', '/TN', item.name, '/Disable'], runInShell: true);
      // Save metadata for task restore
      await _saveQuarantineMetadata(item.name, item.path, item, isTask: true);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    // For services, disable them
    if (item.type.contains('service')) {
      await Process.run('sc', ['config', item.name, 'start=', 'disabled'], runInShell: true);
      // Save metadata for service restore
      await _saveQuarantineMetadata(item.name, item.path, item, isService: true);
      _items.removeWhere((i) => i.id == item.id);
      notifyListeners();
      return true;
    }

    return false;
  }

  /// Get quarantine directory
  Future<Directory> _getQuarantineDir() async {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
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
        if (Platform.isLinux) {
          await Process.run('systemctl', ['--user', 'enable', quarantinedFileName]);
        } else if (Platform.isWindows) {
          await Process.run('sc', ['config', quarantinedFileName, 'start=', 'auto'], runInShell: true);
        }
        await _deleteQuarantineMetadata(quarantinedFileName);
        return true;
      }

      if (isTask && Platform.isWindows) {
        // Re-enable scheduled task
        await Process.run('schtasks', ['/Change', '/TN', quarantinedFileName, '/Enable'], runInShell: true);
        await _deleteQuarantineMetadata(quarantinedFileName);
        return true;
      }

      if (isRegistry && Platform.isWindows) {
        // Registry items cannot be easily restored without backup
        _error = 'Registry items require manual restoration';
        notifyListeners();
        return false;
      }

      // File-based quarantine - move file back
      if (await quarantinedFile.exists()) {
        await quarantinedFile.rename(restorePath);

        // Reload if it's a launch agent/daemon on macOS
        if (Platform.isMacOS && (restorePath.contains('LaunchAgents') || restorePath.contains('LaunchDaemons'))) {
          await Process.run('launchctl', ['load', restorePath]);
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

  /// Get list of quarantined items with metadata
  Future<List<QuarantinedItem>> getQuarantinedItems() async {
    final items = <QuarantinedItem>[];
    try {
      final quarantineDir = await _getQuarantineDir();
      final metadata = await _loadQuarantineMetadata();

      if (await quarantineDir.exists()) {
        await for (final entity in quarantineDir.list()) {
          if (entity is File && !entity.path.endsWith('.metadata.json')) {
            final fileName = entity.path.split(Platform.pathSeparator).last;
            final itemMeta = metadata[fileName] as Map<String, dynamic>?;

            items.add(QuarantinedItem(
              fileName: fileName,
              originalPath: itemMeta?['original_path'] as String? ?? '',
              name: itemMeta?['name'] as String? ?? fileName,
              type: itemMeta?['type_display_name'] as String? ?? 'Unknown',
              quarantinedAt: itemMeta?['quarantined_at'] != null
                  ? DateTime.tryParse(itemMeta!['quarantined_at'] as String)
                  : null,
              isService: itemMeta?['is_service'] as bool? ?? false,
              isRegistry: itemMeta?['is_registry'] as bool? ?? false,
              isTask: itemMeta?['is_task'] as bool? ?? false,
            ));
          }
        }
      }
    } catch (e) {
      // Ignore
    }
    return items;
  }

  /// Delete a quarantined item permanently
  Future<bool> deleteQuarantinedItem(String fileName) async {
    try {
      final quarantineDir = await _getQuarantineDir();
      final file = File('${quarantineDir.path}/$fileName');
      if (await file.exists()) {
        await file.delete();
        await _deleteQuarantineMetadata(fileName);
        return true;
      }
    } catch (e) {
      _error = 'Failed to delete item: $e';
      notifyListeners();
    }
    return false;
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
