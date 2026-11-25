// The hidden VPN signal Home reads. `null` is "could not check", never
// "clean"; `true` only when something is rerouting traffic that is neither
// OrbGuard's own firewall nor something the person said is theirs.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/security/vpn_proxy_detector.dart';
import 'package:orbguard/services/security/vpn_watch.dart';

class _ThrowingDetector extends VpnProxyDetector {
  _ThrowingDetector() : super(platform: TargetPlatform.android);
  int calls = 0;
  @override
  Future<VpnProxyStatus> detect() async {
    calls++;
    throw StateError('scan blew up');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(VpnProxyDetector.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  // What the fake native scan reports right now.
  late bool tunnel;
  late String? proxyHost; // iOS only
  late int scans;
  // The facts newer Android native adds to the tunnel entry; null = absent.
  late bool? metaOwnFirewall;
  late bool? metaOrbVpn;

  DateTime now = DateTime(2026, 11, 25, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tunnel = false;
    proxyHost = null;
    scans = 0;
    metaOwnFirewall = null;
    metaOrbVpn = null;
    now = DateTime(2026, 11, 25, 12);
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'scanNetwork':
          scans++;
          return {
            'threats': [
              if (tunnel)
                {
                  'type': 'network',
                  'name': 'Active VPN Connection Detected',
                  'path': 'VPN',
                  'metadata': {
                    if (metaOwnFirewall != null) 'ownFirewall': metaOwnFirewall,
                    if (metaOrbVpn != null) 'orbVpnInstalled': metaOrbVpn,
                  },
                },
              if (proxyHost != null)
                {
                  'id': 'net_proxy_1',
                  'type': 'network',
                  'name': 'HTTP proxy configured',
                  'path': proxyHost,
                  'metadata': {'proxy_host': proxyHost},
                },
            ],
          };
        case 'getInstalledApps':
          return {'apps': <Map<String, dynamic>>[]};
      }
      return null;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  VpnWatch watch(TargetPlatform platform, {Map<String, String>? env}) =>
      VpnWatch(
        detector: VpnProxyDetector(platform: platform, environment: env ?? {}),
        prefs: SharedPreferences.getInstance,
        clock: () => now,
      );

  group('answers', () {
    test('false when nothing is rerouting as far as the device lets us see',
        () async {
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
      expect(w.lastStatus?.verdict, RerouteVerdict.inconclusive);
    });

    test("false when the tunnel is OrbGuard's own firewall", () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: true), isFalse);
    });

    test('true when a tunnel is active and the person has not answered',
        () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
      expect(await w.saidItIsMine, isFalse);
    });

