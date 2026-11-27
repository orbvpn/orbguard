import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/on_device_trust_badge.dart';
import 'package:orbguard/screens/trust/privacy_explainer_screen.dart';

/// Phase 3.1 — the Privacy Explainer is OrbGuard's credibility surface: it
/// must actually state the four trust promises in plain English, and the
/// reusable [OnDeviceTrustBadge] must show its label wherever it is dropped.
void main() {
  // The explainer's hero + four cards run taller than the default 800×600
  // test surface, and ListView only builds slivers near the viewport — so a
  // default-size surface would silently fail to find the later cards. Use a
  // tall virtual viewport instead of scrolling so every card is built.
  Future<void> pumpTallScreen(WidgetTester tester,
      {TargetPlatform platform = TargetPlatform.android}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: PrivacyExplainerScreen(platform: platform)));
    await tester.pumpAndSettle();
  }

  testWidgets('states all four trust promises in plain English',
      (tester) async {
    await pumpTallScreen(tester);

    expect(find.text('Everything runs on your phone'), findsOneWidget);
    expect(
      find.text("We can't read your messages or listen to your calls"),
      findsOneWidget,
    );
    expect(find.text('What we keep'), findsOneWidget);
    expect(find.text('Your data is yours'), findsOneWidget);
  });

  // The screen names the device it is drawn for, never the machine the test
  // happens to run on.
  for (final (TargetPlatform platform, String noun) in const [
    (TargetPlatform.android, 'phone'),
    (TargetPlatform.iOS, 'phone'),
    (TargetPlatform.macOS, 'Mac'),
    (TargetPlatform.windows, 'computer'),
  ]) {
    testWidgets('names a ${platform.name} device a $noun', (tester) async {
      await pumpTallScreen(tester, platform: platform);

      expect(find.text('Everything runs on your $noun'), findsOneWidget);
      expect(find.textContaining('Results stay on your $noun'), findsOneWidget);
      expect(find.textContaining('Your $noun simply does not'), findsOneWidget);
    });
  }

  testWidgets('shows the on-device trust badge on the explainer screen',
      (tester) async {
    await pumpTallScreen(tester);

    expect(find.text('Private, on your device'), findsOneWidget);
  });

  testWidgets('OnDeviceTrustBadge shows its label standalone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OnDeviceTrustBadge())),
    );

    expect(find.byType(OnDeviceTrustBadge), findsOneWidget);
    expect(find.text('Private, on your device'), findsOneWidget);
  });
}
