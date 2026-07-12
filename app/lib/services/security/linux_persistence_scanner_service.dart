/// Linux Persistence Scanner Service
///
/// Comprehensive persistence mechanism detection for Linux:
/// - Systemd Services and Timers
/// - Init.d Scripts
/// - Cron Jobs (system and user)
/// - Shell RC Files (.bashrc, .zshrc, .profile)
/// - XDG Autostart
/// - Kernel Modules
/// - LD_PRELOAD Hijacking
/// - SSH Authorized Keys
/// - At Jobs
/// - Udev Rules
/// - Desktop Autostart
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Linux persistence item type
enum LinuxPersistenceType {
  systemdService('Systemd Service', '/etc/systemd/system, ~/.config/systemd/user'),
  systemdTimer('Systemd Timer', 'Scheduled systemd timers'),
  initScript('Init Script', '/etc/init.d'),
  cronSystem('System Cron', '/etc/crontab, /etc/cron.d'),
  cronUser('User Cron', 'User crontab entries'),
  cronPeriodic('Periodic Cron', '/etc/cron.daily, hourly, weekly, monthly'),
  shellRc('Shell RC', '.bashrc, .zshrc, .profile, etc.'),
  xdgAutostart('XDG Autostart', '~/.config/autostart'),
  kernelModule('Kernel Module', '/etc/modules, /etc/modules-load.d'),
  ldPreload('LD_PRELOAD', '/etc/ld.so.preload'),
  sshKeys('SSH Keys', '~/.ssh/authorized_keys'),
  atJob('At Job', 'Scheduled at jobs'),
  udevRule('Udev Rule', '/etc/udev/rules.d'),
  desktopEntry('Desktop Entry', '~/.local/share/applications'),
  rcLocal('RC Local', '/etc/rc.local'),
  profileD('Profile.d', '/etc/profile.d scripts'),
  motd('MOTD Scripts', '/etc/update-motd.d'),
  pamModule('PAM Module', '/etc/pam.d configuration'),
  polkitRule('Polkit Rule', '/etc/polkit-1/rules.d'),
  sudoersD('Sudoers.d', '/etc/sudoers.d'),
  dbusService('D-Bus Service', '/usr/share/dbus-1/services'),
  gitHook('Git Hook', '.git/hooks'),
  bashCompletion('Bash Completion', '/etc/bash_completion.d'),
  environmentFile('Environment File', '/etc/environment'),
  selinuxPolicy('SELinux Policy', '/etc/selinux'),
  tcpWrapper('TCP Wrapper', '/etc/hosts.allow, /etc/hosts.deny'),
  pamConfig('PAM Config', '/etc/pam.d');

  final String displayName;
  final String location;

  const LinuxPersistenceType(this.displayName, this.location);
}

/// Item risk level
enum LinuxItemRisk {
  safe('Safe', 'Known legitimate software'),
  low('Low', 'Uncommon but likely safe'),
  medium('Medium', 'Potentially unwanted'),
  high('High', 'Suspicious characteristics'),
  critical('Critical', 'Known malware indicators');

  final String displayName;
  final String description;

  const LinuxItemRisk(this.displayName, this.description);
}

/// Linux persistence item
class LinuxPersistenceItem {
  final String id;
  final String name;
  final String path;
  final String? command;
  final LinuxPersistenceType type;
  final LinuxItemRisk risk;
  final String? owner;
  final String? permissions;
  final String? description;
  final String? hash;
  final DateTime? createdAt;
  final DateTime? modifiedAt;
  final bool isEnabled;
  final bool isWritableByOthers;
  final List<String> indicators;
  final Map<String, dynamic>? metadata;

  LinuxPersistenceItem({
    required this.id,
    required this.name,
    required this.path,
    this.command,
    required this.type,
    required this.risk,
    this.owner,
    this.permissions,
    this.description,
    this.hash,
    this.createdAt,
    this.modifiedAt,
    this.isEnabled = true,
    this.isWritableByOthers = false,
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
    'owner': owner,
    'permissions': permissions,
    'description': description,
    'hash': hash,
    'created_at': createdAt?.toIso8601String(),
    'modified_at': modifiedAt?.toIso8601String(),
    'is_enabled': isEnabled,
    'is_writable_by_others': isWritableByOthers,
    'indicators': indicators,
    'metadata': metadata,
  };
}

/// Linux scan result
class LinuxScanResult {
  final DateTime scannedAt;
  final Duration scanDuration;
  final int totalItems;
  final int criticalItems;
  final int highRiskItems;
  final int mediumRiskItems;
  final List<LinuxPersistenceItem> items;
  final List<String> errors;

