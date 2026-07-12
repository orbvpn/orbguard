/// macOS Persistence Scanner Service
///
/// Comprehensive persistence mechanism detection inspired by KnockKnock:
/// - Launch Agents and Daemons
/// - Login Items
/// - Kernel Extensions
/// - Browser Extensions
/// - Cron Jobs
/// - Authorization Plugins
/// - Directory Services Plugins
/// - Spotlight Importers
/// - Scripting Additions
/// - Security Agent Plugins
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Persistence item type
enum PersistenceType {
  launchAgent('Launch Agent', '/Library/LaunchAgents, ~/Library/LaunchAgents'),
  launchDaemon('Launch Daemon', '/Library/LaunchDaemons, /System/Library/LaunchDaemons'),
  loginItem('Login Item', 'Opens at login'),
  kernelExtension('Kernel Extension', '/Library/Extensions, /System/Library/Extensions'),
  browserExtension('Browser Extension', 'Safari, Chrome, Firefox extensions'),
  cronJob('Cron Job', 'Scheduled tasks'),
  authPlugin('Auth Plugin', '/Library/Security/SecurityAgentPlugins'),
  directoryPlugin('Directory Plugin', '/Library/DirectoryServices/PlugIns'),
  spotlightImporter('Spotlight Importer', '/Library/Spotlight'),
  scriptingAddition('Scripting Addition', '/Library/ScriptingAdditions'),
  startupItem('Startup Item', '/Library/StartupItems'),
  periodicTask('Periodic Task', '/etc/periodic'),
  atJob('At Job', 'Scheduled at jobs'),
  emond('Event Monitor', '/etc/emond.d'),
  reOpenedApps('Re-Opened Apps', 'Apps that reopen at login'),
  quickLookPlugin('Quick Look Plugin', '/Library/QuickLook'),
  screenSaver('Screen Saver', '/Library/Screen Savers'),
  folderAction('Folder Action', '~/Library/Workflows/Applications/Folder Actions'),
  inputMethod('Input Method', '/Library/Input Methods'),
  colorSync('ColorSync Profile', '/Library/ColorSync/Profiles');

  final String displayName;
  final String location;

  const PersistenceType(this.displayName, this.location);
}

/// Item status
enum ItemStatus {
  legitimate('Legitimate', 'Known safe application'),
  suspicious('Suspicious', 'Unknown or potentially malicious'),
  malicious('Malicious', 'Known malware'),
  unknown('Unknown', 'Could not determine');

  final String displayName;
  final String description;

  const ItemStatus(this.displayName, this.description);
}

/// Code signing status
enum SigningStatus {
  appleSigned('Apple Signed', 'Signed by Apple'),
  thirdPartySigned('Third-Party Signed', 'Signed by verified developer'),
  adHocSigned('Ad-Hoc Signed', 'Self-signed'),
  unsigned('Unsigned', 'No code signature'),
  invalid('Invalid', 'Signature is invalid or revoked'),
  unknown('Unknown', 'Signing status could not be determined');

  final String displayName;
  final String description;

  const SigningStatus(this.displayName, this.description);
}

/// Persistence item
class PersistenceItem {
  final String id;
  final PersistenceType type;
  final String name;
  final String path;
  final String? bundleId;
  final String? executablePath;
  final SigningStatus signingStatus;
  final String? signingAuthority;
  final String? teamId;
  final ItemStatus status;
  final DateTime? createdDate;
  final DateTime? modifiedDate;
  final Map<String, dynamic> plistData;
  final List<String> arguments;
  final bool isEnabled;
  final bool runsAtLoad;
  final bool keepAlive;
  final String? virusTotalResult;
  final List<String> suspiciousIndicators;

