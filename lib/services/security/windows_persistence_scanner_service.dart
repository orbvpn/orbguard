/// Windows Persistence Scanner Service
///
/// Comprehensive persistence mechanism detection for Windows:
/// - Registry Run Keys
/// - Scheduled Tasks
/// - Windows Services
/// - Startup Folders
/// - WMI Event Subscriptions
/// - DLL Search Order Hijacking
/// - Browser Extensions
/// - COM Objects
/// - AppInit DLLs
/// - Image File Execution Options
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Windows persistence item type
enum WindowsPersistenceType {
  registryRunKey('Registry Run Key', 'HKLM/HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run'),
  registryRunOnce('Registry RunOnce', 'One-time execution at startup'),
  scheduledTask('Scheduled Task', 'Task Scheduler entries'),
  windowsService('Windows Service', 'System services'),
  startupFolder('Startup Folder', 'Shell:startup locations'),
  wmiSubscription('WMI Subscription', 'WMI event consumers'),
  dllHijack('DLL Hijack', 'DLL search order hijacking'),
  browserExtension('Browser Extension', 'Chrome, Firefox, Edge extensions'),
  comObject('COM Object', 'Component Object Model hijacking'),
  appInitDll('AppInit DLL', 'AppInit_DLLs injection'),
  imageFileExecution('IFEO', 'Image File Execution Options debugger'),
  winlogon('Winlogon', 'Winlogon helper DLLs'),
  lsaPackage('LSA Package', 'Security package loading'),
  printMonitor('Print Monitor', 'Print spooler persistence'),
  bootExecute('Boot Execute', 'Session Manager boot execution'),
  netshHelper('Netsh Helper', 'Network shell helper DLLs'),
  officeAddin('Office Add-in', 'Microsoft Office add-ins'),
  explorerShell('Explorer Shell', 'Shell extensions and handlers');

  final String displayName;
  final String location;

  const WindowsPersistenceType(this.displayName, this.location);
}

/// Item risk level
enum WindowsItemRisk {
  safe('Safe', 'Known legitimate software'),
  low('Low', 'Uncommon but likely safe'),
  medium('Medium', 'Potentially unwanted'),
  high('High', 'Suspicious characteristics'),
  critical('Critical', 'Known malware indicators');

  final String displayName;
  final String description;

  const WindowsItemRisk(this.displayName, this.description);
}

/// Signing status for Windows binaries
enum WindowsSigningStatus {
  microsoftSigned('Microsoft Signed', 'Signed by Microsoft'),
  trustedPublisher('Trusted Publisher', 'Signed by trusted publisher'),
  untrustedPublisher('Untrusted Publisher', 'Signed but not trusted'),
  selfSigned('Self-Signed', 'Self-signed certificate'),
  unsigned('Unsigned', 'No digital signature'),
  invalidSignature('Invalid', 'Signature is invalid or tampered'),
  unknown('Unknown', 'Could not determine signing status');

  final String displayName;
  final String description;

  const WindowsSigningStatus(this.displayName, this.description);
}

/// Windows persistence item
class WindowsPersistenceItem {
  final String id;
  final String name;
  final String path;
  final String? command;
  final WindowsPersistenceType type;
  final WindowsItemRisk risk;
  final WindowsSigningStatus signingStatus;
  final String? publisher;
  final String? description;
  final String? hash;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool isEnabled;
  final bool isHidden;
  final List<String> indicators;
  final Map<String, dynamic>? metadata;

  WindowsPersistenceItem({
    required this.id,
    required this.name,
    required this.path,
    this.command,
    required this.type,
    required this.risk,
    required this.signingStatus,
    this.publisher,
    this.description,
    this.hash,
    this.createdAt,
    this.modifiedAt,
    this.isEnabled = true,
    this.isHidden = false,
    this.indicators = const [],
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'command': command,
    'type': type.name,
    'risk': risk.name,
    'signing_status': signingStatus.name,
    'publisher': publisher,
    'description': description,
    'hash': hash,
    'created_at': createdAt?.toIso8601String(),
    'modified_at': modifiedAt?.toIso8601String(),
    'is_enabled': isEnabled,
    'is_hidden': isHidden,
    'indicators': indicators,
    'metadata': metadata,
  };
}

/// Windows scan result
class WindowsScanResult {
  final DateTime scannedAt;
  final Duration scanDuration;
  final int totalItems;
  final int criticalItems;
  final int highRiskItems;
  final int mediumRiskItems;
  final List<WindowsPersistenceItem> items;
  final List<String> errors;

