// Telemetry Service
//
// Wires Firebase Crashlytics (crash reporting) and Firebase Analytics (usage
// analytics) behind the app's existing privacy opt-out toggles:
//   - priv_crash     → Crashlytics collection
//   - priv_analytics → Analytics collection
// Both default on and are honestly disableable from Settings → Privacy; when a
// toggle is off the corresponding SDK collects and sends nothing. Crash
// collection is additionally suppressed in debug builds so development crashes
// never reach the dashboard.

import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  bool _initialized = false;
  FirebaseAnalytics? _analytics;
  FirebaseAnalyticsObserver? _observer;

  /// Navigator observer for automatic screen-view logging. Null until [init]
  /// has run; wire it into `MaterialApp.navigatorObservers`.
  FirebaseAnalyticsObserver? get navigatorObserver => _observer;

  /// Ensure the default Firebase app exists. Idempotent and shared with the
  /// push service, which may also initialize Firebase.
  static Future<void> ensureFirebaseInitialized() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  }

  /// Initialize telemetry early in main(). Reads the persisted privacy toggles,
  /// applies them to the SDKs, and routes Flutter/async errors to Crashlytics
  /// (which itself no-ops when collection is disabled). Never throws.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await ensureFirebaseInitialized();

      final prefs = await SharedPreferences.getInstance();
      final crash = prefs.getBool('priv_crash') ?? true;
      final analytics = prefs.getBool('priv_analytics') ?? true;

      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(crash && !kDebugMode);

      _analytics = FirebaseAnalytics.instance;
      await _analytics!.setAnalyticsCollectionEnabled(analytics);
      _observer = FirebaseAnalyticsObserver(analytics: _analytics!);

      // Route framework + platform errors to Crashlytics. These no-op when
      // collection is disabled, so they honor the privacy toggle.
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      _initialized = true;
    } catch (e) {
      debugPrint('TelemetryService: init failed: $e');
    }
  }

  /// Apply the privacy toggles live (called from SettingsProvider.updatePrivacy
  /// when the user changes them). Never throws.
  Future<void> applyPrivacySettings({
    required bool analyticsEnabled,
    required bool crashEnabled,
  }) async {
    try {
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(crashEnabled && !kDebugMode);
      await _analytics?.setAnalyticsCollectionEnabled(analyticsEnabled);
    } catch (e) {
      debugPrint('TelemetryService: applyPrivacySettings failed: $e');
    }
  }
}
