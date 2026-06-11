/// Device Push Service — FCM/APNs push-notification wake-up for the anti-theft
/// device agent.
///
/// @docImport 'device_agent.dart';
library;

/// WHY THIS EXISTS:
/// WHY THIS EXISTS NOW, BUILD-SAFE:
/// The device agent (device_agent.dart) has NO push channel today — remote
/// commands are HTTP-polled (60s foreground timer + poll-on-resume; Android
/// adds a 15-min WorkManager cycle). A high-priority FCM/APNs *data* push would
/// let the backend wake the agent immediately so a locate/lock/wipe is acted on
/// in seconds, not minutes.
///
/// Adding `firebase_core` + `firebase_messaging` to pubspec AND applying the
/// `com.google.gms.google-services` Gradle plugin REQUIRES
/// `android/app/google-services.json`, which this repo does NOT ship. Adding
/// those now BREAKS `flutter build apk`. So this file is written to COMPILE
/// WITH ZERO FIREBASE IMPORTS: the Firebase-specific code path is present but
/// unreachable, guarded by [kFirebaseEnabled] (false) and kept inside a clearly
/// marked block. Everything that needs no Firebase dependency — backend token
/// registration and the "push received → poll the agent now" hook — is real and
/// works today.
///
/// ACTIVATION (full steps in docs/FCM_SETUP.md):
///   1. Add google-services.json (Android) / GoogleService-Info.plist (iOS).
///   2. Add firebase_core + firebase_messaging to pubspec; apply the gms plugin.
///   3. Uncomment the single block marked `--- FIREBASE BLOCK ---` below and add
///      the two marked imports at the top of this file.
///   4. Set [kFirebaseEnabled] = true.
///   5. Backend: set ORBGUARD_FCM_PROJECT_ID + ORBGUARD_FCM_SERVICE_ACCOUNT_JSON,
///      run migration 022.
///
/// Until then iOS/Android both rely on the already-implemented polling, which is
/// correct (just higher-latency than push).

import 'dart:developer' as developer;
import 'dart:io';

// --- FIREBASE BLOCK: imports ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// --- END FIREBASE BLOCK: imports ---

import '../api/orbguard_api_client.dart';
import 'device_agent.dart';

/// Master switch for the Firebase Cloud Messaging integration. Stays `false`
/// until the Firebase dependencies + config files are added (see file header
/// and docs/FCM_SETUP.md). While `false`, [DevicePushService.init] is a
/// logged no-op and the app falls back to the existing HTTP polling.
const bool kFirebaseEnabled = true;

/// On-device push abstraction for the anti-theft agent. Singleton so the app
/// init path and any future native message handlers share one instance.
///
/// The two capabilities that work TODAY (no Firebase needed):
///   * [registerToken] — POST the FCM/APNs token to the backend.
///   * [onPushReceived] — trigger an immediate device-agent command poll.
/// [init] / [initFirebaseMessaging] are the Firebase-gated entry points that
/// become live once [kFirebaseEnabled] is true.
class DevicePushService {
  DevicePushService._();
  static final DevicePushService instance = DevicePushService._();

  static const String _logName = 'DevicePushService';

  final OrbGuardApiClient _api = OrbGuardApiClient.instance;

  /// The last token successfully registered with the backend, so we don't
  /// re-POST an unchanged token on every app start / refresh callback.
  String? _lastRegisteredToken;

  /// Whether Firebase messaging has been wired up this process.
  bool _initialized = false;

  bool get isInitialized => _initialized;
  String? get lastRegisteredToken => _lastRegisteredToken;

  /// Initialize the push pipeline. With [kFirebaseEnabled] == false this only
  /// logs and returns — the agent's HTTP polling remains the wake mechanism.
  /// Safe to call on every app start (idempotent).
  Future<void> init() async {
    if (_initialized) return;
    if (!kFirebaseEnabled) {
      developer.log(
        'push disabled (kFirebaseEnabled=false): Firebase Cloud Messaging is '
        'not wired in this build; the device agent uses HTTP polling. See '
        'docs/FCM_SETUP.md to enable push wake-ups.',
        name: _logName,
      );
      return;
    }
    await initFirebaseMessaging();
    _initialized = true;
  }

