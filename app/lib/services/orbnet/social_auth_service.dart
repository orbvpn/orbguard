// lib/services/orbnet/social_auth_service.dart
//
// Native social sign-in (Google, Apple) for the shared OrbVPN/OrbNet account.
// Ported and adapted from OrbX's SocialAuthService, stripped of its logging /
// DI / device-limit coupling and kept self-contained under `orbnet/`.
//
// Each flow runs the platform's native SDK to obtain an OpenID idToken, then
// exchanges that token for OrbNet JWTs through the already-ported
// [AuthApi.oauthLogin] (POST /auth/oauth/login) — the same envelope the
// email/magic-link paths use, so the repository persists it identically.
//
// HONESTY: every method genuinely attempts the real native flow. There is NO
// fake-success path. If the native SDK is unconfigured (no idToken comes back),
// the user cancels, or the backend rejects the token's audience, the caller
// gets a truthful failure / cancellation — never a fabricated session.

import 'dart:io' show Platform;

import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'auth_api.dart';

/// Which native provider produced a [SocialAuthResult].
enum SocialAuthProvider { google, apple }

/// Thrown up the stack when the user backs out of a native sign-in sheet. The
/// UI treats this as a no-op (no error banner), unlike a genuine failure.
class SocialAuthCancelledException implements Exception {
  final SocialAuthProvider provider;
  SocialAuthCancelledException(this.provider);
  @override
  String toString() => 'SocialAuthCancelledException($provider)';
}

/// Outcome of a native social sign-in + backend token exchange.
///
/// On [success], [data] carries the raw OrbNet `/auth/oauth/login` envelope
/// (`{success, data:{user, tokens:{access_token, refresh_token}}}`) so the
/// repository can persist it through the exact same path as email/magic login.
class SocialAuthResult {
  final bool success;
  final bool cancelled;
  final Map<String, dynamic>? data;
  final String? error;
  final SocialAuthProvider provider;

  const SocialAuthResult._({
    required this.success,
    required this.provider,
    this.cancelled = false,
    this.data,
    this.error,
  });

  factory SocialAuthResult.success(
          SocialAuthProvider provider, Map<String, dynamic> data) =>
      SocialAuthResult._(success: true, provider: provider, data: data);

  factory SocialAuthResult.failure(SocialAuthProvider provider, String error) =>
      SocialAuthResult._(success: false, provider: provider, error: error);

  factory SocialAuthResult.canceled(SocialAuthProvider provider) =>
      SocialAuthResult._(success: false, provider: provider, cancelled: true);
}

/// Runs the native Google / Apple flows and exchanges the resulting idToken for
/// OrbNet JWTs. Stateless apart from a one-time GoogleSignIn initialisation.
class SocialAuthService {
  SocialAuthService({
    AuthApi? authApi,
    String? googleServerClientId,
    String? googleClientId,
  })  : _authApi = authApi ?? AuthApi(),
        _googleServerClientId = googleServerClientId ??
            (_envServerClientId.isNotEmpty
                ? _envServerClientId
                : _defaultServerClientId),
        _googleClientId = googleClientId ??
            (_envClientId.isNotEmpty ? _envClientId : _defaultClientId);

  // Defaults (shared OrbVPN Google project orbvpn-f8292), overridable via
  // --dart-define. serverClientId = the OrbVPN OAuth **Web** client that OrbNet
  // already accepts as the idToken audience (verified present in the backend's
  // ORBNET_OAUTH_GOOGLE_VALID_CLIENT_IDS; the same one OrbX passes). clientId =
  // OrbGuard's OWN iOS OAuth client (bundle com.orb.guard) for the iOS flow —
  // iOS only; on Android google_sign_in reads its client from
  // google-services.json, so this stays empty there.
  static const String _defaultServerClientId =
      '428639254932-93ijb65qnhvkacjjd2b5e17olm10fbck.apps.googleusercontent.com';
  static String get _defaultClientId => Platform.isIOS
      ? '428639254932-69dmmhiju98tm6kbq7rdi9fd0pgq1gv8.apps.googleusercontent.com'
      : '';

  final AuthApi _authApi;

  /// The OAuth **Web** client ID the backend expects as the Google idToken
  /// audience. REQUIRED on Android for [GoogleSignIn] to return an idToken at
  /// all. Provide at build time: --dart-define=GOOGLE_OAUTH_SERVER_CLIENT_ID=...
  final String _googleServerClientId;

