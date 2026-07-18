// lib/services/ads/rewarded_ad_service.dart
//
// Network-agnostic rewarded-ad loader/shower for the scan-credit flow (Phase
// A3). Ports the Unity / Adivery / Yandex load+show mechanics from OrbX's
// AdProvider, STRIPPED of all VPN disconnect/reconnect, analytics, batching and
// cooldown logic — this layer only knows how to play ONE rewarded ad and report
// whether the reward callback actually fired.
//
// HONEST BY CONSTRUCTION:
//  • Network IDs come from --dart-define at build time (String.fromEnvironment).
//    A network with no configured ID is UNAVAILABLE and skipped in the waterfall.
//  • With NO network configured, [showRewardedAd] throws
//    [AdsNotConfiguredException] — it never pretends an ad played.
//  • [showRewardedAd] returns true ONLY when the SDK delivered its reward
//    callback (Unity onComplete / Adivery rewarded-close / Yandex onRewarded).
//    A skip, dismiss, load failure or timeout returns false. No fake rewards.
//
// Build-time config (all optional; supply the networks you have a placement for):
//   --dart-define=UNITY_GAME_ID=...         --dart-define=UNITY_REWARDED_PLACEMENT=...
//   --dart-define=ADIVERY_APP_ID=...        --dart-define=ADIVERY_PLACEMENT=...
//   --dart-define=YANDEX_REWARDED_UNIT_ID=...

import 'dart:async';
import 'dart:io';

import 'package:adivery/adivery.dart' as adivery;
import 'package:flutter/foundation.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:yandex_mobileads/mobile_ads.dart' as yandex;

import '../orbnet/models/ad_models.dart';

/// Thrown by [RewardedAdService.showRewardedAd] when no ad network is configured
/// for this build. Callers must surface an honest "ads unavailable" state — the
/// reward pool is never credited without a real, verified ad view.
class AdsNotConfiguredException implements Exception {
  final String message;
  AdsNotConfiguredException(
      [this.message = 'No rewarded-ad network is configured for this build.']);
  @override
  String toString() => message;
}

/// Coarse region hint used to order the waterfall (kit-trimmed port of OrbX's
/// RegionalAdManager): Iran prefers Adivery, Russia/CIS prefers Yandex, the rest
/// of the world prefers Unity.
enum AdRegion { global, iran, russia }

/// The minimal surface the scan-credit provider + UI depend on. Kept small so
/// tests can fake it trivially without touching any native SDK.
abstract class RewardedAdService {
  /// True when at least one rewarded-ad network is configured for this build.
  bool get anyNetworkConfigured;

  /// The provider name to record on the backend session (the first network the
  /// waterfall will try), or null when nothing is configured.
  String? get preferredProvider;

  /// Play a rewarded ad. Returns true ONLY when a real reward was delivered;
  /// false when every configured network failed/was dismissed. Throws
  /// [AdsNotConfiguredException] when no network is configured.
  Future<bool> showRewardedAd();
}

/// Production implementation backed by the Unity / Adivery / Yandex SDKs.
class DefaultRewardedAdService implements RewardedAdService {
  // ── Build-time network configuration (compile-time constants) ──────────────
  static const String _unityGameId = String.fromEnvironment('UNITY_GAME_ID');
  static const String _unityPlacement =
      String.fromEnvironment('UNITY_REWARDED_PLACEMENT');
  static const String _adiveryAppId = String.fromEnvironment('ADIVERY_APP_ID');
  static const String _adiveryPlacement =
      String.fromEnvironment('ADIVERY_PLACEMENT');
  static const String _yandexUnitId =
      String.fromEnvironment('YANDEX_REWARDED_UNIT_ID');

  AdRegion _region;

  DefaultRewardedAdService({AdRegion region = AdRegion.global})
      : _region = region;

  bool get _isAndroid => Platform.isAndroid;

