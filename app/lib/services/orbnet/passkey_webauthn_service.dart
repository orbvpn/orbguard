// lib/services/orbnet/passkey_webauthn_service.dart
//
// Real WebAuthn platform-authenticator client for OrbGuard, ported from OrbVPN's
// PasskeyWebAuthnService. The platform authenticator performs user verification
// (Face / fingerprint / device PIN) and produces a real assertion (login) or
// attestation (registration) that the shared OrbNet backend verifies against
// RP ID `orbai.world`.
//
// Request types are built MANUALLY from the backend's standard WebAuthn options
// rather than via the package's strict `fromJson` — go-webauthn omits optional
// members those generated parsers treat as required and would throw on.

import 'package:passkeys/authenticator.dart';
import 'package:passkeys/types.dart';

class PasskeyWebAuthnService {
  PasskeyWebAuthnService({PasskeyAuthenticator? authenticator})
      : _authenticator = authenticator ?? PasskeyAuthenticator();

  final PasskeyAuthenticator _authenticator;

  /// Whether this device can perform passkey ceremonies (platform authenticator
  /// / screen lock present). Used to gate the passkey UI.
  Future<bool> isAvailable() async {
    try {
      // ignore: deprecated_member_use
      return await _authenticator.canAuthenticate();
    } catch (_) {
      return false;
    }
  }

  /// Cancel any in-flight ceremony (e.g. when leaving the screen).
  Future<void> cancel() async {
    try {
      await _authenticator.cancelCurrentAuthenticatorOperation();
    } catch (_) {}
  }

  /// Run a registration ceremony. [options] is the backend's
  /// PublicKeyCredentialCreationOptions JSON. Returns the attestation credential
  /// JSON to POST to the finish endpoint.
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async {
    final response =
        await _authenticator.register(_buildRegisterRequest(options));
    return response.toJson();
  }

  /// Run an authentication ceremony. [options] is the backend's
  /// PublicKeyCredentialRequestOptions JSON. Returns the assertion credential
  /// JSON to POST to the finish endpoint.
  Future<Map<String, dynamic>> authenticate(
      Map<String, dynamic> options) async {
    final response =
        await _authenticator.authenticate(_buildAuthenticateRequest(options));
    return response.toJson();
  }

  RegisterRequestType _buildRegisterRequest(Map<String, dynamic> o) {
    final rp = _asMap(o['rp']);
    final user = _asMap(o['user']);
    final authSel = _asMap(o['authenticatorSelection']);

    return RegisterRequestType(
      challenge: o['challenge'] as String,
      relyingParty: RelyingPartyType(
        id: (rp['id'] as String?) ?? 'orbai.world',
        name: (rp['name'] as String?) ?? (rp['id'] as String? ?? 'OrbGuard'),
      ),
      user: UserType(
        id: user['id'] as String,
        name: (user['name'] as String?) ?? '',
        displayName: (user['displayName'] as String?) ??
            (user['name'] as String?) ??
            '',
      ),
      authSelectionType: AuthenticatorSelectionType(
        authenticatorAttachment: authSel['authenticatorAttachment'] as String?,
        requireResidentKey: (authSel['requireResidentKey'] as bool?) ?? false,
        residentKey: (authSel['residentKey'] as String?) ?? 'preferred',
        userVerification:
            (authSel['userVerification'] as String?) ?? 'preferred',
      ),
      pubKeyCredParams: _pubKeyCredParams(o['pubKeyCredParams']),
      excludeCredentials: _credentials(o['excludeCredentials']),
      timeout: o['timeout'] as int?,
      attestation: o['attestation'] as String?,
    );
  }

  AuthenticateRequestType _buildAuthenticateRequest(Map<String, dynamic> o) {
    final allow = _credentials(o['allowCredentials']);
    return AuthenticateRequestType(
      relyingPartyId: (o['rpId'] as String?) ?? '',
      challenge: o['challenge'] as String,
      timeout: o['timeout'] as int?,
      userVerification: (o['userVerification'] as String?) ?? 'preferred',
      allowCredentials: allow.isEmpty ? null : allow,
      mediation: MediationType.Optional,
      preferImmediatelyAvailableCredentials: false,
    );
  }

  List<PubKeyCredParamType>? _pubKeyCredParams(dynamic raw) {
    if (raw is! List) return null;
    final params = raw
        .whereType<Map>()
        .map((e) {
          final m = e.cast<String, dynamic>();
          final alg = m['alg'];
          if (alg is! int) return null;
          return PubKeyCredParamType(
            type: (m['type'] as String?) ?? 'public-key',
            alg: alg,
          );
        })
        .whereType<PubKeyCredParamType>()
        .toList();
    return params.isEmpty ? null : params;
  }

  List<CredentialType> _credentials(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) {
          final m = e.cast<String, dynamic>();
          final id = m['id'];
          if (id is! String) return null;
          return CredentialType(
            type: (m['type'] as String?) ?? 'public-key',
            id: id,
            transports:
                (m['transports'] as List?)?.whereType<String>().toList() ??
                    const <String>[],
          );
        })
        .whereType<CredentialType>()
        .toList();
  }

  Map<String, dynamic> _asMap(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
}