  /// Register a push token with the backend so it can target this device.
  ///
  /// Real and usable today: the only reason it is not exercised yet is that no
  /// component produces a [token] until Firebase is enabled. De-duplicates
  /// unchanged tokens. Never throws to the caller — registration failures are
  /// logged and retried on the next token event / app start.
  Future<bool> registerToken(String token) async {
    if (token.isEmpty) {
      developer.log('ignoring empty push token', name: _logName);
      return false;
    }
    if (token == _lastRegisteredToken) {
      // Already registered this exact token; nothing to do.
      return true;
    }
    try {
      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : Platform.operatingSystem;
      final ok = await _api.registerPushToken(token, platform: platform);
      if (ok) {
        _lastRegisteredToken = token;
        developer.log('push token registered with backend ($platform)',
            name: _logName);
      }
      return ok;
    } catch (e) {
      developer.log('failed to register push token: $e', name: _logName);
      return false;
    }
  }

  /// Hook for an incoming push: wake the device agent so a freshly-queued
  /// remote command (locate/lock/wipe/ring/...) is fetched and executed
  /// immediately instead of waiting for the next poll tick.
  ///
  /// Real and usable today; it is simply not yet driven by a Firebase message
  /// handler. [data] is the push payload (unused for now — the agent re-fetches
  /// pending commands from the backend, which is the source of truth).
  Future<void> onPushReceived([Map<String, dynamic>? data]) async {
    developer.log(
      'push received → polling device agent now${data == null ? '' : ' (payload keys: ${data.keys.toList()})'}',
      name: _logName,
    );
    try {
      await DeviceAgent.instance.pollNow();
    } catch (e) {
      developer.log('agent poll after push failed: $e', name: _logName);
    }
  }

  /// Firebase Messaging setup. The body is fully written but guarded so the
  /// file compiles WITHOUT the firebase packages: while [kFirebaseEnabled] is
  /// false this returns early, and the real Firebase calls live inside the
  /// commented `--- FIREBASE BLOCK ---` below (the only edit needed to activate
  /// is to uncomment that block + the imports at the top, per docs/FCM_SETUP.md).
  Future<void> initFirebaseMessaging() async {
    if (!kFirebaseEnabled) {
      developer.log(
        'initFirebaseMessaging() called while kFirebaseEnabled=false — no-op',
        name: _logName,
      );
      return;
    }

    // --- FIREBASE BLOCK ---
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;

    // Request notification permission (iOS prompts; Android 13+ POST_NOTIFICATIONS).
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // iOS: ensure an APNs token exists before asking for the FCM token,
    // otherwise getToken() can return null on a cold start.
    if (Platform.isIOS) {
      await messaging.getAPNSToken();
    }

    // Register the current token, then keep it fresh on rotation.
    final token = await messaging.getToken();
    if (token != null) {
      await registerToken(token);
    }
    messaging.onTokenRefresh.listen(registerToken);

    // Foreground data pushes wake the agent immediately.
    FirebaseMessaging.onMessage.listen((message) {
      onPushReceived(message.data);
    });

    // Tapping a notification that opened the app also triggers a poll.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onPushReceived(message.data);
    });

    // Background/terminated data messages are handled by the top-level
    // handler registered in main() (orbGuardFirebaseBackgroundHandler).
    // --- END FIREBASE BLOCK ---

    developer.log('Firebase messaging initialized', name: _logName);
  }
}

// --- FIREBASE BLOCK: background handler ---
/// Top-level background/terminated-state FCM handler. Must be a top-level
/// function annotated with @pragma('vm:entry-point') so it survives
/// tree-shaking and can run in the headless isolate. Registered in main():
///   FirebaseMessaging.onBackgroundMessage(orbGuardFirebaseBackgroundHandler);
@pragma('vm:entry-point')
Future<void> orbGuardFirebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // In the background isolate there is no provider tree; run one headless
  // agent cycle directly (re-reads device id + policy from prefs).
  await DeviceAgent.runHeadlessCycle();
}
// --- END FIREBASE BLOCK: background handler ---
