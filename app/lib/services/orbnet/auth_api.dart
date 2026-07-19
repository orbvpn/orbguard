// lib/services/orbnet/auth_api.dart
//
// Thin wrappers over the OrbNet auth endpoints. Ported from OrbX (passkey/QR/
// device-management endpoints omitted for Phase A1 — email+password and
// magic-link are the supported paths). All endpoints are POST with no auth
// header (skipAuth), except /auth/logout which sends the current session.

import 'orbnet_api_client.dart';

/// Sent as `client` on every OrbGuard login so OrbNet issues a session without
/// consuming a VPN device slot (OrbGuard has its own device limit). Must match
/// the backend's accepted value (auth.ClientOrbGuard).
const String kOrbGuardClient = 'orbguard';

class AuthApi {
  final OrbNetApiClient _client = OrbNetApiClient.instance;

  /// Login with email + password. [totpCode] is sent when 2FA is required.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? totpCode,
  }) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'email': email,
        'password': password,
        if (totpCode != null && totpCode.isNotEmpty) 'totp_code': totpCode,
        // Identify as OrbGuard so OrbNet issues a no-VPN-device session (own
        // device limit) instead of consuming a VPN device slot.
        'client': kOrbGuardClient,
      },
      skipAuth: true,
    );
  }

  /// Register a new OrbNet account.
  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
    String? referralCode,
  }) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        if (firstName != null) 'first_name': firstName,
        if (lastName != null) 'last_name': lastName,
        if (referralCode != null) 'referral_code': referralCode,
      },
      skipAuth: true,
    );
  }

  /// Refresh the access token. The refresh token is sent in the body.
  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/refresh',
      data: {'refresh_token': refreshToken},
      skipAuth: true,
    );
  }

  /// Request a password reset email.
  Future<Map<String, dynamic>> forgotPassword(String email,
      {String? source}) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/forgot-password',
      data: {
        'email': email,
        if (source != null) 'source': source,
      },
      skipAuth: true,
    );
  }

  /// Reset a password with a token from the reset email.
  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/reset-password',
      data: {'token': token, 'new_password': newPassword},
      skipAuth: true,
    );
  }

  /// Request a magic-link / one-time sign-in code by email.
  /// Returns `is_new_user` to indicate whether an account was just created.
  Future<Map<String, dynamic>> requestMagicLink(
    String email, {
    bool allowRegistration = true,
    bool termsAccepted = true,
  }) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/magic-link/request',
      data: {
        'email': email,
        'source': 'mobile',
        // Identify OrbGuard so the backend sends the OrbGuard-branded email and
        // an orbguard://login deep link (instead of the OrbVPN defaults).
        'client': kOrbGuardClient,
        'allow_registration': allowRegistration,
        'terms_accepted': termsAccepted,
      },
      skipAuth: true,
    );
  }

  /// Verify a magic-link token / code and complete sign-in.
  Future<Map<String, dynamic>> verifyMagicLink(String token) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/magic-link/verify',
      data: {'token': token, 'client': kOrbGuardClient},
      skipAuth: true,
    );
  }

  /// OAuth sign-in with a provider token (wired end-to-end in a later phase).
  Future<Map<String, dynamic>> oauthLogin({
    required String provider,
    required String token,
  }) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/oauth/login',
      data: {'provider': provider, 'token': token, 'client': kOrbGuardClient},
      skipAuth: true,
    );
  }

  // ---- Passkey (WebAuthn) ---------------------------------------------------

  /// Begin a passkey authentication ceremony. Public (no bearer). Optional
  /// [email] targets one account; omit for a discoverable/passwordless prompt.
  /// Returns `{options, session_id}` (WebAuthn request options + session id).
  Future<Map<String, dynamic>> beginPasskeyAuth({String? email}) async {
    final q = (email != null && email.trim().isNotEmpty)
        ? '?email=${Uri.encodeQueryComponent(email.trim())}'
        : '';
    return await _client.post<Map<String, dynamic>>(
      '/auth/passkey/authenticate/begin$q',
      data: const {},
      skipAuth: true,
    );
  }

  /// Finish passkey authentication with the platform assertion. Public (no
  /// bearer). Returns the same auth envelope as magic-link/oauth login.
  Future<Map<String, dynamic>> finishPasskeyAuth({
    required String sessionId,
    required Map<String, dynamic> response,
    String? deviceId,
    String? platform,
    String? deviceName,
    String? fcmToken,
  }) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/passkey/authenticate/finish',
      data: {
        'session_id': sessionId,
        'response': response,
        // OrbGuard's own device limit — no-VPN-device session, so passkey login
        // never consumes a VPN device slot (same as magic-link/oauth).
        'client': kOrbGuardClient,
        if (deviceId != null) 'device_id': deviceId,
        if (platform != null) 'platform': platform,
        if (deviceName != null) 'device_name': deviceName,
        if (fcmToken != null) 'fcm_token': fcmToken,
      },
      skipAuth: true,
    );
  }

  /// Begin passkey REGISTRATION (bearer required — user must be signed in).
  /// Returns `{options, session_id}` (WebAuthn creation options + session id).
  Future<Map<String, dynamic>> beginPasskeyRegistration() async {
    return await _client.post<Map<String, dynamic>>(
      '/security/passkeys/register/begin',
      data: const {},
    );
  }

  /// Finish passkey REGISTRATION with the platform attestation (bearer required).
  Future<Map<String, dynamic>> finishPasskeyRegistration({
    required String sessionId,
    required String name,
    required Map<String, dynamic> response,
  }) async {
    return await _client.post<Map<String, dynamic>>(
      '/security/passkeys/register/finish',
      data: {'session_id': sessionId, 'name': name, 'response': response},
    );
  }

  /// Revoke the current session on the backend (best-effort).
  Future<Map<String, dynamic>> logout({String? refreshToken}) async {
    return await _client.post<Map<String, dynamic>>(
      '/auth/logout',
      data: {
        if (refreshToken != null) 'refresh_token': refreshToken,
      },
    );
  }
}
