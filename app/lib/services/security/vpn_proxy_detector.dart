// Hidden VPN & Proxy detector (Phase 2.3 — "Is your traffic being secretly
// rerouted?").
//
// This service answers one plain question per platform: is an active VPN
// tunnel and/or system proxy sitting between this device and the internet?
// It is grounded ONLY in signals that already exist natively, and it is
// deliberately honest about what each platform cannot see:
//
//   Android — the shared `com.orb.guard/system` scan (`SpywareScanner.scanNetwork`
//     via ConnectivityManager `TRANSPORT_VPN`) tells us definitively whether a
//     VPN tunnel is up. `getInstalledApps` lets us list VPN-capable apps the
//     user has installed (OrbVPN, com.orbvpn.*, is recognised and never
//     flagged). Android does NOT currently expose the system HTTP-proxy setting
//     to this app, and it never tells an app which app owns an active tunnel —
//     both are reported as unknown, not fabricated.
//
//   iOS — the same `scanNetwork` method exposes a real system HTTP-proxy check
//     (`CFNetworkCopySystemProxySettings`). iOS canNOT, from inside the app
//     sandbox, confirm a VPN tunnel or name the app that owns a VPN/proxy, so
//     the tunnel is reported as unknown.
//
//   Desktop (macOS/Windows/Linux) — best-effort: the system proxy is read from
//     the process environment (HTTP(S)_PROXY / ALL_PROXY). Tunnel detection
//     needs a system helper that isn't wired yet, so it is reported as unknown.
//
// Honesty contract (do not weaken):
//   * A "we can't check that here" result is [TriState.unknown]; it never
//     collapses into a reassuring [TriState.no].
//   * We only ever DETECT and GUIDE. We never claim to silently kill or remove
//     another app's VPN.
//   * OrbVPN (package prefix `com.orbvpn.`) is the user's own trusted VPN and is
//     surfaced plainly, never as a threat.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils/platform_info.dart';

/// Tri-state answer. [unknown] means the check could not run on this device —
/// it must never be shown to the user as a clean "no".
enum TriState { yes, no, unknown }

/// Overall verdict for "is my traffic being rerouted?".
enum RerouteVerdict {
  /// A VPN tunnel and/or system proxy is active.
  active,

  /// Every reroute check that could run came back negative.
  clear,

  /// Nothing active was found, but at least one check can't run on this
  /// device — so we cannot honestly promise a clean bill of health.
  inconclusive,

  /// No reroute check is available at all on this platform/build.
  unavailable,
}

/// A VPN-capable app found installed on the device (Android only).
@immutable
class InstalledVpnApp {
  final String packageName;
  final String appName;

  /// True when this is an OrbVPN package (`com.orbvpn.*`) — the user's own,
  /// trusted VPN. Never presented as suspicious.
  final bool isOrbVpn;

  const InstalledVpnApp({
    required this.packageName,
    required this.appName,
    required this.isOrbVpn,
  });

  @override
  bool operator ==(Object other) =>
      other is InstalledVpnApp &&
      other.packageName == packageName &&
      other.appName == appName &&
      other.isOrbVpn == isOrbVpn;

  @override
  int get hashCode => Object.hash(packageName, appName, isOrbVpn);
}

/// Immutable snapshot of a reroute inspection.
@immutable
class VpnProxyStatus {
  final RerouteVerdict verdict;

  /// Whether an active VPN tunnel is present.
  final TriState activeTunnel;

  /// Whether a system proxy is configured/active.
  final TriState systemProxy;

  /// The proxy host, when one is known (desktop env / iOS HTTP proxy).
  final String? proxyHost;

  /// VPN-capable apps installed on the device (Android only; empty elsewhere).
  final List<InstalledVpnApp> installedVpnApps;

  /// Whether this platform can name the app that owns an active tunnel.
  /// False everywhere today — surfaced so the UI never implies otherwise.
  final bool tunnelOwnerIdentifiable;

  /// Human-readable platform name for copy ("This iPhone", "This Mac", …).
  final String platformLabel;

  /// Plain-English list of what could NOT be checked on this device.
  final List<String> limitations;

  /// Set when the whole inspection failed (e.g. native channel missing).
  final String? errorMessage;

