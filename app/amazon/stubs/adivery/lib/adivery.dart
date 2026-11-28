// Amazon Appstore build only. The part of the plugin's API that
// lib/services/ads/rewarded_ad_service.dart calls, with the same
// signatures. Nothing here reaches a platform channel and no listener is
// ever called. The Amazon build never calls it anyway (kAmazonBuild).
library;

typedef EmptyFunction = void Function(String placement);
typedef ErrorFunction = void Function(String placement, String reason);
typedef RewardFunction = void Function(String placement, bool isRewarded);

class AdiveryPlugin {
  static void addListener({
    EmptyFunction? onRewardedLoaded,
    RewardFunction? onRewardedClosed,
    ErrorFunction? onError,
  }) {}

  static void initialize(String appId) {}

  static void prepareRewardedAd(String placementId) {}

  static void show(String placement) {}
}
