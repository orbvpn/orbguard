// What the native network scan says about rerouting, read once and in one
// place: which entries ARE reroute state (so the device check can leave them
// to VpnWatch), and the two facts Android adds to the tunnel entry.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/security/vpn_proxy_detector.dart';

Map<String, dynamic> _tunnel([Map<String, dynamic>? metadata]) => {
      'id': 'network_vpn_1',
      'type': 'network',
      'name': 'Active VPN Connection Detected',
      'path': 'VPN',
      if (metadata != null) 'metadata': metadata,
    };

const Map<String, dynamic> _proxy = {
  'id': 'net_proxy_1',
  'type': 'network',
  'name': 'HTTP proxy configured',
  'path': '10.0.0.9',
  'metadata': {'proxy_host': '10.0.0.9'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isRerouteFinding', () {
    test('true for the tunnel and the proxy entries the detector reads', () {
      expect(VpnProxyDetector.isRerouteFinding(_tunnel()), isTrue);
      expect(VpnProxyDetector.isRerouteFinding(_proxy), isTrue);
      // Exactly the entries the readers recognise.
      expect(VpnProxyDetector.tunnelFromThreats([_tunnel()]), TriState.yes);
      expect(VpnProxyDetector.proxyFromThreats([_proxy]).state, TriState.yes);
    });

    test('false for other network findings', () {
      for (final t in <Map<String, dynamic>>[
        {
          'id': 'network_unvalidated_1',
          'type': 'network',
          'name': 'Unvalidated WiFi Connection',
          'path': 'wlan0',
        },
        {
          'id': 'network_suspicious_route',
          'type': 'network',
          'name': 'Suspicious Network Route',
          'path': '/proc/net/route',
        },
        {'id': 'n1', 'name': 'Odd connection', 'severity': 'HIGH'},
      ]) {
        expect(VpnProxyDetector.isRerouteFinding(t), isFalse, reason: '$t');
        expect(VpnProxyDetector.tunnelFromThreats([t]), TriState.no);
        expect(VpnProxyDetector.proxyFromThreats([t]).state, TriState.no);
      }
    });

    test('a VPN-named entry that is not a network finding is not reroute', () {
      final t = {
        'id': 'p1',
        'type': 'process',
        'name': 'vpn helper process',
        'path': 'VPN',
      };
      expect(VpnProxyDetector.isRerouteFinding(t), isFalse);
      expect(VpnProxyDetector.tunnelFromThreats([t]), TriState.no);
    });
  });

  group('tunnelFacts', () {
    test('reads ownFirewall and orbVpnInstalled from the tunnel entry', () {
      final f = VpnProxyDetector.tunnelFacts([
        _tunnel({'ownFirewall': true, 'orbVpnInstalled': false})
      ]);
      expect(f.ownFirewall, isTrue);
      expect(f.orbVpnInstalled, isFalse);
    });

    test('absent facts are unknown, never "no"', () {
      expect(VpnProxyDetector.tunnelFacts([_tunnel()]).ownFirewall, isNull);
      expect(VpnProxyDetector.tunnelFacts([_tunnel()]).orbVpnInstalled, isNull);
      expect(VpnProxyDetector.tunnelFacts([_tunnel({})]).ownFirewall, isNull);
      expect(VpnProxyDetector.tunnelFacts(const []).ownFirewall, isNull);
      expect(VpnProxyDetector.tunnelFacts([_proxy]).orbVpnInstalled, isNull);
    });

    test('a value that is not a bool is unknown', () {
      final f = VpnProxyDetector.tunnelFacts([
        _tunnel({'ownFirewall': 'yes', 'orbVpnInstalled': 1})
      ]);
      expect(f.ownFirewall, isNull);
      expect(f.orbVpnInstalled, isNull);
    });
  });

  group('detect() carries the facts', () {
    const channel = MethodChannel(VpnProxyDetector.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    void answer(List<Map<String, dynamic>> threats) =>
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'scanNetwork') return {'threats': threats};
          return {'apps': <Object>[]};
        });

    test('Android with the new metadata', () async {
      answer([
        _tunnel({'ownFirewall': false, 'orbVpnInstalled': true})
      ]);
      final s =
          await VpnProxyDetector(platform: TargetPlatform.android).detect();
      expect(s.tunnelIsOwnFirewall, isFalse);
      expect(s.genuineOrbVpnInstalled, isTrue);
    });

    test('Android from an older native build: unknown', () async {
      answer([_tunnel()]);
      final s =
          await VpnProxyDetector(platform: TargetPlatform.android).detect();
      expect(s.tunnelIsOwnFirewall, isNull);
      expect(s.genuineOrbVpnInstalled, isNull);
    });

    test('iPhone and desktop never know them', () async {
      answer([_proxy]);
      final ios = await VpnProxyDetector(platform: TargetPlatform.iOS).detect();
      expect(ios.tunnelIsOwnFirewall, isNull);
      expect(ios.genuineOrbVpnInstalled, isNull);
      final mac = await VpnProxyDetector(
          platform: TargetPlatform.macOS, environment: const {}).detect();
      expect(mac.tunnelIsOwnFirewall, isNull);
      expect(mac.genuineOrbVpnInstalled, isNull);
    });
  });
}
