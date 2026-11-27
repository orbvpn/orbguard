// Tests for the scan-credit gate (ensureScanCredit): what a check a person
// starts costs.
//
//   - A subscriber checks without limit and is never counted.
//   - Anyone else gets the device's first check free, and only the first.
//   - After that a check costs one credit. A phone sends a signed-out person
//     to sign-in and offers an ad or a plan when the credits run out. A Mac
//     offers the plans. Windows and Linux say the check needs OrbGuard
//     Premium, offer sign-in and a plain link, and show no plan, price or
//     store.
//   - When the server cannot be reached the gate says so and the check does
//     not run.
//
// Every test names the device it is about. None reads the machine it runs on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/check_allowance.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/pricing/pricing_screen.dart';
import 'package:orbguard/services/ads/rewarded_ad_service.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/services/orbnet/ad_api.dart';
import 'package:orbguard/services/orbnet/scan_credit_api.dart';
import 'package:orbguard/widgets/scan_credits/credits_sheet.dart';
import 'package:orbguard/widgets/scan_credits/premium_sheet.dart';
import 'package:orbguard/widgets/scan_credits/scan_gate.dart';

import '../support/sale_fakes.dart';

class _FakeAccount extends AccountProvider {
  _FakeAccount({required this.premium, required this.loggedIn})
      : super(enableProactiveRefresh: false);
  final bool premium;
  final bool loggedIn;
  @override
  bool get hasPremium => premium;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  Future<String?> lastLoggedInEmail() async => null;
}

class _FakeScanCredits extends ScanCreditProvider {
  _FakeScanCredits(this._result)
      : super(
          adApi: AdApi(),
          scanCreditApi: ScanCreditApi(),
          adService: DefaultRewardedAdService(),
          isLoggedIn: () => true,
        );
  final ConsumeResult _result;
  int spendCalls = 0;
  @override
  Future<ConsumeResult> spendForScan() async {
    spendCalls++;
    return _result;
  }
}

