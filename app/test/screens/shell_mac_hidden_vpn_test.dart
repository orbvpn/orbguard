/// The Mac reads its own tunnels and proxy (the `networkReroute` channel), so
/// Home's Hidden VPN shield must report what it saw there, never "Not here".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/security/vpn_proxy_detector.dart';
import 'package:orbguard/widgets/home/home_side.dart';

import '../support/shell_harness.dart';

const Size _window = Size(1180, 760);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel(VpnProxyDetector.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  void macSees(Map<String, Object?> wire) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'networkReroute') return wire;
      throw MissingPluginException();
    });
  }

  String chip(WidgetTester tester, Shield shield) => tester
      .widget<ShieldChip>(find.descendant(
          of: find.byKey(ValueKey('shield-tile-${shield.name}')),
          matching: find.byType(ShieldChip)))
      .text;

  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('a Mac with no tunnel and no proxy shows the shield on',
      (tester) async {
    macSees({
      'tunnels': <Object?>[],
      'primaryInterface': 'en0',
      'proxy': <String, Object?>{},
    });
    await mountShell(tester,
        autoCheckSpent: true, platform: TargetPlatform.macOS, size: _window);
    await settle(tester);

    expect(chip(tester, Shield.hiddenVpn), 'On');
    await unmountShell(tester);
  });

  testWidgets('Windows still cannot see a tunnel, so it says Not here',
      (tester) async {
    await mountShell(tester,
        autoCheckSpent: true, platform: TargetPlatform.windows, size: _window);
    await settle(tester);

    expect(chip(tester, Shield.hiddenVpn), 'Not here');
    await unmountShell(tester);
  });
}
