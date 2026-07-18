// lib/services/orbnet/models/ad_models.dart
//
// DTOs for the rewarded-ad → scan-credit flow (Phase A3). Adapted from OrbX's
// `data/models/ad.dart`, trimmed to the fields OrbGuard needs and re-pointed at
// the SCAN-CREDIT reward pool (reward_type = "scan_credits") instead of VPN time.

/// Ad-network identifiers accepted by the backend `/ad/session` endpoint and
/// used to order the client-side waterfall.
class AdProviderId {
  AdProviderId._();
  static const String unityAds = 'unity_ads';
  static const String adivery = 'adivery';
  static const String yandex = 'yandex';
}

/// A rewarded-ad session opened by `POST /ad/session`. Carries the [token] that
/// `POST /ad/verify` later exchanges for the scan-credit reward.
class AdSession {
  final int id;
  final String token;
  final String provider;
  final String adType;
  final String rewardType;
  final num rewardAmount;
  final DateTime? expiresAt;

  const AdSession({
    required this.id,
    required this.token,
    required this.provider,
    this.adType = 'rewarded',
    this.rewardType = 'scan_credits',
    this.rewardAmount = 0,
    this.expiresAt,
  });

  factory AdSession.fromJson(Map<String, dynamic> json) {
    return AdSession(
      id: (json['id'] as num).toInt(),
      token: json['token'] as String,
      provider: json['provider'] as String? ?? '',
      adType: json['ad_type'] as String? ?? 'rewarded',
      rewardType: json['reward_type'] as String? ?? 'scan_credits',
      rewardAmount: (json['reward_amount'] as num?) ?? 0,
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'] as String)
          : null,
    );
  }

  bool get isExpired {
    final e = expiresAt;
    return e != null && DateTime.now().isAfter(e);
  }
}

/// The result of `POST /ad/verify`: the reward that landed in the scan-credit
/// pool. A view only counts once [success] is true — the client never
/// fabricates a reward locally.
class AdRewardResponse {
  final bool success;
  final String rewardType;
  final double scanCreditsEarned;
  final double? newScanCreditBalance;
  final String? provider;

  const AdRewardResponse({
    required this.success,
    this.rewardType = 'scan_credits',
    this.scanCreditsEarned = 0,
    this.newScanCreditBalance,
    this.provider,
  });

  factory AdRewardResponse.fromJson(Map<String, dynamic> json) {
    final reward = json['reward'] as Map<String, dynamic>?;
    return AdRewardResponse(
      success: json['success'] as bool? ?? false,
      rewardType: json['reward_type'] as String? ?? 'scan_credits',
      scanCreditsEarned:
          (reward?['scan_credits_earned'] as num?)?.toDouble() ?? 0,
      newScanCreditBalance:
          (reward?['new_scan_credit_balance'] as num?)?.toDouble(),
      provider: reward?['provider'] as String?,
    );
  }
}
