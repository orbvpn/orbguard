import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/security/vpn_proxy_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tunnelFromThreats', () {
    test('reports an active tunnel from the native VPN threat', () {
      final threats = [
        {'type': 'network', 'name': 'Active VPN Connection Detected', 'path': 'VPN'},
      ];
      expect(VpnProxyDetector.tunnelFromThreats(threats), TriState.yes);
    });

    test('reports no tunnel when the scan is clean (Android always runs it)',
        () {
      expect(VpnProxyDetector.tunnelFromThreats(const []), TriState.no);
    });

    test('ignores unrelated network findings', () {
      final threats = [
        {'type': 'network', 'name': 'Unvalidated WiFi Connection', 'path': 'wlan0'},
      ];
      expect(VpnProxyDetector.tunnelFromThreats(threats), TriState.no);
    });
  });

  group('proxyFromThreats', () {
    test('reports an HTTP proxy with host from the iOS threat', () {
      final threats = [
        {
          'id': 'net_proxy_abc',
          'type': 'network',
          'name': 'HTTP proxy configured',
          'path': '10.0.0.9',
          'metadata': {'proxy_host': '10.0.0.9'},
        },
      ];
      final r = VpnProxyDetector.proxyFromThreats(threats);
      expect(r.state, TriState.yes);
      expect(r.host, '10.0.0.9');
    });

    test('reports no proxy when the scan is clean', () {
      final r = VpnProxyDetector.proxyFromThreats(const []);
      expect(r.state, TriState.no);
      expect(r.host, isNull);
    });
  });

  group('proxyFromEnvironment', () {
    test('detects a proxy from env vars and prettifies the host', () {
      final r = VpnProxyDetector.proxyFromEnvironment(
          const {'HTTPS_PROXY': 'http://proxy.corp:8080'});
      expect(r.state, TriState.yes);
      expect(r.host, 'proxy.corp:8080');
    });

    test('is an honest negative when no proxy env var is set', () {
      final r = VpnProxyDetector.proxyFromEnvironment(const {});
      expect(r.state, TriState.no);
      expect(r.host, isNull);
    });
  });

  group('classifyInstalledVpnApps', () {
    test('recognises OrbVPN (trusted, first) and other VPN apps, ignores rest',
        () {
      final apps = <Map<String, dynamic>>[
        {'packageName': 'com.whatsapp', 'appName': 'WhatsApp'},
        {'packageName': 'com.nordvpn.android', 'appName': 'NordVPN'},
        {'packageName': 'com.orbvpn.android', 'appName': 'OrbVPN'},
        {'packageName': 'free.vpn.unblock.proxy.x', 'appName': 'Turbo VPN'},
        {'packageName': 'com.android.chrome', 'appName': 'Chrome'},
      ];
      final result = VpnProxyDetector.classifyInstalledVpnApps(apps);

      expect(result.map((a) => a.packageName), isNot(contains('com.whatsapp')));
      expect(result.map((a) => a.packageName), isNot(contains('com.android.chrome')));
      // OrbVPN recognised, trusted, and sorted first.
      expect(result.first.isOrbVpn, isTrue);
      expect(result.first.packageName, 'com.orbvpn.android');
      // The other VPN apps are present but never marked as OrbVPN/trusted.
      expect(result.length, 3);
      expect(result.where((a) => a.isOrbVpn).length, 1);
    });

    test('never flags OrbVPN even when its name lacks "vpn"', () {
      final apps = <Map<String, dynamic>>[
        {'packageName': 'com.orbvpn.orbguard', 'appName': 'OrbGuard'},
      ];
      final result = VpnProxyDetector.classifyInstalledVpnApps(apps);
      expect(result.single.isOrbVpn, isTrue);
    });
  });

  group('verdictFor (never fabricates a clean when a signal is unknown)', () {
    test('active when a tunnel is up even if proxy is unknown', () {
      expect(
        VpnProxyDetector.verdictFor(tunnel: TriState.yes, proxy: TriState.unknown),
        RerouteVerdict.active,
      );
    });

    test('clear only when every signal is a known negative', () {
      expect(
        VpnProxyDetector.verdictFor(tunnel: TriState.no, proxy: TriState.no),
        RerouteVerdict.clear,
      );
    });

    test('inconclusive when a negative is mixed with an unknown', () {
      expect(
        VpnProxyDetector.verdictFor(tunnel: TriState.no, proxy: TriState.unknown),
        RerouteVerdict.inconclusive,
      );
    });

    test('unavailable when nothing could be checked', () {
      expect(
        VpnProxyDetector.verdictFor(
            tunnel: TriState.unknown, proxy: TriState.unknown),
        RerouteVerdict.unavailable,
      );
    });
  });

  group('detect() on desktop (env-based, no native channel)', () {
    test('surfaces a proxy from the environment and leaves the tunnel unknown',
        () async {
      final detector = VpnProxyDetector(
        platform: TargetPlatform.macOS,
        environment: const {'HTTP_PROXY': 'socks5://127.0.0.1:1080'},
      );
      final s = await detector.detect();
      expect(s.systemProxy, TriState.yes);
      expect(s.proxyHost, '127.0.0.1:1080');
      expect(s.activeTunnel, TriState.unknown);
      expect(s.verdict, RerouteVerdict.active);
      expect(s.installedVpnApps, isEmpty);
    });

    test('with no proxy env is inconclusive, NOT a fake clean', () async {
      final detector = VpnProxyDetector(
        platform: TargetPlatform.macOS,
        environment: const {},
      );
      final s = await detector.detect();
      expect(s.systemProxy, TriState.no);
      expect(s.activeTunnel, TriState.unknown);
      expect(s.verdict, RerouteVerdict.inconclusive);
    });
  });

  group('detect() on Android (mocked native scan channel)', () {
    const channel = MethodChannel(VpnProxyDetector.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('reports an active tunnel and classifies installed VPN apps',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'scanNetwork':
            return {
              'threats': [
                {'type': 'network', 'name': 'Active VPN Connection Detected', 'path': 'VPN'},
              ],
            };
          case 'getInstalledApps':
            return {
              'apps': [
                {'packageName': 'com.orbvpn.android', 'appName': 'OrbVPN'},
                {'packageName': 'com.nordvpn.android', 'appName': 'NordVPN'},
              ],
            };
        }
        return null;
      });

      final detector = VpnProxyDetector(platform: TargetPlatform.android);
      final s = await detector.detect();

      expect(s.activeTunnel, TriState.yes);
      expect(s.systemProxy, TriState.unknown); // Android proxy read not exposed.
      expect(s.verdict, RerouteVerdict.active);
      expect(s.orbVpnInstalled, isTrue);
      expect(s.installedVpnApps.first.isOrbVpn, isTrue);
      expect(s.tunnelOwnerIdentifiable, isFalse);
    });

    test('is unavailable (not clean) when the native channel is missing',
        () async {
      messenger.setMockMethodCallHandler(channel, null); // no handler
      final detector = VpnProxyDetector(platform: TargetPlatform.android);
      final s = await detector.detect();
      expect(s.verdict, RerouteVerdict.unavailable);
      expect(s.errorMessage, isNotNull);
    });
  });
}
