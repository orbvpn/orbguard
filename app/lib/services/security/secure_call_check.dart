// Secure Call Check — the HONEST "is someone listening to my calls?" check.
//
// ── Honesty contract (read before editing) ─────────────────────────────────
// NO app — including OrbGuard — can read, decrypt, or detect eavesdropping
// INSIDE another app's VoIP call (WhatsApp / Signal / Telegram / WeChat) or a
// cellular call. End-to-end encryption and the OS app sandbox make that
// impossible. This code NEVER touches call audio or message content and never
// claims a call is "tapped" or "being monitored".
//
// What it DOES: it inspects THIS device for the conditions an eavesdropper
// would need first — screen recording/mirroring, traffic interception (system
// proxy / user-installed certificate authority), screen-reading accessibility
// services, jailbreak/root, and (informational) which apps can reach the
// microphone. Every check is grounded in a real signal the native
// `com.orb.guard/system` channel already exposes (see AppDelegate.swift /
// MainActivity.kt). Where the OS gives an app NO way to see a condition, the
// check reports [CallCheckStatus.unavailable] ("not available on this
// platform") — never a fabricated "clean".
//
// All native methods used already exist; no new native code is required.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of a single device-posture check.
enum CallCheckStatus {
  /// Checked, and the eavesdropping-enabling condition is absent.
  clear,

  /// Checked, and a condition that could enable eavesdropping is present.
  warning,

  /// Checked; neutral transparency (e.g. apps that hold microphone access).
  /// Never on its own a reason to distrust the device.
  info,

  /// The OS does not let an app see this condition on this platform.
  unavailable,

  /// The check should have run here but the native call failed.
  error,
}

/// The specific conditions this feature inspects.
enum CallCheckId {
  screenCapture,
  accessibilityServices,
  trafficProxy,
  hostileCerts,
  jailbreakRoot,
  appTampering,
  microphoneApps,
}

/// The overall device posture for holding a private call.
enum CallPostureVerdict {
  /// At least one check ran and none raised a warning.
  clean,

  /// One or more checks found a condition that could enable eavesdropping.
  warnings,

  /// Nothing could actually be checked here (wrong platform / native bridge
  /// missing) — we honestly say so rather than imply "safe".
  cannotCheck,
}

/// One line of the device posture report.
@immutable
class SecureCallCheckItem {
  final CallCheckId id;

  /// Short human title, e.g. "Screen recording or mirroring".
  final String title;

  /// The plain-English question this check answers.
  final String question;

  final CallCheckStatus status;

  /// Human-readable result / explanation for this row.
  final String detail;

  /// Specifics behind a warning/info (app names, proxy host, cert names…).
  final List<String> findings;

  /// `'high'` or `'medium'` when [status] is [CallCheckStatus.warning].
  final String? severity;

  const SecureCallCheckItem({
    required this.id,
    required this.title,
    required this.question,
    required this.status,
    required this.detail,
    this.findings = const [],
    this.severity,
  });

  bool get isWarning => status == CallCheckStatus.warning;
  bool get isHigh => severity == 'high';
}

/// The full device posture, aggregated from every check.
@immutable
class SecureCallPosture {
  final List<SecureCallCheckItem> items;
  final DateTime checkedAt;

  const SecureCallPosture({required this.items, required this.checkedAt});

  Iterable<SecureCallCheckItem> get warnings => items.where((i) => i.isWarning);

  int get warningCount => warnings.length;

  bool get anyWarning => warnings.isNotEmpty;

  /// True when at least one check produced a real result (clear/warning/info).
  bool get anyRan => items.any((i) =>
      i.status == CallCheckStatus.clear ||
      i.status == CallCheckStatus.warning ||
      i.status == CallCheckStatus.info);

  /// True when any active warning is high severity (drives the alert color).
  bool get anyHighSeverity => warnings.any((w) => w.isHigh);

  CallPostureVerdict get verdict {
    if (anyWarning) return CallPostureVerdict.warnings;
    if (anyRan) return CallPostureVerdict.clean;
    return CallPostureVerdict.cannotCheck;
  }
}

/// Result-or-error wrapper for one native fetch, so a failed bridge call
/// becomes an honest [CallCheckStatus.error] row instead of a false "clean".
class _Fetch<T> {
  final T? data;
  final String? error;
  const _Fetch.ok(this.data) : error = null;
  const _Fetch.fail(this.error) : data = null;
  bool get failed => error != null;
}

