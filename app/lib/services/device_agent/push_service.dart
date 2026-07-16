/// Device Push Service — FCM/APNs push-notification wake-up for the anti-theft
/// device agent.
///
/// @docImport 'device_agent.dart';
library;

/// WHY THIS EXISTS:
/// The device agent (device_agent.dart) is HTTP-polled (60s foreground timer +
/// poll-on-resume; Android adds a 15-min WorkManager cycle). A high-priority
/// FCM/APNs *data* push lets the backend wake the agent immediately so a
/// locate/lock/wipe is acted on in seconds, not minutes. Polling remains the
/// fallback whenever push is unavailable.
///
/// STATUS: the client integration is fully wired and ACTIVE ([kFirebaseEnabled]
/// = true): firebase_core + firebase_messaging are in pubspec, the config files
/// (GoogleService-Info.plist / google-services.json for project `orb-guard`) are
/// present, and [DevicePushService.init] initializes Firebase, requests
/// permission, retrieves + registers the token, and wires foreground /
/// opened-app / background handlers.
///
/// REMAINING (provisioning, outside this file):
///   - Backend: set ORBGUARD_FCM_PROJECT_ID=orb-guard and
///     ORBGUARD_FCM_SERVICE_ACCOUNT_JSON (an orb-guard service-account key) on
///     the Azure Container App, and apply migration 022 (device_push_tokens).
///     Until then the backend push sender is a logged no-op and delivery falls
///     back to polling.
///   - iOS release: upload an APNs auth key to the orb-guard Firebase project
///     and set aps-environment=production in Runner.entitlements.

import 'dart:developer' as developer;
import '../../utils/platform_info.dart';

// --- FIREBASE BLOCK: imports ---
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
// --- END FIREBASE BLOCK: imports ---

import '../api/orbguard_api_client.dart';
import 'device_agent.dart';

/// Master switch for the Firebase Cloud Messaging integration. Active (`true`):
/// the Firebase dependencies + config files are present. While `false`,
/// [DevicePushService.init] is a logged no-op and the app falls back to the
/// existing HTTP polling.
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
    if (PlatformInfo.isWeb) {
      developer.log(
        'push disabled on web: FCM wake-ups require a native platform '
        '(no Firebase web config in this build).',
        name: _logName,
      );
      return;
    }
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
      final platform = PlatformInfo.isIOS
          ? 'ios'
          : PlatformInfo.isAndroid
              ? 'android'
              : PlatformInfo.operatingSystem;
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
    // Push is best-effort: any failure here must never escape (init() is
    // fire-and-forget from the provider), the agent's HTTP polling remains
    // the wake mechanism.
    try {
      // Idempotent: telemetry may have already initialized the default app.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      final messaging = FirebaseMessaging.instance;

      // Request notification permission (iOS prompts; Android 13+ POST_NOTIFICATIONS).
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Wire handlers first — they are independent of token availability, so
      // a token that arrives late still registers via onTokenRefresh.
      messaging.onTokenRefresh.listen(registerToken);

      // Foreground data pushes wake the agent immediately.
      FirebaseMessaging.onMessage.listen((message) {
        onPushReceived(message.data);
      });

      // Tapping a notification that opened the app also triggers a poll.
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        onPushReceived(message.data);
      });

      // iOS: FCM requires the APNs device token first. On a cold start APNs
      // delivery takes a moment — and on simulators without push support it
      // never happens — while getAPNSToken()/getToken() THROW
      // [firebase_messaging/apns-token-not-set] rather than waiting. Poll
      // briefly and defer to onTokenRefresh instead of crashing app init.
      if (PlatformInfo.isIOS) {
        final apnsToken = await _waitForApnsToken(messaging);
        if (apnsToken == null) {
          developer.log(
            'APNs token not delivered (expected on simulators without push '
            'support / cold starts) — FCM token registration deferred to '
            'onTokenRefresh; agent polling covers wake-ups meanwhile.',
            name: _logName,
          );
          return;
        }
      }

      // Register the current token, then keep it fresh on rotation.
      final token = await messaging.getToken();
      if (token != null) {
        await registerToken(token);
      }

      // Background/terminated data messages are handled by the top-level
      // handler registered in main() (orbGuardFirebaseBackgroundHandler).

      developer.log('Firebase messaging initialized', name: _logName);
    } on FirebaseException catch (e) {
      developer.log(
        'Firebase messaging init failed (${e.code}) — push disabled this '
        'session, agent polling remains: ${e.message}',
        name: _logName,
      );
    } catch (e) {
      developer.log(
        'Firebase messaging init failed — push disabled this session, agent '
        'polling remains: $e',
        name: _logName,
      );
    }
    // --- END FIREBASE BLOCK ---
  }

  /// Poll for the APNs device token for a few seconds. Returns null if APNs
  /// never delivers one (e.g. simulator hosts without push support), treating
  /// the plugin's `apns-token-not-set` throw the same as "not yet".
  Future<String?> _waitForApnsToken(
    FirebaseMessaging messaging, {
    int attempts = 8,
    Duration delay = const Duration(milliseconds: 750),
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        final token = await messaging.getAPNSToken();
        if (token != null) return token;
      } on FirebaseException catch (e) {
        if (e.code != 'apns-token-not-set') rethrow;
      }
      await Future.delayed(delay);
    }
    return null;
  }
}

// --- FIREBASE BLOCK: background handler ---
/// Top-level background/terminated-state FCM handler. Must be a top-level
/// function annotated with @pragma('vm:entry-point') so it survives
/// tree-shaking and can run in the headless isolate. Registered in main():
///   FirebaseMessaging.onBackgroundMessage(orbGuardFirebaseBackgroundHandler);
@pragma('vm:entry-point')
Future<void> orbGuardFirebaseBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  // In the background isolate there is no provider tree; run one headless
  // agent cycle directly (re-reads device id + policy from prefs).
  await DeviceAgent.runHeadlessCycle();
}
// --- END FIREBASE BLOCK: background handler ---
