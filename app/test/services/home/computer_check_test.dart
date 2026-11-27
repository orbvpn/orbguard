// A computer is checked in six areas, the tabs of its Desktop Security page.
// These tests hold the engine that runs them to the honesty rules:
//  - an area runs only on what it really read; one that read nothing, or
//    broke, could not run and is never counted as passed
//  - an area this computer cannot run is not possible here, never passed
//  - what it found says what it is, in the app's words
//
// The platform is always passed in. Nothing here reads the host.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/providers/desktop_security_provider.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/check_run.dart';
import 'package:orbguard/services/home/computer_check.dart';
import 'package:orbguard/services/security/device_scan_service.dart';

DesktopPersistenceItem _item(String name,
        {DesktopItemRisk risk = DesktopItemRisk.safe,
        List<String> indicators = const [],
        String signing = 'Unknown',
        String? path}) =>
    DesktopPersistenceItem(
      id: name,
      name: name,
      path: path ?? '/Library/LaunchAgents/$name.plist',
      type: 'launchAgent',
      typeDisplayName: 'Launch Agent',
      risk: risk,
      signingStatus: signing,
      indicators: indicators,
    );

DesktopScanResult _scan(List<DesktopPersistenceItem> items,
        {List<String> errors = const []}) =>
    DesktopScanResult(
      platform: 'test',
      scannedAt: DateTime(2026, 11, 28),
      scanDuration: Duration.zero,
      totalItems: items.length,
      criticalItems: 0,
      highRiskItems: 0,
      mediumRiskItems: 0,
      safeItems: items.length,
      items: items,
      errors: errors,
    );

Map<String, dynamic> _app(String name,
        {bool signed = true, bool valid = true}) =>
    {
      'name': name,
      'path': '/Applications/$name.app',
      'is_signed': signed,
      'is_valid': valid,
    };

Map<String, dynamic> _connection(String remote,
        {int pid = 400,
        String process = 'Mail',
        bool? enriched,
        bool bad = false}) =>
    {
      'remote_address': remote,
      'process_id': pid,
      'process_name': process,
      if (enriched != null) 'vt_enriched': enriched,
      if (enriched == true) 'is_known_bad': bad,
    };

Map<String, dynamic> _extension(String name, String level,
        {String browser = 'Chrome'}) =>
    {
      'name': name,
      'browser': browser,
      'risk_level': level,
      'install_path': '/ext/$name',
    };

/// A computer as the provider reads it. Left alone, every area reads
/// something and finds nothing.
class FakeSource implements ComputerSource {
  FakeSource({
    this.sandboxed = false,
    this.ownPid = 100,
    DesktopScanResult? startup,
    CodeSigningReading? signing,
    HostFirewallStatus? firewallStatus,
    NetworkReading? net,
    Map<String, dynamic>? browserScan,
    List<QuarantinedItem>? quarantined,
    this.broken = const {},
  })  : _startup = startup ??
            _scan([_item('com.apple.mdworker'), _item('com.vendor.helper')]),
        _signing = signing ??
            (apps: [_app('Safari'), _app('Notes')], unavailable: null),
        _firewall = firewallStatus ??
            const HostFirewallStatus(
                state: HostFirewallState.enabled,
                detail: 'Firewall is enabled. (State = 1)',
                source: 'socketfilterfw'),
        _net = net ??
            (
              connections: [
                _connection('17.57.144.10', enriched: true),
                _connection('192.168.1.4'),
              ],
              errors: <String>[],
            ),
        _browsers = browserScan ??
            {
              'extensions': [_extension('Dark Reader', 'low')],
              'errors': <String>[],
              'looked': ['Chrome'],
            },
        _quarantined = quarantined ?? const [];

  @override
  final bool sandboxed;

  @override
  final int ownPid;

  /// Areas whose read throws, by stage.
  final Set<String> broken;

  final DesktopScanResult _startup;
  final CodeSigningReading _signing;
  final HostFirewallStatus _firewall;
  final NetworkReading _net;
  final Map<String, dynamic>? _browsers;
  final List<QuarantinedItem> _quarantined;

  final List<String> asked = [];

  Future<T> _read<T>(String stage, T value) async {
    asked.add(stage);
    if (broken.contains(stage)) throw StateError('$stage broke');
    return value;
  }

  @override
  Future<DesktopScanResult> startupItems() => _read('Startup items', _startup);

  @override
  Future<CodeSigningReading> codeSigning() => _read('Code signing', _signing);

  @override
  Future<HostFirewallStatus> firewall() => _read('Firewall', _firewall);