  // ── Per-network availability (config present AND platform-supported) ───────
  bool get _unityConfigured =>
      _unityGameId.isNotEmpty && _unityPlacement.isNotEmpty;
  // Adivery ships an Android-only SDK.
  bool get _adiveryConfigured =>
      _adiveryAppId.isNotEmpty && _adiveryPlacement.isNotEmpty && _isAndroid;
  bool get _yandexConfigured => _yandexUnitId.isNotEmpty;

  bool _configured(String provider) {
    switch (provider) {
      case AdProviderId.unityAds:
        return _unityConfigured;
      case AdProviderId.adivery:
        return _adiveryConfigured;
      case AdProviderId.yandex:
        return _yandexConfigured;
      default:
        return false;
    }
  }

  /// Region-ordered list of the networks that are actually configured.
  List<String> get configuredProviders {
    final List<String> order;
    switch (_region) {
      case AdRegion.iran:
        order = const [
          AdProviderId.adivery,
          AdProviderId.unityAds,
          AdProviderId.yandex,
        ];
        break;
      case AdRegion.russia:
        order = const [
          AdProviderId.yandex,
          AdProviderId.unityAds,
          AdProviderId.adivery,
        ];
        break;
      case AdRegion.global:
        order = const [
          AdProviderId.unityAds,
          AdProviderId.adivery,
          AdProviderId.yandex,
        ];
        break;
    }
    return order.where(_configured).toList(growable: false);
  }

  @override
  bool get anyNetworkConfigured => configuredProviders.isNotEmpty;

  @override
  String? get preferredProvider =>
      configuredProviders.isEmpty ? null : configuredProviders.first;

  /// Update the region hint (e.g. from a backend-detected country code).
  void setRegion(AdRegion region) => _region = region;

  @override
  Future<bool> showRewardedAd() async {
    final providers = configuredProviders;
    if (providers.isEmpty) throw AdsNotConfiguredException();

    for (final provider in providers) {
      final rewarded = await _playOne(provider);
      if (rewarded) return true;
    }
    return false;
  }

  Future<bool> _playOne(String provider) async {
    try {
      switch (provider) {
        case AdProviderId.unityAds:
          return await _showUnity();
        case AdProviderId.adivery:
          return await _showAdivery();
        case AdProviderId.yandex:
          return await _showYandex();
        default:
          return false;
      }
    } catch (e) {
      _log('$provider play error: $e');
      return false;
    }
  }

  // ── Unity Ads (global) ──────────────────────────────────────────────────────
  bool _unityInitialized = false;

  Future<bool> _ensureUnityInitialized() async {
    if (_unityInitialized) return true;
    final c = Completer<bool>();
    try {
      await UnityAds.init(
        gameId: _unityGameId,
        testMode: false,
        onComplete: () {
          _unityInitialized = true;
          if (!c.isCompleted) c.complete(true);
        },
        onFailed: (error, message) {
          _log('Unity init failed: $error $message');
          if (!c.isCompleted) c.complete(false);
        },
      );
    } catch (e) {
      _log('Unity init exception: $e');
      if (!c.isCompleted) c.complete(false);
    }
    return c.future.timeout(const Duration(seconds: 15), onTimeout: () => false);
  }

  Future<bool> _loadUnity() async {
    final c = Completer<bool>();
    try {
      UnityAds.load(
        placementId: _unityPlacement,
        onComplete: (_) {
          if (!c.isCompleted) c.complete(true);
        },
        onFailed: (placement, error, message) {
          _log('Unity load failed: $error $message');
          if (!c.isCompleted) c.complete(false);
        },
      );
    } catch (e) {
      _log('Unity load exception: $e');
      if (!c.isCompleted) c.complete(false);
    }
    return c.future.timeout(const Duration(seconds: 30), onTimeout: () => false);
  }

  Future<bool> _showUnity() async {
    if (!await _ensureUnityInitialized()) return false;
    if (!await _loadUnity()) return false;

    final c = Completer<bool>();
    try {
      UnityAds.showVideoAd(
        placementId: _unityPlacement,
        // onComplete = the user watched to the end (rewarded).
        onComplete: (_) {
          if (!c.isCompleted) c.complete(true);
        },
        onSkipped: (_) {
          if (!c.isCompleted) c.complete(false);
        },
        onFailed: (placement, error, message) {
          _log('Unity show failed: $error $message');
          if (!c.isCompleted) c.complete(false);
        },
      );
    } catch (e) {
      _log('Unity show exception: $e');
      if (!c.isCompleted) c.complete(false);
    }
    return c.future.timeout(const Duration(minutes: 3), onTimeout: () => false);
  }

