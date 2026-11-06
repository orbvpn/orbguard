// A stand-in for the OrbNet auth routes the second-factor flow touches,
// installed as the OrbNet client's Dio adapter so tests exercise the REAL wire
// mapping (envelope parsing, RFC 7807 error codes, bearer handling) without a
// network.
//
// /auth/2fa/complete follows the server's own rules (orbnet
// internal/service/auth/second_factor.go): the pending token is spent only by
// a RIGHT code, so a wrong one leaves it usable; a spent, expired or unknown
// token is TWO_FACTOR_PENDING_INVALID; every attempt is counted before the
// code is looked at and the sixth inside the window is TWO_FACTOR_LOCKED; a
// right code clears the count. Codes are normalised the way the server does
// it (spaces dropped, lower-cased, a hyphen-less recovery code re-hyphenated).

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One request the fake received.
class RecordedRequest {
  RecordedRequest(this.method, this.path, this.headers, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> body;
}

class FakeTwoFactorServer implements HttpClientAdapter {
  FakeTwoFactorServer({required this.accessToken});

  /// Access token every successful sign-in returns.
  final String accessToken;

  static const email = 'twofa@orbvpn.test';
  static const password = 'S3cret!pass';
  static const totpCode = '123456';
  static const recoveryCode = 'ab12-cd34ef';
  static const refreshToken = 'refresh-2fa';
  static const maxAttempts = 5;

  /// Whether the account has TOTP on. Off: every first factor gets tokens.
  bool totpEnabled = true;

  /// Off: the challenge leaves out `two_factor`, as a server that predates
  /// /auth/2fa/complete would.
  bool sendPendingToken = true;

  /// The `expires_in` every challenge announces, in seconds.
  int expiresInSeconds = 300;

  final Map<String, ResponseBody Function(RequestOptions options)>
      _nextAnswers = {};

  /// Answers the next request whose path ends with [pathSuffix] with [answer]
  /// instead of the rules above: a front-door rate limit, a fault, a body of
  /// an unusual shape, or (by throwing) a dropped connection.
  void answerNext(String pathSuffix,
          ResponseBody Function(RequestOptions options) answer) =>
      _nextAnswers[pathSuffix] = answer;

  /// Every request seen, in order.
  final List<RecordedRequest> requests = [];

  int _issued = 0;
  final Set<String> _livePendingTokens = {};
  final Set<String> _usedRecoveryCodes = {};
  int _attempts = 0;

  /// The pending tokens handed out so far, in order.
  final List<String> issuedPendingTokens = [];

  /// Requests that hit [path] (suffix match on the URL path).
  List<RecordedRequest> requestsTo(String path) =>
      requests.where((r) => r.path.endsWith(path)).toList();

  /// Every outstanding pending token runs out, as five minutes passing would.
  void expirePendingTokens() => _livePendingTokens.clear();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final body = options.data is Map
        ? Map<String, dynamic>.from(options.data as Map)
        : <String, dynamic>{};
    requests.add(RecordedRequest(options.method, path,
        Map<String, dynamic>.from(options.headers), body));

    for (final suffix in _nextAnswers.keys) {
      if (path.endsWith(suffix)) {
        return _nextAnswers.remove(suffix)!(options);
      }
    }

    if (path.endsWith('/auth/magic-link/request')) {
      return jsonResponse(200, {'success': true, 'is_new_user': false});
    }
    if (path.endsWith('/auth/magic-link/verify')) {
      if (body['token'] == 'spent-link') {
        return problemResponse(401, 'MAGIC_LINK_USED',
            'Magic Link Already Used', 'This magic link has already been used');
      }
      return totpEnabled ? _challenge() : _session();
    }
    if (path.endsWith('/auth/oauth/login')) {
      return totpEnabled ? _challenge() : _session();
    }
    if (path.endsWith('/auth/login')) return _passwordLogin(body);
    if (path.endsWith('/auth/2fa/complete')) return _complete(body);
    if (path.endsWith('/auth/logout')) {
      return jsonResponse(200, {'success': true});
    }
    return problemResponse(
        404, 'NOT_FOUND', 'Not Found', 'unexpected path: $path');
  }

