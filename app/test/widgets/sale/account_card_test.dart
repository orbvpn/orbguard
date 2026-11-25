// The account card at the top of Me: who is signed in, and that one OrbVPN
// account covers all three apps. Signed out, the whole card is the way in.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/account/security_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/sale/account_card.dart';

import '../../support/real_fonts.dart';
import '../../support/sale_fakes.dart';

const String _note = 'One OrbVPN account for OrbGuard, OrbVPN and OrbBrowser';

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  Future<FakeSaleAccount> pumpCard(
    WidgetTester tester, {
    bool loggedIn = true,
    String? name = 'Sara Ahmadi',
    String? email = 'sara@example.com',
    double width = 390,
    bool dark = true,
  }) async {
    final FakeSaleAccount account =
        FakeSaleAccount(loggedIn: loggedIn, name: name, mail: email);
    final SaleCredits credits = SaleCredits(account: account);
    await pumpSale(
      tester,
      account: account,
      credits: credits.provider,
      width: width,
      dark: dark,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.topCenter, child: AccountCard()),
      ),
    );
    return account;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('signed in: initial, name, email and the one-account note',
      (tester) async {
    await pumpCard(tester);
    expect(find.text('S'), findsOneWidget);
    expect(find.text('Sara Ahmadi'), findsOneWidget);
    expect(find.text('sara@example.com'), findsOneWidget);
    expect(find.text(_note), findsOneWidget);
  });

  testWidgets('with no name, the email is the name and gives the initial',
      (tester) async {
    await pumpCard(tester, name: null, email: 'maya@example.com');
    expect(find.text('M'), findsOneWidget);
    expect(find.text('maya@example.com'), findsOneWidget);
  });

  testWidgets('signed in, pressing it opens account security', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.text('Sara Ahmadi'));
    await settle(tester);
    expect(find.byType(SecurityScreen), findsOneWidget);
  });

  testWidgets('signed out: the card asks to sign in and opens the sheet',
      (tester) async {
    await pumpCard(tester, loggedIn: false);
    expect(find.text('Sign in or create an account'), findsOneWidget);
    expect(find.text(_note), findsOneWidget);
    expect(find.text('sara@example.com'), findsNothing);

    await tester.tap(find.text(_note));
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
        find.ancestor(
            of: find.byType(LoginScreen), matching: find.byType(BottomSheet)),
        findsOneWidget);
  });

  for (final double width in [390.0, 320.0]) {
    for (final bool dark in [true, false]) {
      testWidgets('fits at ${width.toInt()} wide, ${dark ? 'dark' : 'light'}',
          (tester) async {
        for (final bool loggedIn in [true, false]) {
          await pumpCard(tester,
              loggedIn: loggedIn,
              name: 'Alexandra Konstantinopoulou',
              email: 'alexandra.konstantinopoulou@example.com',
              width: width,
              dark: dark);
          expect(tester.takeException(), isNull);
          // A long address may end in an ellipsis; nothing else may.
          expect(
              cutOffText(tester)
                  .where((t) => t != 'alexandra.konstantinopoulou@example.com'),
              isEmpty);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
