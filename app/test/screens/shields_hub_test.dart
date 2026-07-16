import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/shields/shields_screen.dart';
import 'package:orbguard/screens/shields/hidden_vpn_proxy_screen.dart';
import 'package:orbguard/screens/shields/secure_call_screen.dart';

/// P2.1 — the consumer **Protect** hub. Guards two things that regress silently:
/// (1) the hub always offers its six plain-English shields, and (2) the two new
/// features are wired to their DEDICATED screens (not the old precursor screens).
///
/// On the host test platform `Platform.isIOS/isAndroid` are both false, so the
/// VPN/proxy + secure-call detectors short-circuit to "can't check here" without
/// touching a native channel — the new screens mount cleanly here.
void main() {
  Widget host() => const MaterialApp(home: Scaffold(body: ShieldsScreen()));

  testWidgets('offers all six plain-English shields', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    for (final title in const [
      'Spyware & Pegasus',
      "Who's watching you",
      'Scam shield',
      'Hidden VPN & proxy',
      'Secure call',
      'Identity & breach',
    ]) {
      expect(find.text(title), findsOneWidget, reason: 'missing shield: $title');
    }
  });

  // The feature screens open on a live "checking…" spinner (a perpetual
  // animation), so we advance past the push transition with fixed pumps rather
  // than pumpAndSettle — the assertion is only that the RIGHT screen mounted.
  testWidgets('Hidden VPN shield opens the dedicated HiddenVpnProxyScreen',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.text('Hidden VPN & proxy'));
    await tester.pump(); // start the route push
    await tester.pump(const Duration(milliseconds: 400)); // past the transition

    expect(find.byType(HiddenVpnProxyScreen), findsOneWidget);
  });

  testWidgets('Secure call shield opens the dedicated SecureCallScreen',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.tap(find.text('Secure call'));
    await tester.pump(); // start the route push
    await tester.pump(const Duration(milliseconds: 400)); // past the transition

    expect(find.byType(SecureCallScreen), findsOneWidget);
  });
}
