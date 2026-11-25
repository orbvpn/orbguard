// Plans and sign-in are sheets now, not pages pushed over the app: the place
// the product is sold slides up over what the person was doing, and closes
// back to it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/pricing/pricing_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/sale/login_sheet.dart';
import 'package:orbguard/widgets/sale/plans_sheet.dart';

import '../../support/real_fonts.dart';
import '../../support/sale_fakes.dart';

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  Future<FakeSaleAccount> pumpOpener(
    WidgetTester tester,
    Future<void> Function(BuildContext) open,
  ) async {
    final FakeSaleAccount account = FakeSaleAccount();
    final SaleCredits credits = SaleCredits(account: account);
    await pumpSale(
      tester,
      account: account,
      credits: credits.provider,
      child: Builder(
        builder: (context) => Center(
          child: TextButton(
              onPressed: () => open(context), child: const Text('open')),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return account;
  }

  group('showPlansSheet', () {
    testWidgets('presents the pricing screen in a tall sheet', (tester) async {
      bool closed = false;
      await pumpOpener(tester, (ctx) async {
        await showPlansSheet(ctx);
        closed = true;
      });

      expect(find.byType(PricingScreen), findsOneWidget);
      expect(
          find.ancestor(
              of: find.byType(PricingScreen),
              matching: find.byType(BottomSheet)),
          findsOneWidget);
      // 0.94 of the screen, the pricing screen's own page inside it.
      final double h = tester.getSize(find.byType(PricingScreen)).height;
      expect(h, greaterThan(844 * 0.85));
      expect(h, lessThan(844));

      // Its own back button closes the sheet and the future completes.
      Navigator.of(tester.element(find.byType(PricingScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(PricingScreen), findsNothing);
      expect(closed, isTrue);
    });
  });

  group('showLoginSheet', () {
    testWidgets('presents the sign-in screen in a sheet', (tester) async {
      await pumpOpener(tester, (ctx) => showLoginSheet(ctx));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
          find.ancestor(
              of: find.byType(LoginScreen), matching: find.byType(BottomSheet)),
          findsOneWidget);
    });

    testWidgets('closes with true when the person signs in', (tester) async {
      bool? result;
      bool done = false;
      final FakeSaleAccount account = await pumpOpener(tester, (ctx) async {
        result = await showLoginSheet(ctx);
        done = true;
      });
      expect(find.byType(LoginScreen), findsOneWidget);

      // The sign-in finishes; LoginScreen closes its own route with true,
      // and that route is the sheet.
      account.signIn(email: 'a@b.co');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(LoginScreen), findsNothing);
      expect(done, isTrue);
      expect(result, isTrue);
      // Only the sheet closed: the screen that opened it is still there.
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('closing it without signing in is not a sign-in',
        (tester) async {
      bool? result;
      bool done = false;
      await pumpOpener(tester, (ctx) async {
        result = await showLoginSheet(ctx);
        done = true;
      });

      Navigator.of(tester.element(find.byType(LoginScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(done, isTrue);
      expect(result, isNot(isTrue));
      expect(find.text('open'), findsOneWidget);
    });
  });
}
