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
//
// The "two-factor code step" group instead runs the REAL AccountProvider
// against a fake OrbNet (test/services/orbnet/fake_two_factor_server.dart):
// a magic link — tapped while the screen is open, or before it exists, as on
// a cold start — leads to the code step, whose field takes authenticator and
// recovery codes and completes the sign-in. Its app-lock cases mount
// TwoFactorResume the way main.dart does, under a stand-in for AppLockGate
// that swaps the navigator out while locked, as the real gate does.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/account/two_factor_resume.dart';
import 'package:orbguard/services/orbnet/orbnet_api_client.dart';

import '../services/orbnet/fake_two_factor_server.dart';

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

/// Stands in for AppLockGate: while [locked] is true its lock screen takes the
/// place of the navigator, which disposes every route under it — what the
/// real gate does each time the app comes back with the lock on.
class _LockGate extends StatelessWidget {
  const _LockGate({required this.locked, required this.child});

  final ValueListenable<bool> locked;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: locked,
        builder: (context, isLocked, _) => isLocked
            ? const Scaffold(body: Center(child: Text('LOCKED')))
            : child,
      );
}

/// Mounts the sign-in screen as it shows on [platform]. The screen is told
/// the platform itself: left alone it asks the machine it runs on, and the
/// machine that runs these tests is not the phone they describe.
/// [themePlatform] is the look the app is styled with, when a test needs it
/// to differ from the device.
Future<void> _pumpLogin(
  WidgetTester tester,
  AccountProvider account, {
  TargetPlatform platform = TargetPlatform.android,
  TargetPlatform? themePlatform,
}) async {
  // A tall viewport so the whole ListView builds without scrolling.
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AccountProvider>.value(
      value: account,
      child: MaterialApp(
        theme: AppTheme.light.copyWith(platform: themePlatform ?? platform),
        home: LoginScreen(platform: platform),
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

  testWidgets('Apple button is shown on Apple platforms (iOS)', (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account, platform: TargetPlatform.iOS);

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);

    account.dispose();
  });

  // google_sign_in has no Windows or Linux implementation, and Apple only
  // allows its button on Apple platforms. A button that can never work is
  // what Microsoft rejected the Windows build for (10.1.2.10).
  for (final platform in const [TargetPlatform.windows, TargetPlatform.linux]) {
    testWidgets(
        'on ${platform.name} neither Google nor Apple sign-in is offered',
        (tester) async {
      final account = _FakeAccount();
      await _pumpLogin(tester, account, platform: platform);

      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Continue with Apple'), findsNothing);
      // The ways that do work there are still offered.
      expect(find.text('Email me a sign-in link'), findsOneWidget);
      expect(find.text('Use password instead'), findsOneWidget);

      account.dispose();
    });
  }

  testWidgets(
      'a Windows build styled as a phone still offers no Google or Apple '
      'sign-in', (tester) async {
    final account = _FakeAccount();
    await _pumpLogin(tester, account,
        platform: TargetPlatform.windows, themePlatform: TargetPlatform.iOS);

    expect(find.text('Continue with Google'), findsNothing);
    expect(find.text('Continue with Apple'), findsNothing);

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
      'magic-link path: typed email reaches loginWithMagicLink(); code entry is '
      'immediately available (no reveal)', (tester) async {
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
    expect(find.textContaining('We sent a sign-in link to'), findsOneWidget);

    // Regression guard for the Microsoft Store 10.1.2.10 rejection: the code
    // field must be on screen the moment the link is sent. Hiding it behind a
    // "Can't open the link?" reveal left the reviewer with no way to finish
    // sign-in when the orbguard:// link did not open the app.
    expect(find.byKey(const ValueKey('magic_code_field')), findsOneWidget);
    expect(find.text('Verify & sign in'), findsOneWidget);
    // Resending stays available, demoted below the primary action.
    expect(find.text('Resend link'), findsOneWidget);

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

  group('two-factor code step (real provider, fake OrbNet)', () {
    late FakeTwoFactorServer server;
    late AccountProvider account;
    // The provider's clock: a test moves it to run out a pending sign-in.
    late DateTime now;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final exp =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      String seg(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
      server = FakeTwoFactorServer(
          accessToken: '${seg({'alg': 'HS256'})}.${seg({
            'email': FakeTwoFactorServer.email,
            'exp': exp
          })}.sig');
      OrbNetApiClient.instance.debugReset();
      await OrbNetApiClient.instance.initialize();
      OrbNetApiClient.instance.httpClientAdapter = server;
      now = DateTime(2026, 11, 6, 12);
      account = AccountProvider(enableProactiveRefresh: false, clock: () => now);
    });

    /// HOME → OPENER (the screen that asks for sign-in) — no sign-in screen
    /// yet. The opener in between is what a double pop would wrongly close.
    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: account,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: Center(child: Text('HOME'))),
          ),
        ),
      );
      unawaited(tester.state<NavigatorState>(find.byType(Navigator)).push(
          MaterialPageRoute(
              builder: (_) =>
                  const Scaffold(body: Center(child: Text('OPENER'))))));
      await tester.pumpAndSettle();
    }

    /// HOME under the app's root wiring: the lock stand-in around
    /// TwoFactorResume around the navigator, as main.dart mounts them.
    Future<void> pumpLockableApp(
        WidgetTester tester, ValueListenable<bool> locked) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<AccountProvider>.value(
          value: account,
          child: MaterialApp(
            navigatorKey: navigatorKey,
            theme: AppTheme.light,
            builder: (context, child) => _LockGate(
              locked: locked,
              child: TwoFactorResume(
                  navigatorKey: navigatorKey, child: child!),
            ),
            home: const Scaffold(body: Center(child: Text('HOME'))),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> openLogin(WidgetTester tester) async {
      unawaited(tester
          .state<NavigatorState>(find.byType(Navigator))
          .push(MaterialPageRoute(builder: (_) => const LoginScreen())));
      await tester.pumpAndSettle();
    }

    /// What _MagicLinkGate does with an orbguard://login link.
    Future<void> tapMagicLink(WidgetTester tester) async {
      final verified = account.verifyMagicCode('', 'link-token');
      await tester.pumpAndSettle();
      expect(await verified, isFalse);
      expect(account.hasPendingTwoFactor, isTrue);
    }

    Finder codeField() => find.byKey(const ValueKey('two_factor_code_field'));

    testWidgets(
        'a link tapped while the screen is open switches it to the code step; '
        'the code signs in and closes only the sign-in screen', (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      expect(LoginScreen.isOpen, isTrue);

      await tapMagicLink(tester);

      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);
      expect(find.text('Two-factor authentication'), findsOneWidget);
      expect(find.textContaining(FakeTwoFactorServer.email), findsOneWidget);
      // The code step owns the screen's single lime action.
      expect(find.text('Continue with Google'), findsNothing);
      expect(find.text('Email me a sign-in link'), findsNothing);

      await tester.enterText(codeField(), FakeTwoFactorServer.totpCode);
      await tester.tap(find.text('Verify & sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isTrue);
      expect(LoginScreen.isOpen, isFalse);
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });

    testWidgets(
        'cold start: the pending sign-in survives into a sign-in screen opened '
        'after the link was verified', (tester) async {
      await pumpApp(tester);
      expect(LoginScreen.isOpen, isFalse);

      await tapMagicLink(tester);
      await openLogin(tester);

      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);
      await tester.enterText(codeField(), FakeTwoFactorServer.totpCode);
      await tester.tap(find.text('Verify & sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isTrue);
      expect(
          server.requestsTo('/auth/2fa/complete').single.body['pending_token'],
          server.issuedPendingTokens.single);
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });

    testWidgets(
        'the code field keeps a recovery code intact; the toggle swaps label '
        'and keyboard', (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await tapMagicLink(tester);
      expect(tester.widget<TextField>(codeField()).keyboardType,
          TextInputType.number);

      await tester
          .tap(find.byKey(const ValueKey('two_factor_recovery_toggle')));
      await tester.pump();
      expect(find.text('RECOVERY CODE'), findsOneWidget);
      expect(tester.widget<TextField>(codeField()).keyboardType,
          TextInputType.visiblePassword);

      await tester.enterText(codeField(), FakeTwoFactorServer.recoveryCode);
      expect(tester.widget<TextField>(codeField()).controller!.text,
          FakeTwoFactorServer.recoveryCode);
      await tester.tap(find.text('Verify & sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isTrue);
      expect(server.requestsTo('/auth/2fa/complete').single.body['code'],
          FakeTwoFactorServer.recoveryCode);

      account.dispose();
    });

    testWidgets('a wrong code shows the error and keeps the code step',
        (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await tapMagicLink(tester);

      await tester.enterText(codeField(), '000000');
      await tester.tap(find.text('Verify & sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isFalse);
      expect(find.textContaining('That code is incorrect'), findsOneWidget);
      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);

      account.dispose();
    });

    testWidgets('Start over drops the pending sign-in and shows the options',
        (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await tapMagicLink(tester);

      await tester.tap(find.byKey(const ValueKey('two_factor_start_over')));
      await tester.pumpAndSettle();

      expect(account.hasPendingTwoFactor, isFalse);
      expect(find.byKey(const ValueKey('two_factor_panel')), findsNothing);
      expect(find.text('Email me a sign-in link'), findsOneWidget);
      expect(LoginScreen.isOpen, isTrue);

      account.dispose();
    });

    testWidgets('Skip for now abandons the pending sign-in', (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await tapMagicLink(tester);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(LoginScreen.isOpen, isFalse);
      expect(account.hasPendingTwoFactor, isFalse);
      expect(account.isLoggedIn, isFalse);
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });

    testWidgets('going back from the code step abandons the pending sign-in',
        (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await tapMagicLink(tester);

      // The system back button / gesture.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(LoginScreen.isOpen, isFalse);
      expect(account.hasPendingTwoFactor, isFalse);
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });

    testWidgets(
        'with the app lock on, the code step survives a trip to the '
        'authenticator app and comes back after unlock', (tester) async {
      final locked = ValueNotifier(false);
      await pumpLockableApp(tester, locked);
      await openLogin(tester);
      await tapMagicLink(tester);
      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);

      // The user leaves to read the code; the app re-locks on return, which
      // tears down the navigator and the sign-in screen with it.
      locked.value = true;
      await tester.pumpAndSettle();
      expect(find.text('LOCKED'), findsOneWidget);
      expect(LoginScreen.isOpen, isFalse);
      expect(account.hasPendingTwoFactor, isTrue);

      locked.value = false;
      await tester.pumpAndSettle();
      expect(LoginScreen.isOpen, isTrue);
      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);

      await tester.enterText(codeField(), FakeTwoFactorServer.totpCode);
      await tester.tap(find.text('Verify & sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isTrue);
      expect(LoginScreen.isOpen, isFalse);
      expect(find.text('HOME'), findsOneWidget);
      expect(
          server.requestsTo('/auth/2fa/complete').single.body['pending_token'],
          server.issuedPendingTokens.single);

      account.dispose();
    });

    testWidgets(
        'a link verified while the app is locked opens the code step once '
        'unlocked', (tester) async {
      final locked = ValueNotifier(true);
      await pumpLockableApp(tester, locked);

      await tapMagicLink(tester);
      expect(find.text('LOCKED'), findsOneWidget);
      expect(LoginScreen.isOpen, isFalse);

      locked.value = false;
      await tester.pumpAndSettle();

      expect(LoginScreen.isOpen, isTrue);
      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);
      expect(find.textContaining(FakeTwoFactorServer.email), findsOneWidget);

      account.dispose();
    });

    testWidgets(
        'a link verified with no sign-in screen open brings one up for the '
        'code, once', (tester) async {
      final locked = ValueNotifier(false);
      await pumpLockableApp(tester, locked);
      expect(LoginScreen.isOpen, isFalse);

      await tapMagicLink(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);

      // The same link again (app_links replays a launch link): the screen
      // already showing the step is reused, not stacked.
      await tapMagicLink(tester);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('two_factor_panel')), findsOneWidget);

      account.dispose();
    });

    testWidgets(
        'a pending sign-in whose time ran out behind the lock is not '
        'reopened', (tester) async {
      final locked = ValueNotifier(false);
      await pumpLockableApp(tester, locked);
      await openLogin(tester);
      await tapMagicLink(tester);

      locked.value = true;
      await tester.pumpAndSettle();
      now = now.add(const Duration(minutes: 6));
      locked.value = false;
      await tester.pumpAndSettle();

      expect(LoginScreen.isOpen, isFalse);
      expect(find.text('HOME'), findsOneWidget);
      expect(account.hasPendingTwoFactor, isFalse);
      expect(account.lastError, 'Your sign-in expired. Please start again.');
      expect(server.requestsTo('/auth/2fa/complete'), isEmpty);

      account.dispose();
    });

    testWidgets(
        'signed in from a link while the Terms page sits on top: the sign-in '
        'screen closes from under it with true', (tester) async {
      server.totpEnabled = false;
      await pumpApp(tester);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      bool? signInResult;
      unawaited(navigator
          .push<bool>(MaterialPageRoute(builder: (_) => const LoginScreen()))
          .then((result) => signInResult = result));
      await tester.pumpAndSettle();
      unawaited(navigator.push(MaterialPageRoute(
          builder: (_) => const Scaffold(body: Center(child: Text('TERMS'))))));
      await tester.pumpAndSettle();

      final verified = account.verifyMagicCode('', 'link-token');
      await tester.pumpAndSettle();
      expect(await verified, isTrue);

      expect(account.isLoggedIn, isTrue);
      expect(LoginScreen.isOpen, isFalse);
      expect(signInResult, isTrue);
      expect(find.text('TERMS'), findsOneWidget);

      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });

    testWidgets(
        'password form: the code field takes a recovery code and re-posts it '
        'with the password', (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pw_email_field')),
          FakeTwoFactorServer.email);
      await tester.enterText(find.byKey(const ValueKey('pw_password_field')),
          FakeTwoFactorServer.password);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(account.requiresTwoFactor, isTrue);
      expect(account.hasPendingTwoFactor, isFalse);
      expect(find.text('AUTHENTICATOR CODE'), findsOneWidget);

      await tester.enterText(codeField(), FakeTwoFactorServer.recoveryCode);
      await tester.tap(find.text('Verify & sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isTrue);
      final login = server.requestsTo('/auth/login').last.body;
      expect(login['password'], FakeTwoFactorServer.password);
      expect(login['totp_code'], FakeTwoFactorServer.recoveryCode);
      expect(server.requestsTo('/auth/2fa/complete'), isEmpty);
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });

    /// Password mode, the TOTP account's credentials, Sign in: the form now
    /// asks for the authenticator code.
    Future<void> reachPasswordCodePrompt(WidgetTester tester) async {
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pw_email_field')),
          FakeTwoFactorServer.email);
      await tester.enterText(find.byKey(const ValueKey('pw_password_field')),
          FakeTwoFactorServer.password);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(account.requiresTwoFactor, isTrue);
      expect(find.text('AUTHENTICATOR CODE'), findsOneWidget);
    }

    testWidgets(
        'password form: after a code was asked for, an empty code field still '
        'signs in to an account without TOTP', (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await reachPasswordCodePrompt(tester);

      // The user turns to another account, one without TOTP.
      server.totpEnabled = false;
      await tester.enterText(
          find.byKey(const ValueKey('pw_email_field')), 'other@orbvpn.test');
      await tester.tap(find.text('Verify & sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isTrue);
      final login = server.requestsTo('/auth/login').last.body;
      expect(login['email'], 'other@orbvpn.test');
      expect(login, isNot(contains('totp_code')));
      expect(LoginScreen.isOpen, isFalse);
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });

    testWidgets(
        'Skip for now after a password code prompt: the screen opens again '
        'on the plain password form', (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await reachPasswordCodePrompt(tester);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(LoginScreen.isOpen, isFalse);
      expect(account.requiresTwoFactor, isFalse);

      await openLogin(tester);
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();

      expect(find.text('AUTHENTICATOR CODE'), findsNothing);
      expect(find.text('Verify & sign in'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
      expect(account.lastError, isNull);

      account.dispose();
    });

    testWidgets(
        'going back after a password code prompt and a switch to the link '
        'form also reopens on the plain password form', (tester) async {
      await pumpApp(tester);
      await openLogin(tester);
      await reachPasswordCodePrompt(tester);
      // The switch clears the prompt's message but not the step.
      await tester.tap(find.text('Email me a code instead'));
      await tester.pumpAndSettle();
      expect(account.lastError, isNull);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(LoginScreen.isOpen, isFalse);
      expect(find.text('OPENER'), findsOneWidget);

      await openLogin(tester);
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();

      expect(find.text('AUTHENTICATOR CODE'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);

      account.dispose();
    });

    testWidgets('a direct sign-in closes only the sign-in screen',
        (tester) async {
      server.totpEnabled = false;
      await pumpApp(tester);
      await openLogin(tester);
      await tester.tap(find.text('Use password instead'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('pw_email_field')),
          FakeTwoFactorServer.email);
      await tester.enterText(find.byKey(const ValueKey('pw_password_field')),
          FakeTwoFactorServer.password);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(account.isLoggedIn, isTrue);
      expect(LoginScreen.isOpen, isFalse);
      // Both the handler and the logged-in listener ask to close; the screen
      // that opened sign-in must survive that.
      expect(find.text('OPENER'), findsOneWidget);

      account.dispose();
    });
  });
}
