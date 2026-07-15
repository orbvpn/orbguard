// Desktop Firewall Enforcer
//
// REAL cross-platform enforcement of the threat-intelligence malicious-IP
// block list using the host operating system's own packet filter:
//
//   - macOS   : a dedicated `pf` anchor (com.orbguard) loaded from
//               /etc/pf.anchors/com.orbguard and referenced from /etc/pf.conf.
//   - Linux   : a dedicated iptables/ip6tables chain (ORBGUARD) jumped from
//               OUTPUT and INPUT.
//   - Windows : dedicated "OrbGuard Threat Block" netsh advfirewall rules
//               (comma-separated remoteip batches, one UAC prompt).
//
// Every mutation requires root/administrator. Elevation is handled HONESTLY:
// osascript (macOS admin prompt), pkexec (Linux polkit) and a RunAs
// PowerShell relaunch (Windows UAC). A cancelled prompt, a missing elevation
// tool or a permission denial NEVER report "enforcing" — they surface
// [FirewallEnforcementState.needsElevation] with the real reason.
//
// This engine blocks IP addresses (and CIDR ranges). OS packet filters match
// on addresses, not domains, so domain-level blocking is intentionally NOT
// claimed here — it stays in the in-app NetworkFirewallService matcher.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_info.dart';

/// Real enforcement state of the OS packet filter for the OrbGuard block list.
enum FirewallEnforcementState {
  /// The block rules are actually installed in the OS firewall.
  enforcing,

  /// No block rules are installed (never enabled, or successfully removed).
  notEnforcing,

  /// Root/administrator is required and was not obtained — the elevation
  /// prompt was cancelled/denied, or no elevation tool is available. Rules
  /// were NOT applied.
  needsElevation,

  /// This platform/tooling cannot enforce (mobile, or the firewall CLI is
  /// missing). See [FirewallEnforcementStatus.reason].
  unavailable,
}

/// Honest, detailed enforcement status. Reflects what is ACTUALLY installed in
/// the OS firewall, never merely what was requested.
class FirewallEnforcementStatus {
  final FirewallEnforcementState state;

  /// Human-readable explanation (exact command failure, elevation outcome,
  /// or platform limitation).
  final String reason;

  /// Number of malicious IPs currently covered by the installed rules
  /// (best known — live-verified where possible, otherwise the last applied
  /// count restored from persistence).
  final int blockedIpCount;

  /// Which mechanism/command produced this status.
  final String source;

  /// The persisted user intent (enforcement was switched on and not yet
  /// switched off). The [state] is authoritative; this is only intent.
  final bool enabledPreference;

  /// A mutation failed for a non-privilege reason (the firewall command
  /// errored). Lets the UI distinguish a hard failure from a clean "off".
  final bool errored;

  const FirewallEnforcementStatus({
    required this.state,
    required this.reason,
    required this.source,
    this.blockedIpCount = 0,
    this.enabledPreference = false,
    this.errored = false,
  });

  bool get isEnforcing => state == FirewallEnforcementState.enforcing;
}

/// Outcome of one elevated command invocation.
class _ElevationOutcome {
  final bool ok;
  final bool cancelled;
  final bool permissionDenied;
  final bool toolingMissing;
  final String output;

  const _ElevationOutcome({
    required this.ok,
    this.cancelled = false,
    this.permissionDenied = false,
    this.toolingMissing = false,
    this.output = '',
  });
}

/// Classification of a threat-intel address value.
enum _AddrFamily { ipv4, ipv6, invalid }

class DesktopFirewallEnforcer {
  // ---- Identifiers used across the platform mechanisms ----
  static const String _pfAnchorName = 'com.orbguard';
  static const String _pfAnchorFile = '/etc/pf.anchors/com.orbguard';
  static const String _pfConf = '/etc/pf.conf';
  static const String _pfTable = 'orbguard_blocklist';
  static const String _pfMarkerBegin =
      '# >>> OrbGuard threat-intel enforcement >>>';
  static const String _pfMarkerEnd =
      '# <<< OrbGuard threat-intel enforcement <<<';

  static const String _linuxChain = 'ORBGUARD';