  WindowsScanResult({
    required this.scannedAt,
    required this.scanDuration,
    required this.totalItems,
    required this.criticalItems,
    required this.highRiskItems,
    required this.mediumRiskItems,
    required this.items,
    this.errors = const [],
  });

  Map<String, dynamic> toJson() => {
    'scanned_at': scannedAt.toIso8601String(),
    'scan_duration_ms': scanDuration.inMilliseconds,
    'total_items': totalItems,
    'critical_items': criticalItems,
    'high_risk_items': highRiskItems,
    'medium_risk_items': mediumRiskItems,
    'items': items.map((i) => i.toJson()).toList(),
    'errors': errors,
  };
}

/// Windows Persistence Scanner Service
class WindowsPersistenceScannerService {
  static WindowsPersistenceScannerService? _instance;
  static WindowsPersistenceScannerService get instance =>
      _instance ??= WindowsPersistenceScannerService._();

  WindowsPersistenceScannerService._();

  // Known Microsoft binaries (whitelist)
  final Set<String> _microsoftBinaries = {
    'explorer.exe', 'svchost.exe', 'csrss.exe', 'smss.exe', 'lsass.exe',
    'services.exe', 'winlogon.exe', 'dwm.exe', 'taskhostw.exe', 'sihost.exe',
    'RuntimeBroker.exe', 'ShellExperienceHost.exe', 'SearchHost.exe',
    'ctfmon.exe', 'conhost.exe', 'dllhost.exe', 'msiexec.exe', 'spoolsv.exe',
  };

  // Suspicious keywords in commands
  final List<String> _suspiciousKeywords = [
    'powershell -enc', 'powershell -e ', 'powershell -nop',
    'cmd /c', 'wscript', 'cscript', 'mshta', 'regsvr32',
    'rundll32', 'certutil', 'bitsadmin', 'msiexec /q',
    'base64', 'hidden', 'bypass', 'downloadstring',
    'invoke-expression', 'iex', 'webclient', 'downloadfile',
    'new-object', 'system.net', 'reflection.assembly',
    'frombase64string', 'invoke-webrequest', 'start-bitstransfer',
    'invoke-mimikatz', 'invoke-shellcode', 'invoke-bloodhound',
    '-windowstyle hidden', '-executionpolicy bypass', '-noprofile',
  ];

  // Known malware hashes (sample - would be updated from threat intel)
  final Set<String> _knownMalwareHashes = {};

  // Known legitimate publishers
  final Set<String> _knownPublishers = {
    'microsoft', 'google', 'mozilla', 'adobe', 'apple',
    'intel', 'nvidia', 'amd', 'realtek', 'logitech',
  };

  /// Run full Windows persistence scan
  Future<WindowsScanResult> runFullScan({
    void Function(String phase, double progress)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      return WindowsScanResult(
        scannedAt: DateTime.now(),
        scanDuration: Duration.zero,
        totalItems: 0,
        criticalItems: 0,
        highRiskItems: 0,
        mediumRiskItems: 0,
        items: [],
        errors: ['Windows scanning only available on Windows platform'],
      );
    }

    final startTime = DateTime.now();
    final items = <WindowsPersistenceItem>[];
    final errors = <String>[];

    try {
      // Scan registry run keys
      onProgress?.call('Scanning Registry Run Keys...', 0.1);
      items.addAll(await _scanRegistryRunKeys());

      // Scan scheduled tasks
      onProgress?.call('Scanning Scheduled Tasks...', 0.2);
      items.addAll(await _scanScheduledTasks());

      // Scan Windows services
      onProgress?.call('Scanning Windows Services...', 0.35);
      items.addAll(await _scanWindowsServices());

      // Scan startup folders
      onProgress?.call('Scanning Startup Folders...', 0.45);
      items.addAll(await _scanStartupFolders());

      // Scan WMI subscriptions
      onProgress?.call('Scanning WMI Subscriptions...', 0.55);
      items.addAll(await _scanWMISubscriptions());

      // Scan browser extensions
      onProgress?.call('Scanning Browser Extensions...', 0.65);
      items.addAll(await _scanBrowserExtensions());

      // Scan COM objects
      onProgress?.call('Scanning COM Objects...', 0.60);
      items.addAll(await _scanCOMObjects());

      // Scan IFEO
      onProgress?.call('Scanning IFEO Entries...', 0.65);
      items.addAll(await _scanIFEO());

      // Scan Winlogon helpers
      onProgress?.call('Scanning Winlogon...', 0.70);
      items.addAll(await _scanWinlogon());

      // Scan AppInit DLLs
      onProgress?.call('Scanning AppInit DLLs...', 0.75);
      items.addAll(await _scanAppInitDlls());

      // Scan Print Monitors
      onProgress?.call('Scanning Print Monitors...', 0.80);
      items.addAll(await _scanPrintMonitors());

      // Scan LSA Packages
      onProgress?.call('Scanning LSA Packages...', 0.85);
      items.addAll(await _scanLSAPackages());

      // Scan Boot Execute
      onProgress?.call('Scanning Boot Execute...', 0.88);
      items.addAll(await _scanBootExecute());

      // Scan Netsh Helpers
      onProgress?.call('Scanning Netsh Helpers...', 0.91);
      items.addAll(await _scanNetshHelpers());

      // Compute file hashes for suspicious items
      onProgress?.call('Computing file hashes...', 0.95);
      await _computeHashes(items);

      // Analyze all items
      onProgress?.call('Analyzing results...', 0.98);

    } catch (e) {
      errors.add('Scan error: $e');
    }

    final endTime = DateTime.now();
    onProgress?.call('Scan complete', 1.0);

    return WindowsScanResult(
      scannedAt: startTime,
      scanDuration: endTime.difference(startTime),
      totalItems: items.length,
      criticalItems: items.where((i) => i.risk == WindowsItemRisk.critical).length,
      highRiskItems: items.where((i) => i.risk == WindowsItemRisk.high).length,
      mediumRiskItems: items.where((i) => i.risk == WindowsItemRisk.medium).length,
      items: items,
      errors: errors,
    );
  }

