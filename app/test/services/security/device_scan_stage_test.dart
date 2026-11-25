import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/security/device_scan_service.dart';

/// Every finding says which check found it, so it can be shown under the
/// shield that check belongs to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.orb.guard/system');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'initializeScan':
          return null;
        case 'scanNetwork':
          return {
            'threats': [
              {'id': 'n1', 'name': 'Odd connection', 'severity': 'HIGH'},
            ],
          };
        case 'scanProcesses':
        case 'scanFileSystem':
        case 'scanDatabases':
          return {'threats': <Object?>[]};
        case 'scanMemory':
          return {
            'threats': [
              {'id': 'm1', 'name': 'Odd memory', 'severity': 'LOW'},
            ],
          };
        default:
          // What an iPhone answers for everything else.
          throw PlatformException(code: 'UNSUPPORTED', message: 'not on iOS');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('a finding carries the stage that found it', () async {
    final List<Map<String, dynamic>> found =
        await DeviceScanService.instance.performScan();

    expect(found, hasLength(2));
    expect(found[0]['id'], 'n1');
    expect(found[0]['stage'], 'Network connections');
    expect(found[1]['id'], 'm1');
    expect(found[1]['stage'], 'Memory');
  });
}
