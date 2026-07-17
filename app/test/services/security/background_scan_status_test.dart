import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/security/background_scan_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(BackgroundScanStatusBridge.channel, null);
  });

  group('BackgroundScanStatusBridge.fetch', () {
    test('parses a real native payload', () async {
      messenger.setMockMethodCallHandler(BackgroundScanStatusBridge.channel,
          (call) async {
        expect(call.method, 'getBackgroundScanStatus');
        return <String, Object?>{
          'scheduled': true,
          'lastRunIso': '2026-07-17T04:12:00Z',
          'lastFindings': 2,
          'lastSuccess': true,
        };
      });

      final status = await const BackgroundScanStatusBridge().fetch();

      expect(status, isNotNull);
      expect(status!.scheduled, isTrue);
      expect(status.lastRunAt, DateTime.utc(2026, 7, 17, 4, 12));
      expect(status.lastFindings, 2);
      expect(status.lastSuccess, isTrue);
    });

    test('reports a never-run install without inventing a timestamp', () async {
      messenger.setMockMethodCallHandler(BackgroundScanStatusBridge.channel,
          (call) async {
        // Native omits lastRunIso until a background run has really happened.
        return <String, Object?>{
          'scheduled': false,
          'lastFindings': 0,
          'lastSuccess': false,
        };
      });

      final status = await const BackgroundScanStatusBridge().fetch();

      expect(status, isNotNull);
      expect(status!.scheduled, isFalse);
      expect(status.lastRunAt, isNull);
      expect(status.lastFindings, 0);
      expect(status.lastSuccess, isFalse);
    });

    test('returns null when the platform has no implementation', () async {
      // No mock handler registered: the channel throws
      // MissingPluginException, and fetch() degrades honestly to null.
      final status = await const BackgroundScanStatusBridge().fetch();

      expect(status, isNull);
    });
  });
}
