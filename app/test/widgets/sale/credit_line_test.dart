// The sale line under a check's results: how many scan credits are left, and
// one press to the credits sheet. A subscriber sees nothing: there is
// nothing to count.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/sale/credit_line.dart';
import 'package:orbguard/widgets/scan_credits/credits_sheet.dart';

import '../../support/real_fonts.dart';
import '../../support/sale_fakes.dart';

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  Future<SaleCredits> pumpLine(
    WidgetTester tester, {
    bool loggedIn = true,
    bool premium = false,
    double balance = 3,
    double width = 390,
    bool dark = true,
  }) async {
    final FakeSaleAccount account =
        FakeSaleAccount(loggedIn: loggedIn, premium: premium);
    final SaleCredits credits = SaleCredits(account: account, balance: balance);
    await pumpSale(
      tester,
      account: account,
      credits: credits.provider,
      width: width,
      dark: dark,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 22),
        child: Align(alignment: Alignment.topCenter, child: CreditLine()),
      ),
    );
    // The balance it fetched lands.
    await tester.pump(const Duration(milliseconds: 50));
    return credits;
  }

  testWidgets('a free account sees what is left, and Go unlimited',
      (tester) async {
    await pumpLine(tester, balance: 3);
    expect(find.text('3 scan credits left'), findsOneWidget);
    expect(find.text('Go unlimited'), findsOneWidget);
  });

  testWidgets('one left reads in the singular, none left says 0',
      (tester) async {
    await pumpLine(tester, balance: 1);
    expect(find.text('1 scan credit left'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpLine(tester, balance: 0);
    expect(find.text('0 scan credits left'), findsOneWidget);
  });

  testWidgets('signed out, it says later checks use credits', (tester) async {
    await pumpLine(tester, loggedIn: false);
    expect(find.text('Later checks use scan credits'), findsOneWidget);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets('a subscriber sees nothing', (tester) async {
    await pumpLine(tester, premium: true);
    expect(find.byType(SizedBox), findsWidgets);
    expect(tester.getSize(find.byType(CreditLine)), Size.zero);
    expect(find.text('Go unlimited'), findsNothing);
  });

  testWidgets('the whole row is one button that opens the credits sheet',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpLine(tester);
    expect(
        find.descendant(
            of: find.byType(CreditLine),
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && (w.properties.button ?? false))),
        findsOneWidget);
    handle.dispose();

    // A press anywhere on it, even the far end of its text.
    await tester.tap(find.text('3 scan credits left'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(CreditsSheet), findsOneWidget);
  });

  for (final double width in [390.0, 320.0]) {
    for (final bool dark in [true, false]) {
      testWidgets('fits at ${width.toInt()} wide, ${dark ? 'dark' : 'light'}',
          (tester) async {
        for (final bool loggedIn in [true, false]) {
          await pumpLine(tester,
              loggedIn: loggedIn, balance: 12.5, width: width, dark: dark);
          expect(tester.takeException(), isNull);
          expect(cutOffText(tester), isEmpty);
          final RenderBox box = tester.renderObject(find.byType(CreditLine));
          expect(box.size.width, lessThanOrEqualTo(width));
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