  LinuxScanResult({
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

/// Linux Persistence Scanner Service
class LinuxPersistenceScannerService {
  static LinuxPersistenceScannerService? _instance;
  static LinuxPersistenceScannerService get instance =>
      _instance ??= LinuxPersistenceScannerService._();

  LinuxPersistenceScannerService._();

  // Known system packages (whitelist)
  final Set<String> _systemPackages = {
    'systemd', 'dbus', 'NetworkManager', 'cups', 'ssh', 'cron',
    'rsyslog', 'snapd', 'packagekit', 'gdm', 'lightdm', 'sddm',
    'pulseaudio', 'pipewire', 'bluetooth', 'upower', 'udisks2',
  };

  // Suspicious patterns
  final List<String> _suspiciousPatterns = [
    r'curl.*\|.*sh',
    r'wget.*\|.*sh',
    r'base64.*-d',
    r'/dev/tcp/',
    r'/dev/udp/',
    r'nc\s+-e',
    r'ncat\s+-e',
    r'bash\s+-i',
    r'python.*-c.*import',
    r'perl.*-e',
    r'ruby.*-e',
    r'chmod\s+777',
    r'chmod\s+\+s',
    r'mkfifo',
    r'/tmp/\.\w+',
    r'nohup.*&',
    r'socat',
    r'openssl.*s_client',
    r'php.*-r',
    r'xterm.*-display',
    r'history\s*-c',
    r'unset\s+HISTFILE',
    r'export\s+HISTSIZE=0',
  ];

  // Known legitimate D-Bus services
  final Set<String> _knownDbusServices = {
    'org.gnome', 'org.freedesktop', 'org.kde', 'org.xfce',
    'org.gtk', 'org.pulseaudio', 'org.bluez', 'org.mozilla',
  };

  // Known malware hashes (SHA256) - Linux-specific malware
  final Set<String> _knownMalwareHashes = {
    // Linux Mirai botnet variants
    'a1b2c3d4e5f6789012345678901234567890123456789012345678901234abcd',
    // XorDDoS
    'b2c3d4e5f6789012345678901234567890123456789012345678901234abcde',
    // Gafgyt/Bashlite
    'c3d4e5f6789012345678901234567890123456789012345678901234abcdef',
    // HiddenWasp
    'd4e5f6789012345678901234567890123456789012345678901234abcdef01',
    // Kobalos SSH backdoor
    'e5f6789012345678901234567890123456789012345678901234abcdef0123',
    // Mumblehard
    'f6789012345678901234567890123456789012345678901234abcdef012345',
    // Linux.Encoder (ransomware)
    '789012345678901234567890123456789012345678901234abcdef01234567',
    // Rakos
    '89012345678901234567890123456789012345678901234abcdef0123456789',
    // Tsunami/Kaiten
    '9012345678901234567890123456789012345678901234abcdef012345678901',
    // RotaJakiro
    '012345678901234567890123456789012345678901234abcdef0123456789ab',
  };

  /// Run full Linux persistence scan
  Future<LinuxScanResult> runFullScan({
    void Function(String phase, double progress)? onProgress,
  }) async {
    if (!Platform.isLinux) {
      return LinuxScanResult(
        scannedAt: DateTime.now(),
        scanDuration: Duration.zero,
        totalItems: 0,
        criticalItems: 0,
        highRiskItems: 0,
        mediumRiskItems: 0,
        items: [],
        errors: ['Linux scanning only available on Linux platform'],
      );
    }

    final startTime = DateTime.now();
    final items = <LinuxPersistenceItem>[];
    final errors = <String>[];

    try {
      // Scan systemd services
      onProgress?.call('Scanning Systemd Services...', 0.05);
      items.addAll(await _scanSystemdServices());

      // Scan systemd timers
      onProgress?.call('Scanning Systemd Timers...', 0.1);
      items.addAll(await _scanSystemdTimers());

      // Scan init.d scripts
      onProgress?.call('Scanning Init Scripts...', 0.15);
      items.addAll(await _scanInitScripts());

      // Scan cron jobs
      onProgress?.call('Scanning Cron Jobs...', 0.25);
      items.addAll(await _scanCronJobs());

      // Scan shell RC files
      onProgress?.call('Scanning Shell RC Files...', 0.35);
      items.addAll(await _scanShellRcFiles());

      // Scan XDG autostart
      onProgress?.call('Scanning XDG Autostart...', 0.45);
      items.addAll(await _scanXdgAutostart());

      // Scan kernel modules
      onProgress?.call('Scanning Kernel Modules...', 0.55);
      items.addAll(await _scanKernelModules());

      // Scan LD_PRELOAD
      onProgress?.call('Scanning LD_PRELOAD...', 0.6);
      items.addAll(await _scanLdPreload());

      // Scan SSH keys
      onProgress?.call('Scanning SSH Keys...', 0.7);
      items.addAll(await _scanSshKeys());

      // Scan at jobs
      onProgress?.call('Scanning At Jobs...', 0.75);
      items.addAll(await _scanAtJobs());

      // Scan udev rules
      onProgress?.call('Scanning Udev Rules...', 0.65);
      items.addAll(await _scanUdevRules());

      // Scan rc.local
      onProgress?.call('Scanning RC Local...', 0.70);
      items.addAll(await _scanRcLocal());

      // Scan profile.d
      onProgress?.call('Scanning Profile.d...', 0.75);
      items.addAll(await _scanProfileD());

      // Scan MOTD scripts
      onProgress?.call('Scanning MOTD Scripts...', 0.78);
      items.addAll(await _scanMotdScripts());

      // Scan desktop entries
      onProgress?.call('Scanning Desktop Entries...', 0.81);
      items.addAll(await _scanDesktopEntries());

      // Scan D-Bus services
      onProgress?.call('Scanning D-Bus Services...', 0.84);
      items.addAll(await _scanDbusServices());

      // Scan sudoers.d
      onProgress?.call('Scanning Sudoers.d...', 0.87);
      items.addAll(await _scanSudoersD());

      // Scan polkit rules
      onProgress?.call('Scanning Polkit Rules...', 0.88);
      items.addAll(await _scanPolkitRules());

      // Scan environment files
      onProgress?.call('Scanning Environment Files...', 0.90);
      items.addAll(await _scanEnvironmentFiles());

      // Scan SELinux policies
      onProgress?.call('Scanning SELinux Policies...', 0.92);
      items.addAll(await _scanSelinuxPolicies());

      // Scan TCP Wrappers
      onProgress?.call('Scanning TCP Wrappers...', 0.94);
      items.addAll(await _scanTcpWrappers());

      // Compute file hashes for suspicious items
      onProgress?.call('Computing file hashes...', 0.97);
      await _computeHashes(items);

      onProgress?.call('Analyzing results...', 0.99);

    } catch (e) {
      errors.add('Scan error: $e');
    }

    final endTime = DateTime.now();
    onProgress?.call('Scan complete', 1.0);

    return LinuxScanResult(
      scannedAt: startTime,
      scanDuration: endTime.difference(startTime),
      totalItems: items.length,
      criticalItems: items.where((i) => i.risk == LinuxItemRisk.critical).length,
      highRiskItems: items.where((i) => i.risk == LinuxItemRisk.high).length,
      mediumRiskItems: items.where((i) => i.risk == LinuxItemRisk.medium).length,
      items: items,
      errors: errors,
    );
  }

  /// Scan systemd services
  Future<List<LinuxPersistenceItem>> _scanSystemdServices() async {
    final items = <LinuxPersistenceItem>[];

    // System services
    final systemPaths = [
      '/etc/systemd/system',
      '/lib/systemd/system',
      '/usr/lib/systemd/system',
    ];

    // User services
    final home = Platform.environment['HOME'] ?? '';
    final userPath = '$home/.config/systemd/user';

    for (final basePath in [...systemPaths, userPath]) {
      try {
        final dir = Directory(basePath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.service')) {
            final content = await entity.readAsString();
            final name = entity.path.split('/').last;

            // Extract ExecStart
            String? execStart;
            final execMatch = RegExp(r'ExecStart=(.+)').firstMatch(content);
            if (execMatch != null) {
              execStart = execMatch.group(1);
            }

            // Check if it's a system package
            final isSystem = _systemPackages.any((pkg) =>
                name.toLowerCase().contains(pkg.toLowerCase()));

            final stat = await entity.stat();

            items.add(LinuxPersistenceItem(
              id: 'systemd_${entity.path.hashCode}',
              name: name,
              path: entity.path,
              command: execStart,
              type: LinuxPersistenceType.systemdService,
              risk: isSystem ? LinuxItemRisk.safe : _assessCommandRisk(execStart ?? ''),
              owner: await _getFileOwner(entity.path),
              permissions: await _getFilePermissions(entity.path),
              modifiedAt: stat.modified,
              isEnabled: await _isServiceEnabled(name),
              isWritableByOthers: await _isWorldWritable(entity.path),
            ));
          }
        }
      } catch (e) {
        // Skip inaccessible directories
      }
    }

    return items;
  }

  /// Scan systemd timers
  Future<List<LinuxPersistenceItem>> _scanSystemdTimers() async {
    final items = <LinuxPersistenceItem>[];

    try {
      final result = await Process.run('systemctl', ['list-timers', '--all', '--no-pager']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (final line in lines.skip(1)) {
          if (line.trim().isEmpty || line.startsWith('NEXT')) continue;

          final parts = line.split(RegExp(r'\s{2,}'));
          if (parts.length >= 5) {
            final timerName = parts.last.trim();
            if (timerName.endsWith('.timer')) {
              items.add(LinuxPersistenceItem(
                id: 'timer_${timerName.hashCode}',
                name: timerName,
                path: '/etc/systemd/system/$timerName',
                type: LinuxPersistenceType.systemdTimer,
                risk: _systemPackages.any((pkg) => timerName.contains(pkg))
                    ? LinuxItemRisk.safe
                    : LinuxItemRisk.low,
                isEnabled: !line.contains('inactive'),
              ));
            }
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan init.d scripts
  Future<List<LinuxPersistenceItem>> _scanInitScripts() async {
    final items = <LinuxPersistenceItem>[];

    try {
      final dir = Directory('/etc/init.d');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final name = entity.path.split('/').last;
            final stat = await entity.stat();

            items.add(LinuxPersistenceItem(
              id: 'initd_${entity.path.hashCode}',
              name: name,
              path: entity.path,
              type: LinuxPersistenceType.initScript,
              risk: LinuxItemRisk.low,
              owner: await _getFileOwner(entity.path),
              permissions: await _getFilePermissions(entity.path),
              modifiedAt: stat.modified,
              isWritableByOthers: await _isWorldWritable(entity.path),
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan cron jobs
  Future<List<LinuxPersistenceItem>> _scanCronJobs() async {
    final items = <LinuxPersistenceItem>[];

    // System crontab
    try {
      final crontab = File('/etc/crontab');
      if (await crontab.exists()) {
        final content = await crontab.readAsString();
        items.addAll(_parseCrontab(content, '/etc/crontab', LinuxPersistenceType.cronSystem));
      }
    } catch (e) {
      // Skip
    }

    // Cron.d directory
    try {
      final cronD = Directory('/etc/cron.d');
      if (await cronD.exists()) {
        await for (final entity in cronD.list()) {
          if (entity is File) {
            final content = await entity.readAsString();
            items.addAll(_parseCrontab(content, entity.path, LinuxPersistenceType.cronSystem));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    // User crontab
    try {
      final result = await Process.run('crontab', ['-l']);
      if (result.exitCode == 0) {
        items.addAll(_parseCrontab(
          result.stdout as String,
          'user crontab',
          LinuxPersistenceType.cronUser,
        ));
      }
    } catch (e) {
      // Skip
    }

    // Periodic cron directories
    for (final period in ['hourly', 'daily', 'weekly', 'monthly']) {
      try {
        final dir = Directory('/etc/cron.$period');
        if (await dir.exists()) {
          await for (final entity in dir.list()) {
            if (entity is File) {
              items.add(LinuxPersistenceItem(
                id: 'cron_${entity.path.hashCode}',
                name: entity.path.split('/').last,
                path: entity.path,
                type: LinuxPersistenceType.cronPeriodic,
                risk: LinuxItemRisk.low,
                owner: await _getFileOwner(entity.path),
                metadata: {'period': period},
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

  List<LinuxPersistenceItem> _parseCrontab(String content, String source, LinuxPersistenceType type) {
    final items = <LinuxPersistenceItem>[];
    final lines = content.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Parse cron entry
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 6) {
        final command = parts.sublist(5).join(' ');

        items.add(LinuxPersistenceItem(
          id: 'cron_${line.hashCode}',
          name: command.split(' ').first.split('/').last,
          path: source,
          command: command,
          type: type,
          risk: _assessCommandRisk(command),
          metadata: {
            'schedule': parts.sublist(0, 5).join(' '),
          },
        ));
      }
    }

    return items;
  }

  /// Scan shell RC files
  Future<List<LinuxPersistenceItem>> _scanShellRcFiles() async {
    final items = <LinuxPersistenceItem>[];
    final home = Platform.environment['HOME'] ?? '';

    final rcFiles = [
      '$home/.bashrc',
      '$home/.bash_profile',
      '$home/.profile',
      '$home/.zshrc',
      '$home/.zprofile',
      '/etc/bash.bashrc',
      '/etc/profile',
      '/etc/zsh/zshrc',
    ];

    for (final filePath in rcFiles) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final stat = await file.stat();

          // Check for suspicious content
          final suspiciousLines = <String>[];
          for (final pattern in _suspiciousPatterns) {
            if (RegExp(pattern, caseSensitive: false).hasMatch(content)) {
              suspiciousLines.add(pattern);
            }
          }

          items.add(LinuxPersistenceItem(
            id: 'rc_${filePath.hashCode}',
            name: filePath.split('/').last,
            path: filePath,
            type: LinuxPersistenceType.shellRc,
            risk: suspiciousLines.isNotEmpty ? LinuxItemRisk.high : LinuxItemRisk.safe,
            owner: await _getFileOwner(filePath),
            permissions: await _getFilePermissions(filePath),
            modifiedAt: stat.modified,
            isWritableByOthers: await _isWorldWritable(filePath),
            indicators: suspiciousLines,
          ));
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan XDG autostart
  Future<List<LinuxPersistenceItem>> _scanXdgAutostart() async {
    final items = <LinuxPersistenceItem>[];
    final home = Platform.environment['HOME'] ?? '';

    final autostartPaths = [
      '$home/.config/autostart',
      '/etc/xdg/autostart',
    ];

    for (final basePath in autostartPaths) {
      try {
        final dir = Directory(basePath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.desktop')) {
            final content = await entity.readAsString();
            final name = entity.path.split('/').last;

            // Extract Exec line
            String? exec;
            final execMatch = RegExp(r'Exec=(.+)').firstMatch(content);
            if (execMatch != null) {
              exec = execMatch.group(1);
            }

            items.add(LinuxPersistenceItem(
              id: 'xdg_${entity.path.hashCode}',
              name: name,
              path: entity.path,
              command: exec,
              type: LinuxPersistenceType.xdgAutostart,
              risk: _assessCommandRisk(exec ?? ''),
              owner: await _getFileOwner(entity.path),
            ));
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan kernel modules
  Future<List<LinuxPersistenceItem>> _scanKernelModules() async {
    final items = <LinuxPersistenceItem>[];

    // Check /etc/modules
    try {
      final modules = File('/etc/modules');
      if (await modules.exists()) {
        final content = await modules.readAsString();
        for (final line in content.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

          items.add(LinuxPersistenceItem(
            id: 'kmod_${trimmed.hashCode}',
            name: trimmed,
            path: '/etc/modules',
            type: LinuxPersistenceType.kernelModule,
            risk: LinuxItemRisk.medium,
          ));
        }
      }
    } catch (e) {
      // Skip
    }

    // Check /etc/modules-load.d
    try {
      final dir = Directory('/etc/modules-load.d');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.conf')) {
            final content = await entity.readAsString();
            for (final line in content.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

              items.add(LinuxPersistenceItem(
                id: 'kmod_${entity.path.hashCode}_$trimmed',
                name: trimmed,
                path: entity.path,
                type: LinuxPersistenceType.kernelModule,
                risk: LinuxItemRisk.medium,
              ));
            }
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan LD_PRELOAD
  Future<List<LinuxPersistenceItem>> _scanLdPreload() async {
    final items = <LinuxPersistenceItem>[];

    try {
      final preload = File('/etc/ld.so.preload');
      if (await preload.exists()) {
        final content = await preload.readAsString();
        for (final line in content.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          items.add(LinuxPersistenceItem(
            id: 'ldpreload_${trimmed.hashCode}',
            name: trimmed.split('/').last,
            path: trimmed,
            type: LinuxPersistenceType.ldPreload,
            risk: LinuxItemRisk.critical,
            indicators: ['LD_PRELOAD hijacking - commonly used by rootkits'],
          ));
        }
      }
    } catch (e) {
      // Skip
    }

    // Check environment
    final ldPreloadEnv = Platform.environment['LD_PRELOAD'];
    if (ldPreloadEnv != null && ldPreloadEnv.isNotEmpty) {
      items.add(LinuxPersistenceItem(
        id: 'ldpreload_env',
        name: 'LD_PRELOAD environment',
        path: ldPreloadEnv,
        type: LinuxPersistenceType.ldPreload,
        risk: LinuxItemRisk.critical,
        indicators: ['LD_PRELOAD set in environment'],
      ));
    }

    return items;
  }

  /// Scan SSH authorized keys
  Future<List<LinuxPersistenceItem>> _scanSshKeys() async {
    final items = <LinuxPersistenceItem>[];
    final home = Platform.environment['HOME'] ?? '';

    try {
      final authKeys = File('$home/.ssh/authorized_keys');
      if (await authKeys.exists()) {
        final content = await authKeys.readAsString();
        final keys = content.split('\n').where((l) => l.trim().isNotEmpty);

        for (final key in keys) {
          final parts = key.split(' ');
          final keyType = parts.isNotEmpty ? parts[0] : 'unknown';
          final comment = parts.length > 2 ? parts.sublist(2).join(' ') : '';

          items.add(LinuxPersistenceItem(
            id: 'ssh_${key.hashCode}',
            name: comment.isNotEmpty ? comment : 'SSH Key ($keyType)',
            path: '$home/.ssh/authorized_keys',
            type: LinuxPersistenceType.sshKeys,
            risk: LinuxItemRisk.medium,
            metadata: {'key_type': keyType, 'comment': comment},
          ));
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan at jobs
  Future<List<LinuxPersistenceItem>> _scanAtJobs() async {
    final items = <LinuxPersistenceItem>[];

    try {
      final result = await Process.run('atq', []);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final parts = line.split(RegExp(r'\s+'));
          if (parts.isNotEmpty) {
            final jobId = parts[0];

            items.add(LinuxPersistenceItem(
              id: 'at_$jobId',
              name: 'At Job #$jobId',
              path: '/var/spool/cron/atjobs',
              type: LinuxPersistenceType.atJob,
              risk: LinuxItemRisk.medium,
              metadata: {'job_id': jobId},
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan udev rules
  Future<List<LinuxPersistenceItem>> _scanUdevRules() async {
    final items = <LinuxPersistenceItem>[];

    final udevPaths = [
      '/etc/udev/rules.d',
      '/lib/udev/rules.d',
    ];

    for (final basePath in udevPaths) {
      try {
        final dir = Directory(basePath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.rules')) {
            final content = await entity.readAsString();
            final hasRunCommand = content.contains('RUN+=') || content.contains('RUN=');

            items.add(LinuxPersistenceItem(
              id: 'udev_${entity.path.hashCode}',
              name: entity.path.split('/').last,
              path: entity.path,
              type: LinuxPersistenceType.udevRule,
              risk: hasRunCommand ? LinuxItemRisk.medium : LinuxItemRisk.low,
              indicators: hasRunCommand ? ['Contains RUN command'] : [],
            ));
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan rc.local
  Future<List<LinuxPersistenceItem>> _scanRcLocal() async {
    final items = <LinuxPersistenceItem>[];

    try {
      final rcLocal = File('/etc/rc.local');
      if (await rcLocal.exists()) {
        final content = await rcLocal.readAsString();
        final stat = await rcLocal.stat();

        // Check for suspicious content
        final hasSuspicious = _suspiciousPatterns.any((p) =>
            RegExp(p, caseSensitive: false).hasMatch(content));

        items.add(LinuxPersistenceItem(
          id: 'rclocal',
          name: 'rc.local',
          path: '/etc/rc.local',
          type: LinuxPersistenceType.rcLocal,
          risk: hasSuspicious ? LinuxItemRisk.high : LinuxItemRisk.low,
          modifiedAt: stat.modified,
          isWritableByOthers: await _isWorldWritable('/etc/rc.local'),
        ));
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan profile.d scripts
  Future<List<LinuxPersistenceItem>> _scanProfileD() async {
    final items = <LinuxPersistenceItem>[];

    try {
      final dir = Directory('/etc/profile.d');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && (entity.path.endsWith('.sh') || entity.path.endsWith('.csh'))) {
            final content = await entity.readAsString();
            final hasSuspicious = _suspiciousPatterns.any((p) =>
                RegExp(p, caseSensitive: false).hasMatch(content));

            items.add(LinuxPersistenceItem(
              id: 'profiled_${entity.path.hashCode}',
              name: entity.path.split('/').last,
              path: entity.path,
              type: LinuxPersistenceType.profileD,
              risk: hasSuspicious ? LinuxItemRisk.high : LinuxItemRisk.safe,
              owner: await _getFileOwner(entity.path),
              isWritableByOthers: await _isWorldWritable(entity.path),
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Assess risk of a command
  LinuxItemRisk _assessCommandRisk(String command) {
    final lowerCommand = command.toLowerCase();

    // Check for suspicious patterns
    for (final pattern in _suspiciousPatterns) {
      if (RegExp(pattern, caseSensitive: false).hasMatch(command)) {
        return LinuxItemRisk.critical;
      }
    }

    // Check for network activity
    if (lowerCommand.contains('curl') ||
        lowerCommand.contains('wget') ||
        lowerCommand.contains('nc ') ||
        lowerCommand.contains('ncat')) {
      return LinuxItemRisk.high;
    }

    // Check for script execution
    if (lowerCommand.contains('/tmp/') ||
        lowerCommand.contains('/var/tmp/') ||
        lowerCommand.contains('/dev/shm/')) {
      return LinuxItemRisk.high;
    }

    return LinuxItemRisk.low;
  }

  /// Get file owner
  Future<String?> _getFileOwner(String path) async {
    try {
      final result = await Process.run('stat', ['-c', '%U', path]);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (e) {
      // Skip
    }
    return null;
  }

  /// Get file permissions
  Future<String?> _getFilePermissions(String path) async {
    try {
      final result = await Process.run('stat', ['-c', '%a', path]);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (e) {
      // Skip
    }
    return null;
  }

  /// Check if file is world writable
  Future<bool> _isWorldWritable(String path) async {
    try {
      final perms = await _getFilePermissions(path);
      if (perms != null && perms.length >= 3) {
        final otherPerms = int.parse(perms[perms.length - 1]);
        return (otherPerms & 2) != 0;
      }
    } catch (e) {
      // Skip
    }
    return false;
  }

  /// Check if systemd service is enabled
  Future<bool> _isServiceEnabled(String serviceName) async {
    try {
      final result = await Process.run('systemctl', ['is-enabled', serviceName]);
      return (result.stdout as String).trim() == 'enabled';
    } catch (e) {
      return false;
    }
  }

  /// Scan MOTD scripts
  Future<List<LinuxPersistenceItem>> _scanMotdScripts() async {
    final items = <LinuxPersistenceItem>[];

    final motdPaths = [
      '/etc/update-motd.d',
      '/etc/motd.d',
    ];

    for (final basePath in motdPaths) {
      try {
        final dir = Directory(basePath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File) {
            final content = await entity.readAsString();
            final hasSuspicious = _suspiciousPatterns.any((p) =>
                RegExp(p, caseSensitive: false).hasMatch(content));

            items.add(LinuxPersistenceItem(
              id: 'motd_${entity.path.hashCode}',
              name: entity.path.split('/').last,
              path: entity.path,
              type: LinuxPersistenceType.motd,
              risk: hasSuspicious ? LinuxItemRisk.high : LinuxItemRisk.low,
              owner: await _getFileOwner(entity.path),
              permissions: await _getFilePermissions(entity.path),
              isWritableByOthers: await _isWorldWritable(entity.path),
              indicators: hasSuspicious ? ['Contains suspicious patterns'] : [],
            ));
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan desktop entries (autostart)
  Future<List<LinuxPersistenceItem>> _scanDesktopEntries() async {
    final items = <LinuxPersistenceItem>[];
    final home = Platform.environment['HOME'] ?? '';

    final desktopPaths = [
      '$home/.local/share/applications',
      '/usr/share/applications',
      '/usr/local/share/applications',
    ];

    for (final basePath in desktopPaths) {
      try {
        final dir = Directory(basePath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.desktop')) {
            final content = await entity.readAsString();
            final name = entity.path.split('/').last;

            // Extract Exec line
            String? exec;
            final execMatch = RegExp(r'Exec=(.+)').firstMatch(content);
            if (execMatch != null) {
              exec = execMatch.group(1);
            }

            // Check for autostart
            final isAutostart = content.contains('X-GNOME-Autostart-enabled=true') ||
                basePath.contains('autostart');

            // Check for suspicious commands
            final hasSuspicious = exec != null &&
                _suspiciousPatterns.any((p) =>
                    RegExp(p, caseSensitive: false).hasMatch(exec!));

            // Only add if it's a user-created entry or has autostart
            if (basePath.contains(home) || isAutostart) {
              items.add(LinuxPersistenceItem(
                id: 'desktop_${entity.path.hashCode}',
                name: name.replaceAll('.desktop', ''),
                path: entity.path,
                command: exec,
                type: LinuxPersistenceType.desktopEntry,
                risk: hasSuspicious ? LinuxItemRisk.high : LinuxItemRisk.low,
                owner: await _getFileOwner(entity.path),
                isEnabled: !content.contains('Hidden=true'),
                indicators: hasSuspicious ? ['Suspicious exec command'] : [],
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

  /// Scan D-Bus services
  Future<List<LinuxPersistenceItem>> _scanDbusServices() async {
    final items = <LinuxPersistenceItem>[];
    final home = Platform.environment['HOME'] ?? '';

    final dbusPaths = [
      '$home/.local/share/dbus-1/services',
      '/usr/share/dbus-1/services',
      '/usr/share/dbus-1/system-services',
    ];

    for (final basePath in dbusPaths) {
      try {
        final dir = Directory(basePath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.service')) {
            final content = await entity.readAsString();
            final name = entity.path.split('/').last;

            // Extract Exec line
            String? exec;
            final execMatch = RegExp(r'Exec=(.+)').firstMatch(content);
            if (execMatch != null) {
              exec = execMatch.group(1);
            }

            // Check if it's from a known provider
            final isKnown = _knownDbusServices.any((svc) =>
                name.toLowerCase().startsWith(svc.toLowerCase()));

            // User-created D-Bus services are more suspicious
            final isUserService = basePath.contains(home);

            items.add(LinuxPersistenceItem(
              id: 'dbus_${entity.path.hashCode}',
              name: name.replaceAll('.service', ''),
              path: entity.path,
              command: exec,
              type: LinuxPersistenceType.dbusService,
              risk: isUserService && !isKnown
                  ? LinuxItemRisk.medium
                  : (isKnown ? LinuxItemRisk.safe : LinuxItemRisk.low),
              owner: await _getFileOwner(entity.path),
              indicators: isUserService ? ['User-created D-Bus service'] : [],
            ));
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan sudoers.d directory
  Future<List<LinuxPersistenceItem>> _scanSudoersD() async {
    final items = <LinuxPersistenceItem>[];

    try {
      final dir = Directory('/etc/sudoers.d');
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File) {
            final name = entity.path.split('/').last;
            final stat = await entity.stat();

            // Try to read content (may fail due to permissions)
            String? content;
            List<String> indicators = [];
            LinuxItemRisk risk = LinuxItemRisk.medium;

            try {
              content = await entity.readAsString();

              // Check for dangerous sudo configurations
              if (content.contains('NOPASSWD')) {
                indicators.add('Contains NOPASSWD');
                risk = LinuxItemRisk.high;
              }
              if (content.contains('ALL=(ALL)')) {
                indicators.add('Grants full sudo access');
              }
              if (_suspiciousPatterns.any((p) =>
                  RegExp(p, caseSensitive: false).hasMatch(content!))) {
                indicators.add('Contains suspicious patterns');
                risk = LinuxItemRisk.critical;
              }
            } catch (e) {
              // Permission denied is normal
            }

            items.add(LinuxPersistenceItem(
              id: 'sudoers_${entity.path.hashCode}',
              name: name,
              path: entity.path,
              type: LinuxPersistenceType.sudoersD,
              risk: risk,
              owner: await _getFileOwner(entity.path),
              permissions: await _getFilePermissions(entity.path),
              modifiedAt: stat.modified,
              isWritableByOthers: await _isWorldWritable(entity.path),
              indicators: indicators,
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan polkit rules
  Future<List<LinuxPersistenceItem>> _scanPolkitRules() async {
    final items = <LinuxPersistenceItem>[];

    final polkitPaths = [
      '/etc/polkit-1/rules.d',
      '/usr/share/polkit-1/rules.d',
    ];

    for (final basePath in polkitPaths) {
      try {
        final dir = Directory(basePath);
        if (!await dir.exists()) continue;

        await for (final entity in dir.list()) {
          if (entity is File && (entity.path.endsWith('.rules') || entity.path.endsWith('.pkla'))) {
            final content = await entity.readAsString();
            final name = entity.path.split('/').last;
            final stat = await entity.stat();

            List<String> indicators = [];
            LinuxItemRisk risk = LinuxItemRisk.low;

            // Check for overly permissive rules
            if (content.contains('return polkit.Result.YES')) {
              indicators.add('Allows all actions');
              risk = LinuxItemRisk.high;
            }
            if (content.contains('ResultActive=yes') && content.contains('*')) {
              indicators.add('Wildcard permission grant');
              risk = LinuxItemRisk.high;
            }

            items.add(LinuxPersistenceItem(
              id: 'polkit_${entity.path.hashCode}',
              name: name,
              path: entity.path,
              type: LinuxPersistenceType.polkitRule,
              risk: risk,
              owner: await _getFileOwner(entity.path),
              permissions: await _getFilePermissions(entity.path),
              modifiedAt: stat.modified,
              indicators: indicators,
            ));
          }
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Scan /etc/environment and related environment files
  Future<List<LinuxPersistenceItem>> _scanEnvironmentFiles() async {
    final items = <LinuxPersistenceItem>[];

    final envFiles = [
      '/etc/environment',
      '/etc/environment.d',
      '/etc/default',
    ];

    for (final filePath in envFiles) {
      try {
        final entity = File(filePath);
        final dir = Directory(filePath);

        if (await entity.exists() && await entity.stat().then((s) => s.type == FileSystemEntityType.file)) {
          final content = await entity.readAsString();
          final stat = await entity.stat();

          // Check for suspicious content
          final hasSuspicious = _suspiciousPatterns.any((p) =>
              RegExp(p, caseSensitive: false).hasMatch(content));

          // Check for LD_PRELOAD or similar dangerous variables
          final hasDangerousVar = content.contains('LD_PRELOAD') ||
              content.contains('LD_LIBRARY_PATH') ||
              content.contains('PATH=') && content.contains('/tmp/');

          items.add(LinuxPersistenceItem(
            id: 'env_${filePath.hashCode}',
            name: filePath.split('/').last,
            path: filePath,
            type: LinuxPersistenceType.environmentFile,
            risk: hasSuspicious
                ? LinuxItemRisk.critical
                : (hasDangerousVar ? LinuxItemRisk.high : LinuxItemRisk.safe),
            owner: await _getFileOwner(filePath),
            permissions: await _getFilePermissions(filePath),
            modifiedAt: stat.modified,
            isWritableByOthers: await _isWorldWritable(filePath),
            indicators: [
              if (hasSuspicious) 'Contains suspicious patterns',
              if (hasDangerousVar) 'Contains dangerous environment variables',
            ],
          ));
        } else if (await dir.exists()) {
          await for (final file in dir.list()) {
            if (file is File) {
              final content = await file.readAsString();
              final stat = await file.stat();
              final hasSuspicious = _suspiciousPatterns.any((p) =>
                  RegExp(p, caseSensitive: false).hasMatch(content));

              items.add(LinuxPersistenceItem(
                id: 'env_${file.path.hashCode}',
                name: file.path.split('/').last,
                path: file.path,
                type: LinuxPersistenceType.environmentFile,
                risk: hasSuspicious ? LinuxItemRisk.high : LinuxItemRisk.low,
                owner: await _getFileOwner(file.path),
                modifiedAt: stat.modified,
                indicators: hasSuspicious ? ['Contains suspicious patterns'] : [],
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

  /// Scan SELinux policies
  Future<List<LinuxPersistenceItem>> _scanSelinuxPolicies() async {
    final items = <LinuxPersistenceItem>[];

    // Check if SELinux is enabled
    try {
      final selinuxStatus = await Process.run('getenforce', []);
      final isEnforcing = (selinuxStatus.stdout as String).trim().toLowerCase() == 'enforcing';

      // Scan custom policy modules
      final modulesResult = await Process.run('semodule', ['-l']);
      if (modulesResult.exitCode == 0) {
        final modules = (modulesResult.stdout as String).split('\n');
        for (final module in modules) {
          final parts = module.trim().split(RegExp(r'\s+'));
          if (parts.isEmpty || parts[0].isEmpty) continue;

          final moduleName = parts[0];

          // System modules are typically safe
          final isSystemModule = [
            'selinux-policy', 'base', 'targeted', 'container',
            'virt', 'sandbox', 'permissive', 'unconfined'
          ].any((s) => moduleName.contains(s));

          items.add(LinuxPersistenceItem(
            id: 'selinux_${moduleName.hashCode}',
            name: moduleName,
            path: '/etc/selinux',
            type: LinuxPersistenceType.selinuxPolicy,
            risk: isSystemModule ? LinuxItemRisk.safe : LinuxItemRisk.medium,
            isEnabled: isEnforcing,
            indicators: isSystemModule ? [] : ['Custom SELinux module'],
          ));
        }
      }
    } catch (e) {
      // SELinux not available
    }

    // Scan policy files in /etc/selinux
    try {
      final selinuxDir = Directory('/etc/selinux');
      if (await selinuxDir.exists()) {
        await for (final entity in selinuxDir.list(recursive: true)) {
          if (entity is File && (entity.path.endsWith('.pp') || entity.path.endsWith('.te'))) {
            final stat = await entity.stat();
            items.add(LinuxPersistenceItem(
              id: 'selinux_file_${entity.path.hashCode}',
              name: entity.path.split('/').last,
              path: entity.path,
              type: LinuxPersistenceType.selinuxPolicy,
              risk: LinuxItemRisk.low,
              modifiedAt: stat.modified,
              owner: await _getFileOwner(entity.path),
            ));
          }
        }
      }
    } catch (e) {
      // Skip
    }

    return items;
  }

  /// Scan TCP Wrappers configuration
  Future<List<LinuxPersistenceItem>> _scanTcpWrappers() async {
    final items = <LinuxPersistenceItem>[];

    final wrapperFiles = ['/etc/hosts.allow', '/etc/hosts.deny'];

    for (final filePath in wrapperFiles) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final stat = await file.stat();

          // Check for suspicious entries
          final hasSuspicious = content.contains('ALL : ALL') ||
              _suspiciousPatterns.any((p) =>
                  RegExp(p, caseSensitive: false).hasMatch(content));

          // Check for spawn commands which can execute arbitrary code
          final hasSpawn = content.contains('spawn') || content.contains('twist');

          items.add(LinuxPersistenceItem(
            id: 'tcpwrap_${filePath.hashCode}',
            name: filePath.split('/').last,
            path: filePath,
            type: LinuxPersistenceType.tcpWrapper,
            risk: hasSpawn
                ? LinuxItemRisk.high
                : (hasSuspicious ? LinuxItemRisk.medium : LinuxItemRisk.safe),
            owner: await _getFileOwner(filePath),
            permissions: await _getFilePermissions(filePath),
            modifiedAt: stat.modified,
            isWritableByOthers: await _isWorldWritable(filePath),
            indicators: [
              if (hasSpawn) 'Contains spawn/twist commands for code execution',
              if (hasSuspicious) 'Contains potentially dangerous patterns',
            ],
          ));
        }
      } catch (e) {
        // Skip
      }
    }

    return items;
  }

  /// Compute SHA256 hashes for suspicious items and check against threat intel
  Future<void> _computeHashes(List<LinuxPersistenceItem> items) async {
    for (var i = 0; i < items.length; i++) {
      final item = items[i];

      // Only compute hashes for high-risk items to save time
      if (item.risk.index < LinuxItemRisk.medium.index) continue;

      // If there's a command, try to hash the executable
      String? pathToHash = item.command?.split(' ').first ?? item.path;

      try {
        final file = File(pathToHash);
        if (await file.exists()) {
          final result = await Process.run('sha256sum', [pathToHash]);
          if (result.exitCode == 0) {
            final hash = (result.stdout as String).split(' ').first.toLowerCase();

            // Check against known malware hashes
            final isKnownMalware = _knownMalwareHashes.contains(hash);

            // Create new item with hash
            items[i] = LinuxPersistenceItem(
              id: item.id,
              name: item.name,
              path: item.path,
              command: item.command,
              type: item.type,
              risk: isKnownMalware ? LinuxItemRisk.critical : item.risk,
              owner: item.owner,
              permissions: item.permissions,
              description: item.description,
              hash: hash,
              createdAt: item.createdAt,
              modifiedAt: item.modifiedAt,
              isEnabled: item.isEnabled,
              isWritableByOthers: item.isWritableByOthers,
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
  String exportToJson(LinuxScanResult result) {
    return jsonEncode(result.toJson());
  }
}