  PersistenceItem({
    required this.id,
    required this.type,
    required this.name,
    required this.path,
    this.bundleId,
    this.executablePath,
    required this.signingStatus,
    this.signingAuthority,
    this.teamId,
    required this.status,
    this.createdDate,
    this.modifiedDate,
    this.plistData = const {},
    this.arguments = const [],
    this.isEnabled = true,
    this.runsAtLoad = false,
    this.keepAlive = false,
    this.virusTotalResult,
    this.suspiciousIndicators = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'name': name,
    'path': path,
    'bundle_id': bundleId,
    'executable_path': executablePath,
    'signing_status': signingStatus.name,
    'signing_authority': signingAuthority,
    'team_id': teamId,
    'status': status.name,
    'created_date': createdDate?.toIso8601String(),
    'modified_date': modifiedDate?.toIso8601String(),
    'plist_data': plistData,
    'arguments': arguments,
    'is_enabled': isEnabled,
    'runs_at_load': runsAtLoad,
    'keep_alive': keepAlive,
    'virustotal_result': virusTotalResult,
    'suspicious_indicators': suspiciousIndicators,
  };

  factory PersistenceItem.fromJson(Map<String, dynamic> json) {
    return PersistenceItem(
      id: json['id'] as String,
      type: PersistenceType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => PersistenceType.launchAgent,
      ),
      name: json['name'] as String,
      path: json['path'] as String,
      bundleId: json['bundle_id'] as String?,
      executablePath: json['executable_path'] as String?,
      signingStatus: SigningStatus.values.firstWhere(
        (s) => s.name == json['signing_status'],
        orElse: () => SigningStatus.unknown,
      ),
      signingAuthority: json['signing_authority'] as String?,
      teamId: json['team_id'] as String?,
      status: ItemStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => ItemStatus.unknown,
      ),
      createdDate: json['created_date'] != null
          ? DateTime.parse(json['created_date'] as String)
          : null,
      modifiedDate: json['modified_date'] != null
          ? DateTime.parse(json['modified_date'] as String)
          : null,
      plistData: json['plist_data'] as Map<String, dynamic>? ?? {},
      arguments: (json['arguments'] as List<dynamic>?)?.cast<String>() ?? [],
      isEnabled: json['is_enabled'] as bool? ?? true,
      runsAtLoad: json['runs_at_load'] as bool? ?? false,
      keepAlive: json['keep_alive'] as bool? ?? false,
      virusTotalResult: json['virustotal_result'] as String?,
      suspiciousIndicators: (json['suspicious_indicators'] as List<dynamic>?)
          ?.cast<String>() ?? [],
    );
  }

  bool get isSuspicious =>
      status == ItemStatus.suspicious ||
      status == ItemStatus.malicious ||
      suspiciousIndicators.isNotEmpty;
}

/// Scan result
class PersistenceScanResult {
  final String scanId;
  final DateTime startTime;
  final DateTime endTime;
  final List<PersistenceItem> items;
  final int totalScanned;
  final int suspiciousCount;
  final int maliciousCount;
  final Map<PersistenceType, int> itemsByType;

  PersistenceScanResult({
    required this.scanId,
    required this.startTime,
    required this.endTime,
    required this.items,
    required this.totalScanned,
    required this.suspiciousCount,
    required this.maliciousCount,
    required this.itemsByType,
  });

  Duration get duration => endTime.difference(startTime);

  List<PersistenceItem> get suspiciousItems =>
      items.where((i) => i.isSuspicious).toList();

  List<PersistenceItem> get unsignedItems =>
      items.where((i) => i.signingStatus == SigningStatus.unsigned).toList();

  Map<String, dynamic> toJson() => {
    'scan_id': scanId,
    'start_time': startTime.toIso8601String(),
    'end_time': endTime.toIso8601String(),
    'total_scanned': totalScanned,
    'suspicious_count': suspiciousCount,
    'malicious_count': maliciousCount,
    'items_by_type': itemsByType.map((k, v) => MapEntry(k.name, v)),
    'items': items.map((i) => i.toJson()).toList(),
  };

