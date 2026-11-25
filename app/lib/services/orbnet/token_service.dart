// lib/services/orbnet/token_service.dart
//
// JWT token management for the OrbNet session: parse claims, check expiry,
// proactively refresh ~3 minutes before expiry (with token rotation), and
// expose the subscription/identity claims. Ported from OrbX and simplified —
// the VPN-connection buffer and the getProfile-based session poll are dropped
// (not needed for Phase A1); the proactive refresher and the "only end the
// session on a positive auth rejection" rule are kept.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'models/subscription_status.dart';

class TokenService {
  final AuthRepository _authRepository;

  /// Refresh this long before expiry. Must be < the access-token lifetime
  /// (~1h) so we never schedule a refresh at t=0 and spin.
  static const Duration _proactiveRefreshBuffer = Duration(minutes: 3);

  /// Buffer used by [needsRefresh] (a broader "should refresh soon" window).
  static const Duration _refreshBuffer = Duration(minutes: 5);

  /// Grace period right after login — don't immediately try to refresh.
  static const Duration _loginGracePeriod = Duration(seconds: 30);

  Timer? _refreshTimer;
  DateTime? _refreshStartedAt;

  void Function()? _onSessionExpired;

  TokenService(this._authRepository);

  /// Set the callback fired when the session is confirmed dead.
  void setSessionExpiredCallback(void Function() callback) =>
      _onSessionExpired = callback;

  /// The single rule for "is this session truly dead?" — pure + testable.
  /// End the session ONLY when the server rejected the refresh token (401/403),
  /// or there is genuinely no refresh token AND the access token has expired.
  /// A network/unknown outcome is always recoverable.
  static bool shouldEndSession(TokenRefreshOutcome outcome, bool tokenExpired) {
    if (outcome == TokenRefreshOutcome.authRejected) return true;
    if (outcome == TokenRefreshOutcome.noToken && tokenExpired) return true;
    return false;
  }

  /// Start proactive background refresh. Call after login / session load.
  void startProactiveRefresh() {
    _refreshStartedAt = DateTime.now();
    _scheduleNextRefresh();
  }

