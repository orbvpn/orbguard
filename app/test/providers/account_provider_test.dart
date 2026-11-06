// Unit tests for AccountProvider (shared OrbVPN/OrbNet account state).
//
// Proves: logged-out by default; a mocked successful login sets isLoggedIn and
// PERSISTS to secure storage (a fresh provider re-hydrates); logout clears the
// session. The OrbNet REST client's Dio adapter is replaced with a fake so no
// real network is hit, and flutter_secure_storage runs on its in-memory mock.
//
// The "two-factor sign-in" group drives the second-factor state machine
// against a fake OrbNet that follows the server's /auth/2fa/complete rules:
// magic link / Google → pending code step → completion, every refusal, and
// the password path's unchanged re-post.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/services/orbnet/auth_api.dart';
import 'package:orbguard/services/orbnet/auth_repository.dart';
import 'package:orbguard/services/orbnet/orbnet_api_client.dart';
import 'package:orbguard/services/orbnet/social_auth_service.dart';

import '../services/orbnet/fake_two_factor_server.dart';

/// Build a syntactically valid JWT (header.payload.signature) with the given
/// claims. The signature is a throwaway — TokenService parses claims without
/// verifying it.
String _makeJwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  final header = seg({'alg': 'HS256', 'typ': 'JWT'});
  return '$header.${seg(payload)}.sig';
}

/// A fake Dio adapter that returns canned OrbNet auth responses by path.
class _FakeAuthAdapter implements HttpClientAdapter {
  _FakeAuthAdapter(this.accessToken);
  final String accessToken;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;

    Map<String, dynamic> body;
    int status = 200;

    if (path.endsWith('/auth/login')) {
      body = {
        'success': true,
        'data': {
          'user': {
            'id': 42,
            'email': 'user@orbvpn.test',
            'role': 'user',
          },
          'tokens': {
            'access_token': accessToken,
            'refresh_token': 'refresh-xyz',
          },
          'subscription': {
            'group_name': 'premium_monthly',
            'max_devices': 5,
            'status': 'ACTIVE',
          },
        },
      };
    } else if (path.endsWith('/auth/logout')) {
      body = {'success': true};
    } else {
      body = {'success': false, 'message': 'unexpected path: $path'};
      status = 404;
    }

    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A SocialAuthService stand-in: no native SDKs, no network. Returns a canned
/// outcome so the provider → repository → persist wiring can be exercised.
class _FakeSocialAuthService extends SocialAuthService {
  _FakeSocialAuthService({this.envelope, this.error, this.cancel = false});

  /// The raw OrbNet oauth envelope to hand back on success.
  final Map<String, dynamic>? envelope;
  final String? error;
  final bool cancel;

  SocialAuthResult _outcome(SocialAuthProvider provider) {
    if (cancel) return SocialAuthResult.canceled(provider);
    if (envelope != null) return SocialAuthResult.success(provider, envelope!);
    return SocialAuthResult.failure(provider, error ?? 'social failed');
  }

  @override
  Future<SocialAuthResult> signInWithGoogle() async =>
      _outcome(SocialAuthProvider.google);

