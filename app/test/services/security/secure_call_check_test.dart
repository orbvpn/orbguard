import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/security/secure_call_check.dart';

/// Secure Call Check — the honest device-posture check behind the "Secure call"
/// shield. These tests pin the classification + aggregation logic (the
/// non-trivial part): warnings vs. informational vs. "not available on this
/// platform", per-platform capability limits, and the overall verdict. They
/// also pin the honesty contract: a failed native bridge must NEVER read as a
/// clean device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.orb.guard/system');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mock(Map<String, Object?> responses) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      // Unknown methods return null → MissingPluginException, matching an
      // unregistered native handler.
      return responses[call.method];
    });
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  SecureCallCheckItem itemOf(SecureCallPosture p, CallCheckId id) =>
      p.items.firstWhere((i) => i.id == id);

  group('Android', () {
    SecureCallCheck android() => SecureCallCheck(
          channel: channel,
          platformOverride: TargetPlatform.android,
        );

    test('clean device → clean verdict, all seven checks present', () async {
      mock({
        'getEnabledAccessibilityServices': {'services': <Object>[]},
        'getInstalledCertificates': {'certificates': <Object>[]},
        'getInstalledApps': {'apps': <Object>[]},
        'checkRootAccess': {'hasRoot': false, 'accessLevel': 'Limited'},
      });

      final posture = await android().run();

      expect(posture.items.length, CallCheckId.values.length);
      expect(posture.verdict, CallPostureVerdict.clean);
      expect(posture.anyWarning, isFalse);
      expect(itemOf(posture, CallCheckId.jailbreakRoot).status,
          CallCheckStatus.clear);
      expect(itemOf(posture, CallCheckId.accessibilityServices).status,
          CallCheckStatus.clear);
      // Conditions Android cannot inspect are honestly "unavailable".
      expect(itemOf(posture, CallCheckId.screenCapture).status,
          CallCheckStatus.unavailable);
      expect(itemOf(posture, CallCheckId.trafficProxy).status,
          CallCheckStatus.unavailable);
      expect(itemOf(posture, CallCheckId.appTampering).status,
          CallCheckStatus.unavailable);
    });

    test('root + user CA + foreign accessibility → warnings; mic is info',
        () async {
      mock({
        'getEnabledAccessibilityServices': {
          'services': [
            {
              'packageName': 'com.evil.spy',
              'appName': 'SpyApp',
              'className': 'com.evil.spy.Reader',
            }
          ]
        },
        'getInstalledCertificates': {
          'certificates': [
            {
              'isUserInstalled': true,
              'subjectDN': 'CN=Acme MITM,O=Acme,C=US',
              'alias': 'user:1',
            }
          ]
        },
        'getInstalledApps': {
          'apps': [
            {
              'packageName': 'com.chat.app',
              'appName': 'ChatApp',
              'isSystemApp': false,
              'permissions': [
                'android.permission.RECORD_AUDIO',
                'android.permission.INTERNET',
              ],
            }
          ]
        },
        'checkRootAccess': {'hasRoot': true},
      });

      final posture = await android().run();

      expect(posture.verdict, CallPostureVerdict.warnings);
      expect(posture.anyHighSeverity, isTrue);

      final a11y = itemOf(posture, CallCheckId.accessibilityServices);
      expect(a11y.status, CallCheckStatus.warning);
      expect(a11y.findings, contains('SpyApp'));

      final certs = itemOf(posture, CallCheckId.hostileCerts);
      expect(certs.status, CallCheckStatus.warning);
      // CN is extracted from the full DN for a readable label.
      expect(certs.findings, contains('Acme MITM'));

      expect(itemOf(posture, CallCheckId.jailbreakRoot).status,
          CallCheckStatus.warning);

      // Microphone access is transparency, NOT an eavesdropping verdict.
      final mic = itemOf(posture, CallCheckId.microphoneApps);
      expect(mic.status, CallCheckStatus.info);
      expect(mic.findings, contains('ChatApp'));

      // Exactly the three real conditions are warnings (mic stays info).
      expect(posture.warningCount, 3);
    });

    test('our own accessibility service is not flagged as spyware', () async {
      mock({
        'getEnabledAccessibilityServices': {
          'services': [
            {'packageName': 'com.orb.guard', 'appName': 'OrbGuard'}
          ]
        },
        'getInstalledCertificates': {'certificates': <Object>[]},
        'getInstalledApps': {'apps': <Object>[]},
        'checkRootAccess': {'hasRoot': false},
      });

      final posture = await android().run();

      expect(itemOf(posture, CallCheckId.accessibilityServices).status,
          CallCheckStatus.clear);
      expect(posture.verdict, CallPostureVerdict.clean);
    });

    test('missing native bridge → error rows, never a false "clean"', () async {
      // No mock handler registered → every call is MissingPluginException.
      final posture = await android().run();

      expect(posture.verdict, CallPostureVerdict.cannotCheck);
      expect(itemOf(posture, CallCheckId.jailbreakRoot).status,
          CallCheckStatus.error);
      expect(posture.anyWarning, isFalse);
    });
  });

  group('iOS', () {
    SecureCallCheck ios() => SecureCallCheck(
          channel: channel,
          platformOverride: TargetPlatform.iOS,
        );

    test('screen capture + proxy → medium warnings; enum-only checks n/a',
        () async {
      mock({
        'scanProcesses': {
          'threats': [
            {
              'id': 'proc_screencapture_1',
              'name': 'Screen is being captured',
              'type': 'process',
            }
          ]
        },
        'scanNetwork': {
          'threats': [
            {
              'id': 'net_proxy_1',
              'name': 'HTTP proxy configured',
              'path': '10.0.0.1',
            }
          ]
        },
        'scanMemory': {'threats': <Object>[]},
        'checkRootAccess': {'hasRoot': false},
      });

      final posture = await ios().run();

      expect(posture.verdict, CallPostureVerdict.warnings);
      expect(posture.anyHighSeverity, isFalse); // both medium

      expect(itemOf(posture, CallCheckId.screenCapture).status,
          CallCheckStatus.warning);
      final proxy = itemOf(posture, CallCheckId.trafficProxy);
      expect(proxy.status, CallCheckStatus.warning);
      expect(proxy.findings, contains('10.0.0.1'));

      expect(itemOf(posture, CallCheckId.appTampering).status,
          CallCheckStatus.clear);
      expect(itemOf(posture, CallCheckId.jailbreakRoot).status,
          CallCheckStatus.clear);

      // iOS cannot enumerate other apps / certs / a11y services.
      expect(itemOf(posture, CallCheckId.hostileCerts).status,
          CallCheckStatus.unavailable);
      expect(itemOf(posture, CallCheckId.accessibilityServices).status,
          CallCheckStatus.unavailable);
      expect(itemOf(posture, CallCheckId.microphoneApps).status,
          CallCheckStatus.unavailable);
    });

    test('nothing found → clean verdict', () async {
      mock({
        'scanProcesses': {'threats': <Object>[]},
        'scanNetwork': {'threats': <Object>[]},
        'scanMemory': {'threats': <Object>[]},
        'checkRootAccess': {'hasRoot': false},
      });

      final posture = await ios().run();

      expect(posture.verdict, CallPostureVerdict.clean);
      expect(itemOf(posture, CallCheckId.screenCapture).status,
          CallCheckStatus.clear);
    });

    test('injected dylib + debugger → high-severity tampering warning',
        () async {
      mock({
        'scanProcesses': {
          'threats': [
            {'id': 'proc_inject_1', 'name': 'Injected library detected'}
          ]
        },
        'scanNetwork': {'threats': <Object>[]},
        'scanMemory': {
          'threats': [
            {'id': 'mem_debugger_1', 'name': 'Debugger attached to app'}
          ]
        },
        'checkRootAccess': {'hasRoot': false},
      });

      final posture = await ios().run();

      final tamper = itemOf(posture, CallCheckId.appTampering);
      expect(tamper.status, CallCheckStatus.warning);
      expect(tamper.isHigh, isTrue);
      expect(posture.anyHighSeverity, isTrue);
    });
  });

  group('unsupported platform', () {
    test('desktop → every check unavailable, cannotCheck verdict', () async {
      final posture = await SecureCallCheck(
        channel: channel,
        platformOverride: TargetPlatform.linux,
      ).run();

      expect(posture.items.length, CallCheckId.values.length);
      expect(
        posture.items.every((i) => i.status == CallCheckStatus.unavailable),
        isTrue,
      );
      expect(posture.verdict, CallPostureVerdict.cannotCheck);
    });
  });

  group('posture verdict logic', () {
    SecureCallCheckItem item(CallCheckStatus status, {String? severity}) =>
        SecureCallCheckItem(
          id: CallCheckId.jailbreakRoot,
          title: 't',
          question: 'q',
          status: status,
          detail: 'd',
          severity: severity,
        );

    test('any warning ⇒ warnings', () {
      final p = SecureCallPosture(
        items: [item(CallCheckStatus.clear), item(CallCheckStatus.warning)],
        checkedAt: DateTime.now(),
      );
      expect(p.verdict, CallPostureVerdict.warnings);
    });

    test('only clear/info ⇒ clean', () {
      final p = SecureCallPosture(
        items: [item(CallCheckStatus.clear), item(CallCheckStatus.info)],
        checkedAt: DateTime.now(),
      );
      expect(p.verdict, CallPostureVerdict.clean);
    });

    test('only unavailable/error ⇒ cannotCheck', () {
      final p = SecureCallPosture(
        items: [
          item(CallCheckStatus.unavailable),
          item(CallCheckStatus.error),
        ],
        checkedAt: DateTime.now(),
      );
      expect(p.verdict, CallPostureVerdict.cannotCheck);
    });
  });
}
