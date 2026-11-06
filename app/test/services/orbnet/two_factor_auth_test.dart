// Second-factor sign-in at the repository level, against the real wire
// mapping: the OrbNet client's Dio adapter is a fake OrbNet that follows the
// server's /auth/2fa/complete rules (fake_two_factor_server.dart), so these
// prove what the app SENDS and how it reads every documented answer —
// requires_2fa with and without a pending token, completion success, and each
// refusal (wrong code, replayed token, expired token, lockout, front-door
// rate limit, network loss).

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/orbnet/auth_api.dart';
import 'package:orbguard/services/orbnet/auth_repository.dart';
import 'package:orbguard/services/orbnet/models/two_factor_challenge.dart';
import 'package:orbguard/services/orbnet/orbnet_api_client.dart';
import 'package:orbguard/services/orbnet/social_auth_service.dart';

import 'fake_two_factor_server.dart';

/// A syntactically valid JWT; nothing here verifies the signature.
String _makeJwt(Map<String, dynamic> payload) {
  String seg(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${seg({'alg': 'HS256', 'typ': 'JWT'})}.${seg(payload)}.sig';
}

Matcher _twoFactorFailure(TwoFactorFailure reason) =>
    isA<TwoFactorException>().having((e) => e.reason, 'reason', reason);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storage = FlutterSecureStorage();
  late FakeTwoFactorServer server;
  late String accessToken;
  late AuthRepository repo;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    final exp =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    accessToken = _makeJwt({
      'user_id': 26,
      'email': FakeTwoFactorServer.email,
      'exp': exp,
      'subscription_valid': true,
    });
    server = FakeTwoFactorServer(accessToken: accessToken);
    OrbNetApiClient.instance.debugReset();
    await OrbNetApiClient.instance.initialize();
    OrbNetApiClient.instance.httpClientAdapter = server;
    repo = AuthRepository(secureStorage: storage);
  });

  /// Verify a magic link on the TOTP account and return the challenge.
  Future<TwoFactorChallenge> challengeFromMagicLink() async {
    try {
      await repo.verifyMagicLogin('', 'link-token');
    } on TwoFactorRequiredException catch (e) {
      return e.challenge!;
    }
    fail('expected the magic link to ask for the second factor');
  }

  group('TwoFactorChallenge', () {
    test('reads the pending token, email and methods; never prints the token',
        () {
      final challenge = TwoFactorChallenge.fromAuthData({
        'requires_2fa': true,
        'user': {'email': ' someone@orbvpn.test '},
        'two_factor': {
          'pending_token': 'secret-pending-token',
          'expires_in': 300,
          'methods': ['totp', 'recovery_code'],
        },
      })!;

      expect(challenge.pendingToken, 'secret-pending-token');
      expect(challenge.email, 'someone@orbvpn.test');
      expect(challenge.methods, ['totp', 'recovery_code']);
      expect(challenge.expiresIn, const Duration(minutes: 5));
      expect(challenge.acceptsRecoveryCode, isTrue);
      expect(challenge.toString(), isNot(contains('secret-pending-token')));
    });

    test(
        'takes its lifetime from expires_in; five minutes when the server '
        'gives no usable one', () {
      Duration lifetime(Object? expiresIn) =>
          TwoFactorChallenge.fromAuthData({
            'two_factor': {
              'pending_token': 't',
              if (expiresIn != null) 'expires_in': expiresIn,
            },
          })!
              .expiresIn;

      expect(lifetime(120), const Duration(minutes: 2));
      expect(lifetime(90.0), const Duration(seconds: 90));
      expect(lifetime(null), TwoFactorChallenge.defaultLifetime);
      expect(lifetime(0), TwoFactorChallenge.defaultLifetime);
      expect(lifetime(-30), TwoFactorChallenge.defaultLifetime);
      expect(lifetime('300'), TwoFactorChallenge.defaultLifetime);
      expect(TwoFactorChallenge.defaultLifetime, const Duration(minutes: 5));
    });

    test('null when the answer has no usable pending token', () {
      expect(TwoFactorChallenge.fromAuthData({'requires_2fa': true}), isNull);
      expect(
          TwoFactorChallenge.fromAuthData({
            'requires_2fa': true,
            'two_factor': {'pending_token': ''},
          }),
          isNull);
      expect(
          TwoFactorChallenge.fromAuthData({
            'requires_2fa': true,
            'two_factor': {'pending_token': 42},
          }),
          isNull);
    });

    test(
        'recovery codes are offered unless the server listed methods without '
        'them', () {
      TwoFactorChallenge withMethods(List<String>? methods) =>
          TwoFactorChallenge.fromAuthData({
            'two_factor': {
              'pending_token': 't',
              if (methods != null) 'methods': methods,
            },
          })!;

      expect(withMethods(['totp']).acceptsRecoveryCode, isFalse);
      expect(
          withMethods(['totp', 'recovery_code']).acceptsRecoveryCode, isTrue);
      expect(withMethods(null).acceptsRecoveryCode, isTrue);
    });
  });

  group('magic-link verify on a TOTP account', () {
    test('raises the challenge with its pending token and stores nothing',
        () async {
      await storage.write(
          key: 'last_logged_in_email', value: 'prev@orbvpn.test');

      final challenge = await challengeFromMagicLink();

      expect(challenge.pendingToken, server.issuedPendingTokens.single);
      expect(challenge.email, FakeTwoFactorServer.email);
      expect(challenge.acceptsRecoveryCode, isTrue);
      // No session exists before the second factor.
      expect(await storage.read(key: 'auth_token'), isNull);
      expect(await storage.read(key: 'refresh_token'), isNull);
      expect(await storage.read(key: 'user_data'), isNull);
      expect(
          await storage.read(key: 'last_logged_in_email'), 'prev@orbvpn.test');
      expect(repo.getCachedToken(), isNull);
    });

    test('requires_2fa without two_factor still refuses to sign in', () async {
      server.sendPendingToken = false;

      await expectLater(
        repo.verifyMagicLogin('', 'link-token'),
        throwsA(isA<TwoFactorRequiredException>()
            .having((e) => e.challenge, 'challenge', isNull)),
      );
      expect(await storage.read(key: 'auth_token'), isNull);
    });

    test('an account without TOTP signs in directly, as before', () async {
      server.totpEnabled = false;

      final res = await repo.verifyMagicLogin('', 'link-token');

      expect(res.user.email, FakeTwoFactorServer.email);
      expect(await storage.read(key: 'auth_token'), accessToken);
      expect(server.requestsTo('/auth/2fa/complete'), isEmpty);
    });
  });

  group('completeTwoFactor', () {
    test(
        'posts exactly {pending_token, code} with no bearer, then persists '
        'the session like the first step would', () async {
      final challenge = await challengeFromMagicLink();
      // A stale token on disk must not ride along to the public endpoint.
      await storage.write(key: 'auth_token', value: 'stale-access-token');

      final res = await repo.completeTwoFactor(
          challenge.pendingToken, FakeTwoFactorServer.totpCode);

      final sent = server.requestsTo('/auth/2fa/complete').single;
      expect(sent.method, 'POST');
      expect(sent.body, {
        'pending_token': challenge.pendingToken,
        'code': FakeTwoFactorServer.totpCode,
      });
      expect(sent.headers['Authorization'], isNull);

      expect(res.accessToken, accessToken);
      expect(res.user.email, FakeTwoFactorServer.email);
      expect(repo.getCachedToken(), accessToken);
      expect(await storage.read(key: 'auth_token'), accessToken);
      expect(await storage.read(key: 'refresh_token'),
          FakeTwoFactorServer.refreshToken);
      final user = jsonDecode((await storage.read(key: 'user_data'))!)
          as Map<String, dynamic>;
      expect(user['email'], FakeTwoFactorServer.email);
      expect(user['subscription'], isNotNull);
      expect(await storage.read(key: 'last_logged_in_email'),
          FakeTwoFactorServer.email);
    });

    test('a wrong code is invalidCode and leaves the pending token usable',
        () async {
      final challenge = await challengeFromMagicLink();

      await expectLater(
        repo.completeTwoFactor(challenge.pendingToken, '000000'),
        throwsA(_twoFactorFailure(TwoFactorFailure.invalidCode)),
      );
      expect(await storage.read(key: 'auth_token'), isNull);

      final res = await repo.completeTwoFactor(
          challenge.pendingToken, FakeTwoFactorServer.totpCode);
      expect(res.accessToken, accessToken);
    });

    test('a replayed pending token is expired', () async {
      final challenge = await challengeFromMagicLink();
      await repo.completeTwoFactor(
          challenge.pendingToken, FakeTwoFactorServer.totpCode);
      await repo.clearLocalSession();

      await expectLater(
        repo.completeTwoFactor(
            challenge.pendingToken, FakeTwoFactorServer.totpCode),
        throwsA(_twoFactorFailure(TwoFactorFailure.expired)),
      );
      expect(await storage.read(key: 'auth_token'), isNull);
    });

    test('an expired pending token is expired', () async {
      final challenge = await challengeFromMagicLink();
      server.expirePendingTokens();

      await expectLater(
        repo.completeTwoFactor(
            challenge.pendingToken, FakeTwoFactorServer.totpCode),
        throwsA(_twoFactorFailure(TwoFactorFailure.expired)),
      );
    });

    test('after five wrong codes the next attempt is locked, even a right one',
        () async {
      final challenge = await challengeFromMagicLink();
      for (var i = 0; i < FakeTwoFactorServer.maxAttempts; i++) {
        await expectLater(
          repo.completeTwoFactor(challenge.pendingToken, '00000$i'),
          throwsA(_twoFactorFailure(TwoFactorFailure.invalidCode)),
        );
      }

      await expectLater(
        repo.completeTwoFactor(
            challenge.pendingToken, FakeTwoFactorServer.totpCode),
        throwsA(_twoFactorFailure(TwoFactorFailure.locked)),
      );
      expect(await storage.read(key: 'auth_token'), isNull);
    });

    test('a recovery code is sent as typed and completes; it works only once',
        () async {
      final first = await challengeFromMagicLink();
      await repo.completeTwoFactor(first.pendingToken, 'AB12CD34EF');
      expect(server.requestsTo('/auth/2fa/complete').last.body['code'],
          'AB12CD34EF');
      expect(await storage.read(key: 'auth_token'), accessToken);

      await repo.clearLocalSession();
      final second = await challengeFromMagicLink();
      await expectLater(
        repo.completeTwoFactor(
            second.pendingToken, FakeTwoFactorServer.recoveryCode),
        throwsA(_twoFactorFailure(TwoFactorFailure.invalidCode)),
      );
    });

    test('the front-door rate limit (429 RATE_LIMITED) reads as locked',
        () async {
      final challenge = await challengeFromMagicLink();
      server.answerNext(
          '/auth/2fa/complete',
          (_) => FakeTwoFactorServer.problemResponse(
              429, 'RATE_LIMITED', 'Too Many Requests', 'Rate limit exceeded'));

      await expectLater(
        repo.completeTwoFactor(
            challenge.pendingToken, FakeTwoFactorServer.totpCode),
        throwsA(_twoFactorFailure(TwoFactorFailure.locked)),
      );
    });

    test('any other 401 from the completion reads as expired', () async {
      final challenge = await challengeFromMagicLink();
      server.answerNext(
          '/auth/2fa/complete',
          (_) => FakeTwoFactorServer.problemResponse(
              401, 'UNAUTHORIZED', 'Unauthorized', 'Unauthorized'));

      await expectLater(
        repo.completeTwoFactor(
            challenge.pendingToken, FakeTwoFactorServer.totpCode),
        throwsA(_twoFactorFailure(TwoFactorFailure.expired)),
      );
    });

    test('a dropped connection surfaces as a network error, not a refusal',
        () async {
      final challenge = await challengeFromMagicLink();
      server.answerNext(
          '/auth/2fa/complete',
          (options) => throw DioException.connectionError(
              requestOptions: options, reason: 'offline'));

      await expectLater(
        repo.completeTwoFactor(
            challenge.pendingToken, FakeTwoFactorServer.totpCode),
        throwsA(isA<NetworkException>()),
      );
    });

    test('a device-limit 403 passes through with its code', () async {
      final challenge = await challengeFromMagicLink();
      server.answerNext(
          '/auth/2fa/complete',
          (_) => FakeTwoFactorServer.jsonResponse(403, {
                'error': 'DEVICE_LIMIT_EXCEEDED',
                'message': 'You have reached your device limit.',
                'current_devices': 3,
                'max_devices': 2,
              }));

      await expectLater(
        repo.completeTwoFactor(
            challenge.pendingToken, FakeTwoFactorServer.totpCode),
        throwsA(isA<AuthorizationException>()
            .having((e) => e.code, 'code', 'DEVICE_LIMIT_EXCEEDED')
            .having((e) => e.message, 'message',
                'You have reached your device limit.')),
      );
    });
  });

  group('password re-post', () {
    test('a wrong totp_code is invalidCode, not a wrong password', () async {
      await expectLater(
        repo.login(FakeTwoFactorServer.email, FakeTwoFactorServer.password),
        throwsA(isA<TwoFactorRequiredException>()),
      );

      await expectLater(
        repo.login(FakeTwoFactorServer.email, FakeTwoFactorServer.password,
            totpCode: '000000'),
        throwsA(_twoFactorFailure(TwoFactorFailure.invalidCode)),
      );
    });

    test('a wrong password is still an authentication failure', () async {
      await expectLater(
        repo.login(FakeTwoFactorServer.email, 'wrong-password'),
        throwsA(isA<AuthenticationException>()
            .having((e) => e.code, 'code', 'INVALID_CREDENTIALS')),
      );
    });

    test('a recovery code in totp_code signs in', () async {
      final res = await repo.login(
          FakeTwoFactorServer.email, FakeTwoFactorServer.password,
          totpCode: FakeTwoFactorServer.recoveryCode);

      expect(res.accessToken, accessToken);
      expect(server.requestsTo('/auth/login').last.body['totp_code'],
          FakeTwoFactorServer.recoveryCode);
      expect(server.requestsTo('/auth/2fa/complete'), isEmpty);
    });
  });

  group('OAuth exchange', () {
    test('a requires_2fa envelope is handed on for the code prompt', () async {
      final social = SocialAuthService(authApi: AuthApi());

      final result = await social.exchangeWithBackend(
          'google-id-token', 'google', SocialAuthProvider.google, 'fail copy');

      expect(result.success, isTrue);
      final data = result.data!['data'] as Map<String, dynamic>;
      expect(data['requires_2fa'], isTrue);
      expect((data['two_factor'] as Map)['pending_token'],
          server.issuedPendingTokens.single);
    });

    test('an envelope with neither tokens nor a challenge is still a failure',
        () async {
      server.answerNext('/auth/oauth/login',
          (_) => FakeTwoFactorServer.jsonResponse(200, {'success': true}));
      final social = SocialAuthService(authApi: AuthApi());

      final result = await social.exchangeWithBackend(
          'google-id-token', 'google', SocialAuthProvider.google, 'fail copy');

      expect(result.success, isFalse);
      expect(result.error, 'fail copy');
    });
  });

  group('OrbNet error mapping', () {
    test('a sentence under "error" is a message, not a code', () async {
      server.answerNext(
          '/auth/login',
          (_) => FakeTwoFactorServer.jsonResponse(
              400, {'error': 'Something unexpected happened'}));

      await expectLater(
        OrbNetApiClient.instance.post<Map<String, dynamic>>('/auth/login',
            data: const <String, dynamic>{}, skipAuth: true),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', isNull)
            .having((e) => e.statusCode, 'statusCode', 400)
            .having(
                (e) => e.message, 'message', 'Something unexpected happened')),
      );
    });

    test('a non-string detail does not break error handling', () async {
      server.answerNext(
          '/auth/login',
          (_) => FakeTwoFactorServer.jsonResponse(401, {
                'detail': {'nested': true},
                'title': 'Unauthorized',
                'code': 'UNAUTHORIZED',
              }));

      await expectLater(
        OrbNetApiClient.instance.post<Map<String, dynamic>>('/auth/login',
            data: const <String, dynamic>{}, skipAuth: true),
        throwsA(isA<AuthenticationException>()
            .having((e) => e.message, 'message', 'Unauthorized')
            .having((e) => e.code, 'code', 'UNAUTHORIZED')),
      );
    });
  });
}
