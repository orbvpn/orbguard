// The Amazon Appstore build sells nothing. Amazon rejects any purchase path
// outside its own, any pointer to paying elsewhere, ads, and account
// creation in an app without its billing. So in that build:
//
//   - The first check is free. After it, a check spends a credit the
//     account already holds, or the Premium sheet says the check needs
//     OrbGuard Premium and offers sign-in. No plan, price, ad, store or site.
//   - The Me tab's cards, the Expert mode upsell and Settings show the plan
//     an account has and nothing to buy, earn, manage or restore.
//   - Sign-in offers only the ways that never create an account, and the
//     email link asks the server not to create one.
//   - The legal text names no site and no store.
//
// The build turns this on with --dart-define=ORB_AMAZON_BUILD=true. These
// tests turn it on with AmazonBuildScope instead, so they need no define.
// Every test names the device it is about. None reads the machine it runs on.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/legal/legal_documents.dart';
import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/providers/settings_provider.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/legal/legal_screen.dart';
import 'package:orbguard/screens/pricing/pricing_screen.dart';
import 'package:orbguard/screens/settings/settings_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/services/orbnet/orbnet_api_client.dart';
import 'package:orbguard/utils/amazon_build.dart';
import 'package:orbguard/widgets/premium/premium_gate.dart';
import 'package:orbguard/widgets/sale/account_card.dart';
import 'package:orbguard/widgets/sale/credit_line.dart';
import 'package:orbguard/widgets/sale/plan_card.dart';
import 'package:orbguard/widgets/scan_credits/credits_sheet.dart';
import 'package:orbguard/widgets/scan_credits/premium_sheet.dart';
import 'package:orbguard/widgets/scan_credits/scan_gate.dart';

import '../services/orbnet/fake_two_factor_server.dart';
import '../support/sale_fakes.dart';

const String _signIn = 'Sign in';
const String _again = 'Refresh my account';

/// Any word that sells, prices, earns, names a store or a site to pay at,
/// or creates an account.
final RegExp _sold = RegExp(
    r'[$€£¥]|orbai\.world|orbvpn\.com|\bplans\b|see plans|go unlimited|'
    r'\bbuy\b|subscribe|restore purchases|manage subscription|'
    r'App Store|Google Play|Play Store|Microsoft Store|Amazon|'
    r'per month|per year|/mo\b|renews|watch (an )?ads?\b|earn a|ad-free|'
    r'create an account|sign up|continue with google|continue with apple',
    caseSensitive: false);

/// Every piece of text on screen, sheets and routes included.
List<String> _allText(WidgetTester tester) => [
      for (final RenderParagraph p
          in tester.allRenderObjects.whereType<RenderParagraph>())
        p.text.toPlainText(),
      for (final RenderEditable e
          in tester.allRenderObjects.whereType<RenderEditable>())
        e.text?.toPlainText() ?? '',
    ];

void _expectNothingSold(WidgetTester tester) {
  final List<String> words = _allText(tester);
  expect(words, isNotEmpty);
  for (final String w in words) {
    expect(_sold.hasMatch(w), isFalse, reason: w);
  }
  expect(forbiddenMarks(tester), isEmpty);
}