  /// Scan registry run keys
  Future<List<WindowsPersistenceItem>> _scanRegistryRunKeys() async {
    final items = <WindowsPersistenceItem>[];

    final runKeyPaths = [
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
      r'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
      r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
      r'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run',
    ];

    for (final keyPath in runKeyPaths) {
      try {
        final result = await Process.run('reg', ['query', keyPath], runInShell: true);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          for (final line in lines) {
            if (line.contains('REG_SZ') || line.contains('REG_EXPAND_SZ')) {
              final parts = line.trim().split(RegExp(r'\s{2,}'));
              if (parts.length >= 3) {
                final name = parts[0].trim();
                final command = parts.sublist(2).join(' ').trim();

                items.add(WindowsPersistenceItem(
                  id: 'reg_${name.hashCode}',
                  name: name,
                  path: keyPath,
                  command: command,
                  type: keyPath.contains('RunOnce')
                      ? WindowsPersistenceType.registryRunOnce
                      : WindowsPersistenceType.registryRunKey,
                  risk: _assessCommandRisk(command),
                  signingStatus: await _checkSigningStatus(_extractPathFromCommand(command)),
                ));
              }
            }
          }
        }
      } catch (e) {
        // Skip inaccessible keys
      }
    }

    return items;
  }

  /// Scan scheduled tasks
  Future<List<WindowsPersistenceItem>> _scanScheduledTasks() async {
    final items = <WindowsPersistenceItem>[];

    try {
      final result = await Process.run(
        'schtasks',
        ['/query', '/fo', 'csv', '/v'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        bool isHeader = true;

        for (final line in lines) {
          if (line.trim().isEmpty) continue;

          final values = _parseCSVLine(line);

          if (isHeader) {
            isHeader = false;
            continue;
          }

          if (values.length < 9) continue;

          final taskName = values[0].replaceAll('"', '');
          final taskPath = values.length > 8 ? values[8].replaceAll('"', '') : '';
          final status = values.length > 3 ? values[3].replaceAll('"', '') : '';

          // Skip Microsoft system tasks
          if (taskName.startsWith('\\Microsoft\\')) continue;

          items.add(WindowsPersistenceItem(
            id: 'task_${taskName.hashCode}',
            name: taskName.split('\\').last,
            path: taskName,
            command: taskPath,
            type: WindowsPersistenceType.scheduledTask,
            risk: _assessCommandRisk(taskPath),
            signingStatus: await _checkSigningStatus(_extractPathFromCommand(taskPath)),
            isEnabled: status.toLowerCase() == 'ready',
          ));
        }
      }
    } catch (e) {
      // Handle error
    }

    return items;
  }

  /// Scan Windows services
  Future<List<WindowsPersistenceItem>> _scanWindowsServices() async {
    final items = <WindowsPersistenceItem>[];

    try {
      final result = await Process.run(
        'wmic',
        ['service', 'get', 'Name,PathName,StartMode,State,Description', '/format:csv'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        bool isHeader = true;

        for (final line in lines) {
          if (line.trim().isEmpty) continue;

          final values = line.split(',');

          if (isHeader) {
            isHeader = false;
            continue;
          }

          if (values.length < 5) continue;

          final description = values.length > 1 ? values[1] : '';
          final name = values.length > 2 ? values[2] : '';
          final pathName = values.length > 3 ? values[3] : '';
          final startMode = values.length > 4 ? values[4] : '';
          final state = values.length > 5 ? values[5] : '';

          // Skip if no path
          if (pathName.isEmpty || name.isEmpty) continue;

          // Check if it's a system service
          final isSystemPath = pathName.toLowerCase().contains('\\windows\\') ||
              pathName.toLowerCase().contains('\\system32\\');

          items.add(WindowsPersistenceItem(
            id: 'svc_${name.hashCode}',
            name: name,
            path: pathName,
            command: pathName,
            type: WindowsPersistenceType.windowsService,
            risk: isSystemPath ? WindowsItemRisk.safe : _assessCommandRisk(pathName),
            signingStatus: await _checkSigningStatus(_extractPathFromCommand(pathName)),
            description: description,
            isEnabled: startMode.toLowerCase() != 'disabled',
            metadata: {'start_mode': startMode, 'state': state},
          ));
        }
      }
    } catch (e) {
      // Handle error
    }

    return items;
  }

  /// Scan startup folders
  Future<List<WindowsPersistenceItem>> _scanStartupFolders() async {
    final items = <WindowsPersistenceItem>[];

    final startupPaths = [
      Platform.environment['APPDATA'] != null
          ? '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs\\Startup'
          : null,
      'C:\\ProgramData\\Microsoft\\Windows\\Start Menu\\Programs\\Startup',
    ].whereType<String>();

    for (final folderPath in startupPaths) {
      try {
        final dir = Directory(folderPath);
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File) {
              final fileName = entity.path.split('\\').last;

              items.add(WindowsPersistenceItem(
                id: 'startup_${entity.path.hashCode}',
                name: fileName,
                path: entity.path,
                type: WindowsPersistenceType.startupFolder,
                risk: _assessFileRisk(fileName),
                signingStatus: await _checkSigningStatus(entity.path),
                createdAt: (await entity.stat()).changed,
                modifiedAt: (await entity.stat()).modified,
              ));
            }
          }
        }
      } catch (e) {
        // Skip inaccessible folders
      }
    }