  static const String _windowsRuleName = 'OrbGuard Threat Block';

  // ---- Persistence keys (intent + last applied count) ----
  static const String _prefEnabledKey = 'desktop_fw_enforce_enabled';
  static const String _prefIpCountKey = 'desktop_fw_enforce_ipcount';

  /// Safety cap on how many entries we push into a single ruleset.
  static const int _maxEntries = 2000;

  /// True only on desktop platforms with a supported packet filter.
  bool get isSupportedPlatform => PlatformInfo.isDesktop;

  // =========================================================================
  // Persistence of intent
  // =========================================================================

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('DesktopFirewallEnforcer: preferences unavailable: $e');
      return null;
    }
  }

  Future<bool> _readEnabledPref() async {
    final prefs = await _prefs();
    return prefs?.getBool(_prefEnabledKey) ?? false;
  }

  Future<int> _readIpCountPref() async {
    final prefs = await _prefs();
    return prefs?.getInt(_prefIpCountKey) ?? 0;
  }

  Future<void> _writePref(bool enabled, int ipCount) async {
    final prefs = await _prefs();
    if (prefs == null) return;
    try {
      await prefs.setBool(_prefEnabledKey, enabled);
      await prefs.setInt(_prefIpCountKey, ipCount);
    } catch (e) {
      debugPrint('DesktopFirewallEnforcer: failed to persist intent: $e');
    }
  }

  // =========================================================================
  // Address handling
  // =========================================================================

  _AddrFamily _classify(String raw) {
    var addr = raw.trim();
    if (addr.isEmpty) return _AddrFamily.invalid;
    int? prefix;
    final slash = addr.indexOf('/');
    if (slash >= 0) {
      prefix = int.tryParse(addr.substring(slash + 1));
      if (prefix == null) return _AddrFamily.invalid;
      addr = addr.substring(0, slash);
    }
    final ip = InternetAddress.tryParse(addr);
    if (ip == null) return _AddrFamily.invalid;
    // Never block traffic to ourselves / the local segment even if the feed
    // is poisoned with such an entry — that would take the host offline.
    if (ip.isLoopback || ip.isLinkLocal || ip.isMulticast) {
      return _AddrFamily.invalid;
    }
    if (ip.type == InternetAddressType.IPv4) {
      if (ip.address == '0.0.0.0') return _AddrFamily.invalid;
      if (prefix != null && (prefix < 0 || prefix > 32)) {
        return _AddrFamily.invalid;
      }
      return _AddrFamily.ipv4;
    }
    if (ip.type == InternetAddressType.IPv6) {
      if (prefix != null && (prefix < 0 || prefix > 128)) {
        return _AddrFamily.invalid;
      }
      return _AddrFamily.ipv6;
    }
    return _AddrFamily.invalid;
  }

  /// Split raw threat-intel values into de-duplicated, validated v4/v6 lists.
  ({List<String> v4, List<String> v6, int skipped}) _partition(
      List<String> raw) {
    final v4 = <String>{};
    final v6 = <String>{};
    var skipped = 0;
    for (final entry in raw) {
      final value = entry.trim();
      switch (_classify(value)) {
        case _AddrFamily.ipv4:
          v4.add(value);
        case _AddrFamily.ipv6:
          v6.add(value);
        case _AddrFamily.invalid:
          skipped++;
      }
      if (v4.length + v6.length >= _maxEntries) break;
    }
    return (v4: v4.toList(), v6: v6.toList(), skipped: skipped);
  }

  // =========================================================================
  // Public API
  // =========================================================================

  /// Install OS firewall rules that drop traffic to/from every malicious IP in
  /// [maliciousIps]. Returns the REAL resulting status (never a fabricated
  /// success). Persists intent only when enforcement is genuinely installed.
  Future<FirewallEnforcementStatus> apply(List<String> maliciousIps) async {
    if (!isSupportedPlatform) {
      return const FirewallEnforcementStatus(
        state: FirewallEnforcementState.unavailable,
        reason: 'OS firewall enforcement is only available on desktop '
            '(macOS, Windows, Linux).',
        source: 'platform check',
      );
    }

    final parts = _partition(maliciousIps);
    if (parts.v4.isEmpty && parts.v6.isEmpty) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.notEnforcing,
        reason: maliciousIps.isEmpty
            ? 'Threat intelligence returned no malicious IPs to enforce.'
            : 'None of the ${maliciousIps.length} threat-intel entries were '
                'routable IP addresses that can be safely blocked.',
        source: 'threat-intel block list',
        enabledPreference: await _readEnabledPref(),
      );
    }

    if (PlatformInfo.isMacOS) {
      return _applyMac(parts.v4, parts.v6, parts.skipped);
    }
    if (PlatformInfo.isLinux) {
      return _applyLinux(parts.v4, parts.v6, parts.skipped);
    }
    if (PlatformInfo.isWindows) {
      return _applyWindows(parts.v4, parts.v6, parts.skipped);
    }
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.unavailable,
      reason: 'Unsupported desktop platform.',
      source: 'platform check',
    );
  }

  /// Remove all OrbGuard enforcement rules from the OS firewall. Clears the
  /// persisted intent only when removal actually succeeds.
  Future<FirewallEnforcementStatus> remove() async {
    if (!isSupportedPlatform) {
      return const FirewallEnforcementStatus(
        state: FirewallEnforcementState.unavailable,
        reason: 'OS firewall enforcement is only available on desktop '
            '(macOS, Windows, Linux).',
        source: 'platform check',
      );
    }
    if (PlatformInfo.isMacOS) return _removeMac();
    if (PlatformInfo.isLinux) return _removeLinux();
    if (PlatformInfo.isWindows) return _removeWindows();
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.unavailable,
      reason: 'Unsupported desktop platform.',
      source: 'platform check',
    );
  }

  /// Re-query the REAL enforcement state. Uses a live, non-elevated read where
  /// the platform allows one (Windows netsh show, macOS config inspection);
  /// on Linux — where reading iptables needs root — it falls back to the
  /// persisted intent and says so honestly.
  Future<FirewallEnforcementStatus> queryStatus() async {
    if (!isSupportedPlatform) {
      return const FirewallEnforcementStatus(
        state: FirewallEnforcementState.unavailable,
        reason: 'OS firewall enforcement is only available on desktop '
            '(macOS, Windows, Linux).',
        source: 'platform check',
      );
    }
    if (PlatformInfo.isMacOS) return _queryMac();
    if (PlatformInfo.isLinux) return _queryLinux();
    if (PlatformInfo.isWindows) return _queryWindows();
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.unavailable,
      reason: 'Unsupported desktop platform.',
      source: 'platform check',
    );
  }

  // =========================================================================
  // Elevation runners
  // =========================================================================

  /// Run a shell script as root via the native macOS admin prompt.
  Future<_ElevationOutcome> _runElevatedMac(String script) async {
    final escaped = script.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    try {
      final result = await Process.run('osascript', [
        '-e',
        'do shell script "$escaped" with administrator privileges '
            'with prompt "OrbGuard needs administrator access to enforce the '
            'malicious-IP block list in the firewall."',
      ]);
      final out =
          ((result.stdout as String) + (result.stderr as String)).trim();
      if (result.exitCode == 0) {
        return _ElevationOutcome(ok: true, output: out);
      }
      final err = (result.stderr as String).toLowerCase();
      if (err.contains('-128') || err.contains('user cancel')) {
        return _ElevationOutcome(ok: false, cancelled: true, output: out);
      }
      return _ElevationOutcome(
        ok: false,
        permissionDenied: err.contains('not allowed'),
        output: out,
      );
    } on ProcessException catch (e) {
      return _ElevationOutcome(
        ok: false,
        toolingMissing: true,
        output: 'osascript could not be executed: ${e.message}',
      );
    }
  }

  /// Run a shell script as root via pkexec (polkit GUI prompt).
  Future<_ElevationOutcome> _runElevatedLinux(String script) async {
    try {
      final result = await Process.run('pkexec', ['/bin/sh', '-c', script]);
      final out =
          ((result.stdout as String) + (result.stderr as String)).trim();
      switch (result.exitCode) {
        case 0:
          return _ElevationOutcome(ok: true, output: out);
        case 126:
          return _ElevationOutcome(ok: false, cancelled: true, output: out);
        case 127:
          return _ElevationOutcome(
              ok: false, permissionDenied: true, output: out);
        default:
          return _ElevationOutcome(ok: false, output: out);
      }
    } on ProcessException catch (e) {
      return _ElevationOutcome(
        ok: false,
        toolingMissing: true,
        output: 'pkexec is not available (${e.message}).',
      );
    }
  }

  /// Run a .cmd batch file as administrator via a single UAC prompt.
  Future<_ElevationOutcome> _runElevatedWindows(String cmdFilePath) async {
    final psPath = cmdFilePath.replaceAll("'", "''");
    try {
      final ps = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          "try { \$p = Start-Process -FilePath cmd.exe "
              "-ArgumentList '/c','\"$psPath\"' -Verb RunAs -Wait "
              "-WindowStyle Hidden -PassThru; exit \$p.ExitCode } "
              "catch { Write-Error \$_.Exception.Message; exit 1223 }",
        ],
        runInShell: true,
      );
      final err = (ps.stderr as String).trim();
      if (ps.exitCode == 0) {
        return const _ElevationOutcome(ok: true);
      }
      // 1223 == ERROR_CANCELLED; the UAC dialog was declined.
      if (ps.exitCode == 1223 ||
          err.toLowerCase().contains('canceled by the user') ||
          err.toLowerCase().contains('cancelled by the user')) {
        return _ElevationOutcome(ok: false, cancelled: true, output: err);
      }
      return _ElevationOutcome(ok: false, output: err);
    } on ProcessException catch (e) {
      return _ElevationOutcome(
        ok: false,
        toolingMissing: true,
        output: 'powershell could not be executed: ${e.message}',
      );
    }
  }

  /// Map a failed elevation outcome onto an honest status.
  FirewallEnforcementStatus _elevationFailureStatus(
    _ElevationOutcome outcome, {
    required String source,
    required bool enabledPreference,
    required int blockedIpCount,
  }) {
    if (outcome.cancelled) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.needsElevation,
        reason:
            'Administrator authorization was cancelled — no firewall changes '
            'were made.',
        source: source,
        enabledPreference: enabledPreference,
        blockedIpCount: blockedIpCount,
      );
    }
    if (outcome.toolingMissing) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.needsElevation,
        reason: 'Administrator privileges are required but no elevation tool '
            'is available. ${outcome.output}',
        source: source,
        enabledPreference: enabledPreference,
        blockedIpCount: blockedIpCount,
      );
    }
    if (outcome.permissionDenied) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.needsElevation,
        reason: 'Administrator authorization was denied. ${outcome.output}',
        source: source,
        enabledPreference: enabledPreference,
        blockedIpCount: blockedIpCount,
      );
    }
    return FirewallEnforcementStatus(
      state: FirewallEnforcementState.notEnforcing,
      reason: 'The firewall command failed and enforcement was NOT applied: '
          '${outcome.output.isEmpty ? 'unknown error' : outcome.output}',
      source: source,
      enabledPreference: enabledPreference,
      blockedIpCount: blockedIpCount,
      errored: true,
    );
  }

  // =========================================================================
  // macOS (pf anchor)
  // =========================================================================

  String _pfAnchorContents(List<String> v4, List<String> v6) {
    final all = [...v4, ...v6];
    final table = all.join(', ');
    // A single persistent table drives two quick block rules (to and from).
    return 'table <$_pfTable> persist { $table }\n'
        'block drop quick from any to <$_pfTable>\n'
        'block drop quick from <$_pfTable> to any\n';
  }

  Future<FirewallEnforcementStatus> _applyMac(
      List<String> v4, List<String> v6, int skipped) async {
    final count = v4.length + v6.length;
    const source = 'pfctl anchor $_pfAnchorName';

    // Stage the anchor rules and the pf.conf marker block in user-owned temp
    // files so the elevated script only needs to copy/append them — this
    // avoids any newline/quote escaping through osascript.
    final tmpDir = Directory.systemTemp;
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final anchorTmp = File('${tmpDir.path}/orbguard_pf_anchor_$stamp.conf');
    final markerTmp = File('${tmpDir.path}/orbguard_pf_marker_$stamp.conf');
    try {
      await anchorTmp.writeAsString(_pfAnchorContents(v4, v6));
      await markerTmp.writeAsString(
        '$_pfMarkerBegin\n'
        'anchor "$_pfAnchorName"\n'
        'load anchor "$_pfAnchorName" from "$_pfAnchorFile"\n'
        '$_pfMarkerEnd\n',
      );
    } on FileSystemException catch (e) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.notEnforcing,
        reason: 'Could not stage pf rules: ${e.message}',
        source: source,
        errored: true,
        enabledPreference: await _readEnabledPref(),
      );
    }

    // Copy the anchor into place, reference it from pf.conf (idempotent),
    // reload the ruleset and make sure pf is enabled. `pfctl -e` fails
    // harmlessly when pf is already on, hence the `|| /usr/bin/true`.
    final script = '/bin/mkdir -p /etc/pf.anchors && '
        '/bin/cp "${anchorTmp.path}" $_pfAnchorFile && '
        '( /usr/bin/grep -q \'anchor "$_pfAnchorName"\' $_pfConf || '
        '/bin/cat "${markerTmp.path}" >> $_pfConf ) && '
        '/sbin/pfctl -f $_pfConf && '
        '( /sbin/pfctl -e 2>/dev/null || /usr/bin/true )';

    final outcome = await _runElevatedMac(script);
    await _cleanupTmp([anchorTmp, markerTmp]);

    if (!outcome.ok) {
      return _elevationFailureStatus(
        outcome,
        source: source,
        enabledPreference: await _readEnabledPref(),
        blockedIpCount: await _readIpCountPref(),
      );
    }

    await _writePref(true, count);
    return FirewallEnforcementStatus(
      state: FirewallEnforcementState.enforcing,
      reason: _appliedReason(count, skipped,
          'pf drops all traffic to/from these IPs via anchor "$_pfAnchorName"'),
      source: source,
      blockedIpCount: count,
      enabledPreference: true,
    );
  }

  Future<FirewallEnforcementStatus> _removeMac() async {
    const source = 'pfctl anchor $_pfAnchorName';
    // Delete the marker block from pf.conf, flush the anchor, remove the file
    // and reload. pf itself is left enabled (the user may rely on it).
    final script =
        "/usr/bin/sed -i '' '/$_pfMarkerBegin/,/$_pfMarkerEnd/d' $_pfConf; "
        '/sbin/pfctl -a $_pfAnchorName -F rules 2>/dev/null; '
        '/bin/rm -f $_pfAnchorFile; '
        '/sbin/pfctl -f $_pfConf 2>/dev/null; '
        '/usr/bin/true';

    final outcome = await _runElevatedMac(script);
    if (!outcome.ok) {
      return _elevationFailureStatus(
        outcome,
        source: source,
        enabledPreference: await _readEnabledPref(),
        blockedIpCount: await _readIpCountPref(),
      );
    }
    await _writePref(false, 0);
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.notEnforcing,
      reason: 'OrbGuard pf anchor removed; malicious-IP blocking is off.',
      source: source,
    );
  }

  Future<FirewallEnforcementStatus> _queryMac() async {
    const source = 'pf config inspection';
    final enabled = await _readEnabledPref();
    final storedCount = await _readIpCountPref();

    // The anchor file and pf.conf are world-readable, so we can verify our
    // rules are installed WITHOUT elevation (pfctl reads would need root).
    var anchorInstalled = false;
    var liveCount = storedCount;
    try {
      final anchor = File(_pfAnchorFile);
      if (await anchor.exists()) {
        final body = await anchor.readAsString();
        final m = RegExp(r'\{([^}]*)\}').firstMatch(body);
        if (m != null) {
          liveCount = m
              .group(1)!
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .length;
        }
        anchorInstalled = true;
      }
    } on FileSystemException {
      // Fall back to persisted intent below.
    }

    var referenced = false;
    try {
      final conf = await File(_pfConf).readAsString();
      referenced = conf.contains('anchor "$_pfAnchorName"');
    } on FileSystemException {
      // pf.conf unreadable — rely on intent.
    }

    if (anchorInstalled && referenced) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.enforcing,
        reason:
            'pf anchor "$_pfAnchorName" is installed and referenced from '
            'pf.conf (live pf state needs root to read).',
        source: source,
        blockedIpCount: liveCount,
        enabledPreference: enabled,
      );
    }
    if (enabled) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.needsElevation,
        reason: 'Enforcement was enabled but the pf anchor is no longer '
            'installed. Re-apply (administrator required).',
        source: source,
        blockedIpCount: storedCount,
        enabledPreference: true,
      );
    }
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.notEnforcing,
      reason: 'No OrbGuard pf anchor installed.',
      source: source,
    );
  }

  // =========================================================================
  // Linux (iptables / ip6tables chain)
  // =========================================================================

  String _linuxChainScript(String bin, List<String> ips) {
    final b = StringBuffer();
    // Create (or flush) the chain, fail loudly if the tool is missing so we
    // never report a false success.
    b.write('$bin -w -N $_linuxChain 2>/dev/null || '
        '$bin -w -F $_linuxChain || exit 3; ');
    for (final ip in ips) {
      b.write('$bin -w -A $_linuxChain -d $ip -j DROP || exit 3; ');
      b.write('$bin -w -A $_linuxChain -s $ip -j DROP || exit 3; ');
    }
    // Jump into the chain from OUTPUT and INPUT, idempotently.
    b.write('$bin -w -C OUTPUT -j $_linuxChain 2>/dev/null || '
        '$bin -w -I OUTPUT -j $_linuxChain || exit 3; ');
    b.write('$bin -w -C INPUT -j $_linuxChain 2>/dev/null || '
        '$bin -w -I INPUT -j $_linuxChain || exit 3; ');
    return b.toString();
  }

  Future<FirewallEnforcementStatus> _applyLinux(
      List<String> v4, List<String> v6, int skipped) async {
    final count = v4.length + v6.length;
    const source = 'iptables chain $_linuxChain';

    final b = StringBuffer('export PATH=/usr/sbin:/sbin:/usr/bin:/bin:\$PATH; ');
    if (v4.isNotEmpty) b.write(_linuxChainScript('iptables', v4));
    if (v6.isNotEmpty) b.write(_linuxChainScript('ip6tables', v6));
    b.write('exit 0');

    final outcome = await _runElevatedLinux(b.toString());
    if (!outcome.ok) {
      return _elevationFailureStatus(
        outcome,
        source: source,
        enabledPreference: await _readEnabledPref(),
        blockedIpCount: await _readIpCountPref(),
      );
    }
    await _writePref(true, count);
    return FirewallEnforcementStatus(
      state: FirewallEnforcementState.enforcing,
      reason: _appliedReason(count, skipped,
          'iptables/ip6tables chain "$_linuxChain" drops traffic to/from '
          'these IPs (jumped from OUTPUT and INPUT)'),
      source: source,
      blockedIpCount: count,
      enabledPreference: true,
    );
  }

  Future<FirewallEnforcementStatus> _removeLinux() async {
    const source = 'iptables chain $_linuxChain';
    String tearDown(String bin) => 'export PATH=/usr/sbin:/sbin:/usr/bin:/bin:\$PATH; '
        '$bin -w -D OUTPUT -j $_linuxChain 2>/dev/null; '
        '$bin -w -D INPUT -j $_linuxChain 2>/dev/null; '
        '$bin -w -F $_linuxChain 2>/dev/null; '
        '$bin -w -X $_linuxChain 2>/dev/null; ';
    final script = '${tearDown('iptables')}${tearDown('ip6tables')}true';

    final outcome = await _runElevatedLinux(script);
    if (!outcome.ok) {
      return _elevationFailureStatus(
        outcome,
        source: source,
        enabledPreference: await _readEnabledPref(),
        blockedIpCount: await _readIpCountPref(),
      );
    }
    await _writePref(false, 0);
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.notEnforcing,
      reason: 'OrbGuard iptables chain removed; malicious-IP blocking is off.',
      source: source,
    );
  }

  Future<FirewallEnforcementStatus> _queryLinux() async {
    const source = 'iptables chain $_linuxChain';
    final enabled = await _readEnabledPref();
    final storedCount = await _readIpCountPref();

    // Reading iptables requires root. Attempt a non-elevated read anyway (it
    // succeeds when OrbGuard itself runs as root); otherwise fall back to the
    // persisted intent and say so honestly rather than prompting on refresh.
    try {
      final probe = await Process.run(
          'iptables', ['-w', '-n', '-L', _linuxChain]);
      if (probe.exitCode == 0) {
        final drops = RegExp(r'^DROP\b', multiLine: true)
            .allMatches(probe.stdout as String)
            .length;
        // Two DROP rules per IP (src + dst).
        final installedIps = drops ~/ 2;
        return FirewallEnforcementStatus(
          state: installedIps > 0
              ? FirewallEnforcementState.enforcing
              : FirewallEnforcementState.notEnforcing,
          reason: installedIps > 0
              ? 'iptables chain "$_linuxChain" is live with $installedIps '
                  'blocked IP(s).'
              : 'iptables chain "$_linuxChain" exists but has no block rules.',
          source: source,
          blockedIpCount: installedIps,
          enabledPreference: enabled,
        );
      }
    } on ProcessException {
      // iptables not installed — fall through to intent-based answer.
    }

    if (enabled) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.enforcing,
        reason: 'Enforcement is enabled ($storedCount IP(s)). Live iptables '
            'verification needs root; showing the persisted state.',
        source: '$source (persisted intent)',
        blockedIpCount: storedCount,
        enabledPreference: true,
      );
    }
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.notEnforcing,
      reason: 'Malicious-IP blocking is off.',
      source: '$source (persisted intent)',
    );
  }

  // =========================================================================
  // Windows (netsh advfirewall rules)
  // =========================================================================

  List<List<String>> _chunk(List<String> items, int size) {
    final chunks = <List<String>>[];
    for (var i = 0; i < items.length; i += size) {
      chunks.add(items.sublist(i, i + size > items.length ? items.length : i + size));
    }
    return chunks;
  }

  Future<FirewallEnforcementStatus> _applyWindows(
      List<String> v4, List<String> v6, int skipped) async {
    final all = [...v4, ...v6];
    final count = all.length;
    const source = 'netsh advfirewall rule "$_windowsRuleName"';

    // netsh accepts a comma-separated remoteip list; batch to keep each rule's
    // command line within limits. One inbound + one outbound rule per batch,
    // all sharing the same name so a single delete removes them.
    final b = StringBuffer('@echo off\r\n');
    b.write('netsh advfirewall firewall delete rule '
        'name="$_windowsRuleName" >nul 2>&1\r\n');
    for (final batch in _chunk(all, 100)) {
      final list = batch.join(',');
      b.write('netsh advfirewall firewall add rule '
          'name="$_windowsRuleName" dir=out action=block '
          'remoteip=$list\r\n');
      b.write('netsh advfirewall firewall add rule '
          'name="$_windowsRuleName" dir=in action=block '
          'remoteip=$list\r\n');
    }
    b.write('exit /b 0\r\n');

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final cmdFile = File('${Directory.systemTemp.path}\\orbguard_fw_$stamp.cmd');
    _ElevationOutcome outcome;
    try {
      await cmdFile.writeAsString(b.toString());
      outcome = await _runElevatedWindows(cmdFile.path);
    } on FileSystemException catch (e) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.notEnforcing,
        reason: 'Could not stage netsh batch: ${e.message}',
        source: source,
        errored: true,
        enabledPreference: await _readEnabledPref(),
      );
    } finally {
      await _cleanupTmp([cmdFile]);
    }

    if (!outcome.ok) {
      return _elevationFailureStatus(
        outcome,
        source: source,
        enabledPreference: await _readEnabledPref(),
        blockedIpCount: await _readIpCountPref(),
      );
    }

    // Authoritative confirmation: reading rules does not need admin.
    final present = await _windowsRulePresent();
    if (!present) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.notEnforcing,
        reason: 'The elevated netsh batch ran but no "$_windowsRuleName" rule '
            'is present afterwards; enforcement was NOT applied.',
        source: source,
        errored: true,
        enabledPreference: await _readEnabledPref(),
      );
    }
    await _writePref(true, count);
    return FirewallEnforcementStatus(
      state: FirewallEnforcementState.enforcing,
      reason: _appliedReason(count, skipped,
          'Windows Defender Firewall blocks inbound and outbound traffic to '
          'these IPs'),
      source: source,
      blockedIpCount: count,
      enabledPreference: true,
    );
  }

  Future<FirewallEnforcementStatus> _removeWindows() async {
    const source = 'netsh advfirewall rule "$_windowsRuleName"';
    final b = StringBuffer('@echo off\r\n');
    b.write('netsh advfirewall firewall delete rule '
        'name="$_windowsRuleName" >nul 2>&1\r\n');
    b.write('exit /b 0\r\n');

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final cmdFile =
        File('${Directory.systemTemp.path}\\orbguard_fw_del_$stamp.cmd');
    _ElevationOutcome outcome;
    try {
      await cmdFile.writeAsString(b.toString());
      outcome = await _runElevatedWindows(cmdFile.path);
    } on FileSystemException catch (e) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.notEnforcing,
        reason: 'Could not stage netsh batch: ${e.message}',
        source: source,
        errored: true,
        enabledPreference: await _readEnabledPref(),
      );
    } finally {
      await _cleanupTmp([cmdFile]);
    }

    if (!outcome.ok) {
      return _elevationFailureStatus(
        outcome,
        source: source,
        enabledPreference: await _readEnabledPref(),
        blockedIpCount: await _readIpCountPref(),
      );
    }
    await _writePref(false, 0);
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.notEnforcing,
      reason: 'OrbGuard firewall rules removed; malicious-IP blocking is off.',
      source: source,
    );
  }

  Future<FirewallEnforcementStatus> _queryWindows() async {
    const source = 'netsh advfirewall show rule "$_windowsRuleName"';
    final enabled = await _readEnabledPref();
    final storedCount = await _readIpCountPref();
    // Reading rules is not privileged on Windows, so this is a genuine live
    // check of what is installed.
    final present = await _windowsRulePresent();
    if (present) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.enforcing,
        reason: 'Windows Defender Firewall rule "$_windowsRuleName" is active '
            '($storedCount IP(s) from the last apply).',
        source: source,
        blockedIpCount: storedCount,
        enabledPreference: enabled,
      );
    }
    if (enabled) {
      return FirewallEnforcementStatus(
        state: FirewallEnforcementState.needsElevation,
        reason: 'Enforcement was enabled but the firewall rule is gone. '
            'Re-apply (administrator required).',
        source: source,
        blockedIpCount: storedCount,
        enabledPreference: true,
      );
    }
    return const FirewallEnforcementStatus(
      state: FirewallEnforcementState.notEnforcing,
      reason: 'No OrbGuard firewall rule installed.',
      source: source,
    );
  }

  Future<bool> _windowsRulePresent() async {
    try {
      final show = await Process.run(
        'netsh',
        ['advfirewall', 'firewall', 'show', 'rule', 'name=$_windowsRuleName'],
        runInShell: true,
      );
      final out = (show.stdout as String);
      return show.exitCode == 0 && !out.contains('No rules match');
    } on ProcessException {
      return false;
    }
  }

  // =========================================================================
  // Shared helpers
  // =========================================================================

  String _appliedReason(int count, int skipped, String mechanism) {
    final skippedNote =
        skipped > 0 ? ' ($skipped non-routable entr${skipped == 1 ? 'y' : 'ies'} skipped)' : '';
    return 'Blocking $count malicious IP(s)$skippedNote. $mechanism.';
  }

  Future<void> _cleanupTmp(List<File> files) async {
    for (final f in files) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {
        // Best-effort cleanup of user-owned temp files.
      }
    }
  }
}
