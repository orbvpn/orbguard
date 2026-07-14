/// Desktop host collection helpers shared by the per-platform persistence
/// scanner services.
///
/// The OrbGuard Lab backend's desktop scanners (network monitor, browser
/// extension scanner) run on the SERVER host, so all collection here is
/// performed on the local device via Process/filesystem access. The output
/// maps intentionally mirror the backend JSON shapes
/// (orbguard-lab internal/domain/models/desktop_security.go:
/// NetworkConnection, BrowserExtension) so the data can be uploaded for
/// server-side analysis once the backend grows upload-accepting analyze
/// endpoints.
library;

import 'dart:convert';
import 'dart:io';

/// Result of a host-local collection pass. `items` are JSON-shaped maps,
/// `errors` are honest per-step failures (missing tool, permission denied,
/// unparseable output) and `source` describes exactly how the data was
/// obtained.
class HostCollection {
  final List<Map<String, dynamic>> items;
  final List<String> errors;
  final String source;

  const HostCollection({
    required this.items,
    this.errors = const [],
    required this.source,
  });
}

// ===========================================================================
// Network connections
// ===========================================================================

/// Splits "addr:port" handling IPv6 forms like "[::1]:443" and "*:*".
({String address, int port}) splitAddressPort(String raw) {
  var s = raw.trim();
  if (s.startsWith('[')) {
    final close = s.indexOf(']');
    if (close > 0) {
      final addr = s.substring(1, close);
      final rest = s.substring(close + 1);
      final port = rest.startsWith(':') ? int.tryParse(rest.substring(1)) : null;
      return (address: addr, port: port ?? 0);
    }
  }
  final idx = s.lastIndexOf(':');
  if (idx <= 0) return (address: s, port: 0);
  final port = int.tryParse(s.substring(idx + 1));
  return (address: s.substring(0, idx), port: port ?? 0);
}

bool isPublicRoutableIp(String address) {
  if (address.isEmpty || address == '*' || address == '0.0.0.0') return false;
  final ip = InternetAddress.tryParse(address);
  if (ip == null) return false;
  if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) return false;
  if (ip.type == InternetAddressType.IPv4) {
    final parts = ip.address.split('.').map(int.parse).toList();
    if (parts[0] == 10) return false;
    if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return false;
    if (parts[0] == 192 && parts[1] == 168) return false;
    if (parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127) return false; // CGNAT
    if (parts[0] == 169 && parts[1] == 254) return false;
    return true;
  }
  // IPv6: exclude unique-local fc00::/7
  final first = ip.rawAddress[0];
  if ((first & 0xfe) == 0xfc) return false;
  return true;
}

Map<String, dynamic> _connectionMap({
  required String protocol,
  required String localAddress,
  required int localPort,
  required String remoteAddress,
  required int remotePort,
  required String state,
  int? pid,
  String? processName,
}) {
  return {
    'protocol': protocol,
    'local_address': localAddress,
    'local_port': localPort,
    'remote_address': remoteAddress,
    'remote_port': remotePort,
    'state': state,
    if (pid != null) 'process_id': pid,
    if (processName != null && processName.isNotEmpty) 'process_name': processName,
    'is_known_bad': false,
    'is_cnc': false,
    'collected_locally': true,
  };
}