/// Runs the Secure Call device-posture check.
///
/// [channel] and [platformOverride] exist for testing; production code uses the
/// real `com.orb.guard/system` channel and the actual [defaultTargetPlatform].
class SecureCallCheck {
  SecureCallCheck({MethodChannel? channel, TargetPlatform? platformOverride})
      : _channel = channel ?? const MethodChannel('com.orb.guard/system'),
        _platformOverride = platformOverride;

  final MethodChannel _channel;
  final TargetPlatform? _platformOverride;

  TargetPlatform get _platform => _platformOverride ?? defaultTargetPlatform;
  bool get _isIOS => !kIsWeb && _platform == TargetPlatform.iOS;
  bool get _isAndroid => !kIsWeb && _platform == TargetPlatform.android;

  /// Title + plain-English question for each check.
  static const Map<CallCheckId, (String, String)> _meta = {
    CallCheckId.screenCapture: (
      'Screen recording or mirroring',
      'Is your screen being recorded or shared right now?',
    ),
    CallCheckId.accessibilityServices: (
      'Screen-reading accessibility',
      'Can another app read your screen through Accessibility?',
    ),
    CallCheckId.trafficProxy: (
      'Network traffic interception',
      'Is your internet being routed somewhere that could read it?',
    ),
    CallCheckId.hostileCerts: (
      'Untrusted security certificates',
      'Was a certificate added that could unlock your encrypted traffic?',
    ),
    CallCheckId.jailbreakRoot: (
      'Jailbreak or root access',
      "Have the phone's built-in protections been removed?",
    ),
    CallCheckId.appTampering: (
      'App tampering',
      'Is anything hooking into or debugging this app?',
    ),
    CallCheckId.microphoneApps: (
      'Apps that can use the microphone',
      'Which apps have permission to hear your microphone?',
    ),
  };

  /// Run every applicable check and aggregate the device posture.
  Future<SecureCallPosture> run() async {
    final List<SecureCallCheckItem> items;
    if (_isIOS) {
      items = await _runIos();
    } else if (_isAndroid) {
      items = await _runAndroid();
    } else {
      items = _runUnsupportedPlatform();
    }
    return SecureCallPosture(items: items, checkedAt: DateTime.now());
  }

  // ── iOS ────────────────────────────────────────────────────────────────
  // A sandboxed iOS app can inspect its own runtime + device posture (screen
  // capture, MITM proxy, injected dylibs, debugger, jailbreak) but CANNOT
  // enumerate other apps, the certificate store, or accessibility services.

  Future<List<SecureCallCheckItem>> _runIos() async {
    // scanProcesses feeds BOTH the screen-capture and tampering checks — fetch
    // it once. Each threat is tagged by an `id` prefix in AppDelegate.swift.
    final proc = await _fetchList('scanProcesses', 'threats');
    final net = await _fetchList('scanNetwork', 'threats');
    final mem = await _fetchList('scanMemory', 'threats');
    final root = await _fetchMap('checkRootAccess');

    return [
      _iosScreenCapture(proc),
      _unavailable(
        CallCheckId.accessibilityServices,
        'iOS has no screen-reading accessibility services that an app can '
        'enumerate, so there is nothing to check on iPhone.',
      ),
      _iosProxy(net),
      _unavailable(
        CallCheckId.hostileCerts,
        "iOS doesn't let apps read the certificate store, so this can't be "
        'checked on iPhone.',
      ),
      _rootItem(root, ios: true),
      _iosTampering(proc, mem),
      _unavailable(
        CallCheckId.microphoneApps,
        "iOS doesn't let apps list other apps. Review microphone access in "
        'Settings > Privacy & Security > Microphone.',
      ),
    ];
  }

  SecureCallCheckItem _iosScreenCapture(_Fetch<List<Map<String, dynamic>>> f) {
    const id = CallCheckId.screenCapture;
    if (f.failed) return _error(id, f.error!);
    final hits = f.data!.where((t) => _idHas(t, 'proc_screencapture_'));
    if (hits.isEmpty) {
      return _clear(id, 'No screen recording or mirroring is active.');
    }
    return _warn(
      id,
      'medium',
      'Your screen is being recorded or mirrored right now. Anything on '
      'screen during a call can be seen. If you did not start a recording or '
      'AirPlay session, stop it before you talk.',
      const [],
    );
  }

  SecureCallCheckItem _iosProxy(_Fetch<List<Map<String, dynamic>>> f) {
    const id = CallCheckId.trafficProxy;
    if (f.failed) return _error(id, f.error!);
    final hits = f.data!.where((t) => _idHas(t, 'net_proxy_')).toList();
    if (hits.isEmpty) {
      return _clear(id, 'No interception proxy is configured.');
    }
    final hosts =
        hits.map((t) => (t['path'] ?? t['name'] ?? 'proxy').toString()).toList();
    return _warn(
      id,
      'medium',
      "A proxy is routing this device's web traffic and could intercept it. "
      'If you did not set it up, remove it in Settings.',
      hosts,
    );
  }

