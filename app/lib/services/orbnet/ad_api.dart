// lib/services/orbnet/ad_api.dart
//
// Slim client for the OrbNet rewarded-ad endpoints, routed to the SCAN-CREDIT
// pool. Adapted from OrbX's `data/api/rest/ad_api.dart`; the VPN-time coupling
// is dropped and every session carries reward_type = "scan_credits" so the
// backend credits scans (not VPN seconds). Uses the shared [OrbNetApiClient],
// which attaches the OrbNet JWT bearer automatically.

import 'models/ad_models.dart';
import 'orbnet_api_client.dart';

class AdApi {
  final OrbNetApiClient _client;

  AdApi({OrbNetApiClient? client})
      : _client = client ?? OrbNetApiClient.instance;

  /// Open a rewarded-ad session for scan credits. [provider] is the network the
  /// client intends to show (`unity_ads` | `adivery` | `yandex`); [platform] is
  /// `android` | `ios`. Returns the [AdSession] with the verification token.
  Future<AdSession> startScanAdSession({
    required String provider,
    required String platform,
    String? deviceId,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/ad/session',
      data: {
        'provider': provider,
        'ad_type': 'rewarded',
        'platform': platform,
        if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
        // Routes the reward to the scan-credit pool (NOT VPN time).
        'reward_type': 'scan_credits',
      },
    );
    return AdSession.fromJson(_unwrap(res));
  }

  /// Verify a completed rewarded view and claim the scan-credit reward.
  Future<AdRewardResponse> verifyScanAd({
    required int sessionId,
    required String token,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/ad/verify',
      data: {'session_id': sessionId, 'token': token},
    );
    return AdRewardResponse.fromJson(_unwrap(res));
  }

  /// The Go backend sometimes wraps payloads in `{success, data:{...}}`.
  Map<String, dynamic> _unwrap(Map<String, dynamic> res) {
    final data = res['data'];
    return data is Map<String, dynamic> ? data : res;
  }
}