/// macOS: `lsof -nP -i -FpcnPT` machine-readable output.
Future<HostCollection> collectMacosNetworkConnections() async {
  const source = 'lsof -nP -i (local device)';
  final ProcessResult result;
  try {
    result = await Process.run('lsof', ['-nP', '-i', '-FpcnPT']);
  } on ProcessException catch (e) {
    return HostCollection(
      items: const [],
      errors: ['lsof could not be executed: ${e.message}'],
      source: source,
    );
  }
  // lsof exits 1 when some process info is unavailable but still prints
  // usable records, so only fail when there is no stdout at all.
  final stdoutStr = result.stdout as String? ?? '';
  if (stdoutStr.trim().isEmpty) {
    return HostCollection(
      items: const [],
      errors: [
        'lsof returned no socket data (exit ${result.exitCode}): '
            '${(result.stderr as String? ?? '').trim()}',
      ],
      source: source,
    );
  }

  final items = <Map<String, dynamic>>[];
  final errors = <String>[];
  int? pid;
  String cmd = '';
  String proto = '';
  Map<String, dynamic>? pending;

  void flush() {
    if (pending != null) {
      items.add(pending!);
      pending = null;
    }
  }

  for (final line in const LineSplitter().convert(stdoutStr)) {
    if (line.isEmpty) continue;
    final tag = line[0];
    final value = line.substring(1);
    switch (tag) {
      case 'p':
        flush();
        pid = int.tryParse(value);
        break;
      case 'c':
        cmd = value;
        break;
      case 'P':
        proto = value.toLowerCase();
        break;
      case 'n':
        flush();
        String local = value;
        String remote = '';
        final arrow = value.indexOf('->');
        if (arrow >= 0) {
          local = value.substring(0, arrow);
          remote = value.substring(arrow + 2);
        }
        final l = splitAddressPort(local);
        final r = remote.isNotEmpty
            ? splitAddressPort(remote)
            : (address: '', port: 0);
        pending = _connectionMap(
          protocol: proto,
          localAddress: l.address,
          localPort: l.port,
          remoteAddress: r.address,
          remotePort: r.port,
          // UDP sockets and unconnected TCP sockets have no state line;
          // report the honest empty string rather than inventing one.
          state: '',
          pid: pid,
          processName: cmd,
        );
        break;
      case 'T':
        if (value.startsWith('ST=') && pending != null) {
          pending!['state'] = value.substring(3);
        }
        break;
      default:
        break;
    }
  }
  flush();
  if (items.isEmpty) {
    errors.add('lsof output contained no parseable socket records');
  }
  return HostCollection(items: items, errors: errors, source: source);
}

/// Linux: `ss -tunap` with `netstat -tunap` fallback.
Future<HostCollection> collectLinuxNetworkConnections() async {
  ProcessResult? result;
  var source = 'ss -tunap (local device)';
  final errors = <String>[];
  try {
    result = await Process.run('ss', ['-tunap']);
    if (result.exitCode != 0) {
      errors.add('ss exited ${result.exitCode}: ${(result.stderr as String).trim()}');
      result = null;
    }
  } on ProcessException catch (e) {
    errors.add('ss could not be executed: ${e.message}');
  }
  if (result == null) {
    source = 'netstat -tunap (local device)';
    try {
      result = await Process.run('netstat', ['-tunap']);
      if (result.exitCode != 0) {
        return HostCollection(
          items: const [],
          errors: [
            ...errors,
            'netstat exited ${result.exitCode}: ${(result.stderr as String).trim()}',
          ],
          source: source,
        );
      }
    } on ProcessException catch (e) {
      return HostCollection(
        items: const [],
        errors: [...errors, 'netstat could not be executed: ${e.message}'],
        source: source,
      );
    }
  }

  final items = <Map<String, dynamic>>[];
  final processRe = RegExp(r'\(\("([^"]+)",pid=(\d+)');
  final lines = const LineSplitter().convert(result.stdout as String);
  for (final line in lines) {
    final t = line.trim();
    if (t.isEmpty ||
        t.startsWith('Netid') ||
        t.startsWith('Proto') ||
        t.startsWith('Active ')) {
      continue;
    }
    final fields = t.split(RegExp(r'\s+'));
    if (fields.length < 5) continue;
    String proto;
    String state;
    String local;
    String peer;
    if (source.startsWith('ss')) {
      proto = fields[0].toLowerCase();
      state = fields[1];
      local = fields[4];
      peer = fields.length > 5 ? fields[5] : '';
    } else {
      // netstat: Proto Recv-Q Send-Q Local Foreign State [PID/Program]
      proto = fields[0].toLowerCase();
      local = fields[3];
      peer = fields.length > 4 ? fields[4] : '';
      state = proto.startsWith('tcp') && fields.length > 5 ? fields[5] : '';
    }
    if (!proto.startsWith('tcp') && !proto.startsWith('udp')) continue;
    final l = splitAddressPort(local);
    final p = splitAddressPort(peer);
    int? pid;
    String? procName;
    final m = processRe.firstMatch(t);
    if (m != null) {
      procName = m.group(1);
      pid = int.tryParse(m.group(2)!);
    } else {
      // netstat format: 1234/firefox
      final m2 = RegExp(r'(\d+)/([^\s]+)\s*$').firstMatch(t);
      if (m2 != null) {
        pid = int.tryParse(m2.group(1)!);
        procName = m2.group(2);
      }
    }
    items.add(_connectionMap(
      protocol: proto,
      localAddress: l.address,
      localPort: l.port,
      remoteAddress: p.address == '*' ? '' : p.address,
      remotePort: p.port,
      state: state == 'UNCONN' ? '' : state,
      pid: pid,
      processName: procName,
    ));
  }
  if (items.isEmpty) {
    errors.add('$source produced no parseable connection rows');
  }
  // Without root, ss/netstat cannot resolve owning processes of other users;
  // surface that honestly instead of leaving silently-missing fields.
  if (items.isNotEmpty && items.every((i) => i['process_name'] == null)) {
    errors.add(
      'Process names unavailable: $source needs elevated privileges to map sockets to processes',
    );
  }
  return HostCollection(items: items, errors: errors, source: source);
}

