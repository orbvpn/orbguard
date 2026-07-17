import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/security/firewall_realtime.dart';

/// FirewallRealtime — the thin bridge to the native firewall's real-time
/// state. These tests pin the two contracts that matter:
///   1. values from the native side pass through unchanged;
///   2. an absent or failing native engine degrades to the zero value
///      (0 / false) instead of throwing — a broken bridge must never crash
///      the UI, and must never read as fabricated protection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.orbvpn.orbguard/firewall');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  group('blockedToday', () {
    test('returns the native count', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'getBlockedToday');
        return 42;
      });
      expect(await FirewallRealtime().blockedToday(), 42);
    });

    test('returns 0 when the channel is absent (MissingPluginException)',
        () async {
      // No mock handler registered → MissingPluginException, exactly like a
      // platform without the native firewall engine.
      expect(await FirewallRealtime().blockedToday(), 0);
    });

    test('returns 0 when the native side errors', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ENGINE_DOWN', message: 'boom');
      });
      expect(await FirewallRealtime().blockedToday(), 0);
    });
  });

  group('survivesReboot', () {
    test('returns true when the native side confirms auto-restore', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'survivesReboot');
        return true;
      });
      expect(await FirewallRealtime().survivesReboot(), isTrue);
    });

    test('returns false when the native side says no', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      expect(await FirewallRealtime().survivesReboot(), isFalse);
    });

    test('returns false when the channel is absent (MissingPluginException)',
        () async {
      expect(await FirewallRealtime().survivesReboot(), isFalse);
    });

    test('returns false when the native side errors', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ENGINE_DOWN', message: 'boom');
      });
      expect(await FirewallRealtime().survivesReboot(), isFalse);
    });
  });
}