  const VpnProxyStatus({
    required this.verdict,
    required this.activeTunnel,
    required this.systemProxy,
    required this.installedVpnApps,
    required this.tunnelOwnerIdentifiable,
    required this.platformLabel,
    required this.limitations,
    this.proxyHost,
    this.errorMessage,
  });

  /// True when OrbVPN is among the installed VPN apps.
  bool get orbVpnInstalled => installedVpnApps.any((a) => a.isOrbVpn);

  /// VPN apps other than OrbVPN.
  List<InstalledVpnApp> get otherVpnApps =>
      installedVpnApps.where((a) => !a.isOrbVpn).toList(growable: false);

  /// True when something is actively rerouting traffic.
  bool get isRerouted => verdict == RerouteVerdict.active;
}

/// Detects active VPN tunnels and system proxies, per platform, from the
/// signals that already exist natively. See file header for the honesty
/// contract.
class VpnProxyDetector {
  /// The shared native scan channel (`SpywareScanner` / AppDelegate handlers).
  static const String channelName = 'com.orb.guard/system';

  /// OrbVPN packages are the user's own, trusted VPN — recognised, never
  /// flagged.
  static const String orbVpnPackagePrefix = 'com.orbvpn.';

  /// Well-known consumer VPN packages, so we recognise them even if their
  /// package/app name doesn't literally contain "vpn". This is a recognition
  /// aid for a soft "VPN apps you have installed" list — never a blocklist.
  static const Set<String> knownVpnPackages = {
    'com.nordvpn.android',
    'com.expressvpn.vpn',
    'com.surfshark.vpnclient.android',
    'ch.protonvpn.android',
    'com.cloudflare.onedotonedotonedotone', // 1.1.1.1 / WARP
    'com.wireguard.android',
    'net.mullvad.mullvadvpn',
    'com.windscribe.vpn',
    'com.tunnelbear.android.tunnelbear',
    'com.privateinternetaccess.android',
    'de.mobileconcepts.cyberghost',
    'com.anchorfree.hotspotshield',
    'hotspotshield.android.vpn',
    'com.atlasvpn.android',
    'com.ixolit.ipvanish',
    'com.avira.vpn',
    'com.avast.android.vpn',
    'com.hidemyass.hidemyassprovpn',
    'com.privatix.android',
    'org.torproject.android', // Orbot (Tor) — also routes traffic
  };