/// Windows: `netstat -ano` + `tasklist` PID→name mapping.
Future<HostCollection> collectWindowsNetworkConnections() async {
  const source = 'netstat -ano + tasklist (local device)';
  final ProcessResult result;
  try {
    result = await Process.run('netstat', ['-ano'], runInShell: true);
  } on ProcessException catch (e) {
    return HostCollection(
      items: const [],
      errors: ['netstat could not be executed: ${e.message}'],
      source: source,
    );
  }
  if (result.exitCode != 0) {
    return HostCollection(
      items: const [],
      errors: [
        'netstat exited ${result.exitCode}: ${(result.stderr as String).trim()}',
      ],
      source: source,
    );
  }

  final errors = <String>[];
  final pidNames = <int, String>{};
  try {
    final taskResult =
        await Process.run('tasklist', ['/FO', 'CSV', '/NH'], runInShell: true);
    if (taskResult.exitCode == 0) {
      for (final line in const LineSplitter().convert(taskResult.stdout as String)) {
        // "name.exe","1234","Console","1","12,345 K"
        final cols = RegExp(r'"([^"]*)"').allMatches(line).map((m) => m.group(1)!).toList();
        if (cols.length >= 2) {
          final pid = int.tryParse(cols[1]);
          if (pid != null) pidNames[pid] = cols[0];
        }
      }
    } else {
      errors.add('tasklist exited ${taskResult.exitCode}; process names unavailable');
    }
  } on ProcessException catch (e) {
    errors.add('tasklist could not be executed (${e.message}); process names unavailable');
  }

  final items = <Map<String, dynamic>>[];
  for (final line in const LineSplitter().convert(result.stdout as String)) {
    final fields = line.trim().split(RegExp(r'\s+'));
    if (fields.length < 4) continue;
    final proto = fields[0].toLowerCase();
    if (proto != 'tcp' && proto != 'udp') continue;
    final l = splitAddressPort(fields[1]);
    final p = splitAddressPort(fields[2]);
    String state = '';
    int? pid;
    if (proto == 'tcp' && fields.length >= 5) {
      state = fields[3];
      pid = int.tryParse(fields[4]);
    } else {
      pid = int.tryParse(fields[3]);
    }
    items.add(_connectionMap(
      protocol: proto,
      localAddress: l.address,
      localPort: l.port,
      remoteAddress: p.address == '*' ? '' : p.address,
      remotePort: p.port,
      state: state,
      pid: pid,
      processName: pid != null ? pidNames[pid] : null,
    ));
  }
  if (items.isEmpty) {
    errors.add('netstat output contained no parseable connection rows');
  }
  return HostCollection(items: items, errors: errors, source: source);
}

// ===========================================================================
// Browser extensions
// ===========================================================================

