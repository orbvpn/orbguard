// lib/providers/scan_credit_provider.dart
//
// Scan-credit state for the account: the balance a device scan spends (one per
// scan) plus the "watch a rewarded ad to earn one" loop. Mirrors how OrbX earns
// VPN credits, re-pointed at the scan-credit pool.
//
// HONESTY: a credit only lands after a REAL ad view is confirmed by the backend
// (`/ad/verify` success). A skipped/failed ad, an unconfigured build, or a
// logged-out user each produce a clear error and NO credit — never a fake one.
//
// The APIs + ad service are injected for testability; the login probe reads the
// shared OrbNet account state (scan credits require an account).

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../services/ads/rewarded_ad_service.dart';
import '../services/orbnet/ad_api.dart';
import '../services/orbnet/network_error.dart' as net_err;
import '../services/orbnet/orbnet_api_client.dart';
import '../services/orbnet/scan_credit_api.dart';

/// Outcome of [ScanCreditProvider.spendForScan] — enough for the caller (the
/// scan gate) to tell success from "out of credits" from a real error.
class ConsumeResult {
  /// A credit was spent; [balance] is the new balance.
  final bool success;

  /// The balance couldn't cover the scan (HTTP 402) — prompt a rewarded ad.
  final bool outOfCredits;

  /// The scan-credit balance after the attempt (unchanged unless [success]).
  final double balance;

  /// A user-legible error when the attempt failed for a reason other than an
  /// empty balance (offline, not signed in, server error).
  final String? error;

  const ConsumeResult._({
    required this.success,
    required this.outOfCredits,
    required this.balance,
    this.error,
  });

  factory ConsumeResult.spent(double balance) =>
      ConsumeResult._(success: true, outOfCredits: false, balance: balance);

  factory ConsumeResult.empty(double balance) =>
      ConsumeResult._(success: false, outOfCredits: true, balance: balance);

  factory ConsumeResult.failed(String error, double balance) => ConsumeResult._(
      success: false, outOfCredits: false, balance: balance, error: error);
}

class ScanCreditProvider extends ChangeNotifier {
  final AdApi _adApi;
  final ScanCreditApi _scanCreditApi;
  final RewardedAdService _adService;
  final bool Function() _isLoggedIn;
  final String? Function()? _deviceId;

  double _balance = 0;
  bool _loading = false;
  bool _watching = false;
  String? _lastError;

  ScanCreditProvider({
    required AdApi adApi,
    required ScanCreditApi scanCreditApi,
    required RewardedAdService adService,
    required bool Function() isLoggedIn,
    String? Function()? deviceId,
  })  : _adApi = adApi,
        _scanCreditApi = scanCreditApi,
        _adService = adService,
        _isLoggedIn = isLoggedIn,
        _deviceId = deviceId;

  // ── State ───────────────────────────────────────────────────────────────────
  double get balance => _balance;
  bool get loading => _loading;
  bool get isWatchingAd => _watching;
  String? get lastError => _lastError;

  /// Whether a rewarded-ad network is configured for this build. When false the
  /// UI must show an honest "ads unavailable" state, never an earn button that
  /// silently no-ops.
  bool get adsAvailable => _adService.anyNetworkConfigured;

  // ── Balance ──────────────────────────────────────────────────────────────────

  /// Refresh the balance from `GET /scan-credits/balance`. Logged-out users have
  /// no scan-credit pool, so the balance is simply 0.
  Future<void> refresh() async {
    if (!_isLoggedIn()) {
      _balance = 0;
      _lastError = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _lastError = null;
    notifyListeners();
    try {
      _balance = await _scanCreditApi.getBalance();
    } catch (e) {
      _lastError = _friendly(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── Earn: watch a rewarded ad ─────────────────────────────────────────────────

  /// Full earn loop: open a scan-credit ad session → show a REAL rewarded ad →
  /// verify with the backend → adopt the new balance. Returns true only when a
  /// credit was actually earned. Any failure sets [lastError] and credits
  /// nothing. [context] is accepted for the calling UI / future prompts (ATT).
  Future<bool> watchAdForCredit(BuildContext context) async {
    if (_watching) return false;
    _lastError = null;

    // Scan credits are account-scoped — require a signed-in OrbNet account.
    if (!_isLoggedIn()) {
      _lastError = 'Sign in to earn and use scan credits.';
      notifyListeners();
      return false;
    }
    // Never present an earn flow we can't honour.
    if (!_adService.anyNetworkConfigured) {
      _lastError = "Rewarded ads aren't available yet.";
      notifyListeners();
      return false;
    }

    _watching = true;
    notifyListeners();
    try {
      // Guarded above: anyNetworkConfigured ⇒ preferredProvider is non-null.
      final provider = _adService.preferredProvider!;
      final session = await _adApi.startScanAdSession(
        provider: provider,
        platform: _platform,
        deviceId: _deviceId?.call(),
      );

      final rewarded = await _adService.showRewardedAd();
      if (!rewarded) {
        _lastError = "The ad didn't finish, so no credit was earned. Try again.";
        return false;
      }

      final reward = await _adApi.verifyScanAd(
        sessionId: session.id,
        token: session.token,
      );
      if (!reward.success) {
        _lastError = "We couldn't confirm that reward. Please try again.";
        return false;
      }

      // Adopt the server's authoritative balance, then confirm from source.
      final serverBalance = reward.newScanCreditBalance;
      if (serverBalance != null) _balance = serverBalance;
      await _refreshQuietly();
      return true;
    } on AdsNotConfiguredException {
      _lastError = "Rewarded ads aren't available yet.";
      return false;
    } catch (e) {
      _lastError = _friendly(e);
      return false;
    } finally {
      _watching = false;
      notifyListeners();
    }
  }

  // ── Spend: consume a credit for a scan ─────────────────────────────────────────

  /// Spend one scan credit via `POST /scan/consume`. The scan gate reads the
  /// [ConsumeResult] to decide: proceed (spent), prompt an ad (outOfCredits), or
  /// surface an error.
  Future<ConsumeResult> spendForScan() async {
    if (!_isLoggedIn()) {
      return ConsumeResult.failed('Sign in to use scan credits.', _balance);
    }
    try {
      final newBalance = await _scanCreditApi.consume(amount: 1);
      _balance = newBalance;
      notifyListeners();
      return ConsumeResult.spent(newBalance);
    } on InsufficientScanCreditsException {
      // Out of credits — the caller should offer a rewarded ad.
      return ConsumeResult.empty(_balance);
    } catch (e) {
      final msg = _friendly(e);
      _lastError = msg;
      notifyListeners();
      return ConsumeResult.failed(msg, _balance);
    }
  }

  // ── Internals ──────────────────────────────────────────────────────────────────

  String get _platform => Platform.isIOS ? 'ios' : 'android';

  Future<void> _refreshQuietly() async {
    try {
      _balance = await _scanCreditApi.getBalance();
    } catch (_) {
      // The credit already landed server-side; a failed re-read must not turn a
      // successful earn into an error. Keep the optimistic balance.
    }
  }

  String _friendly(Object e) {
    if (net_err.isNetworkError(e)) {
      return 'Network error. Check your connection and try again.';
    }
    if (e is AuthenticationException) {
      return 'Please sign in again to continue.';
    }
    if (e is ApiException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