    return items;
  }

  /// Scan WMI event subscriptions
  Future<List<WindowsPersistenceItem>> _scanWMISubscriptions() async {
    final items = <WindowsPersistenceItem>[];

    try {
      // Query event consumers
      final result = await Process.run(
        'wmic',
        ['/namespace:\\\\root\\subscription', 'path', '__EventConsumer', 'get', '/format:list'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        if (output.contains('CommandLineTemplate') || output.contains('ScriptText')) {
          items.add(WindowsPersistenceItem(
            id: 'wmi_${output.hashCode}',
            name: 'WMI Event Subscription',
            path: 'ROOT\\subscription',
            type: WindowsPersistenceType.wmiSubscription,
            risk: WindowsItemRisk.high,
            signingStatus: WindowsSigningStatus.unknown,
            indicators: ['WMI persistence detected - commonly used by malware'],
          ));
        }
      }
    } catch (e) {
      // Handle error
    }

    return items;
  }

  /// Scan browser extensions
  Future<List<WindowsPersistenceItem>> _scanBrowserExtensions() async {
    final items = <WindowsPersistenceItem>[];
    final userProfile = Platform.environment['USERPROFILE'] ?? '';

    // Chrome extensions
    final chromePath = '$userProfile\\AppData\\Local\\Google\\Chrome\\User Data\\Default\\Extensions';
    items.addAll(await _scanExtensionFolder(chromePath, 'Chrome'));

    // Firefox extensions
    final firefoxPath = '$userProfile\\AppData\\Roaming\\Mozilla\\Firefox\\Profiles';
    try {
      final firefoxDir = Directory(firefoxPath);
      if (await firefoxDir.exists()) {
        await for (final profile in firefoxDir.list()) {
          if (profile is Directory) {
            items.addAll(await _scanExtensionFolder(
              '${profile.path}\\extensions',
              'Firefox',
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    // Edge extensions
    final edgePath = '$userProfile\\AppData\\Local\\Microsoft\\Edge\\User Data\\Default\\Extensions';
    items.addAll(await _scanExtensionFolder(edgePath, 'Edge'));

    return items;
  }

  Future<List<WindowsPersistenceItem>> _scanExtensionFolder(String path, String browser) async {
    final items = <WindowsPersistenceItem>[];

    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await for (final ext in dir.list()) {
          if (ext is Directory) {
            final extId = ext.path.split('\\').last;
            String? extName;

            // Try to read manifest
            try {
              await for (final version in ext.list()) {
                if (version is Directory) {
                  final manifest = File('${version.path}\\manifest.json');
                  if (await manifest.exists()) {
                    final content = jsonDecode(await manifest.readAsString());
                    extName = content['name'] as String?;
                    break;
                  }
                }
              }
            } catch (e) {
              // Skip
            }

            items.add(WindowsPersistenceItem(
              id: 'ext_${extId.hashCode}',
              name: extName ?? extId,
              path: ext.path,
              type: WindowsPersistenceType.browserExtension,
              risk: WindowsItemRisk.low,
              signingStatus: WindowsSigningStatus.unknown,
              metadata: {'browser': browser, 'extension_id': extId},
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan COM objects for hijacking
  Future<List<WindowsPersistenceItem>> _scanCOMObjects() async {
    final items = <WindowsPersistenceItem>[];

    // Check common COM hijack locations
    final comPaths = [
      r'HKCU\SOFTWARE\Classes\CLSID',
      r'HKCU\SOFTWARE\Classes\Wow6432Node\CLSID',
    ];

    for (final keyPath in comPaths) {
      try {
        final result = await Process.run('reg', ['query', keyPath, '/s'], runInShell: true);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          // Look for InprocServer32 entries pointing to non-standard locations
          final matches = RegExp(r'InprocServer32.*\n.*REG_SZ\s+(.+)').allMatches(output);
          for (final match in matches) {
            final dllPath = match.group(1)?.trim() ?? '';
            if (dllPath.isNotEmpty &&
                !dllPath.toLowerCase().contains('\\windows\\') &&
                !dllPath.toLowerCase().contains('\\program files')) {
              items.add(WindowsPersistenceItem(
                id: 'com_${dllPath.hashCode}',
                name: dllPath.split('\\').last,
                path: dllPath,
                type: WindowsPersistenceType.comObject,
                risk: WindowsItemRisk.high,
                signingStatus: await _checkSigningStatus(dllPath),
                indicators: ['COM object in non-standard location'],
              ));
            }
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan Image File Execution Options
  Future<List<WindowsPersistenceItem>> _scanIFEO() async {
    final items = <WindowsPersistenceItem>[];

    try {
      final result = await Process.run(
        'reg',
        ['query', r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options', '/s'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final debuggerMatches = RegExp(r'\\([^\\]+)\n.*Debugger.*REG_SZ\s+(.+)').allMatches(output);

        for (final match in debuggerMatches) {
          final targetExe = match.group(1) ?? '';
          final debuggerPath = match.group(2)?.trim() ?? '';

          if (debuggerPath.isNotEmpty && !_microsoftBinaries.contains(debuggerPath.split('\\').last.toLowerCase())) {
            items.add(WindowsPersistenceItem(
              id: 'ifeo_${targetExe.hashCode}',
              name: 'IFEO: $targetExe',
              path: debuggerPath,
              command: debuggerPath,
              type: WindowsPersistenceType.imageFileExecution,
              risk: WindowsItemRisk.critical,
              signingStatus: await _checkSigningStatus(debuggerPath),
              indicators: ['Image File Execution Options hijacking detected'],
              metadata: {'target': targetExe},
            ));
          }
        }
      }
    } catch (e) {
      // Handle error
    }

    return items;
  }

  /// Assess risk level of a command
  WindowsItemRisk _assessCommandRisk(String command) {
    final lowerCommand = command.toLowerCase();

    // Check for known malware patterns
    for (final keyword in _suspiciousKeywords) {
      if (lowerCommand.contains(keyword.toLowerCase())) {
        return WindowsItemRisk.critical;
      }
    }

    // Check for scripts
    if (lowerCommand.endsWith('.vbs') ||
        lowerCommand.endsWith('.js') ||
        lowerCommand.endsWith('.ps1')) {
      return WindowsItemRisk.high;
    }

    // Check for temp/appdata locations
    if (lowerCommand.contains('\\temp\\') ||
        lowerCommand.contains('\\appdata\\local\\temp')) {
      return WindowsItemRisk.high;
    }

    // Check for program files (usually safe)
    if (lowerCommand.contains('\\program files') ||
        lowerCommand.contains('\\windows\\')) {
      return WindowsItemRisk.safe;
    }

    return WindowsItemRisk.medium;
  }

  /// Assess risk level of a file
  WindowsItemRisk _assessFileRisk(String fileName) {
    final lowerName = fileName.toLowerCase();

    if (lowerName.endsWith('.lnk')) return WindowsItemRisk.low;
    if (lowerName.endsWith('.exe')) return WindowsItemRisk.medium;
    if (lowerName.endsWith('.bat') || lowerName.endsWith('.cmd')) return WindowsItemRisk.high;
    if (lowerName.endsWith('.vbs') || lowerName.endsWith('.js')) return WindowsItemRisk.high;

    return WindowsItemRisk.low;
  }

  /// Check digital signature status
  Future<WindowsSigningStatus> _checkSigningStatus(String? filePath) async {
    if (filePath == null || filePath.isEmpty) {
      return WindowsSigningStatus.unknown;
    }

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return WindowsSigningStatus.unknown;
      }

      final result = await Process.run(
        'powershell',
        ['-Command', 'Get-AuthenticodeSignature "$filePath" | Select-Object -ExpandProperty Status'],
        runInShell: true,
      );

      final status = (result.stdout as String).trim().toLowerCase();

      if (status == 'valid') {
        // Check if Microsoft signed
        final publisherResult = await Process.run(
          'powershell',
          ['-Command', '(Get-AuthenticodeSignature "$filePath").SignerCertificate.Subject'],
          runInShell: true,
        );
        final publisher = (publisherResult.stdout as String).toLowerCase();

        if (publisher.contains('microsoft')) {
          return WindowsSigningStatus.microsoftSigned;
        }
        return WindowsSigningStatus.trustedPublisher;
      } else if (status == 'notsigned') {
        return WindowsSigningStatus.unsigned;
      } else if (status == 'hasherror' || status == 'invalid') {
        return WindowsSigningStatus.invalidSignature;
      }
    } catch (e) {
      // Fall through to unknown
    }

    return WindowsSigningStatus.unknown;
  }

  /// Extract file path from command string
  String? _extractPathFromCommand(String command) {
    // Handle quoted paths
    final quotedMatch = RegExp(r'"([^"]+\.exe)"').firstMatch(command);
    if (quotedMatch != null) return quotedMatch.group(1);

    // Handle unquoted paths
    final unquotedMatch = RegExp(r'([A-Za-z]:\\[^\s]+\.exe)').firstMatch(command);
    if (unquotedMatch != null) return unquotedMatch.group(1);

    return null;
  }

  /// Parse CSV line handling quoted values
  List<String> _parseCSVLine(String line) {
    final values = <String>[];
    var current = '';
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        values.add(current);
        current = '';
      } else {
        current += char;
      }
    }
    values.add(current);

    return values;
  }

  /// Scan Winlogon helper DLLs
  Future<List<WindowsPersistenceItem>> _scanWinlogon() async {
    final items = <WindowsPersistenceItem>[];

    final winlogonKeys = [
      r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
      r'HKCU\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon',
    ];

    final valuesOfInterest = ['Shell', 'Userinit', 'Taskman', 'AppSetup'];

    for (final keyPath in winlogonKeys) {
      try {
        final result = await Process.run('reg', ['query', keyPath], runInShell: true);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          for (final line in lines) {
            for (final valueName in valuesOfInterest) {
              if (line.contains(valueName) && (line.contains('REG_SZ') || line.contains('REG_EXPAND_SZ'))) {
                final parts = line.trim().split(RegExp(r'\s{2,}'));
                if (parts.length >= 3) {
                  final value = parts.sublist(2).join(' ').trim();

                  // Default values are safe
                  final isDefault = (valueName == 'Shell' && value.toLowerCase() == 'explorer.exe') ||
                      (valueName == 'Userinit' && value.toLowerCase().contains('userinit.exe'));

                  if (!isDefault || value.contains(',')) {
                    items.add(WindowsPersistenceItem(
                      id: 'winlogon_${valueName.hashCode}',
                      name: 'Winlogon $valueName',
                      path: keyPath,
                      command: value,
                      type: WindowsPersistenceType.winlogon,
                      risk: isDefault ? WindowsItemRisk.safe : WindowsItemRisk.high,
                      signingStatus: await _checkSigningStatus(_extractPathFromCommand(value)),
                      indicators: isDefault ? [] : ['Non-default Winlogon value'],
                    ));
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan AppInit DLLs
  Future<List<WindowsPersistenceItem>> _scanAppInitDlls() async {
    final items = <WindowsPersistenceItem>[];

    final appInitKeys = [
      r'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows',
      r'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows',
    ];

    for (final keyPath in appInitKeys) {
      try {
        final result = await Process.run('reg', ['query', keyPath, '/v', 'AppInit_DLLs'], runInShell: true);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final match = RegExp(r'AppInit_DLLs\s+REG_SZ\s+(.+)').firstMatch(output);
          if (match != null) {
            final dllPath = match.group(1)?.trim() ?? '';
            if (dllPath.isNotEmpty) {
              items.add(WindowsPersistenceItem(
                id: 'appinit_${dllPath.hashCode}',
                name: 'AppInit DLL',
                path: dllPath,
                command: dllPath,
                type: WindowsPersistenceType.appInitDll,
                risk: WindowsItemRisk.critical,
                signingStatus: await _checkSigningStatus(dllPath),
                indicators: ['AppInit_DLLs is a common malware persistence mechanism'],
              ));
            }
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan Print Monitors
  Future<List<WindowsPersistenceItem>> _scanPrintMonitors() async {
    final items = <WindowsPersistenceItem>[];

    try {
      final result = await Process.run(
        'reg',
        ['query', r'HKLM\SYSTEM\CurrentControlSet\Control\Print\Monitors', '/s'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final matches = RegExp(r'Driver\s+REG_SZ\s+(.+\.dll)', caseSensitive: false).allMatches(output);

        for (final match in matches) {
          final dllName = match.group(1)?.trim() ?? '';
          if (dllName.isNotEmpty) {
            // Check if it's in system32
            final isSystem = dllName.toLowerCase().contains('localspl.dll') ||
                dllName.toLowerCase().contains('win32spl.dll') ||
                dllName.toLowerCase().contains('usbmon.dll');

            items.add(WindowsPersistenceItem(
              id: 'printmon_${dllName.hashCode}',
              name: 'Print Monitor: $dllName',
              path: r'C:\Windows\System32\' + dllName,
              type: WindowsPersistenceType.printMonitor,
              risk: isSystem ? WindowsItemRisk.safe : WindowsItemRisk.high,
              signingStatus: WindowsSigningStatus.unknown,
              indicators: isSystem ? [] : ['Non-standard print monitor DLL'],
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan LSA Security Packages
  Future<List<WindowsPersistenceItem>> _scanLSAPackages() async {
    final items = <WindowsPersistenceItem>[];

    final lsaKeys = [
      (r'HKLM\SYSTEM\CurrentControlSet\Control\Lsa', 'Security Packages'),
      (r'HKLM\SYSTEM\CurrentControlSet\Control\Lsa', 'Authentication Packages'),
      (r'HKLM\SYSTEM\CurrentControlSet\Control\Lsa\OSConfig', 'Security Packages'),
    ];

    final knownPackages = {'kerberos', 'msv1_0', 'schannel', 'wdigest', 'tspkg', 'pku2u', 'livessp', 'cloudap', ''};

    for (final (keyPath, valueName) in lsaKeys) {
      try {
        final result = await Process.run('reg', ['query', keyPath, '/v', valueName], runInShell: true);
        if (result.exitCode == 0) {
          final output = result.stdout as String;
          final match = RegExp(r'REG_MULTI_SZ\s+(.+)', dotAll: true).firstMatch(output);
          if (match != null) {
            final packages = match.group(1)?.trim().split(RegExp(r'[\r\n\s\\0]+')) ?? [];
            for (final pkg in packages) {
              final pkgName = pkg.trim().toLowerCase();
              if (pkgName.isEmpty) continue;

              final isKnown = knownPackages.contains(pkgName);

              if (!isKnown) {
                items.add(WindowsPersistenceItem(
                  id: 'lsa_${pkgName.hashCode}',
                  name: 'LSA Package: $pkg',
                  path: keyPath,
                  type: WindowsPersistenceType.lsaPackage,
                  risk: WindowsItemRisk.critical,
                  signingStatus: WindowsSigningStatus.unknown,
                  indicators: ['Unknown LSA security package - possible credential theft'],
                ));
              }
            }
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan Boot Execute entries
  Future<List<WindowsPersistenceItem>> _scanBootExecute() async {
    final items = <WindowsPersistenceItem>[];

    try {
      final result = await Process.run(
        'reg',
        ['query', r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager', '/v', 'BootExecute'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final match = RegExp(r'REG_MULTI_SZ\s+(.+)', dotAll: true).firstMatch(output);
        if (match != null) {
          final entries = match.group(1)?.trim().split(RegExp(r'[\r\n\\0]+')) ?? [];
          for (final entry in entries) {
            final trimmed = entry.trim();
            if (trimmed.isEmpty) continue;

            // Default is "autocheck autochk *"
            final isDefault = trimmed.toLowerCase() == 'autocheck autochk *';

            items.add(WindowsPersistenceItem(
              id: 'bootexec_${trimmed.hashCode}',
              name: 'Boot Execute',
              path: r'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager',
              command: trimmed,
              type: WindowsPersistenceType.bootExecute,
              risk: isDefault ? WindowsItemRisk.safe : WindowsItemRisk.critical,
              signingStatus: WindowsSigningStatus.unknown,
              indicators: isDefault ? [] : ['Non-default boot execute entry'],
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan Netsh Helper DLLs
  Future<List<WindowsPersistenceItem>> _scanNetshHelpers() async {
    final items = <WindowsPersistenceItem>[];

    try {
      final result = await Process.run(
        'reg',
        ['query', r'HKLM\SOFTWARE\Microsoft\NetSh', '/s'],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = result.stdout as String;
        final matches = RegExp(r'\(Default\)\s+REG_SZ\s+(.+\.dll)', caseSensitive: false).allMatches(output);

        for (final match in matches) {
          final dllPath = match.group(1)?.trim() ?? '';
          if (dllPath.isNotEmpty) {
            // Known system helpers
            final isSystem = dllPath.toLowerCase().contains('\\windows\\') &&
                (dllPath.toLowerCase().contains('netsh') ||
                    dllPath.toLowerCase().contains('dhcpcmonitor') ||
                    dllPath.toLowerCase().contains('ifmon') ||
                    dllPath.toLowerCase().contains('rasmontr'));

            items.add(WindowsPersistenceItem(
              id: 'netsh_${dllPath.hashCode}',
              name: 'Netsh Helper: ${dllPath.split('\\').last}',
              path: dllPath,
              type: WindowsPersistenceType.netshHelper,
              risk: isSystem ? WindowsItemRisk.safe : WindowsItemRisk.high,
              signingStatus: await _checkSigningStatus(dllPath),
              indicators: isSystem ? [] : ['Non-standard Netsh helper DLL'],
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Compute SHA256 hashes for suspicious items
  Future<void> _computeHashes(List<WindowsPersistenceItem> items) async {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      // Only compute hashes for high-risk items to save time
      if (item.risk.index < WindowsItemRisk.medium.index) continue;

      // Get the file path to hash
      String? pathToHash = _extractPathFromCommand(item.command ?? item.path);
      if (pathToHash == null) continue;

      try {
        final result = await Process.run(
          'powershell',
          ['-Command', 'Get-FileHash "$pathToHash" -Algorithm SHA256 | Select-Object -ExpandProperty Hash'],
          runInShell: true,
        );

        if (result.exitCode == 0) {
          final hash = (result.stdout as String).trim();
          if (hash.isNotEmpty && hash.length == 64) {
            // Check against known malware hashes
            final isKnownMalware = _knownMalwareHashes.contains(hash.toLowerCase());

            // Create new item with hash
            items[i] = WindowsPersistenceItem(
              id: item.id,
              name: item.name,
              path: item.path,
              command: item.command,
              type: item.type,
              risk: isKnownMalware ? WindowsItemRisk.critical : item.risk,
              signingStatus: item.signingStatus,
              publisher: item.publisher,
              description: item.description,
              hash: hash,
              createdAt: item.createdAt,
              modifiedAt: item.modifiedAt,
              isEnabled: item.isEnabled,
              isHidden: item.isHidden,
              indicators: isKnownMalware
                  ? [...item.indicators, 'Hash matches known malware']
                  : item.indicators,
              metadata: item.metadata,
            );
          }
        }
      } catch (e) {
        // Skip hash computation on error
      }
    }
  }

  /// Export scan results to JSON
  String exportToJson(WindowsScanResult result) {
    return jsonEncode(result.toJson());
  }
}
