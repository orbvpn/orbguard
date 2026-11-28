// Amazon Appstore build only. The part of the plugin's API that
// lib/services/ads/rewarded_ad_service.dart calls, with the same
// signatures. Nothing here reaches a platform channel: a load always
// reports that nothing came, so no ad is shown and no reward is given. The
// Amazon build never calls it anyway (kAmazonBuild).
library;

class MobileAds {
  MobileAds._();

  static Future<void> initialize() async {}
}

class AdRequestConfiguration {
  const AdRequestConfiguration({required this.adUnitId});

  final String adUnitId;
}

class AdRequestError {
  AdRequestError(this.description);

  final String description;
}

class AdError {
  AdError(this.description);

  final String description;
}

abstract class ImpressionData {
  String getRawData();
}

class Reward {
  const Reward(this.type, this.amount);

  final String type;
  final int amount;
}

class RewardedAdEventListener {
  RewardedAdEventListener({
    this.onAdShown,
    this.onAdFailedToShow,
    this.onAdDismissed,
    this.onAdClicked,
    this.onAdImpression,
    this.onRewarded,
  });

  final void Function()? onAdShown;
  final void Function(AdError error)? onAdFailedToShow;
  final void Function()? onAdDismissed;
  final void Function()? onAdClicked;
  final void Function(ImpressionData impressionData)? onAdImpression;
  final void Function(Reward reward)? onRewarded;
}

/// Never made: no load ever succeeds.
class RewardedAd {
  RewardedAd._();

  Future<void> setAdEventListener(
      {required RewardedAdEventListener eventListener}) async {}

  Future<void> show() async {}
}

class RewardedAdLoader {
  RewardedAdLoader._(this._onAdFailedToLoad);

  final void Function(AdRequestError error)? _onAdFailedToLoad;

  static Future<RewardedAdLoader> create({
    void Function(RewardedAd rewardedAd)? onAdLoaded,
    void Function(AdRequestError error)? onAdFailedToLoad,
  }) async =>
      RewardedAdLoader._(onAdFailedToLoad);

  /// Reports that nothing loaded.
  Future<void> loadAd({AdRequestConfiguration? adRequestConfiguration}) async {
    _onAdFailedToLoad?.call(AdRequestError('not in this build'));
  }
}
