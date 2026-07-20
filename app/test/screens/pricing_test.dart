import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/pricing/pricing_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';

/// The transparent pricing screen — now store-driven. Its whole pitch is its
/// honesty, so the guard here is as much about what ISN'T on screen (fake
/// urgency copy, hardcoded prices) as what is (real store prices + the
/// plain-language renewal promise).
void main() {
  // Deterministic fake products so the store-driven screen has real prices to
  // render. Each yearly is exactly 10× its monthly, so the honest "2 months
  // free" claim is literally true (and the effective /mo is exact).
  ProductDetails pd(String id, double raw, String price) => ProductDetails(
        id: id,
        title: id,
        description: id,
        price: price,
        rawPrice: raw,
        currencyCode: 'USD',
        currencySymbol: '\$',
      );

  final seededProducts = <ProductDetails>[
    pd(OrbGuardProductIds.basicMonthly, 4.99, '\$4.99'),
    pd(OrbGuardProductIds.basicYearly, 49.90, '\$49.90'),
    pd(OrbGuardProductIds.premiumMonthly, 9.99, '\$9.99'),
    pd(OrbGuardProductIds.premiumYearly, 99.90, '\$99.90'),
    pd(OrbGuardProductIds.ultimateMonthly, 14.99, '\$14.99'),
    pd(OrbGuardProductIds.ultimateYearly, 149.90, '\$149.90'),
  ];

  setUp(() {
    IapService.instance.debugSeed(available: true, products: seededProducts);
  });

  // PricingScreen reads AccountProvider (subscription state) and IapService
  // (prices + purchase state). Provide a logged-out (Free) account and the
  // seeded singleton IapService (.value so teardown never closes its stream).
  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>(
            create: (_) => AccountProvider(enableProactiveRefresh: false),
          ),
          ChangeNotifierProvider<IapService>.value(value: IapService.instance),
        ],
        child: const MaterialApp(home: PricingScreen()),
      );

  // The screen is a single tall ListView (3 tier cards + promise band) that
  // overflows the default 800×600 test surface. Widen the surface instead of
  // scrolling so every assertion below sees the whole tree.
  Future<void> pumpTall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 6400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.pump();
  }

  testWidgets('renders the honest-pricing promise band', (tester) async {
    await pumpTall(tester);

    expect(
      find.text(
        'The price you see is the price that renews. Cancel anytime, in '
        'one tap. No hidden fees.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders all three tier names', (tester) async {
    await pumpTall(tester);

    expect(find.text('Guard'), findsOneWidget);
    expect(find.text('Guard+'), findsOneWidget);
    expect(find.text('Guard Ultimate'), findsOneWidget);
  });

  testWidgets('shows the real store price, not a hardcoded one', (tester) async {
    await pumpTall(tester);

    // Monthly (default) headline prices come straight from the seeded store
    // ProductDetails.price strings.
    expect(find.text('\$4.99'), findsOneWidget); // Guard
    expect(find.text('\$9.99'), findsOneWidget); // Guard+
    expect(find.text('\$14.99'), findsOneWidget); // Guard Ultimate
    expect(find.text('Renews monthly at \$4.99.'), findsOneWidget);
  });

  testWidgets('contains no fake-urgency / dark-pattern copy', (tester) async {
    await pumpTall(tester);

    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' \n ')
        .toLowerCase();

    const bannedPhrases = [
      'hurry',
      'limited time',
      'act now',
      "don't wait",
      'act fast',
      'expires in',
      'expires soon',
      'countdown',
      'time is running out',
      'people are viewing',
      'people viewing',
      'while supplies last',
      'sale ends',
    ];

    for (final phrase in bannedPhrases) {
      expect(
        allText.contains(phrase),
        isFalse,
        reason: 'found fake-urgency / dark-pattern copy: "$phrase"',
      );
    }
  });

  testWidgets('yearly toggle shows the real effective per-month price',
      (tester) async {
    await pumpTall(tester);

    await tester.tap(find.text('Yearly'));
    await tester.pump();

    // Guard: $49.90/yr ÷ 12 = $4.1583… → honestly rounded to $4.16/mo.
    expect(find.text('\$4.16'), findsOneWidget);
    expect(find.text('Billed \$49.90 once a year.'), findsOneWidget);
    // 49.90 == 10 × 4.99, so "2 months free" is literally true (shown on every
    // tier since each yearly is exactly 10× its monthly here).
    expect(
      find.text("That's 2 months free versus paying monthly."),
      findsWidgets,
    );
  });

  testWidgets('logged out: choosing a tier routes to sign in (verify is auth-gated)',
      (tester) async {
    await pumpTall(tester);

    await tester.tap(find.text('Choose Guard'));
    await tester.pumpAndSettle();

    // A purchase can only be verified for a signed-in account, so the flow
    // sends the user to sign in first rather than starting a doomed purchase.
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('offers Restore purchases', (tester) async {
    await pumpTall(tester);
    expect(find.text('Restore purchases'), findsOneWidget);
  });
}
