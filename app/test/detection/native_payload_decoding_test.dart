import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/detection/advanced_detection_modules.dart';

/// Regression guard for a bug that silently disabled five detection modules on
/// EVERY platform, Android included.
///
/// `StandardMethodCodec` hands Dart a `Map<Object?, Object?>`, so the old
/// `List<Map<String, dynamic>>.from(result['certificates'])` threw a TypeError
/// on real payloads. The bare `catch (e)` below it swallowed that and returned
/// an empty list, which the scan pipeline then counted as a stage that ran
/// and found nothing — a fabricated "all clear".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.orb.guard/system');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  /// Values shaped exactly like what the platform codec produces: nested maps
  /// are `Map<Object?, Object?>`, never `Map<String, dynamic>`.
  Object? codecShaped(String key, List<Map<String, Object?>> rows) {
    return <Object?, Object?>{
      key: <Object?>[
        for (final row in rows) <Object?, Object?>{...row},
      ],
    };
  }

  test('a user-installed root certificate is decoded and reported', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getInstalledCertificates') return null;
      return codecShaped('certificates', [
        {
          'subject': 'Definitely Not Interception Ltd',
          'issuer': 'Definitely Not Interception Ltd',
          'serial': 'AA',
          'isUserInstalled': true,
          'isSelfSigned': true,
          'isExpired': false,
          'isActive': true,
          'path': 'CurrentUser\\ROOT',
        },
      ]);
    });

    final threats = await CertificateAnalyzer().detectCertificateThreats();

    // The point of the test: a real payload must survive decoding and reach
    // the heuristics. Before the fix this list was always empty.
    expect(threats, isNotEmpty,
        reason: 'a user-installed self-signed root must be flagged');
  });

  test('installed apps decode so permission combos can be evaluated', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'getInstalledApps') return null;
      return codecShaped('apps', [
        {
          'packageName': 'com.example.totalspy',
          'appName': 'TotalSpy',
          'installDate': '',
          // The full-surveillance combo the Dart rules look for.
          'permissions': <Object?>[
            'CAMERA',
            'RECORD_AUDIO',
            'ACCESS_FINE_LOCATION',
            'READ_CONTACTS',
            'READ_SMS',
          ],
        },
      ]);
    });

    final threats = await PermissionAbuseDetector().detectPermissionAbuse();
    expect(threats, isNotEmpty,
        reason: 'an app holding the full surveillance set must be flagged');
  });

  test('a missing native handler reports unavailable, never a clean result',
      () async {
    // No mock handler registered -> MissingPluginException, which must surface
    // as "this check could not run" rather than an empty (clean) list.
    expect(
      () => CertificateAnalyzer().detectCertificateThreats(),
      throwsA(isA<DetectionUnsupportedException>()),
    );
  });
}
