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

  // Records the email/password path so a test can prove the typed credentials
  // are handed to login() verbatim. loginOk controls the returned result.
  int loginCalls = 0;
  String? loginEmail;
  String? loginPassword;
  bool loginOk = true;

  int magicCalls = 0;
  String? magicEmail;
  bool magicOk = true;

  @override
  Future<String?> lastLoggedInEmail() async => null;

  @override
  Future<bool> login(String email, String password, {String? totpCode}) async {
    loginCalls++;
    loginEmail = email;
    loginPassword = password;
    return loginOk;
  }

  @override
  Future<bool> loginWithMagicLink(String email) async {
    magicCalls++;
    magicEmail = email;
    return magicOk;
  }

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
    expect(find.text('Email me a sign-in link'), findsOneWidget);

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
    expect(find.text('Email me a sign-in link'), findsNothing);

    // Social sign-in stays available in both modes.
    expect(find.text('Continue with Google'), findsOneWidget);

    account.dispose();
  });

  testWidgets(
      'password path: typed email+password reach login(); success confirms',
      (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account);

    // Reveal the secondary password form.
    await tester.tap(find.text('Use password instead'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const ValueKey('pw_email_field')), 'nima@example.com');
    await tester.enterText(
        find.byKey(const ValueKey('pw_password_field')), 'S3cret!pass');
    await tester.pump();

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    // The typed credentials were handed to login() verbatim...
    expect(account.loginCalls, 1);
    expect(account.loginEmail, 'nima@example.com');
    expect(account.loginPassword, 'S3cret!pass');
    // ...and a successful sign-in surfaces the honest confirmation (no fake).
    expect(find.text('Signed in'), findsOneWidget);

    account.dispose();
  });

  testWidgets(
      'magic-link path: typed email reaches loginWithMagicLink(); confirms link '
      'sent (code entry is a fallback)', (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account);

    await tester.enterText(
        find.byKey(const ValueKey('magic_email_field')), 'nima@example.com');
    await tester.pump();

    // The default lime action requests a magic sign-in LINK (OrbVPN-style:
    // "tap the link", not "type a 6-digit code").
    await tester.tap(find.text('Email me a sign-in link'));
    await tester.pumpAndSettle();

    expect(account.magicCalls, 1);
    expect(account.magicEmail, 'nima@example.com');
    // On success the screen confirms the link was sent and offers a resend; the
    // code path is a secondary fallback behind an explicit reveal.
    expect(find.textContaining('we sent a sign-in link to'), findsOneWidget);
    expect(find.text('Resend link'), findsOneWidget);
    expect(
        find.text("Can't open the link? Enter the code instead"), findsOneWidget);
    // Not auto-advanced to the code-entry step.
    expect(find.text('Verify & sign in'), findsNothing);

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
