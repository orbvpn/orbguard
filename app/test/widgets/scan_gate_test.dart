// Tests for the scan-credit gate (ensureScanCredit): the metering decision for
// user-initiated scans. Covers the deterministic branches — premium bypass,
// a free user who has a credit, and a real error — without driving the
// Navigator/sheet UI (the out-of-credits→watch-ad path is exercised on device).

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/services/ads/rewarded_ad_service.dart';
import 'package:orbguard/services/orbnet/ad_api.dart';
import 'package:orbguard/services/orbnet/scan_credit_api.dart';
import 'package:orbguard/widgets/scan_credits/scan_gate.dart';

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
}
