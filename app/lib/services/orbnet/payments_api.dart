// lib/services/orbnet/payments_api.dart
//
// Client for the shared OrbNet payments backend — specifically IAP receipt
// verification. An OrbGuard in-app purchase is verified here against OrbNet
// (`POST /payments/verify-receipt`), which grants the ONE shared account
// subscription that unlocks BOTH OrbGuard and OrbVPN.
//
// The request always carries `app: 'orbguard'` so the server validates the
// receipt against OrbGuard's store identity (bundle id com.orb.guard / package
// com.orb.guard / OrbGuard shared secret) — never OrbVPN's. Omitting it would
// default the server to 'orbvpn' and reject OrbGuard receipts on a bundle-id
// mismatch, so it is not optional here.

import 'orbnet_api_client.dart';

/// Which app's store identity the server should validate the receipt against.
/// OrbGuard always sends 'orbguard'.
const String kOrbGuardAppId = 'orbguard';

/// Result of verifying an IAP receipt with OrbNet. `valid == true` means the
/// server accepted the receipt and (for a subscription) wrote/refreshed the
/// shared account subscription — the caller should then refresh the session JWT
/// so the new `subscription_valid` claim is picked up.
class VerifyReceiptResult {
  final bool valid;
  final String? productId;
  final String? transactionId;
  final String? message;

  const VerifyReceiptResult({
    required this.valid,
    this.productId,
    this.transactionId,
    this.message,
  });

  factory VerifyReceiptResult.fromMap(Map<String, dynamic> map) {
    return VerifyReceiptResult(
      valid: map['valid'] as bool? ?? false,
      productId: map['product_id'] as String?,
      transactionId: map['transaction_id'] as String?,
      message: map['message'] as String?,
    );
  }
}

/// Payments endpoints on the OrbNet backend (`api.orbai.world/api/v1`).
class PaymentsApi {
  final OrbNetApiClient _client;

  PaymentsApi({OrbNetApiClient? client})
      : _client = client ?? OrbNetApiClient.instance;

  /// Verify a store receipt / purchase token with OrbNet.
  ///
  /// [platform] is 'ios' or 'android'. [receiptData] is the StoreKit receipt /
  /// JWS transaction (iOS) or the Play purchase token (Android). [productId] is
  /// the store product id (e.g. `orbguard_premium_monthly`). Requires a
  /// signed-in session (the endpoint is auth-gated); the OrbNet client injects
  /// the bearer token automatically.
  ///
  /// Throws [ApiException]/[NetworkException] on transport or server errors so
  /// the caller can leave the store transaction UNFINISHED and retry later —
  /// never silently swallow a failure (that would risk paid-but-not-delivered).
  Future<VerifyReceiptResult> verifyReceipt({
    required String platform,
    required String receiptData,
    required String productId,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/payments/verify-receipt',
      data: {
        'platform': platform,
        'receipt_data': receiptData,
        'product_id': productId,
        'app': kOrbGuardAppId,
      },
    );
    return VerifyReceiptResult.fromMap(_unwrap(res));
  }

  /// The Go backend wraps some payloads in `{success, data:{...}}`.
  Map<String, dynamic> _unwrap(Map<String, dynamic> res) {
    final data = res['data'];
    return data is Map<String, dynamic> ? data : res;
  }
}
