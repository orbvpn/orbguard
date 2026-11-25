// Fakes for the places the product is sold: an account whose state a test
// sets by hand, and a real ScanCreditProvider over fake APIs whose ad a test
// can hold open, finish or fail.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/services/ads/rewarded_ad_service.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/services/orbnet/ad_api.dart';
import 'package:orbguard/services/orbnet/models/ad_models.dart';
import 'package:orbguard/services/orbnet/models/passkey_info.dart';
import 'package:orbguard/services/orbnet/scan_credit_api.dart';

/// An account a test sets by hand. [signIn] flips it the way a finished
/// sign-in does: the state changes and listeners hear about it.
class FakeSaleAccount extends AccountProvider {
  FakeSaleAccount({
    bool loggedIn = false,
    this.premium = false,
    this.plan = 'Guard+',
    this.name,
    this.mail,
  })  : _loggedIn = loggedIn,
        super(enableProactiveRefresh: false);

  bool _loggedIn;
  bool premium;
  String plan;
  String? name;
  String? mail;

  void signIn({String? name, String? email}) {
    _loggedIn = true;
    if (name != null) this.name = name;
    if (email != null) mail = email;
    notifyListeners();
  }

  @override
  bool get isInitialized => true;
  @override
  bool get isLoggedIn => _loggedIn;
  @override
  bool get subscriptionValid => premium;
  @override
  bool get hasPremium => _loggedIn && premium;
  @override
  String? get subscriptionTier => hasPremium ? plan : null;
  @override
  String get subscriptionLabel => hasPremium ? plan : 'Free';
  @override
  String? get displayName => _loggedIn ? (name ?? mail) : null;
  @override
  String? get email => _loggedIn ? mail : null;
  @override
  Future<String?> lastLoggedInEmail() async => null;
  @override
  Future<bool> isPasskeyAvailable() async => false;
  @override
  Future<List<PasskeyInfo>> listPasskeys() async => const [];
}

class FakeScanCreditApi implements ScanCreditApi {
  FakeScanCreditApi(this.balance);
  double balance;
  Object? error;

  @override
  Future<double> getBalance() async {
    final Object? e = error;
    if (e != null) throw e;
    return balance;
  }

  @override
  Future<double> consume({int amount = 1}) async {
    if (balance < amount) throw InsufficientScanCreditsException();
    balance -= amount;
    return balance;
  }
}

class FakeAdApi implements AdApi {
  FakeAdApi(this.credits);
  final FakeScanCreditApi credits;

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
  }) async {
    credits.balance += 1;
    return AdRewardResponse(
        success: true, newScanCreditBalance: credits.balance);
  }
}

/// A rewarded-ad network whose ad stays on screen until the test finishes
/// it with [finish].
class FakeAdService implements RewardedAdService {
  FakeAdService({required this.configured});
  final bool configured;
  Completer<bool>? _ad;

  bool get playing => _ad != null;

  void finish(bool rewarded) {
    final Completer<bool>? ad = _ad;
    _ad = null;
    ad?.complete(rewarded);
  }

  @override
  bool get anyNetworkConfigured => configured;
  @override
  String? get preferredProvider => configured ? AdProviderId.unityAds : null;
  @override
  Future<bool> showRewardedAd() {
    _ad = Completer<bool>();
    return _ad!.future;
  }
}

/// The real provider over fakes. Its login probe reads [account].
class SaleCredits {
  SaleCredits({
    required this.account,
    double balance = 0,
    bool adsConfigured = true,
  })  : api = FakeScanCreditApi(balance),
        ads = FakeAdService(configured: adsConfigured) {
    provider = ScanCreditProvider(
      adApi: FakeAdApi(api),
      scanCreditApi: api,
      adService: ads,
      isLoggedIn: () => account.isLoggedIn,
    );
  }

  final AccountProvider account;
  final FakeScanCreditApi api;
  final FakeAdService ads;
  late final ScanCreditProvider provider;
}

/// Wraps [child] the way the app does: the account, the credits, the store,
/// a theme, and a screen [width] wide.
Future<void> pumpSale(
  WidgetTester tester, {
  required AccountProvider account,
  required ScanCreditProvider credits,
  required Widget child,
  double width = 390,
  double height = 844,
  bool dark = true,
  List<SingleChildWidget> extra = const [],
}) async {
  AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
  addTearDown(() => AppColors.uiBrightness = Brightness.dark);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AccountProvider>.value(value: account),
        ChangeNotifierProvider<ScanCreditProvider>.value(value: credits),
        ChangeNotifierProvider<IapService>.value(value: IapService.instance),
        ...extra,
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
}

/// Every piece of text on screen that was cut short.
List<String> cutOffText(WidgetTester tester) {
  final List<String> cut = [];
  for (final RenderParagraph p
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    if (p.didExceedMaxLines) cut.add(p.text.toPlainText());
  }
  return cut;
}

/// Every em dash, en dash, arrow or middle-dot join in text on screen.
List<String> forbiddenMarks(WidgetTester tester) {
  final RegExp marks = RegExp('[—–→←↑↓⇒⇐·]');
  return [
    for (final RenderParagraph p
        in tester.allRenderObjects.whereType<RenderParagraph>())
      if (marks.hasMatch(p.text.toPlainText())) p.text.toPlainText(),
  ];
}
