// The Me tab (SettingsScreen embedded) in Guard mode: the tab's head, the
// account card, the plan card, then the settings. Nothing about the account
// or the plan shows twice. Pro mode keeps its layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/models/app_mode.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/theme/glass_theme.dart';
import 'package:orbguard/presentation/widgets/page_head.dart';
import 'package:orbguard/providers/settings_provider.dart';
import 'package:orbguard/screens/pricing/pricing_screen.dart';
import 'package:orbguard/screens/settings/settings_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/sale/account_card.dart';
import 'package:orbguard/widgets/sale/plan_card.dart';

import '../support/real_fonts.dart';
import '../support/sale_fakes.dart';

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance(), lb = b.computeLuminance();
  final double hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  Future<SettingsProvider> pumpMe(
    WidgetTester tester, {
    bool pro = false,
    bool loggedIn = false,
    bool premium = false,
    double width = 390,
    double height = 844,
    bool dark = true,
  }) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsProvider settings = SettingsProvider();
    await tester.runAsync(() async {
      await settings.init();
      if (pro) await settings.setAppMode(AppMode.pro);
    });
    final FakeSaleAccount account = FakeSaleAccount(
        loggedIn: loggedIn,
        premium: premium,
        name: 'Sara Ahmadi',
        mail: 'sara@example.com');
    final SaleCredits credits = SaleCredits(account: account, balance: 3);
    await pumpSale(
      tester,
      account: account,
      credits: credits.provider,
      width: width,
      height: height,
      dark: dark,
      extra: [ChangeNotifierProvider<SettingsProvider>.value(value: settings)],
      child: const SettingsScreen(embedded: true),
    );
    await tester.pump(const Duration(milliseconds: 50));
    return settings;
  }

  group('Guard mode', () {
    testWidgets('opens with the head, the account card, then the plan card',
        (tester) async {
      await pumpMe(tester);

      expect(find.widgetWithText(PageHead, 'Me'), findsOneWidget);
      expect(find.byType(AccountCard), findsOneWidget);
      expect(find.byType(PlanCard), findsOneWidget);

      final Rect head = tester.getRect(find.byType(PageHead));
      final Rect acct = tester.getRect(find.byType(AccountCard));
      final Rect plan = tester.getRect(find.byType(PlanCard));
      // The shell draws no header over this tab now.
      expect(head.top, 8);
      expect(acct.top, head.bottom);
      expect(plan.top - acct.bottom, 12);
      // The settings follow the plan card.
      expect(tester.getTopLeft(find.text('Appearance')).dy,
          greaterThan(plan.bottom));
    });

    testWidgets('signed out: no second sign-in or subscription row',
        (tester) async {
      await pumpMe(tester);
      expect(find.text('Sign in / Account'), findsNothing);
      expect(find.text('Subscription'), findsNothing);
      expect(find.text('Sign in or create an account'), findsOneWidget);
    });

    testWidgets('signed in: the email shows once; the account tools stay',
        (tester) async {
      await pumpMe(tester, loggedIn: true, height: 1600);
      expect(find.text('sara@example.com'), findsOneWidget);
      expect(find.text('Subscription'), findsNothing);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Account security'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    for (final double width in [390.0, 320.0]) {
      for (final bool dark in [true, false]) {
        testWidgets(
            'the top fits at ${width.toInt()} wide, '
            '${dark ? 'dark' : 'light'}', (tester) async {
          for (final bool loggedIn in [false, true]) {
            await pumpMe(tester,
                loggedIn: loggedIn, width: width, dark: dark, height: 1600);
            expect(tester.takeException(), isNull);
            expect(cutOffText(tester), isEmpty);
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  });

  group('Pro mode', () {
    testWidgets('keeps its layout under the floating header', (tester) async {
      await pumpMe(tester, pro: true);
      expect(find.byType(PageHead), findsNothing);
      expect(find.byType(AccountCard), findsNothing);
      expect(find.byType(PlanCard), findsNothing);
      expect(find.text('Sign in / Account'), findsOneWidget);
      final double top = tester.getTopLeft(find.text('Account')).dy;
      expect(top, greaterThanOrEqualTo(12 + GlassTheme.headerClearance));
    });

    testWidgets('its subscription row opens the plans as a sheet',
        (tester) async {
      await pumpMe(tester, pro: true);
      await tester.tap(find.text('Subscription'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
          find.ancestor(
              of: find.byType(PricingScreen),
              matching: find.byType(BottomSheet)),
          findsOneWidget);
    });
  });

  group('section labels read in both themes', () {
    for (final bool dark in [true, false]) {
      testWidgets(dark ? 'dark' : 'light', (tester) async {
        await pumpMe(tester, dark: dark, height: 3000);
        final Color bg =
            dark ? AppColors.backgroundDark : AppColors.backgroundLight;
        for (final String label in [
          'Appearance',
          'Protection',
          'Notifications',
          'Privacy & Security',
          'Experience',
          'Advanced',
          'About',
        ]) {
          final Color? ink = tester.widget<Text>(find.text(label)).style?.color;
          expect(ink, isNotNull, reason: label);
          expect(_contrast(ink!, bg), greaterThanOrEqualTo(4.5),
              reason: '$label is too faint on the ${dark ? 'dark' : 'light'} '
                  'background');
        }
      });
    }
  });
}