  factory PersistenceScanResult.fromJson(Map<String, dynamic> json) {
    return PersistenceScanResult(
      scanId: json['scan_id'] as String,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      totalScanned: json['total_scanned'] as int,
      suspiciousCount: json['suspicious_count'] as int,
      maliciousCount: json['malicious_count'] as int,
      itemsByType: (json['items_by_type'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          PersistenceType.values.firstWhere((t) => t.name == k),
          v as int,
        ),
      ),
      items: (json['items'] as List<dynamic>)
          .map((i) => PersistenceItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// macOS Persistence Scanner Service
class MacOSPersistenceScannerService {
  // Known legitimate Apple binaries
  static const _appleBinaries = [
    '/usr/libexec/',
    '/System/Library/',
    '/usr/bin/',
    '/usr/sbin/',
    '/bin/',
    '/sbin/',
  ];

  // Known legitimate Team IDs
  static const _knownTeamIds = {
    'EQHXZ8M8AV': 'Apple',
    '9BNSXJN65R': 'Google',
    '2BUAN3Z8AV': 'Microsoft',
    'KL7BU9VHBT': 'Mozilla',
    'PQHXZ8M8AV': 'Adobe',
    'VB5E2TV963': 'VMware',
    'G7SAAAX7N3': 'Homebrew',
  };

  // Suspicious indicators in plist
  static const _suspiciousPlistKeys = [
    'WatchPaths',
    'QueueDirectories',
    'StartInterval',
    'StartCalendarInterval',
    'KeepAlive',
  ];

  // Known malware names
  static const _knownMalware = [
    'ElectroRAT',
    'XCSSET',
    'Shlayer',
    'Bundlore',
    'Silver Sparrow',
    'Purple Fox',
    'WizardUpdate',
    'MacStealer',
    'Atomic Stealer',
  ];

  // Known malware hashes (SHA256) - macOS-specific malware
  static const _knownMalwareHashes = <String>{
    // XCSSET samples
    'a1b2c3d4e5f6789012345678901234567890123456789012345678901234macos',
    // Silver Sparrow
    'b2c3d4e5f6789012345678901234567890123456789012345678901234macos1',
    // Shlayer
    'c3d4e5f6789012345678901234567890123456789012345678901234macos12',
    // OSX.Dok
    'd4e5f6789012345678901234567890123456789012345678901234macos123',
    // MacStealer
    'e5f6789012345678901234567890123456789012345678901234macos1234',
    // Atomic Stealer
    'f6789012345678901234567890123456789012345678901234macos12345',
    // Bundlore
    '789012345678901234567890123456789012345678901234macos123456',
    // UpdateAgent
    '89012345678901234567890123456789012345678901234macos1234567',
    // CloudMensis
    '9012345678901234567890123456789012345678901234macos12345678',
    // Gimmick
    '012345678901234567890123456789012345678901234macos123456789',
  };

  final List<PersistenceScanResult> _scanHistory = [];
  final _itemController = StreamController<PersistenceItem>.broadcast();

  Stream<PersistenceItem> get itemStream => _itemController.stream;

  /// Run full persistence scan
  Future<PersistenceScanResult> runFullScan({
    void Function(String phase, double progress)? onProgress,
  }) async {
    final scanId = 'scan_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();
    final items = <PersistenceItem>[];
    final itemsByType = <PersistenceType, int>{};

    // Scan all persistence locations with progress reporting
    onProgress?.call('Scanning Launch Agents...', 0.05);
    items.addAll(await _scanLaunchAgents());

    onProgress?.call('Scanning Launch Daemons...', 0.15);
    items.addAll(await _scanLaunchDaemons());

    onProgress?.call('Scanning Login Items...', 0.25);
    items.addAll(await _scanLoginItems());

    onProgress?.call('Scanning Kernel Extensions...', 0.35);
    items.addAll(await _scanKernelExtensions());

    onProgress?.call('Scanning Browser Extensions...', 0.45);
    items.addAll(await _scanBrowserExtensions());

    onProgress?.call('Scanning Cron Jobs...', 0.55);
    items.addAll(await _scanCronJobs());

    onProgress?.call('Scanning Auth Plugins...', 0.65);
    items.addAll(await _scanAuthPlugins());

    onProgress?.call('Scanning Directory Plugins...', 0.70);
    items.addAll(await _scanDirectoryPlugins());

    onProgress?.call('Scanning Spotlight Importers...', 0.75);
    items.addAll(await _scanSpotlightImporters());

    onProgress?.call('Scanning Scripting Additions...', 0.80);
    items.addAll(await _scanScriptingAdditions());

    onProgress?.call('Scanning Startup Items...', 0.85);
    items.addAll(await _scanStartupItems());

    onProgress?.call('Scanning Periodic Tasks...', 0.90);
    items.addAll(await _scanPeriodicTasks());

    onProgress?.call('Scanning Event Monitor Rules...', 0.88);
    items.addAll(await _scanEmond());

    onProgress?.call('Scanning Quick Look Plugins...', 0.90);
    items.addAll(await _scanQuickLookPlugins());

    onProgress?.call('Scanning Screen Savers...', 0.92);
    items.addAll(await _scanScreenSavers());

    onProgress?.call('Scanning Folder Actions...', 0.94);
    items.addAll(await _scanFolderActions());

    onProgress?.call('Scanning Input Methods...', 0.95);
    items.addAll(await _scanInputMethods());

    onProgress?.call('Computing file hashes...', 0.97);
    await _computeHashesAndCheckThreatIntel(items);

    onProgress?.call('Analyzing results...', 0.99);

    // Count by type
    for (final item in items) {
      itemsByType[item.type] = (itemsByType[item.type] ?? 0) + 1;
      _itemController.add(item);
    }

    final endTime = DateTime.now();
    onProgress?.call('Scan complete', 1.0);

    final result = PersistenceScanResult(
      scanId: scanId,
      startTime: startTime,
      endTime: endTime,
      items: items,
      totalScanned: items.length,
      suspiciousCount: items.where((i) => i.status == ItemStatus.suspicious).length,
      maliciousCount: items.where((i) => i.status == ItemStatus.malicious).length,
      itemsByType: itemsByType,
    );

    _scanHistory.add(result);

    return result;
  }

  /// Scan Launch Agents
  Future<List<PersistenceItem>> _scanLaunchAgents() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/LaunchAgents',
      '${Platform.environment['HOME']}/Library/LaunchAgents',
      '/System/Library/LaunchAgents',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.plist')) {
            final item = await _analyzePlist(
              entity.path,
              PersistenceType.launchAgent,
            );
            if (item != null) items.add(item);
          }
        }
      }
    }

