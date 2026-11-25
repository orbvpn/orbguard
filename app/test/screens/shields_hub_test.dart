import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/presentation/widgets/page_head.dart';
import 'package:orbguard/providers/device_security_provider.dart';
import 'package:orbguard/screens/device_security/device_security_screen.dart';
import 'package:orbguard/screens/shields/shields_screen.dart';
import 'package:orbguard/screens/shields/hidden_vpn_proxy_screen.dart';
import 'package:orbguard/screens/shields/secure_call_screen.dart';
import 'package:orbguard/services/home/home_brief.dart';

/// P2.1 — the consumer **Protect** hub. Guards two things that regress silently:
/// (1) the hub always offers its six plain-English shields, and (2) the two new
/// features are wired to their DEDICATED screens (not the old precursor screens).
///
/// On the host test platform `Platform.isIOS/isAndroid` are both false, so the
/// VPN/proxy + secure-call detectors short-circuit to "can't check here" without
/// touching a native channel — the new screens mount cleanly here.
void main() {
  // On the host test platform no platform is a phone, so the "Lost or
  // stolen" section is left out unless a test names a phone.
  Widget host({TargetPlatform? platform}) =>
      MaterialApp(home: Scaffold(body: ShieldsScreen(platform: platform)));

  /// The six cards and the section under them run taller than the default
  /// 600px test surface: use a tall surface so ListView builds every card
  /// without scrolling.
  Future<void> pumpHub(WidgetTester tester, {TargetPlatform? platform}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host(platform: platform));
    await tester.pump();
  }

  testWidgets('opens with the tab\'s own head, saying nothing about state',
      (tester) async {
    await pumpHub(tester);

    final PageHead head = tester.widget(find.byType(PageHead));
    expect(head.title, 'Protect');
    expect(head.subtitle, 'Six shields. Open any one to see what it covers.');
  });

  testWidgets('starts under the status bar, not under a floating header',
      (tester) async {
    await pumpHub(tester);

    // The shell no longer draws its header over this tab.
    final ListView list = tester.widget(find.byType(ListView));
    expect((list.padding! as EdgeInsets).top, 8);
  });

  testWidgets('a phone gets "Find this phone" under the shields',
      (tester) async {
    for (final TargetPlatform phone in [
      TargetPlatform.android,
      TargetPlatform.iOS,
    ]) {
      await pumpHub(tester, platform: phone);
      expect(find.text('LOST OR STOLEN'), findsOneWidget);
      expect(find.text('Find this phone'), findsOneWidget);
      expect(find.text('Locate it, ring it, or photograph whoever has it'),
          findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Find this phone')).dy,
        greaterThan(tester.getTopLeft(find.text(Shield.secureCall.name)).dy),
      );
      // Nothing on the row claims it is or is not set up.
      expect(find.text('Set up'), findsNothing);
    }
  });

  testWidgets('a computer has no "Lost or stolen" section', (tester) async {
    for (final TargetPlatform desk in [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      await pumpHub(tester, platform: desk);
      expect(find.text('LOST OR STOLEN'), findsNothing);
      expect(find.text('Find this phone'), findsNothing);
    }
  });

  testWidgets('"Find this phone" opens the anti-theft screen as a sheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => DeviceSecurityProvider(),
      child: host(platform: TargetPlatform.android),
    ));
    await tester.pump();

    await tester.tap(find.text('Find this phone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(DeviceSecurityScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('names every shield exactly as Home does', (tester) async {
    await pumpHub(tester);

    // One vocabulary: the name a shield carries on Home's orbit is the name
    // it carries here, so nobody has to work out that two words mean one
    // thing.
    for (final shield in Shield.values) {
      expect(find.text(shield.name), findsOneWidget,
          reason: 'missing shield: ${shield.name}');
    }
  });

  testWidgets('lists the shields in the order they sit around the ring',
      (tester) async {
    await pumpHub(tester);

    final tops = [
      for (final shield in Shield.values)
        tester.getTopLeft(find.text(shield.name)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
  });

  testWidgets('does not claim the shields are always watching', (tester) async {
    await pumpHub(tester);

    // Most shields are tools that wait to be used. Only Home, which reads the
    // real guard states, may say that something is on watch.
    expect(find.textContaining(RegExp('always', caseSensitive: false)),
        findsNothing);
  });

  test('no two shields lead to the same screen', () {
    // Home's orbit and this list both open a shield through shieldScreen, so
    // a shield opens the same place from either.
    expect(
      {for (final shield in Shield.values) shieldScreen(shield).runtimeType},
      hasLength(Shield.values.length),
    );
  });

  // The feature screens open on a live "checking…" spinner (a perpetual
  // animation), so we advance past the push transition with fixed pumps rather
  // than pumpAndSettle — the assertion is only that the RIGHT screen mounted.
  testWidgets('Hidden VPN shield opens the dedicated HiddenVpnProxyScreen',
      (tester) async {
    await pumpHub(tester);

    await tester.tap(find.text('Hidden VPN & proxy'));
    await tester.pump(); // start the route push
    await tester.pump(const Duration(milliseconds: 400)); // past the transition

    expect(find.byType(HiddenVpnProxyScreen), findsOneWidget);
  });

  testWidgets('Secure call shield opens the dedicated SecureCallScreen',
      (tester) async {
    await pumpHub(tester);

    await tester.tap(find.text('Secure call'));
    await tester.pump(); // start the route push
    await tester.pump(const Duration(milliseconds: 400)); // past the transition

    expect(find.byType(SecureCallScreen), findsOneWidget);
  });
}
