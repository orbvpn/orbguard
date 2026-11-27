// A computer's check: the six areas of its Desktop Security page, run for
// real and reported the way the phone engine reports its stages, so Home
// draws it in the ring with the same `CheckRun`.
//
// Each area reads what `DesktopSecurityProvider` reads for its tab, and this
// turns that reading into what the check may say. The honesty rules:
//  - an area ran only on something it really read; one that read nothing, or
//    broke, could not run, and is never counted as passed
//  - an area this computer cannot run (no code signing on Linux, no browser
//    it can read, what a sandboxed Mac app is not let see) is not possible
//    here, which is never passed either
//  - what it found is said once, in the app's words, and only what the
//    reading shows
//
// The platform is given, never read from the host, so every rule is covered
// by a test on any machine.
library;

import 'dart:async';
import 'dart:io' show Platform, pid;

import 'package:flutter/foundation.dart';

import '../../providers/desktop_security_provider.dart';
import '../security/desktop_host_collector.dart' show isPublicRoutableIp;
import '../security/device_scan_service.dart';
import 'check_plan.dart';
import 'check_run.dart';

/// The apps whose signatures were verified, or why this computer cannot
/// verify any.
typedef CodeSigningReading = ({
  List<Map<String, dynamic>> apps,
  String? unavailable,
});

/// The connections that were read, and what went wrong reading or looking
/// them up.
typedef NetworkReading = ({
  List<Map<String, dynamic>> connections,
  List<String> errors,
});

/// Where the six areas are read from: the same reads the Desktop Security
/// tabs make.
abstract class ComputerSource {
  /// The app runs in the macOS App Sandbox, which keeps it from seeing most
  /// of the system.
  bool get sandboxed;

  /// This app's own process id.
  int get ownPid;

  Future<DesktopScanResult> startupItems();
  Future<CodeSigningReading> codeSigning();
  Future<HostFirewallStatus> firewall();
  Future<NetworkReading> network();

  /// The provider's browser scan: `extensions`, `errors` and `looked`.
  Future<Map<String, dynamic>?> browsers();

  /// Throws when the quarantine could not be read.
  Future<List<QuarantinedItem>> quarantine();
}

/// The six areas as the app's own [DesktopSecurityProvider] reads them. Its
/// tabs show what the last check read.
class ProviderComputerSource implements ComputerSource {
  ProviderComputerSource(this.provider);

  final DesktopSecurityProvider provider;

  @override
  bool get sandboxed =>
      Platform.environment.containsKey('APP_SANDBOX_CONTAINER_ID');

  @override
  int get ownPid => pid;

  @override
  Future<DesktopScanResult> startupItems() => provider.runFullScan();

  @override
  Future<CodeSigningReading> codeSigning() async {
    await provider.verifyLocalCodeSigning();
    return (
      apps: provider.localSignedApps,
      unavailable: provider.codeSigningUnavailableReason,
    );
  }

  @override
  Future<HostFirewallStatus> firewall() => provider.refreshHostFirewallStatus();

  @override
  Future<NetworkReading> network() async {
    await provider.loadHostNetworkConnections();
    return (
      connections: provider.hostNetworkConnections,
      errors: provider.hostNetworkErrors,
    );
  }

  @override
  Future<Map<String, dynamic>?> browsers() async {
    await provider.loadHostBrowserExtensions();
    return provider.hostBrowserScan;
  }

  @override
  Future<List<QuarantinedItem>> quarantine() => provider.readQuarantinedItems();
}

/// What one area established: what it found, and null when it ran, or why
/// it did not.
typedef _Area = ({List<Map<String, dynamic>> findings, String? error});

class ComputerCheck {
  const ComputerCheck({
    required this.platform,
    required this.source,
    this.areaTimeout = const Duration(minutes: 3),
  });

  /// The computer being checked. It decides the words, and which areas it
  /// can run at all.
  final TargetPlatform platform;

  final ComputerSource source;

  /// How long one area may take before it counts as could not run, so a
  /// read that never answers cannot hold the ring open.
  final Duration areaTimeout;