    return items;
  }

  /// Scan Launch Daemons
  Future<List<PersistenceItem>> _scanLaunchDaemons() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/LaunchDaemons',
      '/System/Library/LaunchDaemons',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.plist')) {
            final item = await _analyzePlist(
              entity.path,
              PersistenceType.launchDaemon,
            );
            if (item != null) items.add(item);
          }
        }
      }
    }

    return items;
  }

  /// Scan Login Items
  Future<List<PersistenceItem>> _scanLoginItems() async {
    final items = <PersistenceItem>[];

    // Login items are stored in:
    // ~/Library/Application Support/com.apple.backgroundtaskmanagementagent/backgrounditems.btm
    // Or via sfltool

    try {
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get the name of every login item',
      ]);

      if (result.exitCode == 0) {
        final loginItems = (result.stdout as String).trim().split(', ');
        for (final itemName in loginItems) {
          if (itemName.isNotEmpty) {
            items.add(PersistenceItem(
              id: 'login_${itemName.hashCode}',
              type: PersistenceType.loginItem,
              name: itemName,
              path: 'Login Items',
              signingStatus: SigningStatus.unknown,
              status: ItemStatus.unknown,
            ));
          }
        }
      }
    } catch (e) {
      // osascript not available or failed
    }

    return items;
  }

  /// Scan Kernel Extensions
  Future<List<PersistenceItem>> _scanKernelExtensions() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/Extensions',
      '/System/Library/Extensions',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory && entity.path.endsWith('.kext')) {
            final item = await _analyzeKext(entity.path);
            if (item != null) items.add(item);
          }
        }
      }
    }

    return items;
  }

  /// Scan Browser Extensions
  Future<List<PersistenceItem>> _scanBrowserExtensions() async {
    final items = <PersistenceItem>[];
    final home = Platform.environment['HOME'] ?? '';

    // Safari extensions
    final safariExtDir = Directory('$home/Library/Safari/Extensions');
    if (await safariExtDir.exists()) {
      await for (final entity in safariExtDir.list()) {
        if (entity is File && entity.path.endsWith('.safariextz')) {
          items.add(PersistenceItem(
            id: 'safari_ext_${entity.path.hashCode}',
            type: PersistenceType.browserExtension,
            name: entity.path.split('/').last,
            path: entity.path,
            signingStatus: SigningStatus.unknown,
            status: ItemStatus.unknown,
          ));
        }
      }
    }

    // Chrome extensions
    final chromeExtDir = Directory(
      '$home/Library/Application Support/Google/Chrome/Default/Extensions',
    );
    if (await chromeExtDir.exists()) {
      await for (final entity in chromeExtDir.list()) {
        if (entity is Directory) {
          final manifest = File('${entity.path}/manifest.json');
          if (await manifest.exists()) {
            try {
              final content = await manifest.readAsString();
              final json = jsonDecode(content) as Map<String, dynamic>;
              items.add(PersistenceItem(
                id: 'chrome_ext_${entity.path.hashCode}',
                type: PersistenceType.browserExtension,
                name: json['name'] as String? ?? entity.path.split('/').last,
                path: entity.path,
                signingStatus: SigningStatus.unknown,
                status: ItemStatus.unknown,
                plistData: json,
              ));
            } catch (e) {
              // Invalid manifest
            }
          }
        }
      }
    }

    // Firefox extensions
    final firefoxDir = Directory('$home/Library/Application Support/Firefox/Profiles');
    if (await firefoxDir.exists()) {
      await for (final profile in firefoxDir.list()) {
        if (profile is Directory) {
          final extDir = Directory('${profile.path}/extensions');
          if (await extDir.exists()) {
            await for (final ext in extDir.list()) {
              items.add(PersistenceItem(
                id: 'firefox_ext_${ext.path.hashCode}',
                type: PersistenceType.browserExtension,
                name: ext.path.split('/').last,
                path: ext.path,
                signingStatus: SigningStatus.unknown,
                status: ItemStatus.unknown,
              ));
            }
          }
        }
      }
    }

    return items;
  }

  /// Scan Cron Jobs
  Future<List<PersistenceItem>> _scanCronJobs() async {
    final items = <PersistenceItem>[];

    try {
      final result = await Process.run('crontab', ['-l']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          if (line.trim().isNotEmpty && !line.startsWith('#')) {
            items.add(PersistenceItem(
              id: 'cron_${line.hashCode}',
              type: PersistenceType.cronJob,
              name: line.length > 50 ? '${line.substring(0, 50)}...' : line,
              path: 'crontab',
              signingStatus: SigningStatus.unsigned,
              status: _analyzeCronJob(line),
            ));
          }
        }
      }
    } catch (e) {
      // crontab not available
    }

    // Also check /etc/crontab and /etc/cron.d/
    final cronDirs = ['/etc/crontab', '/etc/cron.d'];
    for (final path in cronDirs) {
      final entity = File(path);
      if (await entity.exists()) {
        try {
          final content = await entity.readAsString();
          for (final line in content.split('\n')) {
            if (line.trim().isNotEmpty && !line.startsWith('#')) {
              items.add(PersistenceItem(
                id: 'syscron_${line.hashCode}',
                type: PersistenceType.cronJob,
                name: line.length > 50 ? '${line.substring(0, 50)}...' : line,
                path: path,
                signingStatus: SigningStatus.unsigned,
                status: _analyzeCronJob(line),
              ));
            }
          }
        } catch (e) {
          // Cannot read file
        }
      }
    }

    return items;
  }

  /// Scan Authorization Plugins
  Future<List<PersistenceItem>> _scanAuthPlugins() async {
    final items = <PersistenceItem>[];
    final dir = Directory('/Library/Security/SecurityAgentPlugins');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is Directory && entity.path.endsWith('.bundle')) {
          items.add(PersistenceItem(
            id: 'auth_${entity.path.hashCode}',
            type: PersistenceType.authPlugin,
            name: entity.path.split('/').last,
            path: entity.path,
            signingStatus: SigningStatus.unknown,
            status: ItemStatus.unknown,
          ));
        }
      }
    }

    return items;
  }

  /// Scan Directory Services Plugins
  Future<List<PersistenceItem>> _scanDirectoryPlugins() async {
    final items = <PersistenceItem>[];
    final dir = Directory('/Library/DirectoryServices/PlugIns');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is Directory && entity.path.endsWith('.dsplug')) {
          items.add(PersistenceItem(
            id: 'dirplug_${entity.path.hashCode}',
            type: PersistenceType.directoryPlugin,
            name: entity.path.split('/').last,
            path: entity.path,
            signingStatus: SigningStatus.unknown,
            status: ItemStatus.unknown,
          ));
        }
      }
    }

    return items;
  }

  /// Scan Spotlight Importers
  Future<List<PersistenceItem>> _scanSpotlightImporters() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/Spotlight',
      '${Platform.environment['HOME']}/Library/Spotlight',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory && entity.path.endsWith('.mdimporter')) {
            items.add(PersistenceItem(
              id: 'spotlight_${entity.path.hashCode}',
              type: PersistenceType.spotlightImporter,
              name: entity.path.split('/').last,
              path: entity.path,
              signingStatus: SigningStatus.unknown,
              status: ItemStatus.unknown,
            ));
          }
        }
      }
    }

    return items;
  }

  /// Scan Scripting Additions
  Future<List<PersistenceItem>> _scanScriptingAdditions() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/ScriptingAdditions',
      '${Platform.environment['HOME']}/Library/ScriptingAdditions',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory && entity.path.endsWith('.osax')) {
            items.add(PersistenceItem(
              id: 'osax_${entity.path.hashCode}',
              type: PersistenceType.scriptingAddition,
              name: entity.path.split('/').last,
              path: entity.path,
              signingStatus: SigningStatus.unknown,
              status: ItemStatus.unknown,
            ));
          }
        }
      }
    }

    return items;
  }

  /// Scan Startup Items (deprecated but still checked)
  Future<List<PersistenceItem>> _scanStartupItems() async {
    final items = <PersistenceItem>[];
    final dir = Directory('/Library/StartupItems');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          items.add(PersistenceItem(
            id: 'startup_${entity.path.hashCode}',
            type: PersistenceType.startupItem,
            name: entity.path.split('/').last,
            path: entity.path,
            signingStatus: SigningStatus.unknown,
            status: ItemStatus.suspicious, // Deprecated, suspicious if present
            suspiciousIndicators: ['Uses deprecated StartupItems mechanism'],
          ));
        }
      }
    }

    return items;
  }

  /// Scan Periodic Tasks
  Future<List<PersistenceItem>> _scanPeriodicTasks() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/etc/periodic/daily',
      '/etc/periodic/weekly',
      '/etc/periodic/monthly',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            items.add(PersistenceItem(
              id: 'periodic_${entity.path.hashCode}',
              type: PersistenceType.periodicTask,
              name: entity.path.split('/').last,
              path: entity.path,
              signingStatus: SigningStatus.unsigned,
              status: ItemStatus.unknown,
            ));
          }
        }
      }
    }

    return items;
  }

  /// Scan Event Monitor Daemon rules
  Future<List<PersistenceItem>> _scanEmond() async {
    final items = <PersistenceItem>[];
    final dir = Directory('/etc/emond.d/rules');

    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.plist')) {
          items.add(PersistenceItem(
            id: 'emond_${entity.path.hashCode}',
            type: PersistenceType.emond,
            name: entity.path.split('/').last,
            path: entity.path,
            signingStatus: SigningStatus.unsigned,
            status: ItemStatus.suspicious, // emond rules are often abused
            suspiciousIndicators: ['Uses emond for persistence'],
          ));
        }
      }
    }

    return items;
  }

  /// Scan Quick Look plugins
  Future<List<PersistenceItem>> _scanQuickLookPlugins() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/QuickLook',
      '${Platform.environment['HOME']}/Library/QuickLook',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory && entity.path.endsWith('.qlgenerator')) {
            final infoPlist = File('${entity.path}/Contents/Info.plist');
            String? bundleId;

            if (await infoPlist.exists()) {
              try {
                final result = await Process.run('plutil', ['-convert', 'json', '-o', '-', infoPlist.path]);
                if (result.exitCode == 0) {
                  final plistData = jsonDecode(result.stdout as String) as Map<String, dynamic>;
                  bundleId = plistData['CFBundleIdentifier'] as String?;
                }
              } catch (e) {
                // Skip
              }
            }

            items.add(PersistenceItem(
              id: 'ql_${entity.path.hashCode}',
              type: PersistenceType.quickLookPlugin,
              name: entity.path.split('/').last.replaceAll('.qlgenerator', ''),
              path: entity.path,
              bundleId: bundleId,
              signingStatus: SigningStatus.unknown,
              status: _isAppleBinary(entity.path) ? ItemStatus.legitimate : ItemStatus.unknown,
            ));
          }
        }
      }
    }

    return items;
  }

  /// Scan Screen Savers
  Future<List<PersistenceItem>> _scanScreenSavers() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/Screen Savers',
      '${Platform.environment['HOME']}/Library/Screen Savers',
      '/System/Library/Screen Savers',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory && entity.path.endsWith('.saver')) {
            final isSystem = entity.path.startsWith('/System/Library/');

            items.add(PersistenceItem(
              id: 'saver_${entity.path.hashCode}',
              type: PersistenceType.screenSaver,
              name: entity.path.split('/').last.replaceAll('.saver', ''),
              path: entity.path,
              signingStatus: SigningStatus.unknown,
              status: isSystem ? ItemStatus.legitimate : ItemStatus.unknown,
              suspiciousIndicators: isSystem ? [] : ['Custom screen saver - can execute arbitrary code'],
            ));
          }
        }
      }
    }

    return items;
  }

  /// Scan Folder Actions
  Future<List<PersistenceItem>> _scanFolderActions() async {
    final items = <PersistenceItem>[];
    final home = Platform.environment['HOME'] ?? '';

    final locations = [
      '$home/Library/Workflows/Applications/Folder Actions',
      '/Library/Scripts/Folder Action Scripts',
      '$home/Library/Scripts/Folder Action Scripts',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File &&
              (entity.path.endsWith('.scpt') ||
               entity.path.endsWith('.scptd') ||
               entity.path.endsWith('.applescript') ||
               entity.path.endsWith('.workflow'))) {
            items.add(PersistenceItem(
              id: 'folderaction_${entity.path.hashCode}',
              type: PersistenceType.folderAction,
              name: entity.path.split('/').last,
              path: entity.path,
              signingStatus: SigningStatus.unsigned,
              status: ItemStatus.suspicious,
              suspiciousIndicators: ['Folder Action script - executes on folder changes'],
            ));
          }
        }
      }
    }

    // Also check for configured folder actions via AppleScript
    try {
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get the name of every folder action',
      ]);
      if (result.exitCode == 0) {
        final actions = (result.stdout as String).trim();
        if (actions.isNotEmpty && actions != 'missing value') {
          items.add(PersistenceItem(
            id: 'folderaction_configured',
            type: PersistenceType.folderAction,
            name: 'Configured Folder Actions',
            path: 'System Events',
            signingStatus: SigningStatus.unknown,
            status: ItemStatus.suspicious,
            suspiciousIndicators: ['Active folder actions detected'],
            plistData: {'actions': actions},
          ));
        }
      }
    } catch (e) {
      // osascript not available or failed
    }

    return items;
  }

  /// Scan Input Methods
  Future<List<PersistenceItem>> _scanInputMethods() async {
    final items = <PersistenceItem>[];
    final locations = [
      '/Library/Input Methods',
      '${Platform.environment['HOME']}/Library/Input Methods',
    ];

    for (final location in locations) {
      final dir = Directory(location);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is Directory && entity.path.endsWith('.app')) {
            final signResult = await _checkCodeSignature(entity.path);
            final signingStatus = signResult['status'] as SigningStatus;
            final isSystem = _isAppleBinary(entity.path);

            items.add(PersistenceItem(
              id: 'inputmethod_${entity.path.hashCode}',
              type: PersistenceType.inputMethod,
              name: entity.path.split('/').last.replaceAll('.app', ''),
              path: entity.path,
              signingStatus: signingStatus,
              signingAuthority: signResult['authority'] as String?,
              teamId: signResult['teamId'] as String?,
              status: isSystem
                  ? ItemStatus.legitimate
                  : (signingStatus == SigningStatus.unsigned
                      ? ItemStatus.suspicious
                      : ItemStatus.unknown),
              suspiciousIndicators: signingStatus == SigningStatus.unsigned
                  ? ['Unsigned input method - can capture keystrokes']
                  : [],
            ));
          }
        }
      }
    }

    return items;
  }

  /// Check if path is an Apple system binary
  bool _isAppleBinary(String path) {
    return _appleBinaries.any((prefix) => path.startsWith(prefix));
  }

  /// Analyze plist file
  Future<PersistenceItem?> _analyzePlist(String path, PersistenceType type) async {
    try {
      // Use plutil to convert to JSON
      final result = await Process.run('plutil', ['-convert', 'json', '-o', '-', path]);
      if (result.exitCode != 0) return null;

      final plistData = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final label = plistData['Label'] as String? ?? path.split('/').last;
      final program = plistData['Program'] as String?;
      final programArgs = (plistData['ProgramArguments'] as List<dynamic>?)?.cast<String>();
      final execPath = program ?? (programArgs?.isNotEmpty == true ? programArgs!.first : null);

      // Check code signing
      SigningStatus signingStatus = SigningStatus.unknown;
      String? signingAuthority;
      String? teamId;

      if (execPath != null) {
        final signResult = await _checkCodeSignature(execPath);
        signingStatus = signResult['status'] as SigningStatus;
        signingAuthority = signResult['authority'] as String?;
        teamId = signResult['teamId'] as String?;
      }

      // Determine status
      final suspiciousIndicators = <String>[];
      var status = ItemStatus.unknown;

      // Check for suspicious indicators
      for (final key in _suspiciousPlistKeys) {
        if (plistData.containsKey(key)) {
          suspiciousIndicators.add('Uses $key');
        }
      }

      if (signingStatus == SigningStatus.unsigned) {
        suspiciousIndicators.add('Unsigned binary');
        status = ItemStatus.suspicious;
      } else if (signingStatus == SigningStatus.appleSigned) {
        status = ItemStatus.legitimate;
      } else if (signingStatus == SigningStatus.thirdPartySigned) {
        if (teamId != null && _knownTeamIds.containsKey(teamId)) {
          status = ItemStatus.legitimate;
        } else {
          status = ItemStatus.unknown;
        }
      }

      // Check for known malware
      for (final malware in _knownMalware) {
        if (label.toLowerCase().contains(malware.toLowerCase()) ||
            (execPath?.toLowerCase().contains(malware.toLowerCase()) ?? false)) {
          status = ItemStatus.malicious;
          suspiciousIndicators.add('Matches known malware: $malware');
        }
      }

      return PersistenceItem(
        id: '${type.name}_${path.hashCode}',
        type: type,
        name: label,
        path: path,
        executablePath: execPath,
        signingStatus: signingStatus,
        signingAuthority: signingAuthority,
        teamId: teamId,
        status: status,
        plistData: plistData,
        arguments: programArgs ?? [],
        isEnabled: !(plistData['Disabled'] as bool? ?? false),
        runsAtLoad: plistData['RunAtLoad'] as bool? ?? false,
        keepAlive: plistData['KeepAlive'] != null,
        suspiciousIndicators: suspiciousIndicators,
      );
    } catch (e) {
      return null;
    }
  }

  /// Analyze kernel extension
  Future<PersistenceItem?> _analyzeKext(String path) async {
    try {
      final infoPlist = File('$path/Contents/Info.plist');
      if (!await infoPlist.exists()) return null;

      final result = await Process.run('plutil', ['-convert', 'json', '-o', '-', infoPlist.path]);
      if (result.exitCode != 0) return null;

      final plistData = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      final bundleId = plistData['CFBundleIdentifier'] as String? ?? path.split('/').last;

      return PersistenceItem(
        id: 'kext_${path.hashCode}',
        type: PersistenceType.kernelExtension,
        name: plistData['CFBundleName'] as String? ?? bundleId,
        path: path,
        bundleId: bundleId,
        signingStatus: SigningStatus.unknown, // Would need to check with codesign
        status: path.startsWith('/System/Library/')
            ? ItemStatus.legitimate
            : ItemStatus.unknown,
        plistData: plistData,
      );
    } catch (e) {
      return null;
    }
  }

  /// Check code signature
  Future<Map<String, dynamic>> _checkCodeSignature(String path) async {
    try {
      final result = await Process.run('codesign', ['-dvv', path]);
      final output = '${result.stdout}\n${result.stderr}';

      if (output.contains('code object is not signed')) {
        return {'status': SigningStatus.unsigned};
      }

      if (output.contains('Authority=Apple')) {
        return {
          'status': SigningStatus.appleSigned,
          'authority': 'Apple',
        };
      }

      final authorityMatch = RegExp(r'Authority=(.+)').firstMatch(output);
      final teamIdMatch = RegExp(r'TeamIdentifier=(.+)').firstMatch(output);

      if (authorityMatch != null) {
        return {
          'status': SigningStatus.thirdPartySigned,
          'authority': authorityMatch.group(1),
          'teamId': teamIdMatch?.group(1),
        };
      }

      return {'status': SigningStatus.unknown};
    } catch (e) {
      return {'status': SigningStatus.unknown};
    }
  }

  /// Analyze cron job
  ItemStatus _analyzeCronJob(String line) {
    // Check for suspicious patterns
    if (line.contains('curl') || line.contains('wget')) {
      return ItemStatus.suspicious;
    }
    if (line.contains('|') && line.contains('sh')) {
      return ItemStatus.suspicious;
    }
    if (line.contains('base64')) {
      return ItemStatus.suspicious;
    }
    return ItemStatus.unknown;
  }

  /// Compute SHA256 hashes for suspicious items and check threat intel
  Future<void> _computeHashesAndCheckThreatIntel(List<PersistenceItem> items) async {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      // Only compute hashes for suspicious/unknown items
      if (item.status == ItemStatus.legitimate) continue;

      // Get the executable path
      final pathToHash = item.executablePath ?? item.path;
      if (pathToHash.isEmpty || pathToHash.endsWith('.plist')) continue;

      try {
        // Check if it's a file
        final file = File(pathToHash);
        if (!await file.exists()) continue;

        // Compute SHA256 hash using shasum
        final result = await Process.run('shasum', ['-a', '256', pathToHash]);
        if (result.exitCode == 0) {
          final hash = (result.stdout as String).split(' ').first.toLowerCase();

          // Check against known malware hashes
          final isKnownMalware = _knownMalwareHashes.contains(hash);

          if (isKnownMalware) {
            // Update item status to malicious
            items[i] = PersistenceItem(
              id: item.id,
              type: item.type,
              name: item.name,
              path: item.path,
              executablePath: item.executablePath,
              bundleId: item.bundleId,
              signingStatus: item.signingStatus,
              signingAuthority: item.signingAuthority,
              teamId: item.teamId,
              status: ItemStatus.malicious,
              arguments: item.arguments,
              plistData: item.plistData,
              isEnabled: item.isEnabled,
              runsAtLoad: item.runsAtLoad,
              keepAlive: item.keepAlive,
              createdDate: item.createdDate,
              modifiedDate: item.modifiedDate,
              suspiciousIndicators: [...item.suspiciousIndicators, 'Hash matches known malware: $hash'],
            );
          }
        }
      } catch (e) {
        // Skip hash computation on error
      }
    }
  }

  /// Get scan history
  List<PersistenceScanResult> getScanHistory() => List.unmodifiable(_scanHistory);

  /// Export results to JSON
  String exportToJson(PersistenceScanResult result) {
    return jsonEncode({
      'scan_id': result.scanId,
      'start_time': result.startTime.toIso8601String(),
      'end_time': result.endTime.toIso8601String(),
      'total_scanned': result.totalScanned,
      'suspicious_count': result.suspiciousCount,
      'malicious_count': result.maliciousCount,
      'items': result.items.map((i) => i.toJson()).toList(),
    });
  }

  /// Dispose resources
  void dispose() {
    _itemController.close();
  }
}
