/// The half-finished sign-in OrbNet answers when the first factor (a magic
/// link, a Google/Apple token, a passkey or a password) was right but the
/// account has TOTP enabled. The response carries no tokens:
///
///   {"requires_2fa": true, "user": {"email": "..."},
///    "two_factor": {"pending_token": "...", "expires_in": 300,
///                   "methods": ["totp", "recovery_code"]}}
///
/// The pending token goes back to `POST /auth/2fa/complete` together with the
/// user's code. Until then it is the only proof of the first factor, so it is
/// held in memory only, never persisted, and never logged: [toString] leaves
/// it out on purpose.
library;

class TwoFactorChallenge {
  const TwoFactorChallenge({
    required this.pendingToken,
    this.email,
    this.methods = const [],
    this.expiresIn = defaultLifetime,
  });

  /// How long a pending sign-in lasts when the server does not say: the
  /// five minutes OrbNet gives every pending token.
  static const Duration defaultLifetime = Duration(minutes: 5);

  /// Opaque, short-lived, single-use proof of the first factor.
  final String pendingToken;

  /// How long the server keeps the pending sign-in open, from the moment it
  /// answered. The server stays the judge; the app uses this only to stop
  /// offering a code step it knows can no longer succeed.
  final Duration expiresIn;

  /// The account the challenge is for — the only identity the server reveals
  /// before the second factor. Shown above the code field.
  final String? email;

  /// The second factors the server will accept (`totp`, `recovery_code`).
  final List<String> methods;

  /// Recovery codes are offered unless the server listed its methods and left
  /// them out; an empty list means the server did not say, and the code field
  /// sends whatever is typed either way.
  bool get acceptsRecoveryCode =>
      methods.isEmpty || methods.contains('recovery_code');

  /// Reads the challenge from a sign-in response's `data` object. Null when
  /// the response asked for a second factor without a pending token — a
  /// server older than `/auth/2fa/complete`, which only the password path can
  /// answer (by re-posting the password with the code).
  static TwoFactorChallenge? fromAuthData(Map<String, dynamic> data) {
    final twoFactor = data['two_factor'];
    if (twoFactor is! Map) return null;
    final token = twoFactor['pending_token'];
    if (token is! String || token.isEmpty) return null;

    final user = data['user'];
    final email = user is Map ? user['email'] : null;
    final methods = twoFactor['methods'];
    final expiresIn = twoFactor['expires_in'];

    return TwoFactorChallenge(
      pendingToken: token,
      email: email is String && email.trim().isNotEmpty ? email.trim() : null,
      methods: methods is List
          ? List.unmodifiable(methods.whereType<String>())
          : const [],
      expiresIn: expiresIn is num && expiresIn >= 1
          ? Duration(seconds: expiresIn.toInt())
          : defaultLifetime,
    );
  }

  @override
  String toString() => 'TwoFactorChallenge(email: $email, methods: $methods)';
}