  /// Runs the six areas in order, reporting each as it starts and ends, and
  /// completes with what they found. Each finding names its area as `stage`.
  Future<List<Map<String, dynamic>>> run(
      DeviceScanProgressCallback onProgress) async {
    const List<CheckStep> steps = CheckPlan.computer;
    final List<Future<_Area> Function()> areas = [
      _startupItems,
      _codeSigning,
      _firewall,
      _network,
      _browser,
      _quarantine,
    ];
    final List<Map<String, dynamic>> found = [];
    for (int i = 0; i < steps.length; i++) {
      onProgress(DeviceScanProgress(
        stageIndex: i,
        totalStages: steps.length,
        stageName: steps[i].stage,
        stageCompleted: false,
        threatsFound: found.length,
      ));
      _Area area;
      try {
        area = await areas[i]().timeout(areaTimeout);
      } on TimeoutException {
        area = _broke('Took longer than ${areaTimeout.inSeconds} seconds.');
      } on Object catch (e) {
        area = _broke('$e');
      }
      for (final Map<String, dynamic> f in area.findings) {
        found.add({...f, 'stage': steps[i].stage});
      }
      debugPrint('[OrbGuard] ${steps[i].stage}: '
          '${area.error ?? 'ran'}, ${area.findings.length} found');
      onProgress(DeviceScanProgress(
        stageIndex: i,
        totalStages: steps.length,
        stageName: steps[i].stage,
        stageCompleted: true,
        threatsFound: found.length,
        stageError: area.error,
      ));
    }
    return found;
  }

  /// The tab of the Desktop Security page that shows [stage]'s details, or
  /// null for a stage that is not one of the six.
  static int? tabOf(String stage) {
    final int at = CheckPlan.computer.indexWhere((s) => s.stage == stage);
    return at < 0 ? null : at;
  }

  /// Whether [finding] came from one of the six areas.
  static bool isComputerFinding(Map<String, dynamic> finding) {
    final Object? stage = finding['stage'];
    return stage is String && tabOf(stage) != null;
  }

  /// How much of the computer [outcome] could look at, 0 to 100: the share
  /// of the six areas that ran.
  static int coverageOf(CheckOutcome outcome) {
    final int ran = outcome.ran.where((s) => tabOf(s) != null).length;
    return (100 * ran / CheckPlan.computer.length).round();
  }

  // ── How each area reads ────────────────────────────────────────────────

  /// A sandboxed Mac app is kept from what most areas read. Seeing nothing
  /// there is the sandbox, which no second try changes.
  bool get _boxed => platform == TargetPlatform.macOS && source.sandboxed;

  static const _Area _clean = (findings: [], error: null);
  static const _Area _cannot =
      (findings: [], error: DeviceScanService.notSupported);

  static _Area _broke(String why) => (
        findings: const [],
        error: why.trim().isEmpty ? 'Could not run.' : why.trim(),
      );

  static _Area _found(List<Map<String, dynamic>> findings) =>
      (findings: findings, error: null);

  /// Every computer starts things at login of its own, so a scan that saw
  /// none saw nothing.
  ///
  /// On a Mac, nothing on the system volume is reported. Apple seals that
  /// volume and it is read only, so nothing can be added there or changed.
  /// Some of Apple's own daemons there are shell scripts, which carry no
  /// signature, and the scanner would rate them high.
  Future<_Area> _startupItems() async {
    final DesktopScanResult scan = await source.startupItems();
    if (scan.items.isEmpty) {
      if (_boxed) return _cannot;
      return _broke(scan.errors.isEmpty
          ? 'No startup item could be read.'
          : scan.errors.first);
    }
    return _found([
      for (final DesktopPersistenceItem item in scan.items)
        if (item.risk.level >= DesktopItemRisk.medium.level &&
            !(platform == TargetPlatform.macOS &&
                item.path.startsWith('/System/')))
          {
            'id': 'desktop-startup-${item.id}',
            'name': _plain(item.name),
            'description': _plain('${item.typeDisplayName}. '
                '${item.indicators.isEmpty ? item.risk.description : item.indicators.map(_bare).join(', ')}.'),
            // On a Mac a startup item rates high for its signature alone.
            // No signature is common for tools a person installs (Homebrew
            // services, for one), so it is medium there; a known bad item
            // is critical, and a broken signature stays high.
            'severity': switch (item.risk) {
              DesktopItemRisk.critical => 'CRITICAL',
              DesktopItemRisk.high
                  when !(platform == TargetPlatform.macOS &&
                      item.signingStatus == 'Unsigned') =>
                'HIGH',
              _ => 'MEDIUM',
            },
            'type': 'desktop_startup',
            'path': item.path,
          },
    ]);
  }

