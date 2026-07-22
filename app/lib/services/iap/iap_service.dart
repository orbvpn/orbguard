// lib/services/iap/iap_service.dart
//
// OrbGuard in-app purchases (auto-renewable subscriptions) for iOS App Store and
// Google Play. OrbGuard sells the SAME account subscription as OrbVPN: a verified
// purchase here grants the ONE shared OrbNet account subscription, which unlocks
// both apps. So this service does exactly three things and nothing more:
//   1. load the store's ProductDetails for the 6 orbguard_* subscription ids
//      (so the paywall shows the store's real, localized prices — never a
//      hardcoded number);
//   2. start a purchase and listen to the store's purchase stream;
//   3. on a completed/restored purchase, verify the receipt with OrbNet
//      (app: 'orbguard'), refresh the session so the new entitlement claim is
//      picked up, and ONLY THEN tell the store the transaction is finished.
//
// The critical money-safety rule (ported from OrbVPN's proven flow): a NEW
// purchase is finished with the store ONLY after the backend confirms the grant.
// If verification fails or errors, the transaction is left UNFINISHED so the
// store re-delivers it on the next launch and we retry — never "charged but not
// delivered".

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../orbnet/orbnet_api_client.dart';
import '../orbnet/payments_api.dart';

/// The 6 OrbGuard subscription product ids (3 tiers × monthly/yearly). These
/// must exactly match App Store Connect and Google Play Console. The server maps
/// each onto the shared OrbVPN plan (orbguard_basic → orb_basic, premium →
/// premium, ultimate → family).
class OrbGuardProductIds {
  static const String basicMonthly = 'orbguard_basic_monthly';
  static const String basicYearly = 'orbguard_basic_yearly';
  static const String premiumMonthly = 'orbguard_premium_monthly';
  static const String premiumYearly = 'orbguard_premium_yearly';
  static const String ultimateMonthly = 'orbguard_ultimate_monthly';
  static const String ultimateYearly = 'orbguard_ultimate_yearly';

  /// Every subscription product id, queried from the store on init.
  static const Set<String> all = {
    basicMonthly,
    basicYearly,
    premiumMonthly,
    premiumYearly,
    ultimateMonthly,
    ultimateYearly,
  };
}

/// The outcome of a single purchase attempt, surfaced as a one-shot event so the
/// paywall can show a snackbar/sheet without polling.
enum IapOutcome { success, failed, canceled, pending }

/// A one-shot purchase result event.
class IapResult {
  final IapOutcome outcome;
  final String productId;
  final String? message;
  const IapResult(this.outcome, this.productId, {this.message});

  bool get isSuccess => outcome == IapOutcome.success;
}

/// Signature of the hook that refreshes the account session after a confirmed
/// grant (wired to AccountProvider.refreshEntitlement). Returns true when the
/// session was refreshed.
typedef EntitlementRefresh = Future<bool> Function();

/// Signature of the guard that reports whether a user is signed in. Verification
/// is auth-gated, so we must not start a purchase without a session.
typedef LoggedInProbe = bool Function();

/// Singleton IAP service. `ChangeNotifier` so the paywall can rebuild on
/// product-load / purchasing-state changes; [results] is a broadcast stream for
/// transient success/error feedback.
class IapService extends ChangeNotifier {
  IapService._();
  static final IapService instance = IapService._();

  // Lazy so merely constructing the singleton never touches the platform
  // channel (on Android, resolving InAppPurchase.instance kicks off a billing
  // connection). Only initialize()/buy()/restore() need the real store, and
  // widget tests that debugSeed() never reach them. Tests may inject a fake.
  InAppPurchase? _iapOverride;
  InAppPurchase get _iap => _iapOverride ?? InAppPurchase.instance;
  final PaymentsApi _payments = PaymentsApi();

  EntitlementRefresh? _onEntitlementRefresh;
  LoggedInProbe? _isLoggedIn;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  final StreamController<IapResult> _results =
      StreamController<IapResult>.broadcast();