  VpnProxyDetector({
    MethodChannel? channel,
    TargetPlatform? platform,
    Map<String, String>? environment,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _platform = platform ?? defaultTargetPlatform,
        _environment = environment ?? PlatformInfo.environment;

  final MethodChannel _channel;
  final TargetPlatform _platform;
  final Map<String, String> _environment;

  /// Inspect this device for an active VPN tunnel and/or system proxy.
  Future<VpnProxyStatus> detect() async {
    switch (_platform) {
      case TargetPlatform.android:
        return _detectAndroid();
      case TargetPlatform.iOS:
        return _detectIOS();
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return _detectDesktop();
      case TargetPlatform.fuchsia:
        return _unavailable('This device');
    }
  }

  /// Ask the OS to open its VPN settings so the user can review/disconnect a
  /// tunnel themselves. Returns true if a settings screen was opened.
  ///
  /// We only guide — we never disconnect another app's VPN. When the native
  /// `openVpnSettings` method isn't present (it isn't wired yet on any
  /// platform), this returns false and the UI falls back to written steps.
  Future<bool> openSystemVpnSettings() async {
    try {
      final ok = await _channel.invokeMethod<bool>('openVpnSettings');
      return ok ?? true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  // ── Android ────────────────────────────────────────────────────────────

  Future<VpnProxyStatus> _detectAndroid() async {
    List<Map<String, dynamic>> threats;
    List<Map<String, dynamic>> apps;
    try {
      threats = await _invokeList('scanNetwork', 'threats');
      apps = await _invokeList('getInstalledApps', 'apps');
    } on MissingPluginException {
      return _unavailable('This phone',
          error: 'The on-device scan engine is not part of this build '
              '(native channel "$channelName" is not registered).');
    } on PlatformException catch (e) {
      return _unavailable('This phone',
          error: 'The on-device scan could not run: ${e.message ?? e.code}.');
    }

    final tunnel = tunnelFromThreats(threats);
    const proxy = TriState.unknown; // Android proxy read isn't exposed yet.
    final installed = classifyInstalledVpnApps(apps);

    return VpnProxyStatus(
      verdict: verdictFor(tunnel: tunnel, proxy: proxy),
      activeTunnel: tunnel,
      systemProxy: proxy,
      installedVpnApps: installed,
      tunnelOwnerIdentifiable: false,
      platformLabel: 'This phone',
      limitations: const [
        'Android does not let an app read the system HTTP-proxy setting, so a '
            'proxy can’t be confirmed here.',
        'Android never tells an app which VPN app owns an active tunnel.',
      ],
    );
  }

  // ── iOS ────────────────────────────────────────────────────────────────

  Future<VpnProxyStatus> _detectIOS() async {
    List<Map<String, dynamic>> threats;
    try {
      threats = await _invokeList('scanNetwork', 'threats');
    } on MissingPluginException {
      return _unavailable('This iPhone',
          error: 'The on-device scan engine is not part of this build.');
    } on PlatformException catch (e) {
      return _unavailable('This iPhone',
          error: 'The on-device scan could not run: ${e.message ?? e.code}.');
    }

    final proxyResult = proxyFromThreats(threats);
    // iOS can't see a VPN tunnel from inside the sandbox — never inferred.
    const tunnel = TriState.unknown;

    return VpnProxyStatus(
      verdict: verdictFor(tunnel: tunnel, proxy: proxyResult.state),
      activeTunnel: tunnel,
      systemProxy: proxyResult.state,
      proxyHost: proxyResult.host,
      installedVpnApps: const [],
      tunnelOwnerIdentifiable: false,
      platformLabel: 'This iPhone',
      limitations: const [
        'iOS can’t confirm an active VPN tunnel from inside the app.',
        'iOS can’t name which app owns a VPN or proxy.',
        'Only a plain HTTP proxy is visible; encrypted (HTTPS) or auto-config '
            '(PAC) proxies can’t be checked.',
      ],
    );
  }

  // ── Desktop (macOS / Windows / Linux) ───────────────────────────────────

  Future<VpnProxyStatus> _detectDesktop() async {
    final proxyResult = proxyFromEnvironment(_environment);
    const tunnel = TriState.unknown; // Needs a system helper — not wired yet.

    final label = _platform == TargetPlatform.macOS
        ? 'This Mac'
        : _platform == TargetPlatform.windows
            ? 'This PC'
            : 'This computer';

    return VpnProxyStatus(
      verdict: verdictFor(tunnel: tunnel, proxy: proxyResult.state),
      activeTunnel: tunnel,
      systemProxy: proxyResult.state,
      proxyHost: proxyResult.host,
      installedVpnApps: const [],
      tunnelOwnerIdentifiable: false,
      platformLabel: label,
      limitations: const [
        'Desktop VPN-tunnel detection needs a system helper that isn’t '
            'wired up yet.',
        'The proxy check reads environment variables; a proxy set only in '
            'system network settings may not show up here.',
      ],
    );
  }

  // ── Pure, testable helpers ──────────────────────────────────────────────

  /// Whether the Android `scanNetwork` result reports an active VPN tunnel.
  ///
  /// [SpywareScanner.scanNetwork] adds a `type: network` threat with
  /// `path: "VPN"` (name "Active VPN Connection Detected") whenever
  /// ConnectivityManager reports `TRANSPORT_VPN`. Absence is a genuine "no"
  /// because the check always runs on Android; callers on platforms that don't
  /// run this check must pass [TriState.unknown] themselves.
  static TriState tunnelFromThreats(List<Map<String, dynamic>> threats) {
    for (final t in threats) {
      final type = (t['type'] ?? '').toString().toLowerCase();
      if (type != 'network') continue;
      final path = (t['path'] ?? '').toString().toUpperCase();
      final name = (t['name'] ?? '').toString().toLowerCase();
      if (path == 'VPN' || name.contains('vpn')) return TriState.yes;
    }
    return TriState.no;
  }

  /// Whether the iOS `scanNetwork` result reports a system HTTP proxy, plus the
  /// proxy host when present. The AppDelegate handler emits a `type: network`
  /// threat whose id starts `net_proxy` / name contains "proxy", with the host
  /// in `path` (and `metadata.proxy_host`).
  static ({TriState state, String? host}) proxyFromThreats(
      List<Map<String, dynamic>> threats) {
    for (final t in threats) {
      final type = (t['type'] ?? '').toString().toLowerCase();
      if (type != 'network') continue;
      final id = (t['id'] ?? '').toString().toLowerCase();
      final name = (t['name'] ?? '').toString().toLowerCase();
      if (id.startsWith('net_proxy') || name.contains('proxy')) {
        final meta = t['metadata'];
        final metaHost = meta is Map ? meta['proxy_host']?.toString() : null;
        final pathHost = t['path']?.toString();
        final host = (metaHost != null && metaHost.isNotEmpty)
            ? metaHost
            : (pathHost != null && pathHost.isNotEmpty)
                ? pathHost
                : null;
        return (state: TriState.yes, host: host);
      }
    }
    return (state: TriState.no, host: null);
  }

  /// Reads a system proxy from the process environment (desktop). Honest
  /// negative: an empty result means no proxy env var is set (a proxy set only
  /// in system settings won't appear).
  static ({TriState state, String? host}) proxyFromEnvironment(
      Map<String, String> env) {
    const keys = [
      'HTTPS_PROXY',
      'https_proxy',
      'ALL_PROXY',
      'all_proxy',
      'HTTP_PROXY',
      'http_proxy',
    ];
    for (final k in keys) {
      final raw = env[k]?.trim();
      if (raw != null && raw.isNotEmpty) {
        return (state: TriState.yes, host: _prettyProxyHost(raw));
      }
    }
    return (state: TriState.no, host: null);
  }

  static String _prettyProxyHost(String raw) {
    final uri = Uri.tryParse(raw.contains('://') ? raw : 'http://$raw');
    if (uri != null && uri.host.isNotEmpty) {
      return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    }
    return raw;
  }

  /// Filters a raw installed-apps list (from Android `getInstalledApps`) down to
  /// VPN-capable apps. OrbVPN (`com.orbvpn.*`) is marked trusted. Sorted with
  /// OrbVPN first, then alphabetically by app name.
  static List<InstalledVpnApp> classifyInstalledVpnApps(
      List<Map<String, dynamic>> apps) {
    final result = <InstalledVpnApp>[];
    final seen = <String>{};
    for (final a in apps) {
      final pkg = (a['packageName'] ?? '').toString();
      if (pkg.isEmpty || !seen.add(pkg)) continue;
      final name = (a['appName'] ?? pkg).toString();
      final isOrb = pkg.startsWith(orbVpnPackagePrefix);
      final looksVpn = isOrb ||
          knownVpnPackages.contains(pkg) ||
          pkg.toLowerCase().contains('vpn') ||
          name.toLowerCase().contains('vpn');
      if (looksVpn) {
        result.add(InstalledVpnApp(
          packageName: pkg,
          appName: name,
          isOrbVpn: isOrb,
        ));
      }
    }
    result.sort((a, b) {
      if (a.isOrbVpn != b.isOrbVpn) return a.isOrbVpn ? -1 : 1;
      return a.appName.toLowerCase().compareTo(b.appName.toLowerCase());
    });
    return result;
  }

  /// Overall verdict from the tunnel/proxy tri-states. Never invents a "clear"
  /// while a signal is [TriState.unknown].
  static RerouteVerdict verdictFor({
    required TriState tunnel,
    required TriState proxy,
  }) {
    if (tunnel == TriState.yes || proxy == TriState.yes) {
      return RerouteVerdict.active;
    }
    final signals = [tunnel, proxy];
    final anyKnown = signals.any((s) => s != TriState.unknown);
    if (!anyKnown) return RerouteVerdict.unavailable;
    final anyUnknown = signals.any((s) => s == TriState.unknown);
    return anyUnknown ? RerouteVerdict.inconclusive : RerouteVerdict.clear;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> _invokeList(
      String method, String key) async {
    final result = await _channel.invokeMethod(method);
    final raw = (result as Map?)?[key];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) list.add(Map<String, dynamic>.from(item));
      }
    }
    return list;
  }

  VpnProxyStatus _unavailable(String platformLabel, {String? error}) {
    return VpnProxyStatus(
      verdict: RerouteVerdict.unavailable,
      activeTunnel: TriState.unknown,
      systemProxy: TriState.unknown,
      installedVpnApps: const [],
      tunnelOwnerIdentifiable: false,
      platformLabel: platformLabel,
      limitations: const [
        'Hidden VPN & proxy detection isn’t available on this device.',
      ],
      errorMessage: error,
    );
  }
}
