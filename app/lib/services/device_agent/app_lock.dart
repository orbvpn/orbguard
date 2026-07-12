/// Biometric App-Lock — the iOS (and Android/macOS) "best-extent" surface
/// for the thief-selfie feature.
///
/// WHY THIS EXISTS (honest platform reality):
/// A third-party app cannot hook the operating-system lock screen's failed
/// unlock attempts. On iOS there is no DeviceAdminReceiver equivalent at all,
/// so the OS-level "wrong passcode -> selfie" flow that some Android OEM
/// security suites ship is simply not available to us. The genuinely useful
/// thing we CAN do within the platform sandbox is gate the app itself behind
/// a biometric / device-credential prompt and treat repeated failures of THAT
/// prompt as the trigger: a thief who picks up an unlocked phone and opens
/// OrbGuard, or who is poking at the app, gets photographed.
///
/// Behaviour:
///   * When the user has enabled the in-app lock (privacy setting
///     'priv_biometric'), [AppLockGate] requires a successful
///     LocalAuthentication before the app content is shown, and re-locks when
///     the app has been backgrounded longer than the auto-lock timeout
///     ('priv_lock_timeout' minutes; 0 = lock on every resume).
///   * Each failed / cancelled authentication increments a counter. Once the
///     counter reaches [selfieThreshold] AND the user has enabled thief-selfie
///     in anti-theft settings, a front-camera selfie is captured and uploaded
///     with trigger_type 'wrong_pin' (the backend's documented value, matched
///     to the SelfieOnWrongPIN setting). The counter resets on success.
///
/// This file is the ONLY place the in-app-lock failure path triggers a
/// selfie; the remote 'take_selfie' command path lives in device_agent.dart.
library;

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/orbguard_api_client.dart';
import 'agent_api.dart';
import 'device_agent.dart';
import 'selfie_capture.dart';

/// Privacy-setting SharedPreferences keys written by SettingsProvider.
const String _kBiometricEnabledKey = 'priv_biometric';
const String _kLockTimeoutMinutesKey = 'priv_lock_timeout';

/// Manages the locked/unlocked state of the app and the failed-attempt ->
/// thief-selfie trigger. Singleton so the gate widget and any caller share
/// one counter.
class BiometricAppLock extends ChangeNotifier {
  BiometricAppLock._();

  static final BiometricAppLock instance = BiometricAppLock._();

  final LocalAuthentication _auth = LocalAuthentication();
  final SelfieCapture _selfieCapture = SelfieCapture();

  /// Consecutive failed authentication attempts that trigger a thief selfie.
  /// Three balances "honest mistake" against "someone is fishing".
  int selfieThreshold = 3;

  bool _locked = true;
  int _failedAttempts = 0;
  bool _authInFlight = false;
  String? _lastSelfieStatus;

  /// Whether the app content is currently hidden behind the lock.
  bool get isLocked => _locked;

  /// Consecutive failed attempts since the last success.
  int get failedAttempts => _failedAttempts;

  /// Honest detail of the most recent selfie trigger (null until one fires).
  String? get lastSelfieStatus => _lastSelfieStatus;

