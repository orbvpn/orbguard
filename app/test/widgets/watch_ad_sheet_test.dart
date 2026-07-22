// Widget test for WatchAdSheet (Phase A3 — earn-a-scan sheet).
//
// The sheet must be HONEST about availability:
//  • a configured build shows an enabled "Watch ad to earn a scan" action;
//  • an unconfigured build DISABLES the button and shows an "ads aren't
//    available" state — it never offers a reward it can't deliver.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/services/ads/rewarded_ad_service.dart';
import 'package:orbguard/services/orbnet/ad_api.dart';
import 'package:orbguard/services/orbnet/models/ad_models.dart';
import 'package:orbguard/services/orbnet/scan_credit_api.dart';
import 'package:orbguard/widgets/scan_credits/watch_ad_sheet.dart';

class _FakeAdApi implements AdApi {
  @override
  Future<AdSession> startScanAdSession({
    required String provider,
    required String platform,
    String? deviceId,
  }) async =>
      AdSession(id: 1, token: 't', provider: provider);

  @override
  Future<AdRewardResponse> verifyScanAd({
    required int sessionId,
    required String token,
  }) async =>
      const AdRewardResponse(success: true);
}

class _FakeScanCreditApi implements ScanCreditApi {
  final double bal;
  _FakeScanCreditApi(this.bal);
  @override
  Future<double> getBalance() async => bal;
  @override
  Future<double> consume({int amount = 1}) async => bal;
}

class _FakeAdService implements RewardedAdService {
  final bool configured;
  _FakeAdService(this.configured);
  @override
  bool get anyNetworkConfigured => configured;
  @override
  String? get preferredProvider =>
      configured ? AdProviderId.unityAds : null;
  @override
  Future<bool> showRewardedAd() async => false;
}

ScanCreditProvider _provider({required bool configured}) => ScanCreditProvider(
      adApi: _FakeAdApi(),
      scanCreditApi: _FakeScanCreditApi(0),
      adService: _FakeAdService(configured),
      // Logged out is fine for these tests — availability depends on the ad
      // service, and refresh() safely no-ops (balance 0) when logged out.
      isLoggedIn: () => false,
    );

Future<void> _pumpSheet(WidgetTester tester, ScanCreditProvider p) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: WatchAdSheet(provider: p))),
  );
  await tester.pumpAndSettle();
}

/// The BrandButton whose label is [label] (the sheet now has TWO buttons: the
/// primary earn action and the secondary "Go unlimited with a plan").
BrandButton _buttonLabeled(WidgetTester tester, String label) =>
    tester.widget<BrandButton>(
      find.ancestor(of: find.text(label), matching: find.byType(BrandButton)),
    );

void main() {
  testWidgets('configured → enabled primary earn action', (tester) async {
    await _pumpSheet(tester, _provider(configured: true));

    expect(find.text('Watch ad to earn a scan'), findsOneWidget);
    final btn = _buttonLabeled(tester, 'Watch ad to earn a scan');
    expect(btn.onPressed, isNotNull,
        reason: 'earn button must be tappable when a network is configured');
  });

  testWidgets('not configured → disabled button + honest unavailable copy',
      (tester) async {
    await _pumpSheet(tester, _provider(configured: false));

    expect(find.textContaining("aren't available"), findsOneWidget);
    expect(find.text('Watch ad to earn a scan'), findsNothing);
    final btn = _buttonLabeled(tester, 'Ads unavailable');
    expect(btn.onPressed, isNull,
        reason: 'must never offer a reward it cannot deliver');
  });

  testWidgets('always offers the subscription path (even when ads are down)',
      (tester) async {
    // Ads unavailable is exactly when the plan path matters most.
    await _pumpSheet(tester, _provider(configured: false));

    expect(find.text('Go unlimited with a plan'), findsOneWidget);
    final btn = _buttonLabeled(tester, 'Go unlimited with a plan');
    expect(btn.onPressed, isNotNull,
        reason: 'the paywall path must stay available regardless of ad state');
  });
}
