// Amazon Appstore build only. The part of the plugin's API that
// lib/services/ads/rewarded_ad_service.dart calls, with the same
// signatures. Nothing here reaches a platform channel: no ad loads, so no
// ad shows. The Amazon build never calls it anyway (kAmazonBuild).
library;

/// The plugin's entry point, as the app calls it.
class UnityAds {
  /// Reports that it could not start.
  static Future<void> init({
    required String gameId,
    bool testMode = false,
    Function? onComplete,
    Function(UnityAdsInitializationError error, String errorMessage)? onFailed,
  }) async {
    onFailed?.call(UnityAdsInitializationError.unknown, 'not in this build');
  }

  /// Reports that nothing loaded.
  static Future<void> load({
    required String placementId,
    Function(String placementId)? onComplete,
    Function(String placementId, UnityAdsLoadError error, String errorMessage)?
        onFailed,
  }) async {
    onFailed?.call(placementId, UnityAdsLoadError.noFill, 'not in this build');
  }

  /// Reports that nothing showed.
  static Future<void> showVideoAd({
    required String placementId,
    Function(String placementId)? onStart,
    Function(String placementId)? onSkipped,
    Function(String placementId)? onClick,
    Function(String placementId)? onComplete,
    Function(String placementId, UnityAdsShowError error, String errorMessage)?
        onFailed,
  }) async {
    onFailed?.call(
        placementId, UnityAdsShowError.notReady, 'not in this build');
  }
}

enum UnityAdsInitializationError {
  internalError,
  invalidArgument,
  adBlockerDetected,
  unknown,
}

enum UnityAdsLoadError {
  initializeFailed,
  internalError,
  invalidArgument,
  noFill,
  timeout,
  unknown,
}

enum UnityAdsShowError {
  notInitialized,
  notReady,
  videoPlayerError,
  invalidArgument,
  noConnection,
  alreadyShowing,
  internalError,
  timeout,
  unknown,
}