  SecureCallCheckItem _iosTampering(
    _Fetch<List<Map<String, dynamic>>> proc,
    _Fetch<List<Map<String, dynamic>>> mem,
  ) {
    const id = CallCheckId.appTampering;
    if (proc.failed && mem.failed) return _error(id, proc.error!);
    final hits = <Map<String, dynamic>>[
      if (!proc.failed) ...proc.data!.where((t) => _idHas(t, 'proc_inject_')),
      if (!mem.failed)
        ...mem.data!
            .where((t) => _idHas(t, 'mem_debugger_') || _idHas(t, 'mem_dyld_')),
    ];
    if (hits.isEmpty) {
      return _clear(id, 'No code injection or debugger detected.');
    }
    final names =
        hits.map((t) => (t['name'] ?? t['type'] ?? 'tampering').toString());
    return _warn(
      id,
      'high',
      'Code injection or a debugger is attached to this app — a sign the '
      'device is compromised or the app was tampered with.',
      names.toList(),
    );
  }

  // ── Android ──────────────────────────────────────────────────────────────
  // Android can enumerate accessibility services, the user certificate store
  // and installed apps' permissions, but gives an app no reliable global
  // "is my screen being captured" signal and no system-proxy read here.

  Future<List<SecureCallCheckItem>> _runAndroid() async {
    final a11y = await _fetchList('getEnabledAccessibilityServices', 'services');
    final certs = await _fetchList('getInstalledCertificates', 'certificates');
    final apps = await _fetchList('getInstalledApps', 'apps');
    final root = await _fetchMap('checkRootAccess');

    return [
      _unavailable(
        CallCheckId.screenCapture,
        "Android doesn't let an app tell whether the whole screen is being "
        'captured, so this can only be checked on iPhone.',
      ),
      _androidAccessibility(a11y),
      _unavailable(
        CallCheckId.trafficProxy,
        "OrbGuard can't read the system proxy on Android — the certificate "
        'check below covers HTTPS interception.',
      ),
      _androidCerts(certs),
      _rootItem(root, ios: false),
      _unavailable(
        CallCheckId.appTampering,
        'This runtime tamper check is iPhone-only; on Android the root check '
        'above covers device integrity.',
      ),
      _androidMicApps(apps),
    ];
  }

  SecureCallCheckItem _androidAccessibility(
      _Fetch<List<Map<String, dynamic>>> f) {
    const id = CallCheckId.accessibilityServices;
    if (f.failed) return _error(id, f.error!);
    final foreign = f.data!.where((s) {
      final pkg = (s['packageName'] ?? '').toString();
      return pkg.isNotEmpty && !_isOwnOrSafeA11y(pkg);
    }).toList();
    if (foreign.isEmpty) {
      return _clear(id, 'No third-party accessibility services are enabled.');
    }
    final names = foreign
        .map((s) => (s['appName'] ?? s['packageName']).toString())
        .toSet()
        .toList();
    return _warn(
      id,
      'high',
      'An app is using Accessibility, which can read everything on your '
      "screen — including during a call. Turn it off if you don't recognise "
      'it.',
      names,
    );
  }

  SecureCallCheckItem _androidCerts(_Fetch<List<Map<String, dynamic>>> f) {
    const id = CallCheckId.hostileCerts;
    if (f.failed) return _error(id, f.error!);
    final userCerts =
        f.data!.where((c) => c['isUserInstalled'] == true).toList();
    if (userCerts.isEmpty) {
      return _clear(id, 'No user-installed certificate authorities found.');
    }
    final names = userCerts.map(_certLabel).toList();
    return _warn(
      id,
      'high',
      'A user-installed certificate authority can let its owner decrypt your '
      'HTTPS traffic. If your workplace manages this phone this can be '
      'expected — otherwise remove it in Settings > Security.',
      names,
    );
  }

