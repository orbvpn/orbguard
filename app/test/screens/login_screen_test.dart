// Widget tests for the reworked account sign-in screen (Phase A1.5).
//
// Proves the new ordering + honesty contract:
//   1. Magic-link is the PRIMARY/default path — a lime "Email me a sign-in
//      code" button — with the email+password path hidden behind a subtle
//      "Use password instead" reveal.
//   2. Google (always) + Apple (Apple platforms only) buttons are shown
//      prominently above an "or" divider.
//   3. Tapping a social button drives the REAL provider method (no fake path).
//
// AccountProvider is replaced with a tiny fake so no auth stack / native SDK /
// network is touched.

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/screens/account/login_screen.dart';

/// A controllable AccountProvider: records the social calls and never touches
/// secure storage or the native SDKs.
class _FakeAccount extends AccountProvider {
  _FakeAccount() : super(enableProactiveRefresh: false);

  int googleCalls = 0;
  int appleCalls = 0;

  @override
  Future<String?> lastLoggedInEmail() async => null;

  @override
  Future<bool> loginWithGoogle() async {
    googleCalls++;
    return false;
  }

  @override
  Future<bool> loginWithApple() async {
    appleCalls++;
    return false;
  }
}

Future<void> _pumpLogin(
  WidgetTester tester,
  AccountProvider account, {
  TargetPlatform platform = TargetPlatform.android,
}) async {
  // A tall viewport so the whole ListView builds without scrolling.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AccountProvider>.value(
      value: account,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: platform),
        home: const LoginScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppColors.uiBrightness = Brightness.light;
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
      'default view: magic-link is primary, password hidden, Google shown',
      (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account);

    // Header + the primary (default) magic-link CTA.
    expect(find.text('Sign in with your OrbVPN account'), findsOneWidget);
    expect(find.text('Email me a sign-in code'), findsOneWidget);

    // Social sign-in is offered prominently, with the "or" divider.
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('or'), findsOneWidget);

    // Password is SECONDARY — behind a reveal; its field/CTA are not shown yet.
    expect(find.text('Use password instead'), findsOneWidget);
    expect(find.text('PASSWORD'), findsNothing);
    expect(find.text('Sign in'), findsNothing);

    // Anonymous scanning stays available.
    expect(find.text('Skip for now'), findsOneWidget);

    account.dispose();
  });

  testWidgets('Apple button is hidden off Apple platforms (Android)',
      (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account, platform: TargetPlatform.android);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);

    account.dispose();
  });

  testWidgets('Apple button is shown on Apple platforms (iOS)',
      (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account, platform: TargetPlatform.iOS);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);

    account.dispose();
  });

  testWidgets('"Use password instead" reveals the password field + Sign in',
      (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account);

    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    // Password path now visible; magic CTA swapped for the return link.
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Email me a code instead'), findsOneWidget);
    expect(find.text('Email me a sign-in code'), findsNothing);

    // Social sign-in stays available in both modes.
    expect(find.text('Continue with Google'), findsOneWidget);

    account.dispose();
  });

  testWidgets('tapping Continue with Google drives the real provider method',
      (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account);

    await tester.tap(find.byKey(const ValueKey('google_signin_button')));
    await tester.pumpAndSettle();

    expect(account.googleCalls, 1);
    expect(account.appleCalls, 0);

    account.dispose();
  });

  testWidgets('tapping Continue with Apple drives the real provider method',
      (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account, platform: TargetPlatform.iOS);

    await tester.tap(find.byKey(const ValueKey('apple_signin_button')));
    await tester.pumpAndSettle();

    expect(account.appleCalls, 1);
    expect(account.googleCalls, 0);

    account.dispose();
  });
}