  @override
  Future<SocialAuthResult> signInWithApple() async =>
      _outcome(SocialAuthProvider.apple);
}

/// The OrbNet `/auth/oauth/login` envelope (same shape as `/auth/login`).
Map<String, dynamic> _oauthEnvelope(String token) => {
      'success': true,
      'data': {
        'user': {'id': 7, 'email': 'social@orbvpn.test', 'role': 'user'},
        'tokens': {'access_token': token, 'refresh_token': 'refresh-social'},
        'subscription': {
          'group_name': 'premium_monthly',
          'max_devices': 5,
          'status': 'ACTIVE',
        },
      },
    };

/// Wire a provider whose repository uses [social] instead of the real SDKs.
AccountProvider _providerWithSocial(SocialAuthService social) {
  final repo = AuthRepository(
    secureStorage: const FlutterSecureStorage(),
    socialAuthService: social,
  );
  return AccountProvider(authRepository: repo, enableProactiveRefresh: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String accessToken;

  setUp(() async {
    // Fresh in-memory secure storage for every test.
    FlutterSecureStorage.setMockInitialValues({});

    // A ~1h-valid access token carrying identity + subscription claims.
    final exp =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    accessToken = _makeJwt({
      'user_id': 42,
      'email': 'user@orbvpn.test',
      'role': 'user',
      'exp': exp,
      'subscription_tier': 'premium',
      'subscription_valid': true,
    });

    // Rebuild the singleton client and inject the fake adapter.
    OrbNetApiClient.instance.debugReset();
    await OrbNetApiClient.instance.initialize();
    OrbNetApiClient.instance.httpClientAdapter = _FakeAuthAdapter(accessToken);
  });

  test('is logged out by default', () async {
    final provider = AccountProvider(enableProactiveRefresh: false);
    await provider.init();

    expect(provider.isInitialized, isTrue);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.user, isNull);
    expect(provider.subscriptionValid, isFalse);

    provider.dispose();
  });

  test('successful login sets isLoggedIn and persists the session', () async {
    final provider = AccountProvider(enableProactiveRefresh: false);
    await provider.init();

    final ok = await provider.login('User@OrbVPN.test', 'secret');

    expect(ok, isTrue);
    expect(provider.isLoggedIn, isTrue);
    expect(provider.user, isNotNull);
    expect(provider.user!.email, 'user@orbvpn.test');
    expect(provider.lastError, isNull);
    // Subscription claims are read from the JWT.
    expect(provider.subscriptionTier, 'premium');
    expect(provider.subscriptionValid, isTrue);

    // Tokens + user were written with the exact OrbVPN-compatible keys.
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'auth_token'), accessToken);
    expect(await storage.read(key: 'refresh_token'), 'refresh-xyz');
    expect(await storage.read(key: 'user_data'), isNotNull);
    expect(await storage.read(key: 'last_logged_in_email'), 'user@orbvpn.test');

    // A brand-new provider must re-hydrate the session from storage.
    final rehydrated = AccountProvider(enableProactiveRefresh: false);
    await rehydrated.init();
    expect(rehydrated.isLoggedIn, isTrue);
    expect(rehydrated.user!.email, 'user@orbvpn.test');

    provider.dispose();
    rehydrated.dispose();
  });

  test('logout clears the session', () async {
    final provider = AccountProvider(enableProactiveRefresh: false);
    await provider.init();
    await provider.login('user@orbvpn.test', 'secret');
    expect(provider.isLoggedIn, isTrue);

    await provider.logout();

    expect(provider.isLoggedIn, isFalse);
    expect(provider.user, isNull);

    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'auth_token'), isNull);
    expect(await storage.read(key: 'refresh_token'), isNull);
    expect(await storage.read(key: 'user_data'), isNull);
    // The last email is intentionally retained to pre-fill the sign-in form.
    expect(await storage.read(key: 'last_logged_in_email'), 'user@orbvpn.test');

    provider.dispose();
  });

  test('loginWithGoogle sets + persists the session (mocked social + oauth)',
      () async {
    final provider = _providerWithSocial(
      _FakeSocialAuthService(envelope: _oauthEnvelope(accessToken)),
    );
    await provider.init();

    final ok = await provider.loginWithGoogle();

    expect(ok, isTrue);
    expect(provider.isLoggedIn, isTrue);
    expect(provider.user!.email, 'social@orbvpn.test');
    expect(provider.lastError, isNull);
    // Subscription claims still come from the access-token JWT.
    expect(provider.subscriptionValid, isTrue);

    // Tokens were persisted under the shared OrbVPN-compatible keys.
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'auth_token'), accessToken);
    expect(await storage.read(key: 'refresh_token'), 'refresh-social');
    expect(
        await storage.read(key: 'last_logged_in_email'), 'social@orbvpn.test');

    provider.dispose();
  });

  test('loginWithApple sets the session (mocked social + oauth)', () async {
    final provider = _providerWithSocial(
      _FakeSocialAuthService(envelope: _oauthEnvelope(accessToken)),
    );
    await provider.init();

    final ok = await provider.loginWithApple();

    expect(ok, isTrue);
    expect(provider.isLoggedIn, isTrue);
    expect(provider.user!.email, 'social@orbvpn.test');
    expect(provider.hasPremium, isTrue);

    provider.dispose();
  });

  test('a cancelled social sign-in is silent: false, no error, logged out',
      () async {
    final provider = _providerWithSocial(_FakeSocialAuthService(cancel: true));
    await provider.init();

    final ok = await provider.loginWithGoogle();

    expect(ok, isFalse);
    expect(provider.isLoggedIn, isFalse);
    // Cancellation is a no-op — never surfaced as an error banner.
    expect(provider.lastError, isNull);

    provider.dispose();
  });

  test('a failed social sign-in surfaces a clear error, never a fake session',
      () async {
    final provider = _providerWithSocial(
      _FakeSocialAuthService(
          error: "Couldn't sign in with Google — try email instead."),
    );
    await provider.init();

    final ok = await provider.loginWithGoogle();

    expect(ok, isFalse);
    expect(provider.isLoggedIn, isFalse);
    expect(provider.user, isNull);
    expect(provider.lastError,
        "Couldn't sign in with Google — try email instead.");

    provider.dispose();
  });

  group('two-factor sign-in', () {
    const storage = FlutterSecureStorage();
    late FakeTwoFactorServer server;

    setUp(() {
      // The device-claim follow-up reads prefs; with none it is a no-op.
      SharedPreferences.setMockInitialValues({});
      server = FakeTwoFactorServer(accessToken: accessToken);
      OrbNetApiClient.instance.httpClientAdapter = server;
    });

    /// A provider whose magic-link verify has just hit the code step. [clock]
    /// stands in for the wall clock, to move past the step's deadline.
    Future<AccountProvider> pendingFromMagicLink(
        {DateTime Function()? clock}) async {
      final provider =
          AccountProvider(enableProactiveRefresh: false, clock: clock);
      await provider.init();
      expect(
          await provider.loginWithMagicLink(FakeTwoFactorServer.email), isTrue);
      expect(await provider.verifyMagicCode('', 'link-token'), isFalse);
      return provider;
    }

    test(
        'a magic link on a TOTP account waits for the code, signed out and '
        'with nothing stored', () async {
      final provider = await pendingFromMagicLink();

      expect(provider.requiresTwoFactor, isTrue);
      expect(provider.hasPendingTwoFactor, isTrue);
      expect(provider.twoFactorEmail, FakeTwoFactorServer.email);
      expect(provider.twoFactorAcceptsRecoveryCode, isTrue);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.lastError, isNull);
      expect(await storage.read(key: 'auth_token'), isNull);
      expect(await storage.read(key: 'user_data'), isNull);
      // The link is not spent until the code is right, so neither is the
      // marker that lets this device redeem it again.
      expect(await provider.hasPendingMagicRequest(), isTrue);

      provider.dispose();
    });

    test('completeTwoFactor finishes exactly like a direct magic-link success',
        () async {
      final provider = await pendingFromMagicLink();

      final ok = await provider.completeTwoFactor(FakeTwoFactorServer.totpCode);

      expect(ok, isTrue);
      expect(provider.isLoggedIn, isTrue);
      expect(provider.user!.email, FakeTwoFactorServer.email);
      expect(provider.subscriptionValid, isTrue);
      expect(provider.requiresTwoFactor, isFalse);
      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.lastError, isNull);
      expect(server.requestsTo('/auth/2fa/complete').single.body, {
        'pending_token': server.issuedPendingTokens.single,
        'code': FakeTwoFactorServer.totpCode,
      });
      expect(await storage.read(key: 'auth_token'), accessToken);
      expect(await storage.read(key: 'refresh_token'),
          FakeTwoFactorServer.refreshToken);
      expect(await storage.read(key: 'last_logged_in_email'),
          FakeTwoFactorServer.email);
      // One request authorises one sign-in.
      expect(await provider.hasPendingMagicRequest(), isFalse);

      // A fresh provider re-hydrates the completed session.
      final rehydrated = AccountProvider(enableProactiveRefresh: false);
      await rehydrated.init();
      expect(rehydrated.isLoggedIn, isTrue);

      provider.dispose();
      rehydrated.dispose();
    });

    test(
        'a wrong code keeps the pending sign-in; the next right code '
        'completes it with the same token', () async {
      final provider = await pendingFromMagicLink();

      expect(await provider.completeTwoFactor('000000'), isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.hasPendingTwoFactor, isTrue);
      expect(provider.lastError, contains('That code is incorrect'));

      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isTrue);
      expect(provider.isLoggedIn, isTrue);
      final tokensSent = server
          .requestsTo('/auth/2fa/complete')
          .map((r) => r.body['pending_token'])
          .toList();
      expect(tokensSent, [
        server.issuedPendingTokens.single,
        server.issuedPendingTokens.single,
      ]);

      provider.dispose();
    });

    test('an expired sign-in is dropped and the user is told to start again',
        () async {
      final provider = await pendingFromMagicLink();
      server.expirePendingTokens();

      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.requiresTwoFactor, isFalse);
      expect(provider.lastError, 'Your sign-in expired. Please start again.');
      expect(await storage.read(key: 'auth_token'), isNull);

      // Nothing is left to send: a retry fails locally, without a request.
      final sent = server.requestsTo('/auth/2fa/complete').length;
      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isFalse);
      expect(server.requestsTo('/auth/2fa/complete'), hasLength(sent));

      provider.dispose();
    });

    test('a lockout keeps the pending sign-in and says to wait', () async {
      final provider = await pendingFromMagicLink();
      for (var i = 0; i < FakeTwoFactorServer.maxAttempts; i++) {
        expect(await provider.completeTwoFactor('00000$i'), isFalse);
      }

      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.hasPendingTwoFactor, isTrue);
      expect(provider.lastError,
          'Too many attempts. Wait a few minutes, then try again.');

      provider.dispose();
    });

    test('a recovery code completes the sign-in; spaces are dropped', () async {
      final provider = await pendingFromMagicLink();

      expect(await provider.completeTwoFactor(' ab12 cd34ef '), isTrue);
      expect(provider.isLoggedIn, isTrue);
      expect(server.requestsTo('/auth/2fa/complete').single.body['code'],
          'ab12cd34ef');

      provider.dispose();
    });

    test('a code of impossible length is refused without spending an attempt',
        () async {
      final provider = await pendingFromMagicLink();

      expect(await provider.completeTwoFactor('12 345'), isFalse);
      expect(provider.lastError, contains('6-digit code'));
      expect(await provider.completeTwoFactor('a' * 65), isFalse);
      expect(server.requestsTo('/auth/2fa/complete'), isEmpty);
      expect(provider.hasPendingTwoFactor, isTrue);

      provider.dispose();
    });

    test('a dropped connection keeps the pending sign-in for a retry',
        () async {
      final provider = await pendingFromMagicLink();
      server.answerNext(
          '/auth/2fa/complete',
          (options) => throw DioException.connectionError(
              requestOptions: options, reason: 'offline'));

      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isFalse);
      expect(provider.lastError,
          'Network error. Check your connection and try again.');
      expect(provider.hasPendingTwoFactor, isTrue);

      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isTrue);
      expect(provider.isLoggedIn, isTrue);

      provider.dispose();
    });

    test('cancelTwoFactor drops the pending sign-in', () async {
      final provider = await pendingFromMagicLink();

      provider.cancelTwoFactor();

      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.requiresTwoFactor, isFalse);
      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isFalse);
      expect(server.requestsTo('/auth/2fa/complete'), isEmpty);

      provider.dispose();
    });

    test(
        'the code step lasts as long as the server\'s expires_in: inside it a '
        'code goes out, after it the step ends without a request', () async {
      server.expiresInSeconds = 60;
      var now = DateTime(2026, 11, 6, 12);
      final provider = await pendingFromMagicLink(clock: () => now);

      now = now.add(const Duration(seconds: 59));
      expect(await provider.completeTwoFactor('000000'), isFalse);
      expect(server.requestsTo('/auth/2fa/complete'), hasLength(1));
      expect(provider.hasPendingTwoFactor, isTrue);

      now = now.add(const Duration(seconds: 1));
      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isFalse);
      expect(server.requestsTo('/auth/2fa/complete'), hasLength(1));
      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.lastError, 'Your sign-in expired. Please start again.');

      provider.dispose();
    });

    test(
        'expireStaleTwoFactor ends the step only once its time is up, and '
        'says so once', () async {
      var now = DateTime(2026, 11, 6, 12);
      final provider = await pendingFromMagicLink(clock: () => now);
      var notified = 0;
      provider.addListener(() => notified++);

      now = now.add(const Duration(seconds: 299));
      expect(provider.expireStaleTwoFactor(), isFalse);
      expect(provider.hasPendingTwoFactor, isTrue);
      expect(provider.lastError, isNull);
      expect(notified, 0);

      now = now.add(const Duration(seconds: 1));
      expect(provider.expireStaleTwoFactor(), isTrue);
      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.lastError, 'Your sign-in expired. Please start again.');
      expect(notified, 1);

      expect(provider.expireStaleTwoFactor(), isFalse);
      expect(notified, 1);

      provider.dispose();
    });

    test(
        'the same link arriving again keeps the open code step when that '
        'second verify fails', () async {
      // app_links hands a launch link over twice; the second request must
      // not cost the user the step the first one opened.
      final provider = await pendingFromMagicLink();
      final firstToken = server.issuedPendingTokens.single;
      server.answerNext(
          '/auth/magic-link/verify',
          (options) => throw DioException.connectionError(
              requestOptions: options, reason: 'offline'));

      expect(await provider.verifyMagicCode('', 'link-token'), isFalse);

      expect(provider.hasPendingTwoFactor, isTrue);
      expect(provider.lastError, isNull);
      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isTrue);
      expect(
          server.requestsTo('/auth/2fa/complete').single.body['pending_token'],
          firstToken);

      provider.dispose();
    });

    test('a refused link tapped during the code step leaves the step open',
        () async {
      final provider = await pendingFromMagicLink();

      expect(await provider.verifyMagicCode('', 'spent-link'), isFalse);

      expect(provider.hasPendingTwoFactor, isTrue);
      expect(provider.twoFactorEmail, FakeTwoFactorServer.email);
      expect(provider.lastError, isNull);

      provider.dispose();
    });

    test('with no code step open, a refused link still explains itself',
        () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();

      expect(await provider.verifyMagicCode('', 'spent-link'), isFalse);

      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.lastError, contains('invalid or has already been used'));

      provider.dispose();
    });

    test(
        'an answer without a pending token replaces an open code step with '
        'the password guidance', () async {
      final provider = await pendingFromMagicLink();
      server.sendPendingToken = false;

      expect(await provider.verifyMagicCode('', 'link-token'), isFalse);

      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.requiresTwoFactor, isFalse);
      expect(provider.lastError, contains('Use password instead'));

      provider.dispose();
    });

    test('asking for a new link supersedes the pending code step', () async {
      final provider = await pendingFromMagicLink();

      expect(
          await provider.loginWithMagicLink(FakeTwoFactorServer.email), isTrue);

      expect(provider.hasPendingTwoFactor, isFalse);

      provider.dispose();
    });

    test('opening the link again replaces the challenge with a fresh one',
        () async {
      final provider = await pendingFromMagicLink();

      expect(await provider.verifyMagicCode('', 'link-token'), isFalse);
      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isTrue);

      expect(server.issuedPendingTokens, hasLength(2));
      expect(
          server.requestsTo('/auth/2fa/complete').single.body['pending_token'],
          server.issuedPendingTokens.last);

      provider.dispose();
    });

    test(
        'a challenge without a pending token explains the way out instead of '
        'showing a code step that cannot succeed', () async {
      server.sendPendingToken = false;
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();

      expect(await provider.verifyMagicCode('', 'link-token'), isFalse);

      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.requiresTwoFactor, isFalse);
      expect(provider.isLoggedIn, isFalse);
      expect(provider.lastError, contains('Use password instead'));

      provider.dispose();
    });

    test(
        'the password path keeps its re-post: no pending token is held and '
        'the code travels with the password', () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();

      expect(
          await provider.login(
              FakeTwoFactorServer.email, FakeTwoFactorServer.password),
          isFalse);
      expect(provider.requiresTwoFactor, isTrue);
      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.lastError,
          'Enter the 6-digit code from your authenticator app.');

      expect(
          await provider.login(
              FakeTwoFactorServer.email, FakeTwoFactorServer.password,
              totpCode: FakeTwoFactorServer.totpCode),
          isTrue);
      expect(provider.isLoggedIn, isTrue);
      expect(provider.requiresTwoFactor, isFalse);
      expect(server.requestsTo('/auth/login').last.body['totp_code'],
          FakeTwoFactorServer.totpCode);
      expect(server.requestsTo('/auth/2fa/complete'), isEmpty);

      provider.dispose();
    });

    test(
        'a wrong code on the password re-post stays on the code step and '
        'does not blame the password', () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();
      await provider.login(
          FakeTwoFactorServer.email, FakeTwoFactorServer.password);

      expect(
          await provider.login(
              FakeTwoFactorServer.email, FakeTwoFactorServer.password,
              totpCode: '000000'),
          isFalse);

      expect(provider.requiresTwoFactor, isTrue);
      expect(provider.lastError, contains('That code is incorrect'));
      expect(provider.lastError, isNot('Incorrect email or password.'));

      provider.dispose();
    });

    test('the password re-post drops spaces from the code before sending it',
        () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();
      await provider.login(
          FakeTwoFactorServer.email, FakeTwoFactorServer.password);

      expect(
          await provider.login(
              FakeTwoFactorServer.email, FakeTwoFactorServer.password,
              totpCode: ' 123 456 '),
          isTrue);

      expect(server.requestsTo('/auth/login').last.body['totp_code'],
          FakeTwoFactorServer.totpCode);
      expect(provider.isLoggedIn, isTrue);

      provider.dispose();
    });

    test(
        'a code of impossible length on the password re-post is refused '
        'without spending an attempt, and the code step stays', () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();
      await provider.login(
          FakeTwoFactorServer.email, FakeTwoFactorServer.password);
      final posts = server.requestsTo('/auth/login').length;

      for (final code in ['12 345', '12345', 'a' * 65]) {
        expect(
            await provider.login(
                FakeTwoFactorServer.email, FakeTwoFactorServer.password,
                totpCode: code),
            isFalse,
            reason: 'code "$code"');
        expect(provider.requiresTwoFactor, isTrue);
        expect(provider.lastError, contains('6-digit code'));
      }
      expect(server.requestsTo('/auth/login'), hasLength(posts));

      provider.dispose();
    });

    test(
        'a blank code on the password re-post sends the password alone, and '
        'a TOTP account is asked again without an attempt spent', () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();
      await provider.login(
          FakeTwoFactorServer.email, FakeTwoFactorServer.password);
      final posts = server.requestsTo('/auth/login').length;

      for (final code in ['', '   ']) {
        expect(
            await provider.login(
                FakeTwoFactorServer.email, FakeTwoFactorServer.password,
                totpCode: code),
            isFalse,
            reason: 'code "$code"');
        // No totp_code key at all: the server validates a present one at 6
        // to 64 characters, so even blanks must not go out as a code.
        expect(server.requestsTo('/auth/login').last.body,
            isNot(contains('totp_code')),
            reason: 'code "$code"');
        expect(provider.requiresTwoFactor, isTrue);
        expect(provider.lastError,
            'Enter the 6-digit code from your authenticator app.');
      }
      expect(server.requestsTo('/auth/login'), hasLength(posts + 2));

      // The blanks were not counted: every wrong code the lockout allows is
      // still left, and the right code after them signs in.
      for (var i = 0; i < FakeTwoFactorServer.maxAttempts - 1; i++) {
        expect(
            await provider.login(
                FakeTwoFactorServer.email, FakeTwoFactorServer.password,
                totpCode: '000000'),
            isFalse);
        expect(provider.lastError, contains('That code is incorrect'));
      }
      expect(
          await provider.login(
              FakeTwoFactorServer.email, FakeTwoFactorServer.password,
              totpCode: FakeTwoFactorServer.totpCode),
          isTrue);
      expect(provider.isLoggedIn, isTrue);

      provider.dispose();
    });

    test(
        'after a code was asked for, a blank code still signs in to an '
        'account without TOTP', () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();
      await provider.login(
          FakeTwoFactorServer.email, FakeTwoFactorServer.password);
      expect(provider.requiresTwoFactor, isTrue);

      // The user turns to another account, one without TOTP, and leaves the
      // code field that is still on the form empty.
      server.totpEnabled = false;
      expect(
          await provider.login(
              'other@orbvpn.test', FakeTwoFactorServer.password,
              totpCode: ''),
          isTrue);

      expect(provider.isLoggedIn, isTrue);
      expect(provider.requiresTwoFactor, isFalse);
      expect(provider.lastError, isNull);
      final sent = server.requestsTo('/auth/login').last.body;
      expect(sent['email'], 'other@orbvpn.test');
      expect(sent, isNot(contains('totp_code')));
      expect(await storage.read(key: 'auth_token'), accessToken);

      provider.dispose();
    });

    test(
        'cancelTwoFactor ends a password code step too, even with its message '
        'already cleared', () async {
      final provider = AccountProvider(enableProactiveRefresh: false);
      await provider.init();
      await provider.login(
          FakeTwoFactorServer.email, FakeTwoFactorServer.password);
      expect(provider.requiresTwoFactor, isTrue);
      expect(provider.hasPendingTwoFactor, isFalse);
      // Switching the form between link and password clears the message but
      // leaves the step open; leaving the screen after that must still end it.
      provider.clearError();
      var notified = 0;
      provider.addListener(() => notified++);

      provider.cancelTwoFactor();

      expect(provider.requiresTwoFactor, isFalse);
      expect(provider.lastError, isNull);
      expect(notified, 1);

      // Nothing left to end: no rebuild for nothing.
      provider.cancelTwoFactor();
      expect(notified, 1);

      // The next password sign-in starts over: the TOTP account is asked for
      // its code again, without one having been sent.
      expect(
          await provider.login(
              FakeTwoFactorServer.email, FakeTwoFactorServer.password),
          isFalse);
      expect(provider.requiresTwoFactor, isTrue);
      expect(server.requestsTo('/auth/login').last.body,
          isNot(contains('totp_code')));

      provider.dispose();
    });

    test('Google on a TOTP account goes to the code step and completes there',
        () async {
      // A real challenge from the fake server, handed back by a stand-in for
      // the native Google sheet.
      final envelope = await AuthApi()
          .oauthLogin(provider: 'google', token: 'google-id-token');
      final provider =
          _providerWithSocial(_FakeSocialAuthService(envelope: envelope));
      await provider.init();

      expect(await provider.loginWithGoogle(), isFalse);
      expect(provider.hasPendingTwoFactor, isTrue);
      expect(provider.lastError, isNull);
      expect(provider.isLoggedIn, isFalse);

      expect(await provider.completeTwoFactor(FakeTwoFactorServer.totpCode),
          isTrue);
      expect(provider.isLoggedIn, isTrue);
      expect(await storage.read(key: 'auth_token'), accessToken);

      provider.dispose();
    });

    test('logout clears a pending code step', () async {
      final provider = await pendingFromMagicLink();

      await provider.logout();

      expect(provider.hasPendingTwoFactor, isFalse);
      expect(provider.requiresTwoFactor, isFalse);

      provider.dispose();
    });
  });
}
