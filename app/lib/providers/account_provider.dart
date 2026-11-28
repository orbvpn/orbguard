// lib/providers/account_provider.dart
//
// OrbGuard's account state — the shared OrbVPN/OrbNet identity. A thin
// ChangeNotifier over the ported OrbNet auth stack (`lib/services/orbnet/`).
//
// Login is OPTIONAL this phase: it UNLOCKS subscription / credits / remote
// control, but anonymous scanning still works without an account. This provider
// does NOT touch OrbGuard's own anonymous device registration
// (`OrbGuardApiClient` against guard.orbai.world) — the two coexist.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:passkeys/exceptions.dart';

import '../services/device_agent/device_claim_service.dart';
import '../services/orbnet/auth_repository.dart';
import '../services/orbnet/network_error.dart' as net_err;
import '../services/orbnet/orbnet_api_client.dart';
import '../services/orbnet/social_auth_service.dart';
import '../services/orbnet/token_service.dart';
import '../services/orbnet/models/auth_response.dart';
import '../services/orbnet/models/passkey_info.dart';
import '../services/orbnet/models/subscription_status.dart';
import '../services/orbnet/models/two_factor_challenge.dart';
import '../services/orbnet/models/user.dart';
import '../utils/amazon_build.dart';

/// The sign-in method that left a second factor pending. Completion has to
/// finish the way that method finishes: for a magic link that includes
/// spending this device's "asked for a link" marker.
enum _TwoFactorOrigin { magicLink, google, apple, passkey }

/// A sign-in waiting for its second factor, and how it began.
class _PendingTwoFactor {
  const _PendingTwoFactor(this.challenge, this.origin, this.deadline);
  final TwoFactorChallenge challenge;
  final _TwoFactorOrigin origin;

  /// When the server stops honouring [challenge]'s pending token.
  final DateTime deadline;
}

class AccountProvider extends ChangeNotifier {
  late final AuthRepository _repo;
  late final TokenService _tokenService;
  late final bool _enableProactiveRefresh;
  late final DateTime Function() _now;

  User? _user;
  bool _isInitialized = false;
  bool _busy = false;
  String? _error;

  // A password sign-in waiting for its code. It is answered by re-posting the
  // password with the code (login(totpCode:)), which the server still honours.
  bool _passwordTwoFactor = false;

  // A magic-link, Google, Apple or passkey sign-in waiting for its code. The
  // challenge's pending token is a short-lived bearer for the second step, so
  // it lives in memory only — never in storage, never in a log line.
  //
  // It outlives the sign-in screen on purpose. The app lock disposes every
  // route while it covers the app, and with the lock on it does so each time
  // the user switches to the authenticator app to read the code; the screen
  // is put back afterwards (TwoFactorResume). So the challenge ends only when
  // the user leaves the step, finishes it, starts another sign-in, signs out,
  // or its time is up.
  _PendingTwoFactor? _pendingTwoFactor;

  // The server's bounds on a second-factor code (CompleteTwoFactorRequest
  // `code`, LoginRequest `totp_code`): a 6-digit TOTP code at the short end,
  // recovery codes well inside the long.
  static const int _minTwoFactorCodeLength = 6;
  static const int _maxTwoFactorCodeLength = 64;

  /// Whether an email sign-in link may create an account for an address
  /// that has none. The Amazon build creates no accounts: there the server
  /// mails a link only to an existing account, and answers the same either
  /// way.
  final bool allowRegistration;

  /// [enableProactiveRefresh] can be turned off in tests to avoid background
  /// timers. Inject [authRepository]/[tokenService] for testing, and [clock]
  /// to move time past a pending sign-in's deadline.
  AccountProvider({
    AuthRepository? authRepository,
    TokenService? tokenService,
    bool enableProactiveRefresh = true,
    DateTime Function()? clock,
    this.allowRegistration = !kAmazonBuild,
  }) {
    _enableProactiveRefresh = enableProactiveRefresh;
    _now = clock ?? DateTime.now;
    _repo = authRepository ??
        AuthRepository(secureStorage: const FlutterSecureStorage());
    _tokenService = tokenService ?? TokenService(_repo);
    // A confirmed session death (positive 401/403) clears local state.
    _repo.setSessionExpiredCallback(_handleSessionExpired);
    _tokenService.setSessionExpiredCallback(_handleSessionExpired);
  }