const String _signIn = 'Sign in';
const String _plans = 'See plans';
const String _link = 'guard.orbai.world';
const String _again = 'Refresh my account';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<bool?> runGate(
    WidgetTester tester, {
    required _FakeAccount account,
    required _FakeScanCredits credits,
    CheckAllowance? allowance,
    LastScanVerdictController? verdict,
  }) async {
    bool? result;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>.value(value: account),
          ChangeNotifierProvider<ScanCreditProvider>.value(value: credits),
          ChangeNotifierProvider<CheckAllowance>.value(
              value: allowance ?? FakeAllowance()),
          if (verdict != null)
            ChangeNotifierProvider<LastScanVerdictController>.value(
                value: verdict),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () async => result = await ensureScanCredit(ctx),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('premium user scans without spending a credit', (tester) async {
    final account = _FakeAccount(premium: true, loggedIn: true);
    final credits = _FakeScanCredits(ConsumeResult.spent(9));
    final result = await runGate(tester, account: account, credits: credits);

    expect(result, isTrue);
    expect(credits.spendCalls, 0); // subscribers are never metered
    account.dispose();
    credits.dispose();
  });

  testWidgets('free user with a credit spends it and proceeds', (tester) async {
    final account = _FakeAccount(premium: false, loggedIn: true);
    final credits = _FakeScanCredits(ConsumeResult.spent(2));
    final result = await runGate(tester, account: account, credits: credits);

    expect(result, isTrue);
    expect(credits.spendCalls, 1);
    account.dispose();
    credits.dispose();
  });

  testWidgets('a real spend error blocks the scan (no silent run)',
      (tester) async {
    final account = _FakeAccount(premium: false, loggedIn: true);
    final credits = _FakeScanCredits(ConsumeResult.failed('Offline', 0));
    final result = await runGate(tester, account: account, credits: credits);

    expect(result, isFalse);
    expect(find.text('Offline'), findsOneWidget); // surfaced, not swallowed
    account.dispose();
    credits.dispose();
  });

  group('the first check is free', () {
    testWidgets('signed out, nothing checked yet: it runs, with no sheet',
        (tester) async {
      final account = _FakeAccount(premium: false, loggedIn: false);
      final credits = _FakeScanCredits(ConsumeResult.spent(0));
      final allowance = FakeAllowance(used: false);
      final result = await runGate(tester,
          account: account, credits: credits, allowance: allowance);

      expect(result, isTrue);
      expect(credits.spendCalls, 0);
      expect(find.byType(BottomSheet), findsNothing);
      expect(allowance.used, isTrue); // and it is gone
      account.dispose();
      credits.dispose();
    });

    testWidgets('signed in with credits: the free one goes first',
        (tester) async {
      final account = _FakeAccount(premium: false, loggedIn: true);
      final credits = _FakeScanCredits(ConsumeResult.spent(2));
      final allowance = FakeAllowance(used: false);
      final result = await runGate(tester,
          account: account, credits: credits, allowance: allowance);

      expect(result, isTrue);
      expect(credits.spendCalls, 0);
      account.dispose();
      credits.dispose();
    });

    testWidgets('only one: the next check costs a credit', (tester) async {
      final account = _FakeAccount(premium: false, loggedIn: true);
      final credits = _FakeScanCredits(ConsumeResult.spent(1));
      final allowance = FakeAllowance(used: false);
      await runGate(tester,
          account: account, credits: credits, allowance: allowance);
      expect(credits.spendCalls, 0);

      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(credits.spendCalls, 1);
      account.dispose();
      credits.dispose();
    });

    testWidgets('a check Home has on record was the free one', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final verdict = LastScanVerdictController();
      await tester.runAsync(() async {
        await verdict.load();
        await verdict.recordScan(
            threats: const [], coveragePercent: 60, now: DateTime.now());
      });
      final account = _FakeAccount(premium: false, loggedIn: true);
      final credits = _FakeScanCredits(ConsumeResult.spent(1));
      final allowance = FakeAllowance(used: false);
      final result = await runGate(tester,
          account: account,
          credits: credits,
          allowance: allowance,
          verdict: verdict);

      expect(result, isTrue);
      expect(credits.spendCalls, 1); // paid for, not free
      expect(allowance.used, isTrue); // and remembered as gone
      account.dispose();
      credits.dispose();
    });

    testWidgets('a subscriber does not use it up', (tester) async {
      final account = _FakeAccount(premium: true, loggedIn: true);
      final credits = _FakeScanCredits(ConsumeResult.spent(9));
      final allowance = FakeAllowance(used: false);
      await runGate(tester,
          account: account, credits: credits, allowance: allowance);

      expect(allowance.used, isFalse);
      account.dispose();
      credits.dispose();
    });
  });

  group('with the sheets', () {
    setUp(() => IapService.instance.debugSeed(available: false, products: []));

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> startGate(
      WidgetTester tester,
      SaleCredits credits,
      void Function(bool) done, {
      TargetPlatform? platform = TargetPlatform.android,
      double width = 390,
      double height = 844,
    }) async {
      await pumpSale(
        tester,
        account: credits.account,
        credits: credits.provider,
        allowance: FakeAllowance(platform: platform),
        width: width,
        height: height,
        child: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () async => done(await ensureScanCredit(ctx)),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await settle(tester);
    }

    BrandButton button(WidgetTester tester, String label) =>
        tester.widget<BrandButton>(find.ancestor(
            of: find.text(label), matching: find.byType(BrandButton)));

    /// No word on the sheet prices, sells or names a store.
    void expectNothingSold(WidgetTester tester) {
      final RegExp sold = RegExp(
          r'[$€£¥]|\bplans?\b|\bbuy\b|subscribe|App Store|Google Play|'
          r'Play Store|Microsoft Store|per month|per year|/mo\b',
          caseSensitive: false);
      final Iterable<Text> words = tester.widgetList<Text>(find.descendant(
          of: find.byType(PremiumSheet), matching: find.byType(Text)));
      expect(words, isNotEmpty);
      for (final Text t in words) {
        expect(sold.hasMatch(t.data ?? ''), isFalse, reason: t.data);
      }
    }

    for (final TargetPlatform phone in const [
      TargetPlatform.android,
      TargetPlatform.iOS
    ]) {
      testWidgets(
          '$phone, signed out: sign-in opens as a sheet, then the check goes on',
          (tester) async {
        final FakeSaleAccount account = FakeSaleAccount();
        final SaleCredits credits = SaleCredits(account: account, balance: 2);
        bool? result;
        await startGate(tester, credits, (r) => result = r, platform: phone);

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(
            find.ancestor(
                of: find.byType(LoginScreen),
                matching: find.byType(BottomSheet)),
            findsOneWidget);

        account.signIn(email: 'a@b.co');
        await settle(tester);

        expect(result, isTrue);
        expect(credits.api.balance, 1); // the credit was spent
      });
    }

    testWidgets('signed out and closing sign-in: no check', (tester) async {
      final FakeSaleAccount account = FakeSaleAccount();
      final SaleCredits credits = SaleCredits(account: account, balance: 2);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      Navigator.of(tester.element(find.byType(LoginScreen))).pop();
      await settle(tester);

      expect(result, isFalse);
      expect(credits.api.balance, 2);
    });

    testWidgets(
        'out of credits: the credits sheet opens; an earned credit '
        'is spent on the check', (tester) async {
      final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
      final SaleCredits credits = SaleCredits(account: account, balance: 0);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      expect(find.byType(CreditsSheet), findsOneWidget);
      await tester.tap(find.text('Watch ad to earn a scan'));
      await tester.pump();
      credits.ads.finish(true);
      await settle(tester);
      expect(find.text('1 scan credit added.'), findsOneWidget);

      // Close the sheet; the gate spends what was earned.
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);

      expect(result, isTrue);
      expect(credits.api.balance, 0);
    });

    testWidgets('out of credits and closing the sheet: no check',
        (tester) async {
      final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
      final SaleCredits credits = SaleCredits(account: account, balance: 0);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      final BrandButton plan = button(tester, 'Go unlimited with a plan');
      expect(plan.variant, BrandButtonVariant.primary);
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);

      expect(result, isFalse);
    });

    testWidgets('a second tap while the gate is open does not spend twice',
        (tester) async {
      final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
      final Completer<void> server = Completer<void>();
      final SaleCredits credits = SaleCredits(account: account, balance: 3)
        ..api.consumeHold = server;
      final List<bool> results = [];
      await pumpSale(
        tester,
        account: account,
        credits: credits.provider,
        child: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () async => results.add(await ensureScanCredit(ctx)),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.tap(find.text('go'));
      server.complete();
      await settle(tester);

      expect(results, unorderedEquals([true, false]));
      expect(credits.api.consumeCalls, 1);
      expect(credits.api.balance, 2);
    });

    for (final TargetPlatform pc in const [
      TargetPlatform.windows,
      TargetPlatform.linux
    ]) {
      group('$pc', () {
        testWidgets(
            'signed out: says it needs Premium, offers sign-in and the link, '
            'and shows no plan, price or store', (tester) async {
          final FakeSaleAccount account = FakeSaleAccount();
          final SaleCredits credits = SaleCredits(account: account, balance: 0);
          bool? result;
          await startGate(tester, credits, (r) => result = r,
              platform: pc, width: 1100, height: 760);

          expect(find.byType(PremiumSheet), findsOneWidget);
          expect(
              find.ancestor(
                  of: find.byType(PremiumSheet),
                  matching: find.byType(BottomSheet)),
              findsOneWidget);
          expect(find.text('This needs OrbGuard Premium'), findsOneWidget);
          expect(button(tester, _signIn).variant, BrandButtonVariant.primary);
          expect(find.text(_link), findsOneWidget);

          // Nothing sold, nothing priced, no store named.
          expect(find.text(_plans), findsNothing);
          expect(find.byType(CreditsSheet), findsNothing);
          expect(find.byType(PricingScreen), findsNothing);
          expect(find.textContaining('Watch ad'), findsNothing);
          expectNothingSold(tester);
          expect(forbiddenMarks(tester), isEmpty);
          expect(result, isNull); // still waiting on the person
        });

        testWidgets('signed out, then into a subscribed account: it runs',
            (tester) async {
          final FakeSaleAccount account = FakeSaleAccount();
          final SaleCredits credits = SaleCredits(account: account, balance: 0);
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          await tester.tap(find.text(_signIn));
          await settle(tester);
          expect(find.byType(LoginScreen), findsOneWidget);

          account.signIn(email: 'a@b.co', premium: true);
          await settle(tester);

          expect(result, isTrue);
          expect(find.byType(PremiumSheet), findsNothing);
          expect(credits.api.consumeCalls, 0); // a subscriber spends nothing
        });

        testWidgets(
            'signed out, then into a free account with a credit: '
            'the credit is spent and it runs', (tester) async {
          final FakeSaleAccount account = FakeSaleAccount();
          final SaleCredits credits = SaleCredits(account: account, balance: 2);
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          await tester.tap(find.text(_signIn));
          await settle(tester);
          account.signIn(email: 'a@b.co');
          await settle(tester);
          await settle(tester);

          expect(result, isTrue);
          expect(credits.api.balance, 1);
        });

        testWidgets(
            'signed out, then into a free account with no credit: '
            'the sheet stays, with no sign-in left to offer', (tester) async {
          final FakeSaleAccount account = FakeSaleAccount();
          final SaleCredits credits = SaleCredits(account: account, balance: 0);
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          await tester.tap(find.text(_signIn));
          await settle(tester);
          account.signIn(email: 'a@b.co');
          await settle(tester);
          await settle(tester);

          expect(result, isNull);
          expect(find.byType(PremiumSheet), findsOneWidget);
          expect(find.text(_signIn), findsNothing);
          expect(find.text('This account has no Premium yet.'), findsOneWidget);
          expectNothingSold(tester);
          expect(button(tester, _again).variant, BrandButtonVariant.primary);
          expect(find.text(_link), findsOneWidget);
        });

        testWidgets('signed in with a credit: it is spent, with no sheet',
            (tester) async {
          final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
          final SaleCredits credits = SaleCredits(account: account, balance: 1);
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          expect(result, isTrue);
          expect(credits.api.balance, 0);
          expect(find.byType(PremiumSheet), findsNothing);
        });

        testWidgets(
            'signed in, out of credits: a plan bought elsewhere is found '
            'by asking again', (tester) async {
          final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
          final SaleCredits credits = SaleCredits(account: account, balance: 0);
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          expect(find.byType(PremiumSheet), findsOneWidget);
          expect(find.text(_signIn), findsNothing);

          // Nothing has changed yet: it says so and stays.
          account.onRefreshEntitlement = () async => true;
          await tester.tap(find.text(_again));
          await settle(tester);
          expect(
              find.text('Still no Premium on this account.'), findsOneWidget);
          expect(result, isNull);

          // Now the account is subscribed.
          account.onRefreshEntitlement = () async {
            account.premium = true;
            return true;
          };
          await tester.tap(find.text(_again));
          await settle(tester);

          expect(result, isTrue);
          expect(account.entitlementRefreshes, 2);
          expect(credits.api.balance, 0);
        });

        testWidgets('asking again when the server cannot be reached says so',
            (tester) async {
          final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
          final SaleCredits credits = SaleCredits(account: account, balance: 0);
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          await tester.tap(find.text(_again));
          await settle(tester);

          expect(
              find.text(
                  'Could not refresh your account. Try again in a moment.'),
              findsOneWidget);
          expect(result, isNull);
        });

        testWidgets('closing the sheet: no check', (tester) async {
          final FakeSaleAccount account = FakeSaleAccount();
          final SaleCredits credits = SaleCredits(account: account, balance: 0);
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          await tester.tapAt(const Offset(20, 20));
          await settle(tester);

          expect(result, isFalse);
          expect(credits.api.consumeCalls, 0);
        });

        testWidgets('the server cannot be reached: it says so, no check',
            (tester) async {
          final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
          final SaleCredits credits = SaleCredits(account: account, balance: 3)
            ..api.consumeError = Exception('down');
          bool? result;
          await startGate(tester, credits, (r) => result = r, platform: pc);

          expect(result, isFalse);
          expect(find.text('Something went wrong. Please try again.'),
              findsOneWidget);
          expect(find.byType(PremiumSheet), findsNothing);
        });
      });
    }

    group('a Mac', () {
      testWidgets('signed out: offers the plans in lime and sign-in in glass',
          (tester) async {
        final FakeSaleAccount account = FakeSaleAccount();
        final SaleCredits credits = SaleCredits(account: account, balance: 0);
        bool? result;
        await startGate(tester, credits, (r) => result = r,
            platform: TargetPlatform.macOS, width: 1100, height: 760);

        expect(find.byType(PremiumSheet), findsOneWidget);
        expect(find.text('This needs OrbGuard Premium'), findsOneWidget);
        expect(button(tester, _plans).variant, BrandButtonVariant.primary);
        expect(button(tester, _signIn).variant, BrandButtonVariant.secondary);
        // One lime action on the sheet.
        expect(
            tester
                .widgetList<BrandButton>(find.descendant(
                    of: find.byType(PremiumSheet),
                    matching: find.byType(BrandButton)))
                .where((b) => b.variant == BrandButtonVariant.primary),
            hasLength(1));
        // The plans are in the app here, so no link leads out of it.
        expect(find.text(_link), findsNothing);
        expect(find.textContaining('Watch ad'), findsNothing);
        expect(forbiddenMarks(tester), isEmpty);
        expect(result, isNull);
      });

      testWidgets('See plans opens the plans over the sheet', (tester) async {
        final FakeSaleAccount account = FakeSaleAccount();
        final SaleCredits credits = SaleCredits(account: account, balance: 0);
        bool? result;
        await startGate(tester, credits, (r) => result = r,
            platform: TargetPlatform.macOS);

        await tester.tap(find.text(_plans));
        await settle(tester);
        expect(find.byType(PricingScreen), findsOneWidget);

        // Closed without buying: back on the sheet, still no check.
        Navigator.of(tester.element(find.byType(PricingScreen))).pop();
        await settle(tester);
        expect(find.byType(PremiumSheet), findsOneWidget);
        expect(result, isNull);
      });

      testWidgets('a plan bought from the sheet lets the check run',
          (tester) async {
        final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
        final SaleCredits credits = SaleCredits(account: account, balance: 0);
        bool? result;
        await startGate(tester, credits, (r) => result = r,
            platform: TargetPlatform.macOS);

        expect(button(tester, _plans).variant, BrandButtonVariant.primary);
        expect(button(tester, _again).variant, BrandButtonVariant.secondary);
        await tester.tap(find.text(_plans));
        await settle(tester);

        // The store confirmed the purchase and the account now has the plan.
        account
          ..premium = true
          ..signIn();
        Navigator.of(tester.element(find.byType(PricingScreen))).pop();
        await settle(tester);

        expect(result, isTrue);
        expect(find.byType(PremiumSheet), findsNothing);
      });

      testWidgets('signed in with a credit: it is spent, with no sheet',
          (tester) async {
        final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
        final SaleCredits credits = SaleCredits(account: account, balance: 1);
        bool? result;
        await startGate(tester, credits, (r) => result = r,
            platform: TargetPlatform.macOS);

        expect(result, isTrue);
        expect(credits.api.balance, 0);
      });
    });

    testWidgets('a browser is treated as a device with no store',
        (tester) async {
      final FakeSaleAccount account = FakeSaleAccount();
      final SaleCredits credits = SaleCredits(account: account, balance: 0);
      await startGate(tester, credits, (_) {}, platform: null);

      expect(find.byType(PremiumSheet), findsOneWidget);
      expect(find.text(_plans), findsNothing);
    });
  });
}
