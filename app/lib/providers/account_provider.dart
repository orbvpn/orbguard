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

import '../services/device_agent/device_claim_service.dart';
import '../services/orbnet/auth_repository.dart';
import '../services/orbnet/network_error.dart' as net_err;
import '../services/orbnet/orbnet_api_client.dart';
import '../services/orbnet/social_auth_service.dart';
import '../services/orbnet/token_service.dart';
import '../services/orbnet/models/auth_response.dart';
import '../services/orbnet/models/passkey_info.dart';
import '../services/orbnet/models/subscription_status.dart';
import '../services/orbnet/models/user.dart';

class AccountProvider extends ChangeNotifier {
  late final AuthRepository _repo;
  late final TokenService _tokenService;
  late final bool _enableProactiveRefresh;

  User? _user;
  bool _isInitialized = false;
  bool _busy = false;
  String? _error;
  bool _requiresTwoFactor = false;

  /// [enableProactiveRefresh] can be turned off in tests to avoid background
  /// timers. Inject [authRepository]/[tokenService] for testing.
  AccountProvider({
    AuthRepository? authRepository,
    TokenService? tokenService,
    bool enableProactiveRefresh = true,
  }) {
    _enableProactiveRefresh = enableProactiveRefresh;
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

  /// True when the last login attempt needs a TOTP code.
  bool get requiresTwoFactor => _requiresTwoFactor;

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
  /// [totpCode]. Never wipes an existing session on a network error.
  Future<bool> login(String email, String password, {String? totpCode}) async {
    if (_busy) return false;
    _setBusy(true);
    _error = null;
    _requiresTwoFactor = false;
    try {
      final res = await _repo.login(email, password, totpCode: totpCode);
      _user = res.user;
      _startRefresh();
      _bootstrapDeviceOwnership();
      _busy = false;
      notifyListeners();
      return true;
    } on TwoFactorRequiredException {
      _requiresTwoFactor = true;
      _error = 'Enter the 6-digit code from your authenticator app.';
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

  /// Request a one-time sign-in code / magic link by email. Returns true when
  /// the request was accepted (the code/link is then delivered by email).
  Future<bool> loginWithMagicLink(String email) async {
    if (_busy) return false;
    _setBusy(true);
    _error = null;
    try {
      await _repo.requestMagicLink(email);
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

  /// Verify a magic-link code and complete sign-in. Returns true on success.
  Future<bool> verifyMagicCode(String email, String code) async {
    if (_busy) return false;
    _setBusy(true);
    _error = null;
    try {
      final res = await _repo.verifyMagicLogin(email, code);
      _user = res.user;
      _startRefresh();
      _bootstrapDeviceOwnership();
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

  /// Sign in with Google. Returns true on success. A user cancellation returns
  /// false WITHOUT setting an error (silent). Any real failure — including a
  /// missing native config or a backend audience rejection — sets a clear
  /// [lastError]; it never fakes a session.
  Future<bool> loginWithGoogle() => _socialLogin(_repo.signInWithGoogle);

  /// Sign in with Apple. Same contract as [loginWithGoogle].
  Future<bool> loginWithApple() => _socialLogin(_repo.signInWithApple);

  /// Whether this device supports passkey sign-in (gates the passkey button).
  Future<bool> isPasskeyAvailable() => _repo.isPasskeyAvailable();

  /// Number of passkeys registered on the signed-in account (0 if none/unknown).
  Future<int> passkeyCount() => _repo.passkeyCount();

  /// Sign in with a platform passkey. Same contract as [loginWithGoogle]:
  /// true on success, silent false on cancel, clear [lastError] on real failure.
  Future<bool> loginWithPasskey(String email) =>
      _socialLogin(() => _repo.signInWithPasskey(email));

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
    } catch (e) {
      _error = _friendlyError(e);
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
    if (_busy || !isLoggedIn) return false;
    _setBusy(true);
    _error = null;
    try {
      _tokenService.stopProactiveRefresh();
      await _repo.deleteAccount();
      _user = null;
      _requiresTwoFactor = false;
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
  /// (busy → repo → set user/session → notify), plus silent cancellation.
  Future<bool> _socialLogin(Future<AuthResponse> Function() signIn) async {
    if (_busy) return false;
    _setBusy(true);
    _error = null;
    _requiresTwoFactor = false;
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
    _requiresTwoFactor = false;
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

  /// Clear the current error message (e.g. when the user edits a field).
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---- Internals -----------------------------------------------------------

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

  String _friendlyError(Object e) {
    if (net_err.isNetworkError(e)) {
      return 'Network error. Check your connection and try again.';
    }
    if (e is AuthenticationException) {
      return 'Incorrect email or password.';
    }
    if (e is ApiException) {
      return e.message;
    }
    return 'Something went wrong. Please try again.';
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[AccountProvider] $message');
  }

  @override
  void dispose() {
    _tokenService.stopProactiveRefresh();
    super.dispose();
  }
}