  // ---- State getters -------------------------------------------------------

  /// Whether a user is signed in.
  bool get isLoggedIn => _user != null;

  /// The signed-in user (null when logged out).
  User? get user => _user;

  /// The signed-in user's email (null when logged out).
  String? get email => _user?.email;

  /// The user's display name, falling back to email.
  String? get displayName => _user?.displayNameOrFull;

  /// Whether [init] has completed (safe to read login state).
  bool get isInitialized => _isInitialized;

  /// Whether an auth request is in flight.
  bool get isBusy => _busy;

  /// The last user-facing error message (null when none).
  String? get lastError => _error;

  /// True when the last sign-in attempt is waiting for a second factor: the
  /// 6-digit code from an authenticator app, or a recovery code.
  bool get requiresTwoFactor => _passwordTwoFactor || _pendingTwoFactor != null;

  /// True when the waiting sign-in began with a magic link, Google, Apple or a
  /// passkey and completes through [completeTwoFactor]. False while a password
  /// sign-in waits: that one re-posts the password with the code via [login].
  /// The pending sign-in does not depend on any screen staying open.
  bool get hasPendingTwoFactor => _pendingTwoFactor != null;

  /// The account the pending second factor is for, as the server named it.
  String? get twoFactorEmail => _pendingTwoFactor?.challenge.email;

  /// Whether the code step may take a recovery code. True for the password
  /// step too: the server checks `totp_code` with the same rules.
  bool get twoFactorAcceptsRecoveryCode =>
      _pendingTwoFactor?.challenge.acceptsRecoveryCode ?? true;

  /// Subscription status parsed from the current access-token claims.
  SubscriptionStatusFromToken get subscription =>
      _tokenService.getSubscriptionStatus(_repo.getCachedToken());

  /// Subscription tier/plan name (from claims, else the stored user).
  String? get subscriptionTier {
    final tier = subscription.subscriptionTier;
    if (tier != null && tier.isNotEmpty) return tier;
    return _user?.subscription?.planName;
  }

  /// Whether the account currently has a valid/entitled subscription.
  bool get subscriptionValid =>
      subscription.subscriptionValid || (_user?.hasActiveSubscription ?? false);

  /// The single premium-gating key: a signed-in account WITH a live, entitled
  /// subscription. Everything premium (ad-free, the Pro/expert console, deeper
  /// & unlimited scans, remote control/camera) unlocks off this one flag. Free
  /// tier — logged out, OR logged in without a valid subscription — is false;
  /// basic on-demand scanning stays available regardless.
  bool get hasPremium => isLoggedIn && subscriptionValid;

  /// A short, honest label for the current entitlement: the subscription
  /// tier/plan name when premium (falling back to "Premium" when the tier is
  /// unnamed), otherwise "Free". Never names a plan the user hasn't paid for.
  String get subscriptionLabel {
    if (!hasPremium) return 'Free';
    final tier = subscriptionTier;
    return (tier != null && tier.isNotEmpty) ? tier : 'Premium';
  }

  // ---- Actions -------------------------------------------------------------