  /// The iOS OAuth client ID. Optional — google_sign_in reads it from the
  /// bundled GoogleService-Info.plist / Info.plist (GIDClientID) when unset.
  final String _googleClientId;

  static const String _envServerClientId =
      String.fromEnvironment('GOOGLE_OAUTH_SERVER_CLIENT_ID');
  static const String _envClientId =
      String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');

  static const String _googleFailCopy =
      "Couldn't sign in with Google — try email instead.";
  static const String _appleFailCopy =
      "Couldn't sign in with Apple — try email instead.";

  // GoogleSignIn 7.x requires a single initialize() before authenticate().
  Future<void>? _googleInit;

  Future<void> _ensureGoogleInitialized() {
    return _googleInit ??= GoogleSignIn.instance.initialize(
      clientId: _googleClientId.isEmpty ? null : _googleClientId,
      serverClientId:
          _googleServerClientId.isEmpty ? null : _googleServerClientId,
    );
  }

  // ---- Google --------------------------------------------------------------

  /// Interactive Google sign-in. Returns the OrbNet envelope on success, a
  /// cancellation when the user dismisses the sheet, or an honest failure.
  Future<SocialAuthResult> signInWithGoogle() async {
    try {
      await _ensureGoogleInitialized();

      // Platforms that can't drive an app-side flow (e.g. web) must use the
      // platform-provided button instead — surface that honestly.
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        return SocialAuthResult.failure(
            SocialAuthProvider.google, _googleFailCopy);
      }

      final account = await GoogleSignIn.instance
          .authenticate(scopeHint: const ['email', 'profile']);
      final idToken = account.authentication.idToken;

      // A null idToken almost always means no serverClientId was configured
      // (Android) or the OAuth client is misconfigured — never a silent success.
      if (idToken == null || idToken.isEmpty) {
        return SocialAuthResult.failure(
            SocialAuthProvider.google, _googleFailCopy);
      }

      return _exchangeWithBackend(
          idToken, 'google', SocialAuthProvider.google, _googleFailCopy);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        return SocialAuthResult.canceled(SocialAuthProvider.google);
      }
      return SocialAuthResult.failure(
          SocialAuthProvider.google, _googleFailCopy);
    } catch (_) {
      return SocialAuthResult.failure(
          SocialAuthProvider.google, _googleFailCopy);
    }
  }

  // ---- Apple ---------------------------------------------------------------

  /// Interactive Sign in with Apple. Returns the OrbNet envelope on success, a
  /// cancellation when the user dismisses the sheet, or an honest failure.
  Future<SocialAuthResult> signInWithApple() async {
    try {
      if (!await SignInWithApple.isAvailable()) {
        return SocialAuthResult.failure(
            SocialAuthProvider.apple, _appleFailCopy);
      }

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        return SocialAuthResult.failure(
            SocialAuthProvider.apple, _appleFailCopy);
      }

      return _exchangeWithBackend(
          idToken, 'apple', SocialAuthProvider.apple, _appleFailCopy);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return SocialAuthResult.canceled(SocialAuthProvider.apple);
      }
      return SocialAuthResult.failure(
          SocialAuthProvider.apple, _appleFailCopy);
    } catch (_) {
      return SocialAuthResult.failure(
          SocialAuthProvider.apple, _appleFailCopy);
    }
  }

  // ---- Backend exchange ----------------------------------------------------

  /// Exchange a provider idToken for OrbNet JWTs and validate the envelope
  /// actually carries an access token before claiming success.
  Future<SocialAuthResult> _exchangeWithBackend(
    String idToken,
    String provider,
    SocialAuthProvider providerEnum,
    String failCopy,
  ) async {
    try {
      final result =
          await _authApi.oauthLogin(provider: provider, token: idToken);

      final data = result['data'] as Map<String, dynamic>? ?? result;
      final tokens = data['tokens'] as Map<String, dynamic>?;
      final accessToken = (tokens?['access_token'] ??
          data['access_token'] ??
          result['access_token']) as String?;

      if (accessToken == null || accessToken.isEmpty) {
        return SocialAuthResult.failure(providerEnum, failCopy);
      }

      // Hand back the raw envelope; the repository persists it via the same
      // path as email/magic login.
      return SocialAuthResult.success(providerEnum, result);
    } catch (_) {
      // Network failure, or the backend rejected the provider token's audience.
      return SocialAuthResult.failure(providerEnum, failCopy);
    }
  }
}
