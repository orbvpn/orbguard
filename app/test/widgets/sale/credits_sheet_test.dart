// The credits sheet: the free path, told honestly. One credit per check, the
// balance as the server gave it, an ad to earn one when this build can show
// ads, and the one lime way out of counting: a plan.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/pricing/pricing_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/scan_credits/credits_sheet.dart';

import '../../support/real_fonts.dart';
import '../../support/sale_fakes.dart';

const String _ad = 'Watch ad to earn a scan';
const String _plan = 'Go unlimited with a plan';

BrandButton _button(WidgetTester tester, String label) =>
    tester.widget<BrandButton>(find.ancestor(
        of: find.text(label), matching: find.byType(BrandButton)));

Color? _ink(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  /// Opens the sheet from a button, the way the app does, and lets its
  /// balance refresh land. [result] receives what the sheet completed with.
  Future<SaleCredits> open(
    WidgetTester tester, {
    bool loggedIn = true,
    double balance = 3,
    bool ads = true,
    double width = 390,
    bool dark = true,
    void Function(bool?)? result,
    Object? refreshError,
  }) async {
    final FakeSaleAccount account = FakeSaleAccount(loggedIn: loggedIn);
    final SaleCredits credits =
        SaleCredits(account: account, balance: balance, adsConfigured: ads);
    credits.api.error = refreshError;
    await pumpSale(
      tester,
      account: account,
      credits: credits.provider,
      width: width,
      dark: dark,
      child: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              final bool? r = await showCreditsSheet(context);
              result?.call(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return credits;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  group('signed in', () {
    testWidgets('shows the balance as one numeral, then the two ways on',
        (tester) async {
      await open(tester, balance: 3);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('scan credits'), findsOneWidget);
      expect(
          find.text('Each check you start uses one credit.'), findsOneWidget);

      final BrandButton ad = _button(tester, _ad);
      expect(ad.variant, BrandButtonVariant.secondary);
      expect(ad.onPressed, isNotNull);
      final BrandButton plan = _button(tester, _plan);
      expect(plan.variant, BrandButtonVariant.primary);
      expect(plan.onPressed, isNotNull);
      // The ad button sits above the plan button.
      expect(tester.getTopLeft(find.text(_ad)).dy,
          lessThan(tester.getTopLeft(find.text(_plan)).dy));
      // One lime action on the sheet.
      expect(
          tester
              .widgetList<BrandButton>(find.byType(BrandButton))
              .where((b) => b.variant == BrandButtonVariant.primary),
          hasLength(1));
    });

    testWidgets('one credit reads in the singular', (tester) async {
      await open(tester, balance: 1);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('scan credit'), findsOneWidget);
    });

    testWidgets('a part credit prints with one decimal', (tester) async {
      await open(tester, balance: 2.5);
      expect(find.text('2.5'), findsOneWidget);
    });

    testWidgets('out of credits says so', (tester) async {
      await open(tester, balance: 0);
      expect(find.text('0'), findsOneWidget);
      expect(find.text('You are out of credits. Earn one, or go unlimited.'),
          findsOneWidget);
    });

    testWidgets('no ads in this build: the ad button is off and says why',
        (tester) async {
      await open(tester, ads: false);
      expect(_button(tester, _ad).onPressed, isNull);
      expect(
          find.text(
              'A credit cannot be earned by watching an ad in this build yet.'),
          findsOneWidget);
      // The plan path stays open, which is when it matters most.
      expect(_button(tester, _plan).onPressed, isNotNull);
    });

    testWidgets('while the ad plays the button shows progress and is off',
        (tester) async {
      bool? result;
      final SaleCredits credits =
          await open(tester, balance: 0, result: (r) => result = r);

      await tester.tap(find.text(_ad));
      await tester.pump();
      expect(credits.ads.playing, isTrue);
      final BrandButton playing = tester.widget<BrandButton>(
          find.byWidgetPredicate((w) =>
              w is BrandButton && w.variant == BrandButtonVariant.secondary));
      expect(playing.isLoading, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      credits.ads.finish(true);
      await settle(tester);

      expect(find.text('1 scan credit added.'), findsOneWidget);
      expect(_ink(tester, '1 scan credit added.'), AppColors.accentInk);
      expect(find.text('1'), findsOneWidget);

      // Closed by a drag or the barrier, the earned credit still counts.
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);
      expect(result, isTrue);
    });

    testWidgets('an ad that did not finish shows the reason in error ink',
        (tester) async {
      final SaleCredits credits = await open(tester);
      await tester.tap(find.text(_ad));
      await tester.pump();
      credits.ads.finish(false);
      await settle(tester);

      const String msg =
          "The ad didn't finish, so no credit was earned. Try again.";
      expect(find.text(msg), findsOneWidget);
      expect(_ink(tester, msg), AppColors.errorInk);
      expect(find.text('1 scan credit added.'), findsNothing);
    });

    testWidgets('a balance that could not load shows the error, no numeral',
        (tester) async {
      await open(tester, refreshError: Exception('down'));
      expect(find.text('Scan credits'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      expect(
          find.text('Something went wrong. Please try again.'), findsOneWidget);
    });

    testWidgets('Go unlimited closes this sheet and opens the plans',
        (tester) async {
      bool? result = true;
      bool done = false;
      await open(tester, result: (r) {
        result = r;
        done = true;
      });
      await tester.tap(find.text(_plan));
      await settle(tester);

      expect(done, isTrue);
      expect(result, isNot(isTrue));
      expect(find.text(_plan), findsNothing);
      expect(find.byType(PricingScreen), findsOneWidget);
    });
  });

  group('signed out', () {
    testWidgets('no numeral, a heading, and Sign in in place of the ad',
        (tester) async {
      await open(tester, loggedIn: false);

      expect(find.text('Scan credits'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(
          find.text('Each check you start uses one credit. Sign in to get '
              'yours.'),
          findsOneWidget);
      expect(find.text(_ad), findsNothing);
      final BrandButton signIn = _button(tester, 'Sign in');
      expect(signIn.variant, BrandButtonVariant.secondary);
      expect(_button(tester, _plan).variant, BrandButtonVariant.primary);

      await tester.tap(find.text('Sign in'));
      await settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('signing in from it brings the balance', (tester) async {
      final SaleCredits credits = await open(tester, loggedIn: false);
      await tester.tap(find.text('Sign in'));
      await settle(tester);

      (credits.account as FakeSaleAccount).signIn(email: 'a@b.co');
      await settle(tester);

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('3'), findsOneWidget);
      expect(find.text(_ad), findsOneWidget);
    });
  });

  group('fits', () {
    for (final double width in [390.0, 320.0]) {
      for (final bool dark in [true, false]) {
        final String name = '${width.toInt()} wide, ${dark ? 'dark' : 'light'}';
        testWidgets('every state at $name', (tester) async {
          for (final (bool, double, bool) s in [
            (true, 3, true),
            (true, 0, false),
            (false, 0, true),
          ]) {
            await open(tester,
                loggedIn: s.$1,
                balance: s.$2,
                ads: s.$3,
                width: width,
                dark: dark);
            expect(tester.takeException(), isNull, reason: name);
            expect(cutOffText(tester), isEmpty, reason: name);
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  });
}