/// Permission-based local risk heuristics (mirrors the categories used by the
/// backend browser scanner; analysis stays local until the backend accepts
/// uploaded extension payloads).
({String level, List<String> reasons}) assessExtensionRisk(
  List<String> permissions,
  List<String> hostPermissions,
) {
  final perms = permissions.map((p) => p.toLowerCase()).toSet();
  final hosts = hostPermissions.map((p) => p.toLowerCase()).toSet();
  final reasons = <String>[];

  final allUrls = perms.contains('<all_urls>') ||
      hosts.contains('<all_urls>') ||
      hosts.any((h) => h == '*://*/*' || h == 'http://*/*' || h == 'https://*/*');
  if (allUrls) reasons.add('Can read and change data on all websites');
  if (perms.contains('nativemessaging')) {
    reasons.add('Can communicate with native applications outside the browser');
  }
  if (perms.contains('debugger')) {
    reasons.add('Can attach the debugger to browser tabs');
  }
  if (perms.contains('webrequest') || perms.contains('webrequestblocking')) {
    reasons.add('Can intercept network requests');
  }
  if (perms.contains('cookies')) reasons.add('Can read browser cookies');
  if (perms.contains('history')) reasons.add('Can read browsing history');
  if (perms.contains('clipboardread')) reasons.add('Can read the clipboard');
  if (perms.contains('proxy')) reasons.add('Can change proxy settings');
  if (perms.contains('management')) {
    reasons.add('Can manage other extensions');
  }
  if (perms.contains('downloads')) reasons.add('Can manage downloads');
  if (perms.contains('tabs') || perms.contains('scripting')) {
    reasons.add('Can access browser tabs');
  }

  String level;
  if (allUrls && (perms.contains('nativemessaging') || perms.contains('debugger'))) {
    level = 'critical';
  } else if (allUrls &&
      (perms.contains('webrequest') ||
          perms.contains('cookies') ||
          perms.contains('history') ||
          perms.contains('proxy'))) {
    level = 'high';
  } else if (allUrls ||
      perms.contains('cookies') ||
      perms.contains('history') ||
      perms.contains('webrequest') ||
      perms.contains('proxy') ||
      perms.contains('clipboardread')) {
    level = 'medium';
  } else if (reasons.isNotEmpty) {
    level = 'low';
  } else {
    level = 'low';
    reasons.add('No high-impact permissions requested');
  }
  return (level: level, reasons: reasons);
}

Future<String> _resolveChromiumMessage(
  Directory versionDir,
  String raw,
  String? defaultLocale,
) async {
  if (!raw.startsWith('__MSG_')) return raw;
  final key = raw.substring(6, raw.endsWith('__') ? raw.length - 2 : raw.length);
  final localeCandidates = <String>[
    if (defaultLocale != null) defaultLocale,
    if (defaultLocale != null && defaultLocale.contains('_'))
      defaultLocale.split('_').first,
    'en',
    'en_US',
    'en_GB',
  ];
  for (final locale in localeCandidates) {
    final f = File('${versionDir.path}/_locales/$locale/messages.json');
    if (!await f.exists()) continue;
    try {
      final messages = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final entry = messages[key] ??
          messages[key.toLowerCase()] ??
          messages.entries
              .where((e) => e.key.toLowerCase() == key.toLowerCase())
              .map((e) => e.value)
              .firstOrNull;
      if (entry is Map<String, dynamic> && entry['message'] is String) {
        return entry['message'] as String;
      }
    } catch (_) {
      // Fall through to next locale candidate.
    }
  }
  return raw;
}