BrandButton _button(WidgetTester tester, String label) =>
    tester.widget<BrandButton>(find.ancestor(
        of: find.text(label), matching: find.byType(BrandButton)));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    IapService.instance.debugSeed(available: false, products: []);
  });

  test('the Play build is the default: no define, no Amazon', () {
    expect(kAmazonBuild, isFalse);
  });

  group('the scan gate on an Android phone', () {
    Future<void> startGate(
      WidgetTester tester,
      SaleCredits credits,
      void Function(bool) done, {
      bool freeCheckUsed = true,
    }) async {
      await pumpSale(
        tester,
        amazon: true,
        account: credits.account,
        credits: credits.provider,
        allowance: FakeAllowance(
            platform: TargetPlatform.android, used: freeCheckUsed),
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
      await _settle(tester);
    }

    testWidgets('the first check is free, with no sheet', (tester) async {
      final FakeSaleAccount account = FakeSaleAccount();
      final SaleCredits credits = SaleCredits(account: account, balance: 0);
      bool? result;
      await startGate(tester, credits, (r) => result = r, freeCheckUsed: false);

      expect(result, isTrue);
      expect(find.byType(PremiumSheet), findsNothing);
      expect(credits.api.consumeCalls, 0);
    });

    testWidgets(
        'signed out: the Premium sheet says it needs Premium and offers only '
        'sign-in, with no plan, price, ad, store or site', (tester) async {
      final FakeSaleAccount account = FakeSaleAccount();
      final SaleCredits credits = SaleCredits(account: account, balance: 0);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      expect(find.byType(PremiumSheet), findsOneWidget);
      expect(
          find.ancestor(
              of: find.byType(PremiumSheet),
              matching: find.byType(BottomSheet)),
          findsOneWidget);
      expect(find.text('This needs OrbGuard Premium'), findsOneWidget);
      expect(
          find.text(
              'The first check is free. More checks need OrbGuard Premium.'),
          findsOneWidget);
      expect(find.text('Already have Premium? Sign in and it works here too.'),
          findsOneWidget);
      // Sign-in is the one lime action, and the only one.
      expect(_button(tester, _signIn).variant, BrandButtonVariant.primary);
      expect(
          find.descendant(
              of: find.byType(PremiumSheet),
              matching: find.byType(BrandButton)),
          findsOneWidget);

      expect(find.text(PremiumSheet.siteLabel), findsNothing);
      expect(find.byType(CreditsSheet), findsNothing);
      expect(find.byType(PricingScreen), findsNothing);
      _expectNothingSold(tester);
      expect(result, isNull); // still waiting on the person
    });

    testWidgets(
        'signed out, sign-in offers no Google or Apple, and a subscribed '
        'account goes on without spending', (tester) async {
      final FakeSaleAccount account = FakeSaleAccount();
      final SaleCredits credits = SaleCredits(account: account, balance: 0);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      await tester.tap(find.text(_signIn));
      await _settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Continue with Apple'), findsNothing);
      expect(find.text('Email me a sign-in link'), findsOneWidget);
      _expectNothingSold(tester);

      account.signIn(email: 'a@b.co', premium: true);
      await _settle(tester);

      expect(result, isTrue);
      expect(find.byType(PremiumSheet), findsNothing);
      expect(credits.api.consumeCalls, 0);
    });

    testWidgets(
        'signed in with no credit: says the account has no Premium, and '
        'asking again is the one action', (tester) async {
      final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
      final SaleCredits credits = SaleCredits(account: account, balance: 0);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      expect(find.byType(PremiumSheet), findsOneWidget);
      expect(find.text('This account has no Premium yet.'), findsOneWidget);
      expect(find.text(_signIn), findsNothing);
      expect(_button(tester, _again).variant, BrandButtonVariant.primary);
      expect(find.text(PremiumSheet.siteLabel), findsNothing);
      expect(find.byType(CreditsSheet), findsNothing);
      _expectNothingSold(tester);
      expect(result, isNull);

      // A plan the account got elsewhere is found by asking again.
      account.onRefreshEntitlement = () async {
        account.premium = true;
        return true;
      };
      await tester.tap(find.text(_again));
      await _settle(tester);
      expect(result, isTrue);
    });

    testWidgets('signed in with a credit it already holds: it is spent',
        (tester) async {
      final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
      final SaleCredits credits = SaleCredits(account: account, balance: 1);
      bool? result;
      await startGate(tester, credits, (r) => result = r);

      expect(result, isTrue);
      expect(credits.api.balance, 0);
      expect(find.byType(PremiumSheet), findsNothing);
      expect(credits.ads.playing, isFalse); // no ad, ever
    });
  });

  group('the Me tab cards', () {
    Future<FakeSaleAccount> pumpCards(
      WidgetTester tester, {
      bool loggedIn = false,
      bool premium = false,
      double balance = 3,
    }) async {
      final FakeSaleAccount account = FakeSaleAccount(
          loggedIn: loggedIn, premium: premium, mail: 'sara@example.com');
      final SaleCredits credits =
          SaleCredits(account: account, balance: balance);
      await pumpSale(
        tester,
        amazon: true,
        account: account,
        credits: credits.provider,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [AccountCard(), PlanCard(), CreditLine()],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      return account;
    }

    testWidgets(
        'signed out: the account card asks to sign in, and the plan card '
        'says what more checks need and offers sign-in', (tester) async {
      await pumpCards(tester);

      expect(find.text('Sign in or create an account'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(AccountCard), matching: find.text(_signIn)),
          findsOneWidget);
      expect(find.text('Free plan'), findsOneWidget);
      expect(
          find.text(
              'The first check is free. More checks need OrbGuard Premium.'),
          findsOneWidget);
      expect(_button(tester, _signIn).variant, BrandButtonVariant.primary);
      expect(find.textContaining('credit'), findsNothing);
      _expectNothingSold(tester);

      await tester.tap(find.descendant(
          of: find.byType(PlanCard), matching: find.text(_signIn)));
      await _settle(tester);
      expect(
          find.ancestor(
              of: find.byType(LoginScreen), matching: find.byType(BottomSheet)),
          findsOneWidget);
      expect(find.byType(CreditsSheet), findsNothing);
      expect(find.byType(PricingScreen), findsNothing);
    });

    testWidgets(
        'signed in and free: no button, no balance, no credits line, and '
        'nothing to earn', (tester) async {
      await pumpCards(tester, loggedIn: true);

      expect(find.text('This account has no Premium yet.'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(PlanCard), matching: find.byType(BrandButton)),
          findsNothing);
      expect(
          find.descendant(
              of: find.byType(CreditLine), matching: find.byType(Text)),
          findsNothing);
      expect(find.textContaining('credit'), findsNothing);
      _expectNothingSold(tester);
    });

    testWidgets('a subscriber sees the plan the account has', (tester) async {
      await pumpCards(tester, loggedIn: true, premium: true);

      expect(find.text('Guard+ plan'), findsOneWidget);
      expect(find.text('Unlimited checks'), findsOneWidget);
      _expectNothingSold(tester);
    });
  });

  group('the Expert mode upsell', () {
    Future<void> upsell(WidgetTester tester, FakeSaleAccount account) async {
      await pumpSale(
        tester,
        amazon: true,
        account: account,
        credits: SaleCredits(account: account).provider,
        dark: false,
        child: Builder(
          builder: (ctx) => Center(
            child: TextButton(
              onPressed: () =>
                  PremiumGate.ensure(ctx, account, feature: 'Expert mode'),
              child: const Text('go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await _settle(tester);
    }

    testWidgets('signed out: says it is part of Premium and offers sign-in',
        (tester) async {
      await upsell(tester, FakeSaleAccount());

      expect(find.text('Premium feature'), findsOneWidget);
      expect(find.text('Expert mode is part of OrbGuard Premium, along with:'),
          findsOneWidget);
      expect(find.text('Already have Premium? Sign in and it works here too.'),
          findsOneWidget);
      expect(find.text(_signIn), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
      _expectNothingSold(tester);

      await tester.tap(find.text(_signIn));
      await _settle(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('signed in and free: says so, and only closes', (tester) async {
      await upsell(tester, FakeSaleAccount(loggedIn: true));

      expect(find.text('This account has no Premium yet.'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);
      _expectNothingSold(tester);

      await tester.tap(find.text('Got it'));
      await _settle(tester);
      expect(find.text('Premium feature'), findsNothing);
      expect(find.byType(PricingScreen), findsNothing);
    });
  });

  group('sign-in creates no account', () {
    testWidgets(
        'the screen offers no Google or Apple, and does not promise a link '
        'to an address with no account', (tester) async {
      AppColors.uiBrightness = Brightness.light;
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final _MagicAccount account = _MagicAccount();
      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: account,
          child: AmazonBuildScope(
            child: MaterialApp(
              theme: AppTheme.light,
              home: const LoginScreen(platform: TargetPlatform.android),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in with your OrbVPN account'), findsOneWidget);
      expect(
          find.text('Use the OrbVPN account you already have. Signing in '
              'brings your plan and remote control to this device.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('google_signin_button')), findsNothing);
      expect(find.byKey(const ValueKey('apple_signin_button')), findsNothing);
      expect(find.text('or'), findsNothing);
      // The ways that never create an account stay.
      expect(find.text('Email me a sign-in link'), findsOneWidget);
      expect(find.text('Use password instead'), findsOneWidget);
      expect(find.text('Skip for now'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('magic_email_field')), 'nima@example.com');
      await tester.tap(find.text('Email me a sign-in link'));
      await tester.pumpAndSettle();

      expect(account.magicCalls, 1);
      expect(
          find.text('Check your email. If nima@example.com has an account, '
              'we sent it a sign-in link.\nTap the link on this device, or '
              'copy that link and paste it below.'),
          findsOneWidget);
      expect(find.textContaining('We sent a sign-in link to'), findsNothing);
      _expectNothingSold(tester);
      account.dispose();
    });

    group('the email link request', () {
      late FakeTwoFactorServer server;

      setUp(() async {
        String seg(Map<String, dynamic> m) =>
            base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
        server = FakeTwoFactorServer(
            accessToken: '${seg({'alg': 'HS256'})}.${seg({
              'email': FakeTwoFactorServer.email
            })}.sig');
        OrbNetApiClient.instance.debugReset();
        await OrbNetApiClient.instance.initialize();
        OrbNetApiClient.instance.httpClientAdapter = server;
      });

      test('the Amazon build asks the server not to create an account',
          () async {
        final AccountProvider account = AccountProvider(
            enableProactiveRefresh: false, allowRegistration: false);
        expect(await account.loginWithMagicLink('new@orbvpn.test'), isTrue);
        final requests = server.requestsTo('/auth/magic-link/request');
        expect(requests, hasLength(1));
        expect(requests.single.body['allow_registration'], isFalse);
        account.dispose();
      });

      test('the Play build still lets a link create one', () async {
        final AccountProvider account =
            AccountProvider(enableProactiveRefresh: false);
        expect(account.allowRegistration, isTrue);
        await account.loginWithMagicLink('new@orbvpn.test');
        expect(
            server
                .requestsTo('/auth/magic-link/request')
                .single
                .body['allow_registration'],
            isTrue);
        account.dispose();
      });
    });
  });

  group('the legal text', () {
    test('every cut is found, and what is left names no site or store', () {
      const String both = '${LegalDocs.terms}\n${LegalDocs.privacy}';
      for (final String cut in LegalDocs.amazonCuts.keys) {
        expect(both.contains(cut), isTrue, reason: cut);
      }
      for (final String doc in const [LegalDocs.terms, LegalDocs.privacy]) {
        final String amazon = LegalDocs.forAmazon(doc);
        for (final String word in const [
          'orbai.world',
          'http',
          'Google Play',
          'App Store',
          'website',
          'pricing',
        ]) {
          expect(amazon.contains(word), isFalse, reason: word);
        }
      }
    });

    for (final LegalDoc doc in LegalDoc.values) {
      testWidgets('the ${doc.name} screen has no link to the web',
          (tester) async {
        AppColors.uiBrightness = Brightness.light;
        await tester.pumpWidget(AmazonBuildScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: LegalScreen(doc: doc),
          ),
        ));
        await tester.pump();

        final String text =
            tester.widget<SelectableText>(find.byType(SelectableText)).data!;
        expect(text.contains('orbai.world'), isFalse);
        expect(find.byType(TextButton), findsNothing);
        expect(find.textContaining('on the web'), findsNothing);
        expect(find.textContaining('published online'), findsNothing);
      });
    }
  });

  group('Settings', () {
    Future<void> pumpSettings(
        WidgetTester tester, FakeSaleAccount account) async {
      AppColors.uiBrightness = Brightness.light;
      tester.view.physicalSize = const Size(1400, 5200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final SettingsProvider settings = SettingsProvider();
      await settings.init();
      final ScanCreditProvider credits = SaleCredits(account: account).provider;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<AccountProvider>.value(value: account),
            ChangeNotifierProvider<ScanCreditProvider>.value(value: credits),
          ],
          child: AmazonBuildScope(
            child: MaterialApp(
              theme: AppTheme.light,
              home: const SettingsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'signed out: no plans, no subscription to view, no server address',
        (tester) async {
      await pumpSettings(tester, FakeSaleAccount());

      expect(find.text('Sign in / Account'), findsOneWidget);
      expect(find.text('Plans & pricing'), findsNothing);
      expect(find.text('Subscription'), findsNothing);
      expect(find.text('API Configuration'), findsNothing);
      expect(find.text('Restore purchases'), findsNothing);
      expect(find.text('Part of OrbGuard Premium'), findsOneWidget);
      _expectNothingSold(tester);
    });

    testWidgets(
        'a subscriber sees the plan, with nothing to manage or restore here',
        (tester) async {
      await pumpSettings(
          tester, FakeSaleAccount(loggedIn: true, premium: true));

      expect(find.text('Subscription'), findsOneWidget);
      expect(find.text('Guard+. Unlocks OrbGuard, OrbVPN & OrbBrowser'),
          findsOneWidget);
      expect(find.text('Manage subscription'), findsNothing);
      expect(find.text('Restore purchases'), findsNothing);
      expect(find.text('Plans & pricing'), findsNothing);
      _expectNothingSold(tester);
    });

    testWidgets('a free account reads Free plan, and the tile opens nothing',
        (tester) async {
      await pumpSettings(tester, FakeSaleAccount(loggedIn: true));

      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('Free plan. View plans & subscribe'), findsNothing);
      await tester.tap(find.text('Subscription'));
      await _settle(tester);
      expect(find.byType(PricingScreen), findsNothing);
    });
  });
}

/// Records the email link request and never touches the network.
class _MagicAccount extends AccountProvider {
  _MagicAccount() : super(enableProactiveRefresh: false);

  int magicCalls = 0;

  @override
  Future<String?> lastLoggedInEmail() async => null;

  @override
  Future<bool> loginWithMagicLink(String email) async {
    magicCalls++;
    return true;
  }
}