    test('false once the person says the active tunnel is theirs', () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();

      expect(await w.saidItIsMine, isTrue);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
      // And it is remembered by a fresh instance while the tunnel stays.
      final again = watch(TargetPlatform.android);
      expect(await again.unknownVpnActive(ownFirewallOn: false), isFalse);
    });

    test('forgetMine takes it back', () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();
      await w.forgetMine();

      expect(await w.saidItIsMine, isFalse);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
    });

    test('null when the detector reports unavailable', () async {
      messenger.setMockMethodCallHandler(channel, null); // not in this build
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isNull);
      expect(w.lastStatus?.verdict, RerouteVerdict.unavailable);
    });

    test('null when the detector throws, never false', () async {
      final w = VpnWatch(
        detector: _ThrowingDetector(),
        prefs: SharedPreferences.getInstance,
        clock: () => now,
      );
      expect(await w.unknownVpnActive(ownFirewallOn: false), isNull);
      expect(w.lastStatus?.verdict, RerouteVerdict.unavailable);
    });

    test('null when the person had said "mine" but the check now fails',
        () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();
      messenger.setMockMethodCallHandler(channel, null);
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isNull);
    });

    test('markAsMine does nothing when nothing is active', () async {
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();
      tunnel = true;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isTrue);
    });
  });

  group('cache', () {
    test('a second ask within ten minutes reuses the scan', () async {
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      tunnel = true; // changed on the device, not yet seen
      now = now.add(const Duration(minutes: 9));
      expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
      expect(scans, 1);
    });

    test('after ten minutes it scans again', () async {
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      tunnel = true;
      now = now.add(const Duration(minutes: 10, seconds: 1));
      expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
      expect(scans, 2);
    });

    test('force bypasses the cache', () async {
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      tunnel = true;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isTrue);
      expect(scans, 2);
    });

    test('ownFirewallOn is applied to a cached scan without a rescan',
        () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
      expect(await w.unknownVpnActive(ownFirewallOn: true), isFalse);
      expect(scans, 1);
    });

    test('a failed check is not cached', () async {
      final d = _ThrowingDetector();
      final w = VpnWatch(
        detector: d,
        prefs: SharedPreferences.getInstance,
        clock: () => now,
      );
      expect(await w.unknownVpnActive(ownFirewallOn: false), isNull);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isNull);
      expect(d.calls, 2);
    });

    test('asking again with the same result does not notify again', () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      var n = 0;
      w.addListener(() => n++);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.unknownVpnActive(ownFirewallOn: false, force: true);
      expect(n, 1);
    });

    test('two asks at once share one scan', () async {
      final w = watch(TargetPlatform.android);
      await Future.wait([
        w.unknownVpnActive(ownFirewallOn: false),
        w.unknownVpnActive(ownFirewallOn: false, force: true),
      ]);
      expect(scans, 1);
    });

    test('notifies listeners when the answer may have changed', () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      var n = 0;
      w.addListener(() => n++);
      await w.unknownVpnActive(ownFirewallOn: false);
      final afterCheck = n;
      await w.markAsMine();
      expect(afterCheck, greaterThan(0));
      expect(n, greaterThan(afterCheck));
    });
  });

  group('"it is mine" when what is active changes', () {
    test('Android: cleared once a check sees no tunnel; the next tunnel asks',
        () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();

      tunnel = false;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isFalse);
      tunnel = true;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isTrue);
      expect(await w.saidItIsMine, isFalse);
    });

    test("Android: cleared when the tunnel seen is OrbGuard's firewall",
        () async {
      // Android runs one VPN at a time: while the firewall is up, the
      // person's own VPN is not, so the next tunnel is a new one.
      tunnel = true;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();

      expect(
          await w.unknownVpnActive(ownFirewallOn: true, force: true), isFalse);
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isTrue);
    });

    test('Android: a failed check does not clear the answer', () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();

      final failing = VpnWatch(
        detector: _ThrowingDetector(),
        prefs: SharedPreferences.getInstance,
        clock: () => now,
      );
      expect(await failing.unknownVpnActive(ownFirewallOn: false), isNull);

      final again = watch(TargetPlatform.android);
      expect(await again.unknownVpnActive(ownFirewallOn: false), isFalse);
    });

    test('iPhone: the same proxy host stays answered, even after a gap',
        () async {
      proxyHost = '10.0.0.9:8080';
      final w = watch(TargetPlatform.iOS);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
      await w.markAsMine();
      expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);

      proxyHost = null;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isFalse);
      proxyHost = '10.0.0.9:8080';
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isFalse);
    });

    test('iPhone: a DIFFERENT proxy host asks again', () async {
      proxyHost = '10.0.0.9:8080';
      final w = watch(TargetPlatform.iOS);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();

      proxyHost = '203.0.113.7:3128';
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isTrue);
      expect(await w.saidItIsMine, isFalse);
    });

    test('desktop: a different proxy in the environment asks again', () async {
      final first = VpnWatch(
        detector: VpnProxyDetector(
            platform: TargetPlatform.macOS,
            environment: const {'HTTPS_PROXY': 'http://proxy.corp:8080'}),
        prefs: SharedPreferences.getInstance,
        clock: () => now,
      );
      expect(await first.unknownVpnActive(ownFirewallOn: false), isTrue);
      await first.markAsMine();
      expect(await first.unknownVpnActive(ownFirewallOn: false), isFalse);

      final other = VpnWatch(
        detector: VpnProxyDetector(
            platform: TargetPlatform.macOS,
            environment: const {'HTTPS_PROXY': 'http://evil.example:9000'}),
        prefs: SharedPreferences.getInstance,
        clock: () => now,
      );
      expect(await other.unknownVpnActive(ownFirewallOn: false), isTrue);
    });

    test('a proxy appearing next to an answered tunnel asks again', () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();
      // Android cannot see proxies today; simulate a status that has both by
      // moving to the iOS reading of the same prefs.
      proxyHost = '10.0.0.9:8080';
      final ios = watch(TargetPlatform.iOS);
      expect(await ios.unknownVpnActive(ownFirewallOn: false), isTrue);
    });
  });

  group('native facts on the tunnel entry', () {
    test('native ownFirewall true decides, whatever the parameter says',
        () async {
      tunnel = true;
      metaOwnFirewall = true;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
      expect(w.lastTunnelIsOwnFirewall, isTrue);
    });

    test(
        'native ownFirewall false decides: a stale Dart flag cannot hide '
        'another VPN', () async {
      tunnel = true;
      metaOwnFirewall = false;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: true), isTrue);
      expect(w.lastTunnelIsOwnFirewall, isFalse);
    });

    test('without the native fact the parameter decides', () async {
      tunnel = true;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: true), isFalse);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
    });

    test(
        'genuine OrbVPN installed: a tunnel that is not the firewall is '
        'treated as theirs, with nothing to answer', () async {
      tunnel = true;
      metaOwnFirewall = false;
      metaOrbVpn = true;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
      expect(w.lastTunnelTreatedAsOrbVpn, isTrue);
      expect(await w.saidItIsMine, isFalse);
    });

    test('OrbVPN not installed, or not known: the tunnel asks', () async {
      tunnel = true;
      metaOwnFirewall = false;
      metaOrbVpn = false;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
      expect(w.lastTunnelTreatedAsOrbVpn, isFalse);

      metaOrbVpn = null;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isTrue);
      expect(w.lastTunnelTreatedAsOrbVpn, isFalse);
    });

    test('the firewall wins over OrbVPN: our own tunnel is named as ours',
        () async {
      tunnel = true;
      metaOwnFirewall = true;
      metaOrbVpn = true;
      final w = watch(TargetPlatform.android);
      expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
      expect(w.lastTunnelIsOwnFirewall, isTrue);
      expect(w.lastTunnelTreatedAsOrbVpn, isFalse);
    });

    test('native firewall tunnel clears an earlier "mine"', () async {
      tunnel = true;
      metaOwnFirewall = false;
      final w = watch(TargetPlatform.android);
      await w.unknownVpnActive(ownFirewallOn: false);
      await w.markAsMine();

      metaOwnFirewall = true;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isFalse);
      metaOwnFirewall = false;
      expect(
          await w.unknownVpnActive(ownFirewallOn: false, force: true), isTrue);
    });
  });
}
