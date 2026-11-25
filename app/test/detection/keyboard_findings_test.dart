import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/detection/advanced_detection_modules.dart';

/// Which keyboards a check may report.
///
/// A keyboard that can reach the internet is nearly every keyboard there is,
/// the phone's own included. Reporting each one as critical put "Your phone
/// needs attention" on a stock phone and pointed "Fix this" at Google's voice
/// typing. A keyboard is worth a person's time only when it was added to the
/// phone, is turned on, can reach the internet and is not a household name.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.orb.guard/system');

  Map<String, Object?> keyboard({
    required String package,
    required String name,
    bool system = false,
    bool enabled = true,
    bool inUse = false,
    List<String> permissions = const ['INTERNET'],
  }) =>
      {
        'packageName': package,
        'appName': name,
        'isSystemApp': system,
        'isEnabled': enabled,
        'isDefault': inUse,
        'permissions': permissions,
      };

  Future<List<Map<String, dynamic>>> check(
      List<Map<String, Object?>> keyboards) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'getInstalledKeyboards' => {'keyboards': keyboards},
        // The native check that used to be added on top. It reports the same
        // keyboards a second time, in harsher words.
        'detectIMEAbuse' => {
            'threats': [
              for (final k in keyboards)
                if (k['isSystemApp'] != true && k['isEnabled'] == true)
                  {
                    'id': 'ime_abuse_${k['packageName']}',
                    'name': 'Third-Party Keyboard With Network Access',
                    'severity': k['isDefault'] == true ? 'CRITICAL' : 'HIGH',
                    'type': 'keylogger',
                    'path': k['packageName'],
                  },
            ],
          },
        _ => null,
      };
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    return KeystrokeLoggerDetector().detectKeyloggers();
  }

  test('a keyboard that came with the phone is not a finding', () async {
    final found = await check([
      keyboard(
          package: 'com.google.android.tts',
          name: 'Google voice typing',
          system: true),
      keyboard(
          package: 'com.vendor.keyboard',
          name: 'Phone maker keyboard',
          system: true,
          inUse: true),
    ]);

    expect(found, isEmpty);
  });

  test('a keyboard that is turned off is not a finding', () async {
    final found = await check([
      keyboard(
          package: 'com.example.fastkeys', name: 'FastKeys', enabled: false),
    ]);

    expect(found, isEmpty);
  });

  test('a keyboard with no way to the internet is not a finding', () async {
    final found = await check([
      keyboard(
          package: 'com.example.offlinekeys',
          name: 'Offline Keys',
          inUse: true,
          permissions: const ['VIBRATE']),
    ]);

    expect(found, isEmpty);
  });

  test('a widely used keyboard is not a finding, even when added', () async {
    final found = await check([
      keyboard(
          package: 'com.touchtype.swiftkey',
          name: 'Microsoft SwiftKey',
          inUse: true),
      keyboard(package: 'com.google.android.inputmethod.latin', name: 'Gboard'),
    ]);

    expect(found, isEmpty);
  });

  test('an added keyboard in use is reported once, and not as critical',
      () async {
    final found = await check([
      keyboard(package: 'com.example.fastkeys', name: 'FastKeys', inUse: true),
    ]);

    expect(found, hasLength(1));
    final Map<String, dynamic> finding = found.single;
    expect(finding['id'], 'keyboard_com.example.fastkeys');
    expect(finding['name'], 'A keyboard you added can send what you type');
    expect(finding['description'], contains('FastKeys'));
    expect(finding['severity'], 'MEDIUM');
    expect(finding['type'], 'keylogger');
    expect(finding['path'], 'com.example.fastkeys');
  });

  test('an added keyboard that is on but not in use is a low finding',
      () async {
    final found = await check([
      keyboard(package: 'com.example.fastkeys', name: 'FastKeys'),
    ]);

    expect(found.single['severity'], 'LOW');
  });

  test('the words of a finding hold no dash', () async {
    final found = await check([
      keyboard(package: 'com.example.fastkeys', name: 'FastKeys', inUse: true),
    ]);

    final String words =
        '${found.single['name']} ${found.single['description']}';
    expect(words, isNot(matches(RegExp('[—–]'))));
  });
}
