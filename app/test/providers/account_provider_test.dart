// Unit tests for AccountProvider (shared OrbVPN/OrbNet account state).
//
// Proves: logged-out by default; a mocked successful login sets isLoggedIn and
// PERSISTS to secure storage (a fresh provider re-hydrates); logout clears the
// session. The OrbNet REST client's Dio adapter is replaced with a fake so no
// real network is hit, and flutter_secure_storage runs on its in-memory mock.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/services/orbnet/auth_repository.dart';
import 'package:orbguard/services/orbnet/orbnet_api_client.dart';
import 'package:orbguard/services/orbnet/social_auth_service.dart';

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
    expect(await storage.read(key: 'last_logged_in_email'), 'social@orbvpn.test');

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
}
