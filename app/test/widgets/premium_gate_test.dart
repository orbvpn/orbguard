// Widget tests for the premium gate (subscription gating).
//
// Proves the three load-bearing behaviours:
//   1. hasPremium == true  → PremiumGate.ensure returns true and shows NO sheet.
//   2. hasPremium == false → ensure returns false AND presents the upsell sheet
//      (with the right primary CTA: "Sign in" logged out, "See plans" logged in).
//   3. The Settings "Expert (Pro) mode" toggle is blocked when not premium — it
//      does NOT flip the app mode and instead shows the upsell.
//
// AccountProvider is replaced with a tiny fake so hasPremium/isLoggedIn are
// controlled directly (no auth stack, no network, no secure storage I/O).

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/settings_provider.dart';
import 'package:orbguard/screens/settings/settings_screen.dart';
import 'package:orbguard/widgets/premium/premium_gate.dart';

/// A controllable AccountProvider: hasPremium / isLoggedIn are fixed inputs.
class _FakeAccount extends AccountProvider {
  _FakeAccount({this.premium = false, this.loggedIn = false})
    : super(enableProactiveRefresh: false);

  final bool premium;
  final bool loggedIn;

  @override
  bool get isInitialized => true;
  @override
  bool get isLoggedIn => loggedIn;
  @override
  bool get subscriptionValid => premium;
  @override
  bool get hasPremium => premium;
}

/// Host for the `ensure` tests: a single button that calls PremiumGate.ensure
/// with the Builder's (navigator-backed) context.
Widget _ensureHost(
  AccountProvider account, {
  required void Function(BuildContext) onTap,
}) {
  return ChangeNotifierProvider<AccountProvider>.value(
    value: account,
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              key: const Key('go'),
              onPressed: () => onTap(ctx),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Keep the brand ink tokens resolvable + storage plugins inert.
    AppColors.uiBrightness = Brightness.light;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('hasPremium true → ensure returns true and shows no upsell', (
    tester,
  ) async {
    final account = _FakeAccount(premium: true, loggedIn: true);
    bool? result;

    await tester.pumpWidget(
      _ensureHost(
        account,
        onTap: (ctx) =>
            result = PremiumGate.ensure(ctx, account, feature: 'Deep scan'),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('Premium feature'), findsNothing);

    account.dispose();
  });

  testWidgets(
    'hasPremium false, logged out → returns false, upsell to Sign in',
    (tester) async {
      final account = _FakeAccount(premium: false, loggedIn: false);
      bool? result;

      await tester.pumpWidget(
        _ensureHost(
          account,
          onTap: (ctx) => result = PremiumGate.ensure(
            ctx,
            account,
            feature: 'Expert (Pro) mode',
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('go')));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      // The upsell sheet is shown, with a sign-in primary action.
      expect(find.text('Premium feature'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('See plans'), findsNothing);

      account.dispose();
    },
  );

  testWidgets('hasPremium false, logged in → upsell primary is See plans', (
    tester,
  ) async {
    final account = _FakeAccount(premium: false, loggedIn: true);
    bool? result;

    await tester.pumpWidget(
      _ensureHost(
        account,
        onTap: (ctx) => result = PremiumGate.ensure(ctx, account),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('Premium feature'), findsOneWidget);
    expect(find.text('See plans'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);

    account.dispose();
  });

  testWidgets(
    'Settings Pro toggle is blocked (no flip + upsell) when not premium',
    (tester) async {
      // A tall viewport so the whole settings list (incl. the Experience toggle)
      // builds without needing to scroll.
      tester.view.physicalSize = const Size(1400, 4200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final settings = SettingsProvider();
      await settings.init();
      final account = _FakeAccount(premium: false, loggedIn: false);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsProvider>.value(value: settings),
            ChangeNotifierProvider<AccountProvider>.value(value: account),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: SettingsScreen(embedded: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(settings.isProMode, isFalse);

      // Tap the one SwitchListTile (Expert/Pro mode) to try to enable it.
      final toggle = find.byType(SwitchListTile);
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      // Gated: mode did NOT flip, and the upsell sheet is shown instead.
      expect(settings.isProMode, isFalse);
      expect(find.text('Premium feature'), findsOneWidget);

      account.dispose();
    },
  );
}