  /// Whether the OS can perform biometric / device-credential auth at all.
  /// Returns false (and the gate stays open) on platforms/devices with no
  /// authentication hardware so the user is never locked out.
  Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      // canCheckBiometrics is false on devices with only a passcode, but
      // authenticate() with biometricOnly:false still works via the device
      // credential, so device-supported is the gate we honour here.
      return true;
    } on PlatformException catch (e) {
      developer.log('biometric availability check failed: ${e.code}',
          name: 'BiometricAppLock');
      return false;
    }
  }

  /// Whether the user turned the in-app lock on in privacy settings.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kBiometricEnabledKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Auto-lock timeout in minutes (0 = lock on every resume).
  static Future<int> lockTimeoutMinutes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_kLockTimeoutMinutesKey) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Marks the app locked so the gate re-prompts on next foreground.
  void lock() {
    if (!_locked) {
      _locked = true;
      notifyListeners();
    }
  }

  /// Prompts for biometric / device-credential auth. On success unlocks and
  /// resets the failure counter; on failure increments it and — past the
  /// threshold — fires a thief selfie. Returns true iff unlocked.
  Future<bool> authenticate() async {
    if (_authInFlight) return !_locked;
    _authInFlight = true;
    try {
      bool ok;
      try {
        ok = await _auth.authenticate(
          localizedReason: 'Authenticate to unlock OrbGuard',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
            useErrorDialogs: true,
          ),
        );
      } on PlatformException catch (e) {
        // Treat a hard auth error (lockout, user cancel, no enrolment) as a
        // failed attempt rather than crashing the gate.
        developer.log('authenticate() PlatformException: ${e.code}',
            name: 'BiometricAppLock');
        ok = false;
      }

      if (ok) {
        _failedAttempts = 0;
        _locked = false;
        notifyListeners();
        return true;
      }
      await _onFailedAttempt();
      return false;
    } finally {
      _authInFlight = false;
    }
  }

  Future<void> _onFailedAttempt() async {
    _failedAttempts++;
    developer.log('app-lock failed attempt #$_failedAttempts',
        name: 'BiometricAppLock');
    notifyListeners();
    if (_failedAttempts >= selfieThreshold) {
      // Fire-and-forget; never block the lock UI on camera/network.
      unawaited(_captureThiefSelfie());
    }
  }

  /// Captures and uploads a front-camera selfie — but only when the user has
  /// enabled thief-selfie in anti-theft settings (honours consent). Every
  /// skip/failure is recorded honestly in [lastSelfieStatus]; nothing is
  /// silently claimed.
  Future<void> _captureThiefSelfie() async {
    final agent = DeviceAgent.instance;
    if (!agent.policy.thiefSelfieEnabled) {
      _lastSelfieStatus =
          'failed-unlock selfie skipped: thief selfie disabled in settings';
      developer.log(_lastSelfieStatus!, name: 'BiometricAppLock');
      return;
    }

    String? deviceId = agent.deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        deviceId = prefs.getString(kRegisteredDeviceIdPrefsKey);
      } catch (_) {
        deviceId = null;
      }
    }
    if (deviceId == null || deviceId.isEmpty) {
      _lastSelfieStatus =
          'failed-unlock selfie skipped: device not registered yet';
      developer.log(_lastSelfieStatus!, name: 'BiometricAppLock');
      return;
    }

    final api = DeviceAgentApi(OrbGuardApiClient.instance, deviceId);
    final result = await _selfieCapture.captureAndUpload(
      api,
      triggerType: 'wrong_pin',
      attemptCount: _failedAttempts,
    );
    _lastSelfieStatus = result.ok
        ? 'failed-unlock selfie uploaded (id=${result.selfieId})'
        : 'failed-unlock selfie failed: ${result.failureReason}';
    developer.log(_lastSelfieStatus!, name: 'BiometricAppLock');
  }
}

/// Wraps the app content behind the biometric lock when the user enabled it.
///
/// Wire it once at the app root, e.g. `home: AppLockGate(child: HomeShell())`
/// or as a builder around MaterialApp's child. When the lock is disabled or
/// unavailable it renders [child] untouched, so it is safe to leave in place
/// regardless of the user's setting.
class AppLockGate extends StatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate>
    with WidgetsBindingObserver {
  final BiometricAppLock _lock = BiometricAppLock.instance;

  bool _enabled = false;
  bool _available = false;
  bool _initialized = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lock.addListener(_onLockChanged);
    _init();
  }

  Future<void> _init() async {
    final enabled = await BiometricAppLock.isEnabled();
    final available = enabled ? await _lock.isAvailable() : false;
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _available = available;
      _initialized = true;
    });
    if (_enabled && _available) {
      // Lock on cold start and prompt immediately.
      _lock.lock();
      unawaited(_lock.authenticate());
    }
  }

  void _onLockChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled || !_available) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_maybeRelockOnResume());
    }
  }

  Future<void> _maybeRelockOnResume() async {
    if (_lock.isLocked) {
      // Already locked (e.g. fresh start); ensure a prompt is showing.
      unawaited(_lock.authenticate());
      return;
    }
    final timeoutMin = await BiometricAppLock.lockTimeoutMinutes();
    final since = _backgroundedAt;
    final elapsedOk = timeoutMin == 0 ||
        (since != null &&
            DateTime.now().difference(since) >=
                Duration(minutes: timeoutMin));
    if (elapsedOk) {
      _lock.lock();
      unawaited(_lock.authenticate());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lock.removeListener(_onLockChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Until we know the setting state, and whenever the lock is off/unusable,
    // show the app untouched — never lock the user out.
    if (!_initialized || !_enabled || !_available || !_lock.isLocked) {
      return widget.child;
    }
    return _LockScreen(
      failedAttempts: _lock.failedAttempts,
      onUnlock: () => _lock.authenticate(),
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.failedAttempts, required this.onUnlock});

  final int failedAttempts;
  final Future<bool> Function() onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline,
                    size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text('OrbGuard is locked',
                    style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Authenticate to continue.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                if (failedAttempts > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Failed attempts: $failedAttempts',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () => onUnlock(),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