  /// A broken signature is a sign an app was changed. No signature is not,
  /// so those apps are named together, quietly.
  Future<_Area> _codeSigning() async {
    final CodeSigningReading reading = await source.codeSigning();
    if (reading.unavailable != null) return _cannot;
    final List<Map<String, dynamic>> apps = reading.apps;
    // Every Mac and PC has signed software of its own. When none reads as
    // signed, the signatures were not read.
    if (!apps.any((a) => a['is_signed'] == true)) {
      if (_boxed) return _cannot;
      return _broke(apps.isEmpty
          ? 'No app signature could be read.'
          : 'No app read as signed, so the signatures were not read.');
    }
    final List<Map<String, dynamic>> unsigned = [
      for (final a in apps)
        if (a['is_signed'] != true) a,
    ];
    final int n = unsigned.length;
    return _found([
      for (final a in apps)
        if (a['is_signed'] == true && a['is_valid'] != true)
          {
            'id': 'desktop-signature-${a['path']}',
            'name': _plain('The signature of ${_appName(a)} does not check '
                'out'),
            'description': 'The system could not confirm who made it, or '
                'that it has not been changed since. Make sure you trust '
                'where it came from.',
            'severity': 'MEDIUM',
            'type': 'desktop_signing',
            'path': '${a['path'] ?? ''}',
          },
      if (n > 0)
        {
          'id': 'desktop-unsigned',
          'name': n == 1
              ? _plain('${_appName(unsigned.single)} is not signed')
              : '$n apps are not signed',
          'description': n == 1
              ? 'Nobody vouches for who made it. Make sure you installed it '
                  'yourself.'
              : 'Nobody vouches for who made them. Make sure you installed '
                  'them yourself.',
          'severity': 'LOW',
          'type': 'desktop_signing',
          'path': n == 1 ? '${unsigned.single['path'] ?? ''}' : 'unsigned',
        },
    ]);
  }