  /// Stop proactive refresh. Call on logout / dispose.
  void stopProactiveRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshStartedAt = null;
  }

  void _scheduleNextRefresh() {
    _refreshTimer?.cancel();

    final currentToken = _authRepository.getCachedToken();
    if (currentToken == null) return;

    final expiration = getTokenExpiration(currentToken);
    if (expiration == null) {
      // Unknown expiry — check again in an hour.
      _refreshTimer =
          Timer(const Duration(hours: 1), _performProactiveRefresh);
      return;
    }

    final refreshTime = expiration.subtract(_proactiveRefreshBuffer);
    final now = DateTime.now();

    // Respect the post-login grace period.
    if (_refreshStartedAt != null) {
      final sinceStart = now.difference(_refreshStartedAt!);
      if (sinceStart < _loginGracePeriod) {
        final graceRemaining = _loginGracePeriod - sinceStart;
        _refreshTimer = Timer(graceRemaining, _scheduleNextRefresh);
        return;
      }
    }

    if (now.isAfter(refreshTime)) {
      _performProactiveRefresh();
    } else {
      _refreshTimer =
          Timer(refreshTime.difference(now), _performProactiveRefresh);
    }
  }

  Future<void> _performProactiveRefresh() async {
    // Coordinate with any in-progress refresh triggered elsewhere.
    final inProgress = await _authRepository.awaitRefreshIfInProgress();
    if (inProgress != null) {
      inProgress ? _scheduleNextRefresh() : _handleRefreshFailure();
      return;
    }

    try {
      final success = await _authRepository.refreshToken();
      if (success) {
        _scheduleNextRefresh();
      } else {
        _handleRefreshFailure();
      }
    } catch (e) {
      _log('Proactive refresh error: $e');
      _handleRefreshFailure();
    }
  }

  /// Force-end the session ONLY with positive proof it is dead; otherwise keep
  /// it and retry. A network blip must never log the user out.
  void _handleRefreshFailure() {
    final outcome = _authRepository.lastRefreshOutcome;
    final currentToken = _authRepository.getCachedToken();
    final tokenExpired = currentToken == null || isTokenExpired(currentToken);

    if (shouldEndSession(outcome, tokenExpired)) {
      _onSessionExpired?.call();
      return;
    }

    final remaining = timeUntilExpiration(currentToken);
    final retryDelay = (!tokenExpired && remaining.inMinutes > 10)
        ? const Duration(minutes: 5)
        : const Duration(minutes: 1);
    _refreshTimer = Timer(retryDelay, _performProactiveRefresh);
  }

  // ---- JWT parsing ---------------------------------------------------------

  /// Parse JWT claims WITHOUT verifying the signature.
  Map<String, dynamic>? parseJwt(String? token) {
    if (token == null || token.isEmpty) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = _decodeBase64(parts[1]);
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (e) {
      _log('Failed to parse JWT: $e');
      return null;
    }
  }

  String _decodeBase64(String str) {
    String normalized = str;
    switch (str.length % 4) {
      case 2:
        normalized = '$str==';
        break;
      case 3:
        normalized = '$str=';
        break;
    }
    normalized = normalized.replaceAll('-', '+').replaceAll('_', '/');
    return utf8.decode(base64Decode(normalized));
  }

  DateTime? getTokenExpiration(String? token) {
    final claims = parseJwt(token);
    final exp = claims?['exp'];
    if (exp is! int) return null;
    return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
  }

  bool isTokenExpired(String? token) {
    final expiration = getTokenExpiration(token);
    if (expiration == null) return true; // fail safe
    return DateTime.now().isAfter(expiration);
  }

  bool needsRefresh(String? token) {
    final expiration = getTokenExpiration(token);
    if (expiration == null) return true;
    return DateTime.now().isAfter(expiration.subtract(_refreshBuffer));
  }

  Duration timeUntilExpiration(String? token) {
    final expiration = getTokenExpiration(token);
    if (expiration == null) return Duration.zero;
    final remaining = expiration.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  int? getUserId(String? token) => parseJwt(token)?['user_id'] as int?;
  String? getUserEmail(String? token) => parseJwt(token)?['email'] as String?;
  String? getUserRole(String? token) => parseJwt(token)?['role'] as String?;

  /// Normalized subscription info from the JWT claims.
  Map<String, dynamic> getSubscriptionInfo(String? token) {
    final claims = parseJwt(token);
    if (claims == null) return {};
    return {
      'subscriptionTier': claims['subscription_tier'],
      'subscriptionId': claims['subscription_id'],
      'subscriptionGroupId': claims['subscription_group_id'],
      'subscriptionValid': claims['subscription_valid'] ?? false,
      'subscriptionStatus': claims['subscription_status'],
      'subscriptionExpiresAt': claims['subscription_expires_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              (claims['subscription_expires_at'] as int) * 1000)
          : null,
      'gracePeriodEndsAt': claims['grace_period_ends_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(
              (claims['grace_period_ends_at'] as int) * 1000)
          : null,
      'deviceLimit': claims['device_limit'] ?? 1,
      'isAdSupported': claims['is_ad_supported'] ?? false,
      'autoRenew': claims['auto_renew'] ?? false,
      'paymentGateway': claims['payment_gateway'],
      'active': claims['active'] ?? true,
      'enabled': claims['enabled'] ?? true,
      'resellerId': claims['reseller_id'],
    };
  }

  /// Subscription status from the JWT claims (convenience wrapper).
  SubscriptionStatusFromToken getSubscriptionStatus(String? token) {
    return SubscriptionStatusFromToken.fromMap(getSubscriptionInfo(token));
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[TokenService] $message');
  }
}