  // ── Adivery (Iran, Android-only) ────────────────────────────────────────────
  bool _adiveryInitialized = false;
  Completer<bool>? _adiveryLoad;
  Completer<bool>? _adiveryShow;

  void _ensureAdiveryInitialized() {
    if (_adiveryInitialized) return;
    // Register listeners BEFORE initialize so no early native callback is lost.
    adivery.AdiveryPlugin.addListener(
      onRewardedLoaded: (placement) {
        if (_adiveryLoad?.isCompleted == false) _adiveryLoad!.complete(true);
      },
      onRewardedClosed: (placement, isRewarded) {
        if (_adiveryShow?.isCompleted == false) {
          _adiveryShow!.complete(isRewarded);
        }
      },
      onError: (placement, reason) {
        _log('Adivery error: $reason');
        if (_adiveryLoad?.isCompleted == false) _adiveryLoad!.complete(false);
        if (_adiveryShow?.isCompleted == false) _adiveryShow!.complete(false);
      },
    );
    adivery.AdiveryPlugin.initialize(_adiveryAppId);
    _adiveryInitialized = true;
  }

  Future<bool> _showAdivery() async {
    if (!_isAndroid) return false;
    _ensureAdiveryInitialized();

    _adiveryLoad = Completer<bool>();
    adivery.AdiveryPlugin.prepareRewardedAd(_adiveryPlacement);
    final loaded = await _adiveryLoad!.future
        .timeout(const Duration(seconds: 30), onTimeout: () => false);
    if (!loaded) return false;

    _adiveryShow = Completer<bool>();
    adivery.AdiveryPlugin.show(_adiveryPlacement);
    return _adiveryShow!.future
        .timeout(const Duration(minutes: 3), onTimeout: () => false);
  }

  // ── Yandex (Russia/CIS) ─────────────────────────────────────────────────────
  bool _yandexInitialized = false;

  Future<void> _ensureYandexInitialized() async {
    if (_yandexInitialized) return;
    await yandex.MobileAds.initialize();
    _yandexInitialized = true;
  }

  Future<bool> _showYandex() async {
    await _ensureYandexInitialized();

    final loadCompleter = Completer<yandex.RewardedAd?>();
    final loader = await yandex.RewardedAdLoader.create(
      onAdLoaded: (ad) {
        if (!loadCompleter.isCompleted) loadCompleter.complete(ad);
      },
      onAdFailedToLoad: (error) {
        _log('Yandex load failed: ${error.description}');
        if (!loadCompleter.isCompleted) loadCompleter.complete(null);
      },
    );
    await loader.loadAd(
      adRequestConfiguration:
          yandex.AdRequestConfiguration(adUnitId: _yandexUnitId),
    );
    final ad = await loadCompleter.future
        .timeout(const Duration(seconds: 30), onTimeout: () => null);
    if (ad == null) return false;

    final showCompleter = Completer<bool>();
    var rewarded = false;
    await ad.setAdEventListener(
      eventListener: yandex.RewardedAdEventListener(
        onAdShown: () {},
        onAdFailedToShow: (error) {
          _log('Yandex show failed: ${error.description}');
          if (!showCompleter.isCompleted) showCompleter.complete(false);
        },
        // Reward is decided by onRewarded; dismiss just closes the completer.
        onAdDismissed: () {
          if (!showCompleter.isCompleted) showCompleter.complete(rewarded);
        },
        onAdClicked: () {},
        onAdImpression: (_) {},
        onRewarded: (_) {
          rewarded = true;
        },
      ),
    );
    await ad.show();
    return showCompleter.future
        .timeout(const Duration(minutes: 3), onTimeout: () => false);
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[RewardedAdService] $message');
  }
}