  @override
  Future<NetworkReading> network() => _read('Network', _net);

  @override
  Future<Map<String, dynamic>?> browsers() => _read('Browser', _browsers);

  @override
  Future<List<QuarantinedItem>> quarantine() =>
      _read('Quarantine', _quarantined);
}

/// What one run reported: the findings, and how each area ended.
class _Run {
  _Run(this.findings, this.reports);

  final List<Map<String, dynamic>> findings;
  final List<DeviceScanProgress> reports;

  /// stage to null (ran) or the reason it did not.
  Map<String, String?> get ends => {
        for (final r in reports.where((r) => r.stageCompleted))
          r.stageName: r.stageError,
      };

  List<Map<String, dynamic>> foundBy(String stage) => [
        for (final f in findings)
          if (f['stage'] == stage) f
      ];
}

Future<_Run> _check(
  FakeSource source, {
  TargetPlatform platform = TargetPlatform.macOS,
}) async {
  final List<DeviceScanProgress> reports = [];
  final List<Map<String, dynamic>> found =
      await ComputerCheck(platform: platform, source: source).run(reports.add);
  return _Run(found, reports);
}

void main() {
  test('reports the six areas in order, each started and then ended', () async {
    final _Run run = await _check(FakeSource());

    final List<String> stages = [
      for (final s in CheckPlan.computer) s.stage,
    ];
    expect(
      [for (final r in run.reports) '${r.stageName} ${r.stageCompleted}'],
      [
        for (final String s in stages) ...['$s false', '$s true'],
      ],
    );
    expect(run.reports.every((r) => r.totalStages == 6), isTrue);
    expect(run.ends.values, everyElement(isNull));
    expect(run.findings, isEmpty);
  });

  test('runs through CheckRun as six checks that ran clean', () async {
    final CheckRun check = CheckRun(
        plan: CheckPlan.computer, beat: Duration.zero, settle: Duration.zero);
    final CheckOutcome? outcome = await check.start(
        ComputerCheck(platform: TargetPlatform.windows, source: FakeSource())
            .run);

    expect(outcome!.ran, hasLength(6));
    expect(outcome.ranClean, hasLength(6));
    expect(outcome.notPossible, isEmpty);
    expect(outcome.failed, isEmpty);
    expect(ComputerCheck.coverageOf(outcome), 100);
  });

  test('an area that throws could not run, and the others still run', () async {
    final FakeSource source = FakeSource(broken: {'Firewall'});
    final _Run run = await _check(source);

    expect(run.ends['Firewall'], isNotNull);
    expect(run.ends['Firewall'], isNot(DeviceScanService.notSupported));
    expect(source.asked, hasLength(6));
    expect(run.ends.values.where((e) => e == null), hasLength(5));
  });

  group('startup items', () {
    test('a risky item is found, worded by what the scanner saw', () async {
      final _Run run = await _check(FakeSource(
        startup: _scan([
          _item('com.apple.mdworker'),
          _item('com.updater.agent',
              risk: DesktopItemRisk.high,
              indicators: ['Unsigned binary', 'Uses KeepAlive']),
          _item('com.maybe.fine', risk: DesktopItemRisk.low),
        ]),
      ));

      final List<Map<String, dynamic>> found = run.foundBy('Startup items');
      expect(found, hasLength(1));
      expect(found.single['name'], 'com.updater.agent');
      expect(found.single['severity'], 'HIGH');
      expect(found.single['description'],
          'Launch Agent. Unsigned binary, Uses KeepAlive.');
      expect(found.single['path'],
          '/Library/LaunchAgents/com.updater.agent.plist');
      expect(run.ends['Startup items'], isNull);
    });

    // A Mac rates a startup item high for no signature alone, and tools a
    // person installs (Homebrew services, for one) often have none.
    test('on a Mac, an item with no signature is medium, not high', () async {
      final _Run run = await _check(FakeSource(
        startup: _scan([
          _item('homebrew.mxcl.postgresql',
              risk: DesktopItemRisk.high,
              signing: 'Unsigned',
              indicators: ['Unsigned binary']),
          _item('com.changed.agent',
              risk: DesktopItemRisk.high,
              signing: 'Invalid',
              indicators: ['Signature does not check out']),
          _item('com.known.bad',
              risk: DesktopItemRisk.critical,
              signing: 'Unsigned',
              indicators: ['Unsigned binary', 'Matches known malware: bad']),
        ]),
      ));

      expect({
        for (final f in run.foundBy('Startup items')) f['name']: f['severity']
      }, {
        'homebrew.mxcl.postgresql': 'MEDIUM',
        'com.changed.agent': 'HIGH',
        'com.known.bad': 'CRITICAL',
      });
    });

    test('elsewhere, an item rated high stays high', () async {
      final _Run run = await _check(
          FakeSource(
            startup: _scan([
              _item('updater.bat',
                  risk: DesktopItemRisk.high, signing: 'Unsigned'),
            ]),
          ),
          platform: TargetPlatform.windows);

      expect(run.foundBy('Startup items').single['severity'], 'HIGH');
    });

    test('a scan that read nothing could not run, it is not clean', () async {
      final _Run run = await _check(FakeSource(
        startup:
            _scan(const [], errors: ['Scan error: Operation not permitted']),
      ));

      expect(run.ends['Startup items'], 'Scan error: Operation not permitted');
      expect(run.foundBy('Startup items'), isEmpty);
    });

    test('a scan that saw no item at all could not run either', () async {
      final _Run run = await _check(FakeSource(startup: _scan(const [])));

      expect(run.ends['Startup items'], isNotNull);
      expect(run.ends['Startup items'], isNot(DeviceScanService.notSupported));
    });

    test('a sandboxed Mac that cannot read them cannot run the area', () async {
      final _Run run = await _check(FakeSource(
        sandboxed: true,
        startup:
            _scan(const [], errors: ['Scan error: Operation not permitted']),
      ));

      expect(run.ends['Startup items'], DeviceScanService.notSupported);
    });

    // Seen on a real Mac: Apple's own disabled daemons there are shell
    // scripts, which carry no signature, so the scanner rates them high.
    // The system volume is sealed by Apple and read only: nothing can be
    // added to it or changed in it, so nothing there is reported.
    test('on a Mac, nothing on the sealed system volume is found', () async {
      final _Run run = await _check(FakeSource(
        startup: _scan([
          _item('org.net-snmp.snmpd',
              risk: DesktopItemRisk.high,
              indicators: ['Uses KeepAlive', 'Unsigned binary'],
              path: '/System/Library/LaunchDaemons/org.net-snmp.snmpd.plist'),
          _item('com.updater.agent',
              risk: DesktopItemRisk.high,
              indicators: ['Unsigned binary'],
              path: '/Library/LaunchDaemons/com.updater.agent.plist'),
        ]),
      ));

      expect(run.ends['Startup items'], isNull);
      expect([for (final f in run.foundBy('Startup items')) f['name']],
          ['com.updater.agent']);
    });

    test('elsewhere, a path that looks the same is still found', () async {
      final _Run run = await _check(
          FakeSource(
            startup: _scan([
              _item('agent',
                  risk: DesktopItemRisk.high, path: '/System/agent.service'),
            ]),
          ),
          platform: TargetPlatform.linux);

      expect(run.foundBy('Startup items'), hasLength(1));
    });
  });

  group('code signing', () {
    test('a broken signature is found, one app each', () async {
      final _Run run = await _check(FakeSource(
        signing: (
          apps: [_app('Safari'), _app('Zoomer', valid: false)],
          unavailable: null,
        ),
      ));

      final List<Map<String, dynamic>> found = run.foundBy('Code signing');
      expect(found, hasLength(1));
      expect(
          found.single['name'], 'The signature of Zoomer does not check out');
      expect(found.single['severity'], 'MEDIUM');
      expect(found.single['path'], '/Applications/Zoomer.app');
    });

    test('apps with no signature are found together, as one thing', () async {
      final _Run run = await _check(FakeSource(
        signing: (
          apps: [
            _app('Safari'),
            _app('Tool', signed: false, valid: false),
            _app('Other', signed: false, valid: false),
          ],
          unavailable: null,
        ),
      ));

      final List<Map<String, dynamic>> found = run.foundBy('Code signing');
      expect(found, hasLength(1));
      expect(found.single['name'], '2 apps are not signed');
      expect(found.single['severity'], 'LOW');
      expect(
          found.single['description'],
          'Nobody vouches for who made them. Make sure you installed them '
          'yourself.');
    });

    test('a computer with no code signing cannot run the area', () async {
      final _Run run = await _check(
        FakeSource(signing: (
          apps: const [],
          unavailable: 'Linux has no platform code-signing infrastructure',
        )),
        platform: TargetPlatform.linux,
      );

      expect(run.ends['Code signing'], DeviceScanService.notSupported);
    });

    test('verifying no app at all could not run', () async {
      final _Run run = await _check(
          FakeSource(signing: (apps: const [], unavailable: null)));

      expect(run.ends['Code signing'], isNotNull);
      expect(run.ends['Code signing'], isNot(DeviceScanService.notSupported));
    });
  });

  group('firewall', () {
    HostFirewallStatus status(HostFirewallState state) =>
        HostFirewallStatus(state: state, detail: 'detail', source: 'tool');

    test('a firewall that is on ran clean', () async {
      final _Run run = await _check(FakeSource());

      expect(run.ends['Firewall'], isNull);
      expect(run.foundBy('Firewall'), isEmpty);
    });

    test('a firewall that is off is found, named for the system', () async {
      final Map<TargetPlatform, String> names = {
        TargetPlatform.macOS: 'macOS Firewall is off',
        TargetPlatform.windows: 'Windows Firewall is off',
        TargetPlatform.linux: 'The system firewall is off',
      };
      for (final MapEntry<TargetPlatform, String> e in names.entries) {
        final _Run run = await _check(
            FakeSource(firewallStatus: status(HostFirewallState.disabled)),
            platform: e.key);

        final List<Map<String, dynamic>> found = run.foundBy('Firewall');
        expect(found, hasLength(1), reason: '${e.key}');
        expect(found.single['name'], e.value);
        expect(found.single['severity'], 'LOW');
        expect(run.ends['Firewall'], isNull);
      }
    });

    test('a state that could not be read could not run', () async {
      final _Run run = await _check(
          FakeSource(firewallStatus: status(HostFirewallState.unknown)));

      expect(run.ends['Firewall'], 'detail');
      expect(run.foundBy('Firewall'), isEmpty);
    });

    test('Linux with no firewall to read cannot run the area', () async {
      final _Run run = await _check(
          FakeSource(firewallStatus: status(HostFirewallState.unavailable)),
          platform: TargetPlatform.linux);

      expect(run.ends['Firewall'], DeviceScanService.notSupported);
    });

    test('a Mac whose firewall tool would not start could not run', () async {
      final _Run run = await _check(
          FakeSource(firewallStatus: status(HostFirewallState.unavailable)));

      expect(run.ends['Firewall'], 'detail');
    });

    test('a sandboxed Mac that cannot read it cannot run the area', () async {
      final _Run run = await _check(FakeSource(
          sandboxed: true, firewallStatus: status(HostFirewallState.unknown)));

      expect(run.ends['Firewall'], DeviceScanService.notSupported);
    });
  });

  group('network', () {
    test('a connection to a known bad address is found', () async {
      final _Run run = await _check(FakeSource(
        net: (
          connections: [
            _connection('17.57.144.10', enriched: true),
            _connection('45.9.148.3',
                process: 'helperd', enriched: true, bad: true),
          ],
          errors: const [],
        ),
      ));

      final List<Map<String, dynamic>> found = run.foundBy('Network');
      expect(found, hasLength(1));
      expect(found.single['name'], 'A connection to a known bad address');
      expect(
          found.single['description'],
          'helperd is connected to 45.9.148.3, which threat intelligence '
          'lists as malicious.');
      expect(found.single['severity'], 'HIGH');
    });

    test('connections that could not be read could not run', () async {
      final _Run run = await _check(FakeSource(net: (
        connections: const [],
        errors: ['lsof could not be executed'],
      )));

      expect(run.ends['Network'], 'lsof could not be executed');
    });

    test('connections nobody could look up could not run', () async {
      final _Run run = await _check(FakeSource(net: (
        connections: [_connection('17.57.144.10')],
        errors: ['VirusTotal enrichment unavailable for 17.57.144.10'],
      )));

      expect(run.ends['Network'], isNotNull);
      expect(run.ends['Network'], isNot(DeviceScanService.notSupported));
    });

    test('only local connections need no look up, and ran clean', () async {
      final _Run run = await _check(FakeSource(
          net: (connections: [_connection('192.168.1.4')], errors: const [])));

      expect(run.ends['Network'], isNull);
    });

    test('a sandboxed Mac that sees only its own connections cannot run it',
        () async {
      final _Run run = await _check(FakeSource(
        sandboxed: true,
        ownPid: 777,
        net: (
          connections: [
            _connection('17.57.144.10', pid: 777, enriched: true),
          ],
          errors: const [],
        ),
      ));

      expect(run.ends['Network'], DeviceScanService.notSupported);
    });
  });

  group('browser', () {
    test('extensions that can read every site are found together', () async {
      final _Run run = await _check(FakeSource(browserScan: {
        'extensions': [
          _extension('Dark Reader', 'low'),
          _extension('Grabber', 'critical'),
          _extension('Blocker', 'high', browser: 'Firefox'),
          _extension('Sites', 'medium'),
        ],
        'errors': const <String>[],
        'looked': ['Chrome', 'Firefox'],
      }));

      final List<Map<String, dynamic>> found = run.foundBy('Browser');
      expect(found, hasLength(1));
      expect(found.single['name'],
          '2 browser extensions can read and change every site you visit');
      expect(
          found.single['description'],
          'Grabber and Blocker. Remove any you do not use or do not '
          'recognise.');
      expect(found.single['severity'], 'LOW');
    });

    test('one such extension is named', () async {
      final _Run run = await _check(FakeSource(browserScan: {
        'extensions': [_extension('Grabber', 'high')],
        'errors': const <String>[],
        'looked': ['Chrome'],
      }));

      expect(run.foundBy('Browser').single['name'],
          'Grabber can read and change every site you visit');
      expect(
          run.foundBy('Browser').single['description'],
          'A Chrome extension. Remove it if you do not use it or do not '
          'recognise it.');
    });

    test('no browser it can read means the area is not possible here',
        () async {
      final _Run run = await _check(FakeSource(browserScan: {
        'extensions': const <Map<String, dynamic>>[],
        'errors': const <String>[],
        'looked': const <String>[],
      }));

      expect(run.ends['Browser'], DeviceScanService.notSupported);
    });

    test('browsers that could not be read could not run', () async {
      final _Run run = await _check(FakeSource(browserScan: {
        'extensions': const <Map<String, dynamic>>[],
        'errors': ['Chrome: cannot list profiles: Operation not permitted'],
        'looked': ['Chrome'],
      }));

      expect(run.ends['Browser'],
          'Chrome: cannot list profiles: Operation not permitted');
    });
  });

  group('quarantine', () {
    test('a quarantine that could be read ran clean', () async {
      final _Run run = await _check(FakeSource(quarantined: [
        QuarantinedItem(
            fileName: 'a.plist',
            originalPath: '/x/a.plist',
            name: 'a',
            type: 'Launch Agent'),
      ]));

      expect(run.ends['Quarantine'], isNull);
      expect(run.foundBy('Quarantine'), isEmpty);
    });

    test('one that could not be read could not run', () async {
      final _Run run = await _check(FakeSource(broken: {'Quarantine'}));

      expect(run.ends['Quarantine'], isNotNull);
    });
  });

  test('every finding names its area, its kind and never uses a dash',
      () async {
    final _Run run = await _check(FakeSource(
      startup: _scan([
        _item('com.updater.agent',
            risk: DesktopItemRisk.critical,
            indicators: ['Matches known malware']),
      ]),
      signing: (
        apps: [_app('Zoomer', valid: false), _app('Tool', signed: false)],
        unavailable: null,
      ),
      firewallStatus: const HostFirewallStatus(
          state: HostFirewallState.disabled, detail: 'off', source: 'tool'),
      browserScan: {
        'extensions': [_extension('Grabber', 'critical')],
        'errors': const <String>[],
        'looked': ['Chrome'],
      },
    ));

    expect(run.findings, hasLength(5));
    for (final Map<String, dynamic> f in run.findings) {
      expect(CheckPlan.computer.map((s) => s.stage), contains(f['stage']));
      expect(ComputerCheck.isComputerFinding(f), isTrue);
      expect(f['id'], isNotEmpty);
      expect(f['type'], startsWith('desktop_'));
      expect(
          '${f['name']} ${f['description']}', isNot(matches(RegExp('[—–·]'))));
    }
  });

  test('each area opens its own tab of the details', () {
    expect(
      [for (final s in CheckPlan.computer) ComputerCheck.tabOf(s.stage)],
      [0, 1, 2, 3, 4, 5],
    );
    expect(ComputerCheck.tabOf('Keylogger detection'), isNull);
  });

  test('coverage is the share of the six areas that ran', () {
    CheckOutcome outcome(int ran) => CheckOutcome(
          findings: const [],
          ran: [for (final s in CheckPlan.computer.take(ran)) s.stage],
          notPossible: const [],
          failed: const [],
        );

    expect(ComputerCheck.coverageOf(outcome(6)), 100);
    expect(ComputerCheck.coverageOf(outcome(5)), 83);
    expect(ComputerCheck.coverageOf(outcome(3)), 50);
    expect(ComputerCheck.coverageOf(outcome(0)), 0);
  });
}