  bool _available = false;
  bool _initialized = false;
  bool _loadingProducts = false;
  String? _purchasingProductId;
  bool _restoring = false;
  bool _restoreDelivered = false;
  final Map<String, ProductDetails> _productsById = {};

  /// Purchases whose backend verification failed TRANSIENTLY (left unfinished
  /// with the store). Kept so this session can retry them — on paywall open and
  /// before a re-buy of the same product (a fresh buyNonConsumable for a product
  /// with an unfinished transaction throws duplicate-transaction on iOS).
  final Map<String, PurchaseDetails> _unverified = {};

  // ---- Wiring --------------------------------------------------------------

  /// Register the session-refresh hook + login probe. Call once at startup
  /// before [initialize] (or any time before the first purchase).
  void configure({
    required EntitlementRefresh onEntitlementRefresh,
    required LoggedInProbe isLoggedIn,
  }) {
    _onEntitlementRefresh = onEntitlementRefresh;
    _isLoggedIn = isLoggedIn;
  }

  // ---- State getters -------------------------------------------------------

  /// Whether the store is reachable (false on unsupported platforms / no store).
  bool get isAvailable => _available;

  /// Whether product details are currently being (re)loaded.
  bool get isLoadingProducts => _loadingProducts;

  /// Loaded products keyed by product id (empty until [initialize] resolves).
  Map<String, ProductDetails> get productsById =>
      Map.unmodifiable(_productsById);

  /// The product id currently mid-purchase, or null when idle.
  String? get purchasingProductId => _purchasingProductId;

  /// Whether any purchase is in flight.
  bool get isBusy => _purchasingProductId != null || _restoring;

  /// One-shot purchase results (success / failure / cancel), for snackbars.
  Stream<IapResult> get results => _results.stream;

  ProductDetails? productFor(String id) => _productsById[id];

  // ---- Lifecycle -----------------------------------------------------------

  /// Connect to the store, start listening to the purchase stream, and load the
  /// subscription product details. Idempotent and non-throwing. Safe to call at
  /// app startup; the purchase stream immediately replays any purchase left
  /// unfinished on a previous run, which we then verify + finish.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _connect();
    if (!_available) return;

    await loadProducts();

