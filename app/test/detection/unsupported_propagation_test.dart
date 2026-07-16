import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/detection/advanced_detection_modules.dart';

/// P0.4 honesty pin: on a platform where the native capability doesn't exist
/// (iOS can't enumerate installed apps / certificates / accessibility services
/// / keyboards), the detection modules must PROPAGATE that as a
/// [DetectionUnsupportedException] — not swallow it into an empty list that the
/// scan would render as a false "clean / 0 findings".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.orb.guard/system');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      // Mirror what the iOS native side does for these methods.
      throw PlatformException(
        code: 'UNSUPPORTED',
        message: 'iOS does not provide a public API for ${call.method}',
      );
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('certificate detector surfaces UNSUPPORTED, not a fake clean', () {
    expect(CertificateAnalyzer().detectCertificateThreats(),
        throwsA(isA<DetectionUnsupportedException>()));
  });

  test('accessibility detector surfaces UNSUPPORTED', () {
    expect(AccessibilityAbuseDetector().detectAccessibilityAbuse(),
        throwsA(isA<DetectionUnsupportedException>()));
  });

  test('keylogger detector surfaces UNSUPPORTED', () {
    expect(KeystrokeLoggerDetector().detectKeyloggers(),
        throwsA(isA<DetectionUnsupportedException>()));
  });

  test('permission-abuse detector surfaces UNSUPPORTED', () {
    expect(PermissionAbuseDetector().detectPermissionAbuse(),
        throwsA(isA<DetectionUnsupportedException>()));
  });
}
