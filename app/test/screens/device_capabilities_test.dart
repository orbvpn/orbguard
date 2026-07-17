import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/glass_widgets.dart';
import 'package:orbguard/screens/trust/device_capabilities_screen.dart';

/// P3.2 — the honest per-platform capability matrix. These tests pin the
/// two hardest honesty guarantees the screen exists to make:
///  1. iOS must show the sandboxed "not available" row for the full malware
///     scan (never a fake "clean"/"available" claim — no tool can scan other
///     apps for malware on iOS).
///  2. Desktop must show REAL capability (the OS firewall) as Available,
///     while a mobile-only check (secure-call device posture) honestly
///     reads "not available on desktop" rather than silently passing.
void main() {
  Widget host(TargetPlatform platform) => MaterialApp(
        home: DeviceCapabilitiesScreen(platformOverride: platform),
      );

  /// The capability card for [id], keyed by [DeviceCapabilitiesScreen] so
  /// assertions can target one row without depending on layout or order.
  Finder cardFor(String id) => find.byKey(ValueKey('capability_$id'));

  // The full matrix (7 cards + honesty footer, each with a multi-sentence
  // explanation) is taller than the default 800×600 test surface, so a plain
  // pump would leave the lower rows unmounted (off the lazy ListView's
  // build/cache range) and every "not found" below would be a false
  // negative, not a real regression. Enlarge the surface so the whole
  // ListView fits without scrolling.
  Future<void> pumpScreen(WidgetTester tester, TargetPlatform platform) async {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(platform));
    await tester.pump();
  }

  testWidgets('renders all seven protection-area cards plus the honesty footer',
      (tester) async {
    await pumpScreen(tester, TargetPlatform.android);

    for (final id in const [
      'spyware',
      'stalkerware',
      'scam',
      'vpn_proxy',
      'secure_call',
      'dark_web',
      'firewall',
    ]) {
      expect(cardFor(id), findsOneWidget, reason: 'missing capability row: $id');
    }
    // 7 protection-area cards + 1 closing honesty-footer card.
    expect(find.byType(GlassCard), findsNWidgets(8));
  });

  group('iOS', () {
    testWidgets(
        'shows the honest sandbox / not-available row for the malware scan',
        (tester) async {
      await pumpScreen(tester, TargetPlatform.iOS);

      final spyware = cardFor('spyware');
      expect(
        find.descendant(
            of: spyware, matching: find.text('Spyware & Pegasus scan')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: spyware, matching: find.text('Not available')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: spyware, matching: find.textContaining('sandboxes every app')),
        findsOneWidget,
      );

      // Never a false "clean"/"available" claim for full malware scanning.
      expect(
        find.descendant(of: spyware, matching: find.text('Available')),
        findsNothing,
      );
      expect(
        find.descendant(of: spyware, matching: find.text('Limited')),
        findsNothing,
      );
    });

    testWidgets('phone-native checks (secure call, scam) read Available',
        (tester) async {
      await pumpScreen(tester, TargetPlatform.iOS);

      expect(
        find.descendant(
            of: cardFor('secure_call'), matching: find.text('Available')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: cardFor('scam'), matching: find.text('Available')),
        findsOneWidget,
      );
    });
  });

  group('Android', () {
    testWidgets('accessibility-service inspection and firewall read Available',
        (tester) async {
      await pumpScreen(tester, TargetPlatform.android);

      expect(
        find.descendant(
            of: cardFor('stalkerware'), matching: find.text('Available')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: cardFor('firewall'), matching: find.text('Available')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: cardFor('spyware'), matching: find.text('Available')),
        findsOneWidget,
      );
    });
  });

  group('macOS (desktop)', () {
    testWidgets(
        'firewall reads Available; mobile-only secure-call reads not '
        'available on desktop', (tester) async {
      await pumpScreen(tester, TargetPlatform.macOS);

      final firewall = cardFor('firewall');
      expect(
        find.descendant(of: firewall, matching: find.text('Available')),
        findsOneWidget,
      );

      final secureCall = cardFor('secure_call');
      expect(
        find.descendant(of: secureCall, matching: find.text('Not available')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: secureCall,
            matching: find.textContaining('Not available on desktop')),
        findsOneWidget,
      );
    });
  });
}