    // Android crash recovery: the Play plugin only re-delivers past purchases
    // through a restore (its purchase stream carries new purchase updates, not
    // a startup replay). An unacknowledged purchase (app killed after paying,
    // before verify) would otherwise sit until Google auto-refunds it (~3 days)
    // unless the user manually taps Restore. A silent restore surfaces it into
    // the normal verify path; the backend is idempotent for already-granted
    // subs. iOS/macOS genuinely replay via the stream, so this is Android-only.
    if (Platform.isAndroid && (_isLoggedIn?.call() ?? false)) {
      try {
        await _iap.restorePurchases();
      } catch (e) {
        _log('startup Android purchase replay failed: $e');
      }
    }
  }

  /// Probe store availability and (once available) subscribe to the purchase
  /// stream. Separate from [initialize] so a failed first probe (offline at
  /// launch) can be retried later — [loadProducts] re-runs it, which is what
  /// makes the paywall's "Try again" actually able to recover.
  Future<void> _connect() async {
    try {
      _available = await _iap.isAvailable();
    } catch (e) {
      _available = false;
      _log('isAvailable failed: $e');
    }

    if (!_available) {
      notifyListeners();
      return;
    }

    // Listen BEFORE querying so replayed past purchases are not missed.
    _sub ??= _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) => _log('purchaseStream error: $e'),
    );
  }

  /// (Re)load the store's ProductDetails for all subscription ids. Also
  /// re-probes a previously-unavailable store (retry path) and retries any
  /// purchase whose verification failed transiently earlier this session.
  Future<void> loadProducts() async {
    if (!_available) {
      await _connect();
      if (!_available) return;
    }
    _loadingProducts = true;
    notifyListeners();
    try {
      final resp = await _iap.queryProductDetails(OrbGuardProductIds.all);
      if (resp.error != null) {
        _log('queryProductDetails error: ${resp.error}');
      }
      if (resp.notFoundIDs.isNotEmpty) {
        _log('product ids not found in store: ${resp.notFoundIDs}');
      }
      _productsById
        ..clear()
        ..addEntries(resp.productDetails.map((p) => MapEntry(p.id, p)));
    } catch (e) {
      _log('loadProducts failed: $e');
    } finally {
      _loadingProducts = false;
      notifyListeners();
    }

    // Opening the paywall is a natural retry point for purchases whose verify
    // failed transiently (network blip): finish delivering what was paid for.
    await retryUnverified();
  }

  /// Re-verify purchases whose backend verification failed TRANSIENTLY earlier
  /// in this session (they are still unfinished with the store). Called when
  /// the paywall opens and before re-buying the same product; safe to call any
  /// time — no-op when there is nothing to retry or while another purchase is
  /// being processed.
  Future<void> retryUnverified() async {
    if (_unverified.isEmpty || isBusy) return;
    for (final id in List<String>.from(_unverified.keys)) {
      await retryUnverifiedProduct(id);
    }
  }

  /// Re-verify one product's unfinished purchase (no busy guard — [buy] calls
  /// this while holding the purchasing latch for that same product).
  Future<void> retryUnverifiedProduct(String productId) async {
    final purchase = _unverified[productId];
    if (purchase == null) return;
    final finish = await _verifyAndGrant(purchase);
    if (finish && purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
      } catch (e) {
        _log('completePurchase (retry) failed for ${purchase.productID}: $e');
      }
    }
  }

  // ---- Purchase ------------------------------------------------------------

  /// Start a subscription purchase for [productId]. Returns false immediately if
  /// the store is unavailable, the product is unknown, the user is not signed in
  /// (verification is auth-gated), or a purchase is already in flight. The real
  /// outcome arrives asynchronously via [results] / [purchasingProductId].
  Future<bool> buy(String productId) async {
    if (!_available) {
      _emit(IapOutcome.failed, productId,
          message: 'The store is unavailable right now.');
      return false;
    }
    if (isBusy) return false;
    if (_isLoggedIn != null && !_isLoggedIn!()) {
      _emit(IapOutcome.failed, productId,
          message: 'Please sign in before subscribing.');
      return false;
    }
    final product = _productsById[productId];
    if (product == null) {
      _emit(IapOutcome.failed, productId,
          message: 'This plan is not available right now.');
      return false;
    }

    // Already paid but not yet activated (a transient verify failure left the
    // transaction unfinished)? Retry the ACTIVATION, not the purchase — a fresh
    // buyNonConsumable would throw duplicate-transaction on iOS and could
    // double-charge on Android.
    if (_unverified.containsKey(productId)) {
      _purchasingProductId = productId;
      notifyListeners();
      try {
        await retryUnverifiedProduct(productId);
      } finally {
        _clearPurchasing(productId);
      }
      return true;
    }

    _purchasingProductId = productId;
    notifyListeners();

    try {
      final param = PurchaseParam(productDetails: product);
      // Auto-renewable subscriptions are "non-consumable" in the plugin's model.
      final started = await _iap.buyNonConsumable(purchaseParam: param);
      if (!started) {
        _purchasingProductId = null;
        notifyListeners();
        _emit(IapOutcome.failed, productId,
            message: 'Could not start the purchase.');
        return false;
      }
      return true;
    } catch (e) {
      _purchasingProductId = null;
      notifyListeners();
      _emit(IapOutcome.failed, productId, message: _friendly(e));
      return false;
    }
  }

  /// Restore previously-bought subscriptions (App Store requires a visible
  /// "Restore" action). Restored purchases flow through the same verify path.
  Future<void> restore() async {
    if (!_available || isBusy) return;
    _restoring = true;
    _restoreDelivered = false;
    notifyListeners();
    try {
      await _iap.restorePurchases();
      // Restored events arrive on the purchase stream shortly AFTER the call
      // returns. Wait briefly; if nothing came, say so — silence would leave
      // the user staring at a button that appears to do nothing.
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!_restoreDelivered) {
        _emit(IapOutcome.failed, '',
            message: 'No previous purchases found for this store account.');
      }
    } catch (e) {
      _log('restore failed: $e');
      _emit(IapOutcome.failed, '', message: _friendly(e));
    } finally {
      _restoring = false;
      notifyListeners();
    }
  }

  // ---- Purchase stream handling -------------------------------------------

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      // Whether it's safe to finish (acknowledge/consume) the transaction. For a
      // NEW purchase this stays false until the backend confirms the grant, so a
      // failed verify leaves it pending for retry rather than losing the money.
      var finish = false;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          // The purchase is now the store's to settle (e.g. Ask-to-Buy / SCA).
          // Release the busy latch so a never-resolving pending doesn't block the
          // paywall for the rest of the session — the stream still delivers the
          // eventual purchased/canceled update, which we verify + finish then.
          _clearPurchasing(purchase.productID);
          _emit(IapOutcome.pending, purchase.productID);
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.status == PurchaseStatus.restored) {
            _restoreDelivered = true;
          }
          finish = await _verifyAndGrant(purchase);
          break;

        case PurchaseStatus.error:
          finish = true; // terminal — clear it from the store queue
          _clearPurchasing(purchase.productID);
          _emit(IapOutcome.failed, purchase.productID,
              message: purchase.error?.message ?? 'The purchase failed.');
          break;

        case PurchaseStatus.canceled:
          finish = true; // terminal
          _clearPurchasing(purchase.productID);
          _emit(IapOutcome.canceled, purchase.productID);
          break;
      }

      if (purchase.pendingCompletePurchase && finish) {
        try {
          await _iap.completePurchase(purchase);
        } catch (e) {
          _log('completePurchase failed for ${purchase.productID}: $e');
        }
      }
    }
  }

  /// Verify a purchased/restored transaction with OrbNet and, on success,
  /// refresh the session. Returns true when it is safe to finish the transaction
  /// (backend granted entitlement), false to leave it pending for retry.
  Future<bool> _verifyAndGrant(PurchaseDetails purchase) async {
    // A verify call needs a signed-in session. If somehow signed out, keep the
    // transaction pending — it will replay and verify once the user signs in.
    if (_isLoggedIn != null && !_isLoggedIn!()) {
      _log('purchased while signed out; leaving pending for retry');
      // Keep it for in-session retry: once the user signs in and the paywall
      // reopens (retryUnverified), activation completes without a relaunch.
      _unverified[purchase.productID] = purchase;
      _clearPurchasing(purchase.productID);
      _emit(IapOutcome.failed, purchase.productID,
          message: 'Sign in to finish activating your subscription.');
      return false;
    }

    try {
      // Android is the only Play platform; everything else (iOS, macOS) is
      // StoreKit and must be verified as 'ios' against Apple.
      final platform = Platform.isAndroid ? 'android' : 'ios';
      final receiptData = _receiptFor(purchase);

      final result = await _payments.verifyReceipt(
        platform: platform,
        receiptData: receiptData,
        productId: purchase.productID,
      );

      if (!result.valid) {
        // The server positively rejected the receipt. This is terminal for THIS
        // receipt (retrying won't help), so finish it to clear the queue, but
        // surface the failure.
        _unverified.remove(purchase.productID);
        _clearPurchasing(purchase.productID);
        _emit(IapOutcome.failed, purchase.productID,
            message: result.message ?? 'We could not verify this purchase.');
        return true;
      }

      // Granted. Refresh the session so subscription claims flip to active.
      try {
        await _onEntitlementRefresh?.call();
      } catch (e) {
        _log('entitlement refresh after grant failed: $e');
      }

      _unverified.remove(purchase.productID);
      _clearPurchasing(purchase.productID);
      _emit(IapOutcome.success, purchase.productID);
      return true;
    } catch (e) {
      _clearPurchasing(purchase.productID);
      // Distinguish a TERMINAL client rejection (a 4xx: product mismatch, already
      // claimed by another account, validation) from a TRANSIENT failure (no server
      // verdict — network/timeout — or a 5xx / auth-expired). Retrying a terminal
      // rejection is futile and would re-verify + re-error on every launch forever,
      // so finish it to clear the store queue. A transient failure is left UNFINISHED
      // so the store re-delivers and we retry — never charge-without-grant.
      if (_isTerminalVerifyError(e)) {
        _log('verify terminally rejected (finishing to clear queue): $e');
        _unverified.remove(purchase.productID);
        _emit(IapOutcome.failed, purchase.productID, message: _friendly(e));
        return true;
      }
      // Remember it so THIS session can retry (paywall open / tapping the plan
      // again) — the launch-time stream replay only covers the next run.
      _unverified[purchase.productID] = purchase;
      _log('verify errored transiently (leaving pending for retry): $e');
      _emit(IapOutcome.failed, purchase.productID,
          message:
              'Purchase received — activating it failed, we\'ll retry automatically.');
      return false;
    }
  }

  /// Whether a verify exception is a terminal client rejection (safe to finish the
  /// transaction) vs a transient failure (leave pending and retry). Only a positive
  /// 4xx server verdict is terminal; no-response (network/timeout), 5xx, and 401
  /// (needs re-auth) are all retry-able.
  bool _isTerminalVerifyError(Object e) {
    if (e is NetworkException) return false; // no server verdict — retry
    if (e is ServerException) return false; // 5xx — retry
    if (e is AuthenticationException) return false; // 401 — retry after re-auth
    if (e is ApiException) return true; // other 4xx — positive rejection, terminal
    return false; // unknown — be conservative, keep the money safe and retry
  }

  /// The receipt/token to send to the backend.
  ///  • iOS: the StoreKit receipt / JWS transaction (serverVerificationData).
  ///  • Android: the Play purchase token (the reliable source is the typed
  ///    GooglePlayPurchaseDetails; fall back to serverVerificationData).
  String _receiptFor(PurchaseDetails purchase) {
    if (Platform.isAndroid && purchase is GooglePlayPurchaseDetails) {
      return purchase.billingClientPurchase.purchaseToken;
    }
    return purchase.verificationData.serverVerificationData;
  }

  // ---- Helpers -------------------------------------------------------------

  void _clearPurchasing(String productId) {
    if (_purchasingProductId == productId || productId.isEmpty) {
      _purchasingProductId = null;
      notifyListeners();
    }
  }

  void _emit(IapOutcome outcome, String productId, {String? message}) {
    if (!_results.isClosed) {
      _results.add(IapResult(outcome, productId, message: message));
    }
  }

  String _friendly(Object e) {
    if (e is NetworkException) {
      return 'Network error. Check your connection and try again.';
    }
    if (e is ApiException) return e.message;
    return 'Something went wrong with the purchase. Please try again.';
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[IapService] $message');
  }

  // ---- Testing seam --------------------------------------------------------

  /// Seed availability + product details without touching the real store, for
  /// widget/unit tests. Marks the service initialized so [initialize] no-ops.
  @visibleForTesting
  void debugSeed({
    required bool available,
    List<ProductDetails> products = const [],
    InAppPurchase? platform,
  }) {
    if (platform != null) _iapOverride = platform;
    _available = available;
    _initialized = true;
    _loadingProducts = false;
    _productsById
      ..clear()
      ..addEntries(products.map((p) => MapEntry(p.id, p)));
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    _results.close();
    super.dispose();
  }
}
