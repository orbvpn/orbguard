// lib/services/orbnet/auth_repository.dart
//
// Backend-agnostic auth repository for the shared OrbVPN/OrbNet account.
// Ported from OrbX and simplified for OrbGuard Phase A1: email+password login,
// magic-link sign-in, token refresh with rotation, and logout. Passkey / QR /
// social-OAuth / device-management flows are intentionally omitted this phase.
//
// Token storage keys are IDENTICAL to OrbX so a shared on-device session is
// possible: `auth_token`, `refresh_token`, `user_data`, `last_logged_in_email`.
//
// The crown jewel — kept verbatim in spirit — is [refreshToken]'s rule: the
// app may force a logout ONLY when the server POSITIVELY rejects the refresh
// token (401/403). Every other failure (offline, timeout, transient 5xx) keeps
// the session and retries.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_api.dart';
import 'models/auth_response.dart';
import 'models/user.dart';
import 'network_error.dart' as net_err;
import 'orbnet_api_client.dart';

/// Thrown when the account has 2FA enabled and a TOTP code is required.
class TwoFactorRequiredException implements Exception {
  final String message;
  TwoFactorRequiredException(
      [this.message = 'Two-factor authentication required']);
  @override
  String toString() => message;
}

/// Result of a magic-link request (unified sign-in/sign-up flow).
class MagicLinkResult {
  final bool success;
  final bool isNewUser;
  MagicLinkResult({required this.success, required this.isNewUser});
}

/// Precise outcome of the most recent token-refresh attempt — the single
/// source of truth for "should we log the user out?". Only [authRejected]
/// justifies a forced logout.
enum TokenRefreshOutcome {
  success,
  authRejected,
  networkError,
  noToken,
  unknown,
}

class AuthRepository {
  final OrbNetApiClient _restClient = OrbNetApiClient.instance;
  final AuthApi _authApi = AuthApi();
  final FlutterSecureStorage _secureStorage;

  // In-memory token cache (updated synchronously on refresh, before the slower
  // secure-storage write) so the 401-retry never re-sends a stale token.
  String? _cachedAccessToken;
  String? _cachedRefreshToken;

  // Mutex: with token rotation, only ONE refresh may run at a time.
  bool _isRefreshing = false;
  Completer<bool>? _refreshCompleter;

  TokenRefreshOutcome _lastRefreshOutcome = TokenRefreshOutcome.success;

  AuthRepository({required FlutterSecureStorage secureStorage})
      : _secureStorage = secureStorage {
    // Wire the REST client's 401 interceptor to this repository.
    _restClient.setTokenRefreshCallback(refreshToken);
    _restClient.setCachedTokenGetter(getCachedToken);
    _restClient.setRefreshAuthRejectionProbe(() => lastRefreshWasAuthRejection);
  }

  /// The outcome of the most recent [refreshToken] call.
  TokenRefreshOutcome get lastRefreshOutcome => _lastRefreshOutcome;

  /// True only when the most recent refresh was a positive server auth
  /// rejection (401/403). Consulted by the REST 401 interceptor via a probe.
  bool get lastRefreshWasAuthRejection =>
      _lastRefreshOutcome == TokenRefreshOutcome.authRejected;

  bool get isRefreshInProgress => _isRefreshing;

  String? getCachedToken() => _cachedAccessToken;
  String? getCachedRefreshToken() => _cachedRefreshToken;

  /// Register the logout callback. Forwards it to the REST client so a
  /// confirmed 401 during any request triggers the same logout.
  void setSessionExpiredCallback(void Function() callback) {
    _restClient.setSessionExpiredCallback(() async => callback());
  }

  /// Wait for an in-progress refresh to finish.
  /// Returns its result, or null if no refresh was running.
  Future<bool?> awaitRefreshIfInProgress() async {
    if (!_isRefreshing || _refreshCompleter == null) return null;
    try {
      return await _refreshCompleter!.future;
    } catch (_) {
      return false;
    }
  }

  // ---- Login ---------------------------------------------------------------

  /// Login with email + password. Throws [TwoFactorRequiredException] when the
  /// account needs a TOTP code.
  Future<AuthResponse> login(String email, String password,
      {String? totpCode}) async {
    email = email.trim().toLowerCase();

    // Clear any stale tokens first (cache + storage) so an old expired token
    // never rides along and trips a 500 on the login endpoint.
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'refresh_token');

