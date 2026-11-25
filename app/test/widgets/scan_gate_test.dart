// Tests for the scan-credit gate (ensureScanCredit): the metering decision for
// user-initiated scans. Covers the deterministic branches (premium bypass,
// a free user who has a credit, and a real error) and the two sheets it
// opens: sign-in for a signed-out person, credits for one who is out.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/services/ads/rewarded_ad_service.dart';
import 'package:orbguard/services/orbnet/ad_api.dart';
import 'package:orbguard/services/orbnet/scan_credit_api.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/scan_credits/credits_sheet.dart';
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

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  Future<bool?> runGate(
    WidgetTester tester, {
    required _FakeAccount account,
    required _FakeScanCredits credits,
  }) async {
    bool? result;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>.value(value: account),
          ChangeNotifierProvider<ScanCreditProvider>.value(value: credits),
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

  group('with the sheets', () {
    setUp(() => IapService.instance.debugSeed(available: false, products: []));

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    Future<void> startGate(WidgetTester tester, SaleCredits credits,
        void Function(bool) done) async {
      await pumpSale(
        tester,
        account: credits.account,
        credits: credits.provider,
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

    testWidgets('signed out: sign-in opens as a sheet, then the check goes on',
        (tester) async {
      final FakeSaleAccount account = FakeSaleAccount();
      final SaleCredits credits = SaleCredits(account: account, balance: 2);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
          find.ancestor(
              of: find.byType(LoginScreen), matching: find.byType(BottomSheet)),
          findsOneWidget);

      account.signIn(email: 'a@b.co');
      await settle(tester);

      expect(result, isTrue);
      expect(credits.api.balance, 1); // the credit was spent
    });

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

      final BrandButton plan = tester.widget<BrandButton>(find.ancestor(
          of: find.text('Go unlimited with a plan'),
          matching: find.byType(BrandButton)));
      expect(plan.variant, BrandButtonVariant.primary);
      await tester.tapAt(const Offset(20, 20));
      await settle(tester);

      expect(result, isFalse);
    });
  });
}
