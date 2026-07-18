// Unit tests for ScanCreditProvider (Phase A3 — earn/spend scan credits).
//
// Proves the HONEST contract with fakes for the apis + ad service:
//  • a real, verified ad view credits the balance;
//  • a failed/skipped ad credits NOTHING and never calls verify (no fake reward);
//  • an unconfigured build never opens a session — it surfaces an honest error;
//  • a logged-out user can neither earn nor spend;
//  • spendForScan reports success vs out-of-credits (HTTP 402) distinctly.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/services/ads/rewarded_ad_service.dart';
import 'package:orbguard/services/orbnet/ad_api.dart';
import 'package:orbguard/services/orbnet/models/ad_models.dart';
import 'package:orbguard/services/orbnet/scan_credit_api.dart';

class _FakeAdApi implements AdApi {
  int sessionCalls = 0;
  int verifyCalls = 0;
  String? lastProvider;
  Object? sessionError;
  AdRewardResponse reward = const AdRewardResponse(
    success: true,
    scanCreditsEarned: 1,
    newScanCreditBalance: 1,
  );

  @override
  Future<AdSession> startScanAdSession({
    required String provider,
    required String platform,
    String? deviceId,
  }) async {
    sessionCalls++;
    lastProvider = provider;
    final err = sessionError;
    if (err != null) throw err;
    return AdSession(id: 42, token: 'tok-$provider', provider: provider);
  }

  @override
  Future<AdRewardResponse> verifyScanAd({
    required int sessionId,
    required String token,
  }) async {
    verifyCalls++;
    return reward;
  }
}

class _FakeScanCreditApi implements ScanCreditApi {
  double balance;
  bool insufficient;
  int consumeCalls = 0;

  _FakeScanCreditApi({
    this.balance = 0,
    this.insufficient = false,
  });

  @override
  Future<double> getBalance() async => balance;

  @override
  Future<double> consume({int amount = 1}) async {
    consumeCalls++;
    if (insufficient) throw InsufficientScanCreditsException();
    balance -= amount;
    return balance;
  }
}

class _FakeAdService implements RewardedAdService {
  final bool configured;
  final bool reward;
  int showCalls = 0;

  _FakeAdService({this.configured = true, this.reward = true});

  @override
  bool get anyNetworkConfigured => configured;

  @override
  String? get preferredProvider =>
      configured ? AdProviderId.unityAds : null;

  @override
  Future<bool> showRewardedAd() async {
    showCalls++;
    if (!configured) throw AdsNotConfiguredException();
    return reward;
  }
}

ScanCreditProvider _provider({
  _FakeAdApi? adApi,
  _FakeScanCreditApi? creditApi,
  _FakeAdService? adService,
  bool loggedIn = true,
}) {
  return ScanCreditProvider(
    adApi: adApi ?? _FakeAdApi(),
    scanCreditApi: creditApi ?? _FakeScanCreditApi(),
    adService: adService ?? _FakeAdService(),
    isLoggedIn: () => loggedIn,
  );
}

/// Drive watchAdForCredit from inside a real widget callback so a live
/// BuildContext is passed synchronously (no async-gap lint, no fake context).
Future<bool> _watch(WidgetTester tester, ScanCreditProvider p) async {
  bool? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await p.watchAdForCredit(context),
        child: const Text('go'),
      ),
    ),
  ));
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  return result ?? (throw StateError('watchAdForCredit did not complete'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('successful watch credits the balance (real verified reward)',
      (tester) async {
    final adApi = _FakeAdApi()
      ..reward = const AdRewardResponse(
        success: true,
        scanCreditsEarned: 1,
        newScanCreditBalance: 3,
      );
    final creditApi = _FakeScanCreditApi(balance: 3);
    final adService = _FakeAdService(configured: true, reward: true);
    final p = _provider(adApi: adApi, creditApi: creditApi, adService: adService);

    final ok = await _watch(tester, p);

    expect(ok, isTrue);
    expect(p.balance, 3);
    expect(p.lastError, isNull);
    expect(adApi.sessionCalls, 1);
    expect(adApi.lastProvider, AdProviderId.unityAds);
    expect(adApi.verifyCalls, 1);
    expect(adService.showCalls, 1);
  });

  testWidgets('ad failed → no credit, honest error, verify NEVER called',
      (tester) async {
    final adApi = _FakeAdApi();
    final creditApi = _FakeScanCreditApi(balance: 0);
    final adService = _FakeAdService(configured: true, reward: false);
    final p = _provider(adApi: adApi, creditApi: creditApi, adService: adService);

    final ok = await _watch(tester, p);

    expect(ok, isFalse);
    expect(p.balance, 0);
    expect(p.lastError, isNotNull);
    expect(adApi.sessionCalls, 1); // session opened...
    expect(adApi.verifyCalls, 0); // ...but never verified — no fake reward
  });

  testWidgets('ads not configured → honest error, no session opened',
      (tester) async {
    final adApi = _FakeAdApi();
    final adService = _FakeAdService(configured: false);
    final p = _provider(adApi: adApi, adService: adService);

    final ok = await _watch(tester, p);

    expect(ok, isFalse);
    expect(p.adsAvailable, isFalse);
    expect(p.lastError, "Rewarded ads aren't available yet.");
    expect(adApi.sessionCalls, 0);
    expect(adService.showCalls, 0);
  });

  testWidgets('logged-out watch → honest error, no session', (tester) async {
    final adApi = _FakeAdApi();
    final p = _provider(adApi: adApi, loggedIn: false);

    final ok = await _watch(tester, p);

    expect(ok, isFalse);
    expect(p.lastError, contains('Sign in'));
    expect(adApi.sessionCalls, 0);
  });

  test('spendForScan success decrements the balance', () async {
    final creditApi = _FakeScanCreditApi(balance: 2);
    final p = _provider(creditApi: creditApi);

    final r = await p.spendForScan();

    expect(r.success, isTrue);
    expect(r.outOfCredits, isFalse);
    expect(r.balance, 1);
    expect(p.balance, 1);
    expect(creditApi.consumeCalls, 1);
  });

  test('spendForScan out of credits (HTTP 402) → outOfCredits result',
      () async {
    final creditApi = _FakeScanCreditApi(balance: 0, insufficient: true);
    final p = _provider(creditApi: creditApi);

    final r = await p.spendForScan();

    expect(r.success, isFalse);
    expect(r.outOfCredits, isTrue);
    expect(r.error, isNull);
    expect(creditApi.consumeCalls, 1);
  });

  test('spendForScan while logged out → failed result, no consume call',
      () async {
    final creditApi = _FakeScanCreditApi(balance: 5);
    final p = _provider(creditApi: creditApi, loggedIn: false);

    final r = await p.spendForScan();

    expect(r.success, isFalse);
    expect(r.outOfCredits, isFalse);
    expect(r.error, isNotNull);
    expect(creditApi.consumeCalls, 0);
  });

  test('refresh pulls the balance from the api', () async {
    final creditApi = _FakeScanCreditApi(balance: 7);
    final p = _provider(creditApi: creditApi);

    await p.refresh();

    expect(p.balance, 7);
    expect(p.loading, isFalse);
    expect(p.lastError, isNull);
  });
}