  /// Hydrate the session from secure storage. Never throws; safe to call once
  /// at startup (e.g. `AccountProvider()..init()`).
  Future<void> init() async {
    if (_isInitialized) return;
    try {
      final user = await _repo.loadUser();
      if (user != null) {
        _user = user;
        _startRefresh();
      }
    } catch (e) {
      _log('init failed: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Sign in with email + password. Returns true on success. On a 2FA-enabled
  /// account, returns false and sets [requiresTwoFactor]; call again with a
  /// [totpCode] (authenticator or recovery code). A blank [totpCode] counts as
  /// none. Never wipes an existing session on a network error.
  Future<bool> login(String email, String password, {String? totpCode}) async {
    if (_busy) return false;
    // A blank code field is no code: the password goes out alone and the
    // server answers for the account typed in. The field stays on the form
    // once a code was asked for, so this is how the user still reaches an
    // account without TOTP; one with TOTP is just asked again, and the
    // server counts an attempt only when there is a code to check.
    final typed = totpCode?.replaceAll(_whitespace, '') ?? '';
    final code = typed.isEmpty ? null : _twoFactorCodeOrNull(typed);
    if (typed.isNotEmpty && code == null) {
      // The re-post checks the code with the same rules as the code step,
      // so the same malformed code is refused here without a request; the
      // password step stays open for a proper one.
      _error = _twoFactorCodeShape;
      notifyListeners();
      return false;
    }
    _setBusy(true);
    _error = null;
    _passwordTwoFactor = false;
    // A new first factor supersedes a code step left open by another method.
    _pendingTwoFactor = null;
    try {
      final res = await _repo.login(email, password, totpCode: code);
      _user = res.user;
      _startRefresh();
      _bootstrapDeviceOwnership();
      _busy = false;
      notifyListeners();
      return true;
    } on TwoFactorRequiredException {
      // The password step keeps its re-post (the UI sends the password again
      // with the code), so a pending token in this answer is not held.
      _passwordTwoFactor = true;
      _error = 'Enter the 6-digit code from your authenticator app.';
      _busy = false;
      notifyListeners();
      return false;
    } on TwoFactorException catch (e) {
      // The password was right and only the code was refused: stay on the
      // code step instead of blaming the password.
      _passwordTwoFactor = true;
      _error = _twoFactorMessage(e.reason);
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = _friendlyError(e, credentialsFlow: true);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Request a one-time sign-in code / magic link by email. Returns true when
  /// the request was accepted (the code/link is then delivered by email).
  Future<bool> loginWithMagicLink(String email) async {
    if (_busy) return false;
    _setBusy(true);
    _error = null;
    // Asking for a fresh link starts over; a code step still open is moot.
    _pendingTwoFactor = null;
    try {
      await _repo.requestMagicLink(email,
          allowRegistration: allowRegistration);
      _busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _friendlyError(e, magicFlow: true);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Verify a magic-link code and complete sign-in. Returns true on success.
  /// For an account with TOTP enabled it returns false with
  /// [hasPendingTwoFactor] set: finish with [completeTwoFactor].
  Future<bool> verifyMagicCode(String email, String code) async {
    if (_busy) return false;
    _setBusy(true);
    _error = null;
    _passwordTwoFactor = false;
    // A code step already open stays until this verify has an answer. The
    // same link can arrive twice (app_links replays a launch link to its
    // first listener) or be tapped again, and if that second request fails
    // the step it would have replaced is still good.
    try {
      final res = await _repo.verifyMagicLogin(email, code);
      _pendingTwoFactor = null;
      _user = res.user;
      _startRefresh();
      _bootstrapDeviceOwnership();
      // One request authorises one sign-in.
      await _repo.clearPendingMagicRequest();
      _busy = false;
      notifyListeners();
      return true;
    } on TwoFactorRequiredException catch (e) {
      // The link proved the mailbox; the account still owes its code. The
      // server leaves the link unspent until the code is right, and the
      // "asked for a link" marker stays too, so an abandoned code step can be
      // restarted by opening the same link again.
      _awaitSecondFactor(e, _TwoFactorOrigin.magicLink);
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      // With a code step still open, that step is what the user finishes; a
      // refused or failed extra link says nothing about it, and an error
      // about the link would only sit under the code field.
      if (_pendingTwoFactor == null) {
        _error = _friendlyError(e, magicFlow: true);
      }
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Finish the pending sign-in with [code]: the 6-digit authenticator code
  /// or a recovery code. Returns true once signed in, which then looks exactly
  /// like a direct success of the method that started it (session stored,
  /// refresh running, device claimed). A wrong code, a lockout or a network
  /// failure keeps the pending sign-in so the user can retry; an expired one
  /// is dropped and the user starts again.
  Future<bool> completeTwoFactor(String code) async {
    if (_busy) return false;
    final pending = _pendingTwoFactor;
    if (pending == null || _isPastDeadline(pending)) {
      // Nothing to send the code with, or the server's window for it has
      // closed: either way the answer is "start again", without a request.
      _pendingTwoFactor = null;
      _error = _twoFactorExpired;
      notifyListeners();
      return false;
    }
    final normalized = _twoFactorCodeOrNull(code);
    if (normalized == null) {
      _error = _twoFactorCodeShape;
      notifyListeners();
      return false;
    }
    _setBusy(true);
    _error = null;
    try {
      final res = await _repo.completeTwoFactor(
          pending.challenge.pendingToken, normalized);
      _pendingTwoFactor = null;
      _user = res.user;
      _startRefresh();
      _bootstrapDeviceOwnership();
      if (pending.origin == _TwoFactorOrigin.magicLink) {
        // One request authorises one sign-in, as on a direct success.
        await _repo.clearPendingMagicRequest();
      }
      _busy = false;
      notifyListeners();
      return true;
    } on TwoFactorException catch (e) {
      if (e.reason == TwoFactorFailure.expired) _pendingTwoFactor = null;
      _error = _twoFactorMessage(e.reason);
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = _friendlyError(e);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Abandon the code step: the user chose to start over, or left the sign-in
  /// screen. A pending token is dropped now rather than left to expire. A
  /// password step ends too, so the next sign-in screen opens on the plain
  /// form: the account typed there has not been asked for a code.
  void cancelTwoFactor() {
    if (_pendingTwoFactor == null && !_passwordTwoFactor && _error == null) {
      return;
    }
    _pendingTwoFactor = null;
    _passwordTwoFactor = false;
    _error = null;
    notifyListeners();
  }

  /// Ends a pending sign-in whose time is up, with the message that says so,
  /// and returns true when it ended one. The code step cannot tell by itself
  /// that its minutes ran out while the app sat behind the lock or in the
  /// background, so whatever is about to put it back on screen asks first.
  bool expireStaleTwoFactor() {
    final pending = _pendingTwoFactor;
    if (pending == null || !_isPastDeadline(pending)) return false;
    _pendingTwoFactor = null;
    _error = _twoFactorExpired;
    notifyListeners();
    return true;
  }

  /// Sign in with Google. Returns true on success. A user cancellation returns
  /// false WITHOUT setting an error (silent). Any real failure — including a
  /// missing native config or a backend audience rejection — sets a clear
  /// [lastError]; it never fakes a session.
  Future<bool> loginWithGoogle() =>
      _socialLogin(_repo.signInWithGoogle, _TwoFactorOrigin.google);

  /// Sign in with Apple. Same contract as [loginWithGoogle].
  Future<bool> loginWithApple() =>
      _socialLogin(_repo.signInWithApple, _TwoFactorOrigin.apple);

  /// Whether this device supports passkey sign-in (gates the passkey button).
  Future<bool> isPasskeyAvailable() => _repo.isPasskeyAvailable();

  /// Number of passkeys registered on the signed-in account (0 if none/unknown).
  Future<int> passkeyCount() => _repo.passkeyCount();

  /// Sign in with a platform passkey. Same contract as [loginWithGoogle]:
  /// true on success, silent false on cancel, clear [lastError] on real failure.
  Future<bool> loginWithPasskey(String email) => _socialLogin(
      () => _repo.signInWithPasskey(email), _TwoFactorOrigin.passkey);

  /// Register a passkey for the signed-in account (biometric setup). Returns
  /// true on success; sets [lastError] and returns false on failure/cancel.
  Future<bool> registerPasskey({String name = 'OrbGuard passkey'}) async {
    if (_busy || !isLoggedIn) return false;
    _setBusy(true);
    _error = null;
    try {
      final ok = await _repo.registerPasskey(name);
      _busy = false;
      notifyListeners();
      return ok;
    } on PasskeyAuthCancelledException {
      // Backing out of the passkey sheet is a choice, not a failure.
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e is AuthenticatorException
          ? _passkeyError(e, adding: true)
          : _friendlyError(e);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// The signed-in account's registered passkeys. Throws on failure (the
  /// management screen distinguishes "none" from "couldn't load").
  Future<List<PasskeyInfo>> listPasskeys() => _repo.listPasskeys();

  /// Rename a passkey. Throws on failure.
  Future<void> renamePasskey(int passkeyId, String name) =>
      _repo.renamePasskey(passkeyId, name);

  /// Delete a passkey. Throws on failure.
  Future<void> deletePasskey(int passkeyId) => _repo.deletePasskey(passkeyId);

  /// Permanently delete the account and ALL its data on OrbNet (irreversible),
  /// then clear local state. Returns true on success; sets [lastError] on
  /// failure. The caller is responsible for the confirmation UX.
  Future<bool> deleteAccount() async {
    if (_busy) return false;
    if (!isLoggedIn) {
      // The session may have died between opening the screen and confirming —
      // set a real error so the UI never replays a stale unrelated one.
      _error = 'Your session has expired. Please sign in again.';
      notifyListeners();
      return false;
    }
    _setBusy(true);
    _error = null;
    try {
      _tokenService.stopProactiveRefresh();
      await _repo.deleteAccount();
      _user = null;
      _passwordTwoFactor = false;
      _pendingTwoFactor = null;
      _busy = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _friendlyError(e);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Shared driver for the social sign-in paths — mirrors [login]'s shape
  /// (busy → repo → set user/session → notify), plus silent cancellation and
  /// the second-factor step a TOTP account owes after the provider sheet.
  Future<bool> _socialLogin(
      Future<AuthResponse> Function() signIn, _TwoFactorOrigin origin) async {
    if (_busy) return false;
    _setBusy(true);
    _error = null;
    _passwordTwoFactor = false;
    _pendingTwoFactor = null;
    try {
      final res = await signIn();
      _user = res.user;
      _startRefresh();
      _bootstrapDeviceOwnership();
      _busy = false;
      notifyListeners();
      return true;
    } on SocialAuthCancelledException {
      // The user backed out of the native sheet — not an error.
      _busy = false;
      notifyListeners();
      return false;
    } on PasskeyAuthCancelledException {
      // Backing out of the passkey sheet is a choice, not a failure.
      _busy = false;
      notifyListeners();
      return false;
    } on TwoFactorRequiredException catch (e) {
      _awaitSecondFactor(e, origin);
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = _friendlyError(e);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Link this device to the just-signed-in OrbNet account so the user can
  /// control it from the web (best-effort, non-blocking, idempotent). No-op if
  /// the device isn't registered yet — the agent re-attempts on next start.
  void _bootstrapDeviceOwnership() {
    // Fire-and-forget: ownership claim must never delay or fail the login.
    unawaited(DeviceClaimService.instance.claimIfReady());
  }

  /// Sign out. Best-effort backend revoke, then always clears local state.
  Future<void> logout() async {
    _tokenService.stopProactiveRefresh();
    try {
      await _repo.logout();
    } catch (e) {
      _log('logout error: $e');
    }
    _user = null;
    _error = null;
    _passwordTwoFactor = false;
    _pendingTwoFactor = null;
    notifyListeners();
  }

  /// Force-refresh the session so a just-completed purchase's new subscription
  /// claims (`subscription_valid` / tier / expiry) are reflected immediately.
  ///
  /// After an IAP is verified, the OrbNet backend writes the shared account
  /// subscription, but THIS device still holds the pre-purchase access token
  /// whose claims say "not subscribed". A token refresh mints a new token that
  /// carries the updated claims, so [hasPremium] / [subscriptionValid] flip to
  /// true without a re-login. Called by the IAP flow right after a confirmed
  /// grant. No-op when logged out; never throws. Returns true when the session
  /// was refreshed.
  Future<bool> refreshEntitlement() async {
    if (!isLoggedIn) return false;
    var refreshed = false;
    try {
      refreshed = await _repo.refreshToken();
    } catch (e) {
      _log('refreshEntitlement failed: $e');
    }
    // Notify regardless: even if the network refresh failed, listeners should
    // re-read whatever the freshest cached claims are.
    notifyListeners();
    return refreshed;
  }

  /// The last email that signed in on this device (to pre-fill the form).
  Future<String?> lastLoggedInEmail() => _repo.getLastLoggedInEmail();

  /// True when this device asked for a magic link recently. The deep-link
  /// handler requires this before auto-consuming a code: an `orbguard://login`
  /// URL is attacker-supplyable, and without the check an unsolicited link
  /// would silently sign the user into the SENDER's account and then claim
  /// this device to it via [_bootstrapDeviceOwnership].
  Future<bool> hasPendingMagicRequest() => _repo.hasPendingMagicRequest();

  /// Clear the current error message (e.g. when the user edits a field).
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---- Internals -----------------------------------------------------------

  static const String _twoFactorExpired =
      'Your sign-in expired. Please start again.';

  static const String _twoFactorCodeShape =
      'Enter the 6-digit code from your authenticator app, or one of your '
      'recovery codes.';

  // One definition of the spaces a typed code may carry, so "blank" in
  // login() and the length check in _twoFactorCodeOrNull() cannot disagree.
  static final RegExp _whitespace = RegExp(r'\s');

  /// [code] as the server reads it, whitespace dropped, or null when no code
  /// is that short or that long. The server drops spaces too, but only after
  /// its length check, so "123 45" would pass that check and spend one of the
  /// few attempts the lockout allows on a code that cannot be right.
  static String? _twoFactorCodeOrNull(String code) {
    final normalized = code.replaceAll(_whitespace, '');
    if (normalized.length < _minTwoFactorCodeLength ||
        normalized.length > _maxTwoFactorCodeLength) {
      return null;
    }
    return normalized;
  }

  bool _isPastDeadline(_PendingTwoFactor pending) =>
      !_now().isBefore(pending.deadline);

  static String _twoFactorMessage(TwoFactorFailure reason) => switch (reason) {
        TwoFactorFailure.invalidCode =>
          'That code is incorrect. Enter the current code from your '
              'authenticator app and try again.',
        TwoFactorFailure.locked =>
          'Too many attempts. Wait a few minutes, then try again.',
        TwoFactorFailure.expired => _twoFactorExpired,
      };

  /// Holds the challenge a first factor earned so the code step can complete
  /// it. Without a pending token there is nothing to send a code with — only
  /// the password re-post can answer such a server — so say that instead of
  /// showing a code field that could never succeed.
  void _awaitSecondFactor(
      TwoFactorRequiredException e, _TwoFactorOrigin origin) {
    final challenge = e.challenge;
    if (challenge == null) {
      // The newest answer about this sign-in wins over a code step still
      // open from an earlier one: showing both would contradict itself.
      _pendingTwoFactor = null;
      _error = 'This account uses two-factor authentication. Choose '
          '"Use password instead" and enter your authenticator code there.';
      return;
    }
    _pendingTwoFactor = _PendingTwoFactor(
        challenge, origin, _now().add(challenge.expiresIn));
    _error = null;
  }

  void _startRefresh() {
    if (_enableProactiveRefresh) _tokenService.startProactiveRefresh();
  }

  /// Triggered by the auth stack only on a CONFIRMED session death (positive
  /// 401/403). Clears local state without a redundant network call.
  void _handleSessionExpired() {
    _tokenService.stopProactiveRefresh();
    _user = null;
    // Fire-and-forget local cleanup; the tokens are already server-invalid.
    _repo.clearLocalSession();
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }

  String _friendlyError(Object e,
      {bool credentialsFlow = false, bool magicFlow = false}) {
    if (net_err.isNetworkError(e)) {
      return 'Network error. Check your connection and try again.';
    }
    if (e is AuthenticationException) {
      // "Incorrect email or password" only makes sense where a password was
      // typed. Everywhere else a 401 means the SESSION died (expired/revoked
      // refresh) — saying "incorrect password" on e.g. delete-account would be
      // nonsense.
      if (credentialsFlow) return 'Incorrect email or password.';
      // In the magic-link flow the user has no session yet, so "your session
      // expired" is both wrong and a dead end — it tells them to do the thing
      // they are already doing. Name the real problem and the way out.
      if (magicFlow) {
        return 'That sign-in code is invalid or has already been used. '
            'Tap Resend link to get a new one.';
      }
      return 'Your session has expired. Please sign in again.';
    }
    if (e is AuthenticatorException) return _passkeyError(e);
    final msg = e.toString().toLowerCase();
    if (msg.contains('exclude') ||
        msg.contains('already registered') ||
        msg.contains('matched an entry')) {
      // The authenticator refused a duplicate (excludeCredentials matched).
      return 'A passkey for this account already exists on this device.';
    }
    if (e is ApiException) {
      return e.message;
    }
    return 'Something went wrong. Please try again.';
  }

  /// What a failed passkey ceremony means for the person, in their words.
  /// The platform reports these before any request reaches the server.
  static String _passkeyError(AuthenticatorException e,
          {bool adding = false}) =>
      switch (e) {
        NoCredentialsAvailableException() =>
          'There is no passkey for this account on this device. '
              'Use email instead.',
        DeviceNotSupportedException() || PasskeyUnsupportedException() =>
          adding
              ? 'This device cannot use passkeys.'
              : 'This device cannot use passkeys. Use email instead.',
        ExcludeCredentialsCanNotBeRegisteredException() =>
          'A passkey for this account already exists on this device.',
        _ when adding => "Couldn't add a passkey. Try again later.",
        _ => "Couldn't sign in with a passkey. Use email instead.",
      };

  void _log(String message) {
    if (kDebugMode) debugPrint('[AccountProvider] $message');
  }

  @override
  void dispose() {
    _tokenService.stopProactiveRefresh();
    super.dispose();
  }
}
