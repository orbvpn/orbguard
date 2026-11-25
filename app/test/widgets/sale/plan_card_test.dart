// The plan card on the Me tab: the plan the person is on, told plainly, and
// the two ways forward for a free account.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/pricing/pricing_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/sale/plan_card.dart';
import 'package:orbguard/widgets/scan_credits/credits_sheet.dart';

import '../../support/real_fonts.dart';
import '../../support/sale_fakes.dart';

BrandButton _button(WidgetTester tester, String label) =>
    tester.widget<BrandButton>(find.ancestor(
        of: find.text(label), matching: find.byType(BrandButton)));

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  Future<SaleCredits> pumpCard(
    WidgetTester tester, {
    bool loggedIn = true,
    bool premium = false,
    String plan = 'Guard+',
    double balance = 3,
    double width = 390,
    bool dark = true,
  }) async {
    final FakeSaleAccount account =
        FakeSaleAccount(loggedIn: loggedIn, premium: premium, plan: plan);
    final SaleCredits credits = SaleCredits(account: account, balance: balance);
    await pumpSale(
      tester,
      account: account,
      credits: credits.provider,
      width: width,
      dark: dark,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Align(alignment: Alignment.topCenter, child: PlanCard()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return credits;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('free, signed in', () {
    testWidgets('names the plan, the balance and the two ways on',
        (tester) async {
      await pumpCard(tester, balance: 3);
      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('3 scan credits'), findsOneWidget);
      expect(
          find.text('Each check you start uses one credit.'), findsOneWidget);
      expect(_button(tester, 'Earn a credit').variant,
          BrandButtonVariant.secondary);
      expect(
          _button(tester, 'Go unlimited').variant, BrandButtonVariant.primary);
    });

    testWidgets('the chip is amber when no credits are left', (tester) async {
      await pumpCard(tester, balance: 0);
      expect(find.text('0 scan credits'), findsOneWidget);
      expect(tester.widget<Text>(find.text('0 scan credits')).style?.color,
          Brand.amberInk);
    });

    testWidgets('one credit reads in the singular', (tester) async {
      await pumpCard(tester, balance: 1);
      expect(find.text('1 scan credit'), findsOneWidget);
    });

    testWidgets('the chip opens the credits sheet', (tester) async {
      await pumpCard(tester);
      await tester.tap(find.text('3 scan credits'));
      await settle(tester);
      expect(find.byType(CreditsSheet), findsOneWidget);
    });

    testWidgets('Earn a credit opens the credits sheet', (tester) async {
      await pumpCard(tester);
      await tester.tap(find.text('Earn a credit'));
      await settle(tester);
      expect(find.byType(CreditsSheet), findsOneWidget);
    });

    testWidgets('Go unlimited opens the plans', (tester) async {
      await pumpCard(tester);
      await tester.tap(find.text('Go unlimited'));
      await settle(tester);
      expect(find.byType(PricingScreen), findsOneWidget);
    });
  });

  group('free, signed out', () {
    testWidgets('asks to sign in, or go unlimited', (tester) async {
      await pumpCard(tester, loggedIn: false);
      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('Sign in to get scan credits, or go unlimited.'),
          findsOneWidget);
      expect(find.textContaining('scan credits', findRichText: true),
          findsOneWidget); // only the line; no balance chip
      expect(_button(tester, 'Sign in').variant, BrandButtonVariant.secondary);
      expect(
          _button(tester, 'Go unlimited').variant, BrandButtonVariant.primary);

      await tester.tap(find.text('Sign in'));
      await settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('subscriber', () {
    testWidgets('names the real plan and what it unlocks', (tester) async {
      await pumpCard(tester, premium: true, plan: 'Guard+');
      expect(find.text('Guard+ plan'), findsOneWidget);
      expect(find.text('Unlimited checks'), findsOneWidget);
      expect(tester.widget<Text>(find.text('Unlimited checks')).style?.color,
          Brand.limeInk);
      expect(find.text('Also unlocks OrbVPN and OrbBrowser premium.'),
          findsOneWidget);
      expect(find.byType(BrandButton), findsNothing);
      expect(find.text('Free plan'), findsNothing);
    });
  });

  for (final double width in [390.0, 320.0]) {
    for (final bool dark in [true, false]) {
      testWidgets('fits at ${width.toInt()} wide, ${dark ? 'dark' : 'light'}',
          (tester) async {
        for (final (bool, bool) s in [
          (true, false),
          (false, false),
          (true, true)
        ]) {
          await pumpCard(tester,
              loggedIn: s.$1,
              premium: s.$2,
              plan: 'Guard Ultimate',
              balance: 12.5,
              width: width,
              dark: dark);
          expect(tester.takeException(), isNull);
          expect(cutOffText(tester), isEmpty);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
}