  ResponseBody _passwordLogin(Map<String, dynamic> body) {
    if (body['password'] != password) {
      return problemResponse(401, 'INVALID_CREDENTIALS',
          'Authentication Failed', 'Invalid email or password');
    }
    if (!totpEnabled) return _session();
    final code = body['totp_code'];
    if (code is! String || code.isEmpty) return _challenge();
    return _checkCode(code, onSuccess: _session);
  }

  ResponseBody _complete(Map<String, dynamic> body) {
    final token = body['pending_token'];
    final code = body['code'];
    if (token is! String || code is! String || code.length < 6) {
      return problemResponse(422, 'VALIDATION_ERROR', 'Validation Error',
          'One or more fields failed validation');
    }
    if (!_livePendingTokens.contains(token)) {
      return problemResponse(
          401,
          'TWO_FACTOR_PENDING_INVALID',
          'Sign-In Expired',
          'This sign-in has expired or was already completed. Please start '
              'again');
    }
    return _checkCode(code, onSuccess: () {
      _livePendingTokens.remove(token);
      return _session();
    });
  }

  ResponseBody _checkCode(String code,
      {required ResponseBody Function() onSuccess}) {
    _attempts++;
    if (_attempts > maxAttempts) {
      return problemResponse(429, 'TWO_FACTOR_LOCKED', 'Too Many Attempts',
          'Too many incorrect codes. Please wait a few minutes and try again');
    }
    final normalized = code.replaceAll(' ', '').toLowerCase();
    var ok = normalized == totpCode;
    if (!ok) {
      final recovery = normalized.length == 10 && !normalized.contains('-')
          ? '${normalized.substring(0, 4)}-${normalized.substring(4)}'
          : normalized;
      ok = recovery == recoveryCode && _usedRecoveryCodes.add(recovery);
    }
    if (!ok) {
      return problemResponse(401, 'TWO_FACTOR_INVALID', 'Invalid Code',
          'The two-factor code is incorrect');
    }
    _attempts = 0;
    return onSuccess();
  }

  ResponseBody _challenge() {
    final data = <String, dynamic>{
      'requires_2fa': true,
      'user': {'email': email},
    };
    if (sendPendingToken) {
      final token = 'pending-${++_issued}';
      issuedPendingTokens.add(token);
      _livePendingTokens.add(token);
      data['two_factor'] = {
        'pending_token': token,
        'expires_in': expiresInSeconds,
        'methods': ['totp', 'recovery_code'],
      };
    }
    return jsonResponse(200, {'success': true, 'data': data});
  }

  ResponseBody _session() => jsonResponse(200, {
        'success': true,
        'data': {
          'user': {'id': 26, 'email': email, 'role': 'user'},
          'tokens': {
            'access_token': accessToken,
            'refresh_token': refreshToken,
          },
          'subscription': {
            'group_name': 'premium_monthly',
            'max_devices': 5,
            'status': 'ACTIVE',
          },
        },
      });

  /// An RFC 7807 problem body, as orbnet's httputil.Error writes it.
  static ResponseBody problemResponse(
          int status, String code, String title, String detail) =>
      ResponseBody.fromString(
        jsonEncode({
          'type': 'https://api.orbai.world/errors/$code',
          'title': title,
          'status': status,
          'detail': detail,
          'code': code,
        }),
        status,
        headers: {
          Headers.contentTypeHeader: [
            'application/problem+json; charset=utf-8'
          ],
        },
      );

  static ResponseBody jsonResponse(int status, Map<String, dynamic> body) =>
      ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

  @override
  void close({bool force = false}) {}
}
