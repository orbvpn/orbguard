// lib/services/orbnet/scan_credit_api.dart
//
// Client for the scan-credit balance + consumption endpoints. Scan credits are
// the account-scoped currency a device scan spends (one per scan); they are
// topped up by watching rewarded ads (see [AdApi]). A `POST /scan/consume` the
// balance can't cover comes back as HTTP 402 — surfaced here as a typed
// [InsufficientScanCreditsException] ("out of credits, go watch an ad").

import 'orbnet_api_client.dart';

/// Thrown by [ScanCreditApi.consume] when the account has no scan credit left to
/// spend (backend replies HTTP 402). The signal to prompt a rewarded ad.
class InsufficientScanCreditsException implements Exception {
  final String message;
  InsufficientScanCreditsException(
      [this.message = 'Out of scan credits. Watch an ad to earn one.']);
  @override
  String toString() => message;
}

class ScanCreditApi {
  final OrbNetApiClient _client;

  ScanCreditApi({OrbNetApiClient? client})
      : _client = client ?? OrbNetApiClient.instance;

  /// Current scan-credit balance from `GET /scan-credits/balance`.
  Future<double> getBalance() async {
    final res =
        await _client.get<Map<String, dynamic>>('/scan-credits/balance');
    final data = _unwrap(res);
    return (data['scan_credits'] as num?)?.toDouble() ?? 0;
  }

  /// Spend [amount] (default 1) scan credit via `POST /scan/consume`. Returns the
  /// new balance. Throws [InsufficientScanCreditsException] on HTTP 402 when the
  /// balance can't cover the spend.
  Future<double> consume({int amount = 1}) async {
    try {
      final res = await _client.post<Map<String, dynamic>>(
        '/scan/consume',
        data: {'amount': amount},
      );
      final data = _unwrap(res);
      final balance = (data['scan_credits'] as num?)?.toDouble();
      if (balance == null) {
        throw ApiException('Malformed /scan/consume response');
      }
      return balance;
    } on PaymentRequiredException {
      throw InsufficientScanCreditsException();
    }
  }

  /// The Go backend sometimes wraps payloads in `{success, data:{...}}`.
  Map<String, dynamic> _unwrap(Map<String, dynamic> res) {
    final data = res['data'];
    return data is Map<String, dynamic> ? data : res;
  }
}