  Future<_Area> _firewall() async {
    final HostFirewallStatus status = await source.firewall();
    switch (status.state) {
      case HostFirewallState.enabled:
        return _clean;
      case HostFirewallState.disabled:
        return _found([
          {
            'id': 'desktop-firewall-off',
            'name': switch (platform) {
              TargetPlatform.macOS => 'macOS Firewall is off',
              TargetPlatform.windows => 'Windows Firewall is off',
              _ => 'The system firewall is off',
            },
            'description': 'Any app on this ${_noun()} can accept '
                'connections from other devices on your network.'
                '${switch (platform) {
              TargetPlatform.macOS =>
                ' You can turn it on in System Settings, under Network.',
              TargetPlatform.windows =>
                ' You can turn it on in Windows Security.',
              _ => '',
            }}',
            'severity': 'LOW',
            'type': 'desktop_firewall',
            'path': 'firewall',
          },
        ]);
      case HostFirewallState.unknown:
        return _boxed ? _cannot : _broke(status.detail);
      case HostFirewallState.unavailable:
        // A Linux computer may have no firewall OrbGuard can read. A Mac and
        // a PC always have one, so there it broke.
        return platform == TargetPlatform.linux || _boxed
            ? _cannot
            : _broke(status.detail);
    }
  }

  Future<_Area> _network() async {
    final NetworkReading reading = await source.network();
    final List<Map<String, dynamic>> connections = reading.connections;
    if (connections.isEmpty) {
      if (_boxed) return _cannot;
      return _broke(reading.errors.isEmpty
          ? 'No connection could be read.'
          : reading.errors.first);
    }
    // A sandboxed app sees its own connections and nobody else's.
    if (_boxed && connections.every((c) => c['process_id'] == source.ownPid)) {
      return _cannot;
    }
    // Connections are judged by looking them up. With none looked up,
    // nothing was judged.
    final bool outward = connections
        .any((c) => isPublicRoutableIp('${c['remote_address'] ?? ''}'));
    if (outward && !connections.any((c) => c['vt_enriched'] == true)) {
      return _broke(reading.errors.firstWhere((e) => e.contains('VirusTotal'),
          orElse: () => 'The connections could not be looked up.'));
    }
    final Map<String, Map<String, dynamic>> bad = {};
    for (final Map<String, dynamic> c in connections) {
      if (c['is_known_bad'] != true) continue;
      bad.putIfAbsent('${c['remote_address']}', () => c);
    }
    return _found([
      for (final MapEntry<String, Map<String, dynamic>> e in bad.entries)
        {
          'id': 'desktop-network-${e.key}',
          'name': 'A connection to a known bad address',
          'description': _plain('${_processOf(e.value)} is connected to '
              '${e.key}, which threat intelligence lists as malicious.'),
          'severity': 'HIGH',
          'type': 'desktop_network',
          'path': e.key,
        },
    ]);
  }

  /// An extension that can read and change every site, and reach more
  /// besides, can watch what is done in the browser. Many useful ones can,
  /// so they are named together, quietly, for the person to look over.
  Future<_Area> _browser() async {
    final Map<String, dynamic>? scan = await source.browsers();
    if (scan == null) return _broke('The browsers could not be read.');
    final List<Map<String, dynamic>> extensions = [
      for (final Object? e in (scan['extensions'] as List?) ?? const [])
        if (e is Map) Map<String, dynamic>.from(e),
    ];
    final List<String> errors = [
      for (final Object? e in (scan['errors'] as List?) ?? const [])
        if (e is String) e,
    ];
    final List<Object?> looked = (scan['looked'] as List?) ?? const [];
    if (extensions.isEmpty && errors.isNotEmpty) {
      return _boxed ? _cannot : _broke(errors.first);
    }
    // No browser it can read is on this computer: nothing was looked at.
    if (extensions.isEmpty && looked.isEmpty) return _cannot;

    final List<Map<String, dynamic>> wide = [
      for (final Map<String, dynamic> e in extensions)
        if (e['risk_level'] == 'high' || e['risk_level'] == 'critical') e,
    ];
    if (wide.isEmpty) return _clean;
    final int n = wide.length;
    final String browser = '${wide.first['browser'] ?? 'browser'}';
    return _found([
      {
        'id': 'desktop-extensions',
        'name': n == 1
            ? _plain('${_extensionName(wide.single)} can read and change '
                'every site you visit')
            : '$n browser extensions can read and change every site you '
                'visit',
        'description': n == 1
            ? _plain('${_article(browser)} $browser extension. Remove it if '
                'you do not use it or do not recognise it.')
            : _plain('${_listed([for (final e in wide) _extensionName(e)])}. '
                'Remove any you do not use or do not recognise.'),
        'severity': 'LOW',
        'type': 'desktop_browser',
        'path': 'extensions',
      },
    ]);
  }

  /// What is in quarantine is already contained. The area runs when the
  /// quarantine can be read.
  Future<_Area> _quarantine() async {
    await source.quarantine();
    return _clean;
  }

  // ── Words ──────────────────────────────────────────────────────────────

  String _noun() => switch (platform) {
        TargetPlatform.macOS => 'Mac',
        TargetPlatform.windows => 'PC',
        _ => 'computer',
      };

  static String _appName(Map<String, dynamic> app) {
    final String name = '${app['name'] ?? ''}'.trim();
    return name.isEmpty ? 'an app' : name;
  }

  static String _extensionName(Map<String, dynamic> extension) {
    final String name = '${extension['name'] ?? ''}'.trim();
    return name.isEmpty ? 'An extension' : name;
  }

  static String _processOf(Map<String, dynamic> connection) {
    final String name = '${connection['process_name'] ?? ''}'.trim();
    return name.isEmpty ? 'An app' : name;
  }

  static String _article(String word) =>
      RegExp('^[AEIOUaeiou]').hasMatch(word) ? 'An' : 'A';

  /// "A", "A and B", "A, B and C".
  static String _listed(List<String> names) => names.length == 1
      ? names.single
      : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';

  /// A scanner's note without the full stop it may end with.
  static String _bare(String note) =>
      note.trim().replaceAll(RegExp(r'\.+$'), '');

  /// Words a scanner hands over, kept to the app's own punctuation: no long
  /// dashes and no dot joins.
  static String _plain(String words) => words
      .replaceAll(RegExp(r'\s*[\u2014\u2013\u00B7]\s*'), ', ')
      .replaceAll('..', '.');
}
