// Reroute state has one owner, VpnWatch. The device check never lists an
// active tunnel or system proxy as a finding: it would count the same thing
// twice (as spyware and as a hidden VPN), and OrbGuard's own firewall tunnel
// would become something the check "found".

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/security/device_scan_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.orb.guard/system');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<Map<String, Object?>> network;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initializeScan':
          return null;
        case 'scanNetwork':
          return {'threats': network};
        case 'scanProcesses':
        case 'scanFileSystem':
        case 'scanDatabases':
        case 'scanMemory':
          return {'threats': <Object?>[]};
        default:
          throw PlatformException(code: 'UNSUPPORTED', message: 'not here');
      }
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  const tunnel = {
    'id': 'network_vpn_1',
    'type': 'network',
    'name': 'Active VPN Connection Detected',
    'path': 'VPN',
    'metadata': {'ownFirewall': true, 'orbVpnInstalled': false},
  };
  const proxy = {
    'id': 'net_proxy_1',
    'type': 'network',
    'name': 'HTTP proxy configured',
    'path': '10.0.0.9',
  };
  const wifi = {
    'id': 'network_unvalidated_1',
    'type': 'network',
    'name': 'Unvalidated WiFi Connection',
    'path': 'wlan0',
  };

  test('tunnel and proxy entries are not findings; other network ones are',
      () async {
    network = [tunnel, proxy, wifi];
    final found = await DeviceScanService.instance.performScan();

    expect(found.map((f) => f['id']), ['network_unvalidated_1']);
    expect(found.single['stage'], 'Network connections');
  });

  test('a network stage that saw only reroute state still ran, cleanly',
      () async {
    network = [tunnel];
    final updates = <DeviceScanProgress>[];
    final found =
        await DeviceScanService.instance.performScan(onProgress: updates.add);

    expect(found, isEmpty);
    final done = updates.firstWhere(
        (u) => u.stageName == 'Network connections' && u.stageCompleted);
    expect(done.stageError, isNull);
    expect(done.threatsFound, 0);
  });
}