/// Scans Chromium-family extension directories.
/// [roots] maps a browser display name to its user-data dir (the directory
/// containing `Default`, `Profile 1`, ...).
Future<HostCollection> collectChromiumExtensions(
  Map<String, String> roots,
) async {
  final items = <Map<String, dynamic>>[];
  final errors = <String>[];
  final scannedBrowsers = <String>[];

  for (final entry in roots.entries) {
    final browser = entry.key;
    final root = Directory(entry.value);
    if (!await root.exists()) continue;
    scannedBrowsers.add(browser);

    final profiles = <Directory>[];
    try {
      await for (final e in root.list()) {
        if (e is! Directory) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        if (name == 'Default' || name.startsWith('Profile ')) profiles.add(e);
      }
    } on FileSystemException catch (e) {
      errors.add('$browser: cannot list profiles: ${e.message}');
      continue;
    }

    for (final profile in profiles) {
      final extRoot = Directory('${profile.path}/Extensions');
      if (!await extRoot.exists()) continue;
      try {
        await for (final extDir in extRoot.list()) {
          if (extDir is! Directory) continue;
          final extId = extDir.path.split(Platform.pathSeparator).last;
          if (extId == 'Temp') continue;
          // Pick the latest version directory containing a manifest.
          Directory? versionDir;
          await for (final v in extDir.list()) {
            if (v is Directory && await File('${v.path}/manifest.json').exists()) {
              if (versionDir == null ||
                  v.path.compareTo(versionDir.path) > 0) {
                versionDir = v;
              }
            }
          }
          if (versionDir == null) continue;
          try {
            final manifest = jsonDecode(
                await File('${versionDir.path}/manifest.json').readAsString())
                as Map<String, dynamic>;
            final defaultLocale = manifest['default_locale'] as String?;
            final name = await _resolveChromiumMessage(
              versionDir,
              manifest['name'] as String? ?? extId,
              defaultLocale,
            );
            final description = await _resolveChromiumMessage(
              versionDir,
              manifest['description'] as String? ?? '',
              defaultLocale,
            );
            final permissions = (manifest['permissions'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                const <String>[];
            final hostPermissions = (manifest['host_permissions'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                // Manifest v2 mixes host patterns into `permissions`.
                permissions.where((p) => p.contains('://') || p == '<all_urls>').toList();
            final risk = assessExtensionRisk(permissions, hostPermissions);
            items.add({
              'browser': browser,
              'extension_id': extId,
              'name': name,
              'version': manifest['version'] as String? ?? '',
              'description': description,
              'permissions': permissions,
              'host_permissions': hostPermissions,
              'risk_level': risk.level,
              'risk_reasons': risk.reasons,
              'install_path': versionDir.path,
              'profile_path': profile.path,
              'collected_locally': true,
            });
          } on FormatException catch (e) {
            errors.add('$browser/$extId: unparseable manifest: ${e.message}');
          } on FileSystemException catch (e) {
            errors.add('$browser/$extId: cannot read manifest: ${e.message}');
          }
        }
      } on FileSystemException catch (e) {
        errors.add('$browser: cannot list extensions in ${profile.path}: ${e.message}');
      }
    }
  }

  return HostCollection(
    items: items,
    errors: errors,
    source: scannedBrowsers.isEmpty
        ? 'no Chromium-family browser profiles found on this device'
        : 'manifest scan of ${scannedBrowsers.join(', ')} profiles (local device)',
  );
}

/// Scans Firefox `extensions.json` in every profile under [profilesRoot].
Future<HostCollection> collectFirefoxExtensions(String profilesRoot) async {
  final items = <Map<String, dynamic>>[];
  final errors = <String>[];
  final root = Directory(profilesRoot);
  if (!await root.exists()) {
    return const HostCollection(
      items: [],
      source: 'Firefox not installed (no profiles directory)',
    );
  }

  var profilesScanned = 0;
  try {
    await for (final profile in root.list()) {
      if (profile is! Directory) continue;
      final extFile = File('${profile.path}/extensions.json');
      if (!await extFile.exists()) continue;
      profilesScanned++;
      try {
        final data = jsonDecode(await extFile.readAsString()) as Map<String, dynamic>;
        final addons = (data['addons'] as List?)?.whereType<Map<String, dynamic>>() ??
            const Iterable<Map<String, dynamic>>.empty();
        for (final addon in addons) {
          if (addon['type'] != 'extension') continue;
          final location = addon['location'] as String? ?? '';
          final locale = addon['defaultLocale'] as Map<String, dynamic>? ?? const {};
          final userPerms = addon['userPermissions'] as Map<String, dynamic>? ?? const {};
          final permissions = (userPerms['permissions'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const <String>[];
          final origins = (userPerms['origins'] as List?)
                  ?.whereType<String>()
                  .toList() ??
              const <String>[];
          final risk = assessExtensionRisk(permissions, origins);
          items.add({
            'browser': 'Firefox',
            'extension_id': addon['id'] as String? ?? '',
            'name': locale['name'] as String? ?? addon['id'] as String? ?? 'Unknown',
            'version': addon['version'] as String? ?? '',
            'description': locale['description'] as String? ?? '',
            'author': locale['creator'] as String? ?? '',
            'permissions': permissions,
            'host_permissions': origins,
            'risk_level': risk.level,
            'risk_reasons': risk.reasons,
            'install_path': addon['path'] as String? ?? '',
            'profile_path': profile.path,
            'enabled': addon['active'] as bool? ?? !(addon['userDisabled'] as bool? ?? false),
            'location': location,
            'collected_locally': true,
          });
        }
      } on FormatException catch (e) {
        errors.add('Firefox ${profile.path}: unparseable extensions.json: ${e.message}');
      } on FileSystemException catch (e) {
        errors.add('Firefox ${profile.path}: cannot read extensions.json: ${e.message}');
      }
    }
  } on FileSystemException catch (e) {
    errors.add('Firefox: cannot list profiles: ${e.message}');
  }

  return HostCollection(
    items: items,
    errors: errors,
    source: profilesScanned == 0
        ? 'Firefox installed but no profiles with extensions.json found'
        : 'extensions.json scan of $profilesScanned Firefox profile(s) (local device)',
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