  SecureCallCheckItem _androidMicApps(_Fetch<List<Map<String, dynamic>>> f) {
    const id = CallCheckId.microphoneApps;
    if (f.failed) return _error(id, f.error!);
    final micApps = f.data!.where((a) {
      if (a['isSystemApp'] == true) return false;
      final perms = a['permissions'];
      return perms is List &&
          perms.any((p) => p.toString().contains('RECORD_AUDIO'));
    }).toList();
    if (micApps.isEmpty) {
      return _clear(id, 'No installed apps request microphone access.');
    }
    final names = micApps
        .map((a) => (a['appName'] ?? a['packageName']).toString())
        .toList()
      ..sort();
    final n = names.length;
    return _info(
      id,
      '$n app${n == 1 ? '' : 's'} can use the microphone. This is normal for '
      "calls, messaging and voice apps — review anything you don't recognise.",
      names,
    );
  }

  // ── Shared ───────────────────────────────────────────────────────────────

  SecureCallCheckItem _rootItem(_Fetch<Map<String, dynamic>> f,
      {required bool ios}) {
    const id = CallCheckId.jailbreakRoot;
    if (f.failed) return _error(id, f.error!);
    final hasRoot = f.data!['hasRoot'] == true;
    if (!hasRoot) {
      return _clear(id,
          ios ? 'Your iPhone is not jailbroken.' : 'Your device is not rooted.');
    }
    final word = ios ? 'jailbroken' : 'rooted';
    return _warn(
      id,
      'high',
      'Your device appears to be $word. This removes the sandbox that stops '
      'other apps from reading your data, including your calls.',
      const [],
    );
  }

  List<SecureCallCheckItem> _runUnsupportedPlatform() {
    const reason =
        'This device check runs on iPhone and Android, not on this platform.';
    return CallCheckId.values.map((id) => _unavailable(id, reason)).toList();
  }

  // ── Native fetch helpers ────────────────────────────────────────────────

  Future<_Fetch<List<Map<String, dynamic>>>> _fetchList(
      String method, String key) async {
    try {
      final res = await _channel.invokeMethod(method);
      final raw = (res as Map?)?[key];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      }
      return _Fetch.ok(list);
    } catch (e) {
      return _Fetch.fail(_reason(e));
    }
  }

  Future<_Fetch<Map<String, dynamic>>> _fetchMap(String method) async {
    try {
      final res = await _channel.invokeMethod(method);
      return _Fetch.ok(
          res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{});
    } catch (e) {
      return _Fetch.fail(_reason(e));
    }
  }

  static String _reason(Object e) {
    if (e is MissingPluginException) {
      return 'the device-check bridge is not part of this build';
    }
    if (e is PlatformException) {
      return e.message ?? e.code;
    }
    return e.toString();
  }

  // ── Small pure helpers ──────────────────────────────────────────────────

  static bool _idHas(Map<String, dynamic> threat, String prefix) =>
      (threat['id'] as String?)?.startsWith(prefix) ?? false;

  static const List<String> _safeA11y = [
    'com.google.android.marvin.talkback',
    'com.google.android.talkback',
    'com.android.talkback',
  ];

  static bool _isOwnOrSafeA11y(String pkg) =>
      pkg == 'com.orb.guard' ||
      pkg.startsWith('com.android.') ||
      pkg.startsWith('com.google.android.') ||
      _safeA11y.contains(pkg);

  /// Prefer the certificate's CN; fall back to the full subject/alias.
  static String _certLabel(Map<String, dynamic> c) {
    final subject =
        (c['subjectDN'] ?? c['subject'] ?? c['alias'] ?? 'Unknown certificate')
            .toString();
    final cn = RegExp('CN=([^,]+)').firstMatch(subject)?.group(1);
    return cn?.trim() ?? subject;
  }

  // ── Item constructors ───────────────────────────────────────────────────

  SecureCallCheckItem _make(
    CallCheckId id,
    CallCheckStatus status,
    String detail, {
    List<String> findings = const [],
    String? severity,
  }) {
    final m = _meta[id]!;
    return SecureCallCheckItem(
      id: id,
      title: m.$1,
      question: m.$2,
      status: status,
      detail: detail,
      findings: findings,
      severity: severity,
    );
  }

  SecureCallCheckItem _clear(CallCheckId id, String detail) =>
      _make(id, CallCheckStatus.clear, detail);

  SecureCallCheckItem _warn(CallCheckId id, String severity, String detail,
          List<String> findings) =>
      _make(id, CallCheckStatus.warning, detail,
          findings: findings, severity: severity);

  SecureCallCheckItem _info(
          CallCheckId id, String detail, List<String> findings) =>
      _make(id, CallCheckStatus.info, detail, findings: findings);

  SecureCallCheckItem _unavailable(CallCheckId id, String reason) =>
      _make(id, CallCheckStatus.unavailable, reason);

  SecureCallCheckItem _error(CallCheckId id, String why) =>
      _make(id, CallCheckStatus.error, "Couldn't run this check: $why");
}