    final result =
        await _authApi.login(email: email, password: password, totpCode: totpCode);

    final AuthResponse response = await _persistAuthResult(result);
    _log('Login successful: ${response.user.email}');
    return response;
  }

  /// Register a new account, then log in with the same credentials.
  Future<AuthResponse> register({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    String? referralCode,
  }) async {
    await _authApi.register(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
      referralCode: referralCode,
    );
    return await login(email, password);
  }

  // ---- Magic link ----------------------------------------------------------

  /// Request a magic-link / one-time code by email.
  Future<MagicLinkResult> requestMagicLink(String email,
      {bool allowRegistration = true}) async {
    email = email.trim().toLowerCase();

    // Clear stale tokens for a clean upcoming sign-in.
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'refresh_token');

    final response = await _authApi.requestMagicLink(email,
        allowRegistration: allowRegistration);
    final isNewUser = response['is_new_user'] == true;
    return MagicLinkResult(success: true, isNewUser: isNewUser);
  }

  /// Verify a magic-link code/token and complete sign-in.
  Future<AuthResponse> verifyMagicLogin(String email, String code) async {
    final result = await _authApi.verifyMagicLink(code);
    final response = await _persistAuthResult(result);
    _log('Magic login successful: ${response.user.email}');
    return response;
  }

  /// Shared handling for a login/verify response: parse the Go envelope
  /// `{success, data:{user, tokens:{access_token, refresh_token}, subscription}}`,
  /// detect 2FA, cache + persist tokens, and store the user.
  Future<AuthResponse> _persistAuthResult(Map<String, dynamic> result) async {
    final data = result['data'] as Map<String, dynamic>? ?? result;

    if (data['requires_2fa'] == true) {
      throw TwoFactorRequiredException();
    }

    final tokens = data['tokens'] as Map<String, dynamic>?;
    final userData = data['user'] as Map<String, dynamic>? ??
        result['user'] as Map<String, dynamic>;

    final accessToken = (tokens?['access_token'] ??
        data['access_token'] ??
        result['access_token']) as String;

    // An empty token also indicates 2FA is required.
    if (accessToken.isEmpty) {
      throw TwoFactorRequiredException();
    }

    final refreshToken = (tokens?['refresh_token'] ??
        data['refresh_token'] ??
        result['refresh_token']) as String?;

    _cachedAccessToken = accessToken;
    _cachedRefreshToken = refreshToken;

    await _secureStorage.write(key: 'auth_token', value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secureStorage.write(key: 'refresh_token', value: refreshToken);
    }

    // Login returns subscription alongside (not inside) user — merge it in.
    if (userData['subscription'] == null && data['subscription'] != null) {
      userData['subscription'] = data['subscription'];
    }

    await _secureStorage.write(key: 'user_data', value: jsonEncode(userData));

    final user = User.fromJson(userData);
    await _saveLastLoggedInEmail(user.email);

    return AuthResponse(
        accessToken: accessToken, refreshToken: refreshToken, user: user);
  }

  // ---- Token refresh (the crown jewel) -------------------------------------

  /// Refresh the access token using the refresh token, with rotation.
  ///
  /// Golden rule: on failure, only [TokenRefreshOutcome.authRejected] (a
  /// positive 401/403) clears the session. Network / transient failures keep
  /// the refresh token and are retried later.
  Future<bool> refreshToken() async {
    // Coalesce concurrent callers onto a single in-flight refresh.
    if (_isRefreshing && _refreshCompleter != null) {
      try {
        return await _refreshCompleter!.future;
      } catch (_) {
        return false;
      }
    }

    _isRefreshing = true;
    _refreshCompleter = Completer<bool>();

    try {
      String? refreshTokenValue = _cachedRefreshToken;
      refreshTokenValue ??= await _secureStorage.read(key: 'refresh_token');

      if (refreshTokenValue == null || refreshTokenValue.isEmpty) {
        _lastRefreshOutcome = TokenRefreshOutcome.noToken;
        _refreshCompleter?.complete(false);
        return false;
      }

      Map<String, dynamic> result;
      try {
        result = await _authApi.refreshToken(refreshTokenValue);
      } catch (apiError) {
        // Classify the failure. Clear the refresh token ONLY on a positive
        // server rejection — never on a network error.
        if (net_err.isAuthRejectionError(apiError)) {
          _lastRefreshOutcome = TokenRefreshOutcome.authRejected;
          _cachedRefreshToken = null;
          try {
            await _secureStorage.delete(key: 'refresh_token');
          } catch (_) {}
        } else if (net_err.isNetworkError(apiError)) {
          _lastRefreshOutcome = TokenRefreshOutcome.networkError;
        } else {
          _lastRefreshOutcome = TokenRefreshOutcome.unknown;
        }
        _refreshCompleter?.complete(false);
        return false;
      }

      final data = result['data'] as Map<String, dynamic>? ?? result;
      final tokens = data['tokens'] as Map<String, dynamic>?;

      final newAccessToken = (tokens?['access_token'] ??
          data['access_token'] ??
          result['access_token']) as String;
      final newRefreshToken = (tokens?['refresh_token'] ??
          data['refresh_token'] ??
          result['refresh_token']) as String?;

      // Update the cache IMMEDIATELY so concurrent callers see new tokens.
      _cachedAccessToken = newAccessToken;
      if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
        _cachedRefreshToken = newRefreshToken;
      }

      try {
        await _secureStorage.write(key: 'auth_token', value: newAccessToken);
        if (newRefreshToken != null && newRefreshToken.isNotEmpty) {
          await _secureStorage.write(
              key: 'refresh_token', value: newRefreshToken);
        }
      } catch (_) {
        // Tokens remain cached; they'll persist on the next success.
      }

      // Refresh may also return updated user data.
      final userData = data['user'] as Map<String, dynamic>?;
      if (userData != null) {
        try {
          await _secureStorage.write(
              key: 'user_data', value: jsonEncode(userData));
        } catch (_) {}
      }

      _lastRefreshOutcome = TokenRefreshOutcome.success;
      _refreshCompleter?.complete(true);
      return true;
    } catch (e) {
      _lastRefreshOutcome = net_err.isAuthRejectionError(e)
          ? TokenRefreshOutcome.authRejected
          : net_err.isNetworkError(e)
              ? TokenRefreshOutcome.networkError
              : TokenRefreshOutcome.unknown;
      _refreshCompleter?.complete(false);
      return false;
    } finally {
      _isRefreshing = false;
      _refreshCompleter = null;
    }
  }

  // ---- Session load / logout ----------------------------------------------

  /// Hydrate the session from secure storage. Returns the stored [User], or
  /// null when there is no valid session on disk.
  Future<User?> loadUser() async {
    try {
      _cachedAccessToken = await _secureStorage.read(key: 'auth_token');
      _cachedRefreshToken = await _secureStorage.read(key: 'refresh_token');

      if (_cachedAccessToken == null) return null;

      final userDataJson = await _secureStorage.read(key: 'user_data');
      if (userDataJson == null) return null;

      final userData = jsonDecode(userDataJson) as Map<String, dynamic>;
      return User.fromJson(userData);
    } catch (e) {
      _log('Failed to load user: $e');
      return null;
    }
  }

  /// Logout. Best-effort backend revocation, then always clear local tokens.
  Future<void> logout() async {
    try {
      final refreshToken = _cachedRefreshToken ??
          await _secureStorage.read(key: 'refresh_token');
      try {
        await _authApi.logout(refreshToken: refreshToken);
      } catch (e) {
        // Never block local cleanup on a failed network call.
        _log('Backend logout failed (best-effort): $e');
      }
    } finally {
      _cachedAccessToken = null;
      _cachedRefreshToken = null;
      await _secureStorage.delete(key: 'auth_token');
      await _secureStorage.delete(key: 'refresh_token');
      await _secureStorage.delete(key: 'user_data');
      // Keep `last_logged_in_email` so we can pre-fill the sign-in form.
    }
  }

  /// Clear only the local session (no backend call). Used when the server has
  /// already invalidated the session (a confirmed 401/403).
  Future<void> clearLocalSession() async {
    _cachedAccessToken = null;
    _cachedRefreshToken = null;
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'refresh_token');
    await _secureStorage.delete(key: 'user_data');
  }

  Future<void> _saveLastLoggedInEmail(String email) async {
    await _secureStorage.write(
        key: 'last_logged_in_email', value: email.trim().toLowerCase());
  }

  Future<String?> getLastLoggedInEmail() async =>
      await _secureStorage.read(key: 'last_logged_in_email');

  void _log(String message) {
    if (kDebugMode) debugPrint('[AuthRepository] $message');
  }
}
