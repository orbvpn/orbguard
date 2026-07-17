import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/security/remediation.dart';

/// "Fix" must map each finding to the right device-native action: an app to its
/// App Info (uninstall/disable), a VPN to VPN settings, and anything else to
/// guidance — never a silent no-op that pretends to have fixed something.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('kindFor', () {
    test('high-risk / malware app → App Info', () {
      expect(
        Remediation.kindFor({
          'type': 'app_risk',
          'metadata': {'package': 'com.samsung.bixby'},
        }),
        RemediationKind.appInfo,
      );
      expect(
        Remediation.kindFor({
          'type': 'malware',
          'metadata': {'package': 'com.evil'},
        }),
        RemediationKind.appInfo,
      );
    });

    test('active VPN → VPN settings', () {
      expect(
        Remediation.kindFor({
          'type': 'network',
          'name': 'Active VPN Connection Detected',
          'path': 'VPN',
        }),
        RemediationKind.vpnSettings,
      );
    });

    test('everything else → guidance only', () {
      expect(
        Remediation.kindFor({'type': 'accessibility', 'name': 'Spyware'}),
        RemediationKind.guidanceOnly,
      );
    });

    test('app finding without a package is not treated as App Info', () {
      expect(
        Remediation.kindFor({'type': 'app_risk', 'name': 'something'}),
        RemediationKind.guidanceOnly,
      );
    });
  });

  group('fix invokes the right native method', () {
    const channel = MethodChannel('com.orb.guard/system');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('app finding → openAppDetails with the package', () async {
      final r = Remediation();
      final ok = await r.fix({
        'type': 'app_risk',
        'metadata': {'package': 'com.samsung.bixby'},
      });
      expect(ok, isTrue);
      expect(calls.single.method, 'openAppDetails');
      expect((calls.single.arguments as Map)['package'], 'com.samsung.bixby');
    });

    test('VPN finding → openVpnSettings', () async {
      final r = Remediation();
      final ok = await r.fix({'type': 'network', 'path': 'VPN'});
      expect(ok, isTrue);
      expect(calls.single.method, 'openVpnSettings');
    });

    test('guidance-only finding invokes nothing, returns false', () async {
      final r = Remediation();
      final ok = await r.fix({'type': 'accessibility'});
      expect(ok, isFalse);
      expect(calls, isEmpty);
    });
  });
}
