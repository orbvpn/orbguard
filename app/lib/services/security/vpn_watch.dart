// The Hidden VPN & proxy signal for Home: "is something rerouting this
// device's traffic that the person does not know about?"
//
// [VpnProxyDetector] can say THAT a tunnel or proxy is active, never WHOSE it
// is (Android hides the tunnel's owner; iPhone and desktop only see a proxy
// host). Many people run a VPN on purpose, so flagging every active tunnel on
// the first screen would be a false alarm for most of them. OrbGuard asks
// once ("This VPN is mine") and remembers the answer for as long as it can
// tell it is still the same thing.
//
// The memory rule (do not loosen it without a reason a person could check):
//
//   * A tunnel (Android). Nothing identifies a tunnel, so "mine" covers the
//     tunnel that is up now and is cleared as soon as a check sees no tunnel,
//     or sees that the tunnel is OrbGuard's own firewall (Android runs one
//     VPN at a time, so the person's VPN is not up then). The next tunnel
//     asks again.
//   * A proxy whose host is known (iPhone, desktop). "Mine" covers that host.
//     It is kept while the proxy comes and goes (a Wi-Fi proxy disappears on
//     mobile data and comes back), and a proxy at a DIFFERENT host asks again.
//   * A proxy whose host is not known. Treated like a tunnel: cleared once a
//     check sees no proxy.
//   * Whether a tunnel is OrbGuard's own firewall: the Android scan's live
//     native flag (`ownFirewall` on the tunnel entry) decides when present;
//     the `ownFirewallOn` parameter decides only when it is absent (older
//     native build). So a stale Dart flag cannot hide another VPN.
//   * A tunnel that is not the firewall, with the GENUINE OrbVPN installed
//     (signing certificate checked natively): treated as the person's own,
//     with nothing to ask. A product decision kept from the native code;
//     Android cannot say which app runs the tunnel, and the screen says so.
//   * A check that fails or cannot run says nothing about what is active, so
//     it never clears the answer and its result is null, never false.
//   * Something new appearing next to what was answered (a proxy beside an
//     answered tunnel) asks again; the answer only covers what was active
//     when it was given.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vpn_proxy_detector.dart';

class VpnWatch extends ChangeNotifier {
  VpnWatch({
    VpnProxyDetector? detector,
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? clock,
  })  : detector = detector ?? VpnProxyDetector(),
        _prefs = prefs ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now;

  /// The one watch the app shares: Home reads it, the Hidden VPN & proxy
  /// screen answers it, so both always agree.
  static final VpnWatch shared = VpnWatch();

  /// How long a scan answers for before it runs again.
  static const Duration cacheFor = Duration(minutes: 10);

  static const String _prefsKey = 'vpn_watch_mine';

  /// The detector behind the answers (also used to open VPN settings).
  final VpnProxyDetector detector;
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;

  VpnProxyStatus? _lastStatus;
  DateTime? _lastScanAt;
  Future<VpnProxyStatus?>? _inFlight;
  bool? _lastOwnFirewallOn;

  _Mine? _mine;
  bool _mineLoaded = false;

  /// The status behind the last answer, for the screen. When a check threw,
  /// this is an honest "could not check" status, not the previous scan.
  VpnProxyStatus? get lastStatus => _lastStatus;

  /// The `ownFirewallOn` given with the last answer, or null before any.
  bool? get lastOwnFirewallOn => _lastOwnFirewallOn;

  /// Whether the tunnel in [lastStatus] was taken to be OrbGuard's own
  /// firewall (the native fact when the scan carried it, else the
  /// parameter). False when no tunnel was seen.
  bool get lastTunnelIsOwnFirewall {
    final s = _lastStatus;
    if (s == null || s.activeTunnel != TriState.yes) return false;
    return _firewallFor(s, _lastOwnFirewallOn ?? false);
  }

  /// Whether the tunnel in [lastStatus] was treated as the person's own
  /// because the genuine OrbVPN is installed and the tunnel is not the
  /// firewall. False when no tunnel was seen or that is not known.
  bool get lastTunnelTreatedAsOrbVpn {
    final s = _lastStatus;
    if (s == null || s.activeTunnel != TriState.yes) return false;
    return _orbVpnFor(s, _lastOwnFirewallOn ?? false);
  }

  /// The native fact decides; the parameter only fills in when it is absent.
  static bool _firewallFor(VpnProxyStatus s, bool param) =>
      s.tunnelIsOwnFirewall ?? param;

  static bool _orbVpnFor(VpnProxyStatus s, bool param) =>
      !_firewallFor(s, param) && s.genuineOrbVpnInstalled == true;

  /// The latest answer for Home.
  ///   null  : the check could not run on this device or build, so nothing is known
  ///   false : nothing is rerouting traffic as far as this device lets OrbGuard see,
  ///           or what is active is OrbGuard's own firewall, or the person said it is theirs
  ///   true  : a tunnel or proxy is active and the person has not said it is theirs
  ///
  /// [ownFirewallOn] is used only when the scan does not carry the native
  /// `ownFirewall` fact (an older Android build); then it must be whether
  /// OrbGuard's firewall VPN service is running now, not merely switched on.
  Future<bool?> unknownVpnActive({
    required bool ownFirewallOn,
    bool force = false,
  }) async {
    _lastOwnFirewallOn = ownFirewallOn;
    await _loadMine();

    final cached = _lastStatus;
    final at = _lastScanAt;
    final fresh = force ||
        cached == null ||
        at == null ||
        _clock().difference(at) >= cacheFor;

    VpnProxyStatus? status;
    if (fresh) {
      status =
          await (_inFlight ??= _scan().whenComplete(() => _inFlight = null));
    } else {
      status = cached;
    }

    bool? answer;
    if (status != null && status.verdict != RerouteVerdict.unavailable) {
      if (_forgetWhatIsGone(status, ownFirewallOn: ownFirewallOn)) {
        await _saveMine();
      }
      answer = _uncovered(status, ownFirewallOn: ownFirewallOn);
    }
    _notifyIfChanged(answer);
    return answer;
  }

  // What listeners last heard about, so a listener that asks again does not
  // loop: only a change in the answer or in what was seen notifies.
  String? _heard;

  void _notifyIfChanged(bool? answer) {
    final s = _lastStatus;
    final now = '$answer|${s?.verdict}|${s?.activeTunnel}|${s?.systemProxy}|'
        '${s?.proxyHost}|${_mine?.toJson()}';
    if (now == _heard) return;
    _heard = now;
    notifyListeners();
  }

  /// The person said the VPN or proxy now active is theirs. Does nothing
  /// when the last check saw nothing active.
  Future<void> markAsMine() async {
    await _loadMine();
    final s = _lastStatus;
    if (s == null || !s.isRerouted) return;
    final firewall = _firewallFor(s, _lastOwnFirewallOn ?? false);
    final tunnel = s.activeTunnel == TriState.yes && !firewall;
    final proxy = s.systemProxy == TriState.yes;
    if (!tunnel && !proxy) return;
    _mine = _Mine(
      tunnel: tunnel || (_mine?.tunnel ?? false),
      proxy: proxy || (_mine?.proxy ?? false),
      proxyHost: proxy ? s.proxyHost : _mine?.proxyHost,
      at: _clock(),
    );
    await _saveMine();
    notifyListeners();
  }

  /// They took that back.
  Future<void> forgetMine() async {
    await _loadMine();
    _mine = null;
    await _saveMine();
    notifyListeners();
  }

  /// True when the last check saw something active and every active thing
  /// is covered by the person's answer. False when nothing is active now,
  /// since there is nothing for the answer to be about.
  Future<bool> get saidItIsMine async {
    await _loadMine();
    final s = _lastStatus;
    final mine = _mine;
    if (s == null || mine == null || !s.isRerouted) return false;
    final tunnelActive = s.activeTunnel == TriState.yes;
    final proxyActive = s.systemProxy == TriState.yes;
    final param = _lastOwnFirewallOn ?? false;
    final firewall = _firewallFor(s, param);
    final orbVpn = _orbVpnFor(s, param);
    final tunnelOk = !tunnelActive || mine.tunnel || firewall || orbVpn;
    final proxyOk = !proxyActive || _proxyCovered(mine, s);
    // Only "theirs" when the answer covers at least one active thing.
    final anyByAnswer = (tunnelActive && mine.tunnel && !firewall && !orbVpn) ||
        (proxyActive && _proxyCovered(mine, s));
    return tunnelOk && proxyOk && anyByAnswer;
  }

  // ── Internals ───────────────────────────────────────────────────────────

  Future<VpnProxyStatus?> _scan() async {
    try {
      final s = await detector.detect();
      _lastStatus = s;
      _lastScanAt = _clock();
      return s;
    } catch (e) {
      debugPrint('VpnWatch: check failed: $e');
      // Not cached: the next ask tries again.
      _lastScanAt = null;
      _lastStatus = VpnProxyStatus(
        verdict: RerouteVerdict.unavailable,
        activeTunnel: TriState.unknown,
        systemProxy: TriState.unknown,
        installedVpnApps: const [],
        tunnelOwnerIdentifiable: false,
        platformLabel: _lastStatus?.platformLabel ?? 'This device',
        limitations: const [
          'The check could not finish just now, so nothing is known yet.',
        ],
        errorMessage: 'Try the check again in a moment.',
      );
      return null;
    }
  }

  bool _proxyCovered(_Mine mine, VpnProxyStatus s) =>
      mine.proxy && mine.proxyHost == s.proxyHost;

  /// True when something is active that neither the firewall nor the
  /// person's answer covers.
  bool _uncovered(VpnProxyStatus s, {required bool ownFirewallOn}) {
    final mine = _mine;
    final tunnelActive = s.activeTunnel == TriState.yes;
    final proxyActive = s.systemProxy == TriState.yes;
    if (!tunnelActive && !proxyActive) return false;
    final tunnelOk = !tunnelActive ||
        _firewallFor(s, ownFirewallOn) ||
        _orbVpnFor(s, ownFirewallOn) ||
        (mine?.tunnel ?? false);
    final proxyOk = !proxyActive || (mine != null && _proxyCovered(mine, s));
    return !(tunnelOk && proxyOk);
  }

  /// Applies the memory rule to a real scan. Returns true when the stored
  /// answer changed.
  bool _forgetWhatIsGone(VpnProxyStatus s, {required bool ownFirewallOn}) {
    final mine = _mine;
    if (mine == null) return false;
    var tunnel = mine.tunnel;
    var proxy = mine.proxy;
    if (tunnel &&
        (s.activeTunnel == TriState.no ||
            (s.activeTunnel == TriState.yes &&
                _firewallFor(s, ownFirewallOn)))) {
      tunnel = false;
    }
    if (proxy && mine.proxyHost == null && s.systemProxy == TriState.no) {
      proxy = false;
    }
    if (tunnel == mine.tunnel && proxy == mine.proxy) return false;
    _mine = (tunnel || proxy)
        ? _Mine(
            tunnel: tunnel,
            proxy: proxy,
            proxyHost: proxy ? mine.proxyHost : null,
            at: mine.at)
        : null;
    return true;
  }

  Future<void> _loadMine() async {
    if (_mineLoaded) return;
    _mineLoaded = true;
    try {
      final raw = (await _prefs()).getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      _mine = _Mine.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('VpnWatch: could not read the saved answer: $e');
    }
  }

  Future<void> _saveMine() async {
    try {
      final prefs = await _prefs();
      final mine = _mine;
      if (mine == null) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, jsonEncode(mine.toJson()));
      }
    } catch (e) {
      debugPrint('VpnWatch: could not save the answer: $e');
    }
  }
}

/// What the person said is theirs.
@immutable
class _Mine {
  final bool tunnel;
  final bool proxy;
  final String? proxyHost;
  final DateTime at;

  const _Mine({
    required this.tunnel,
    required this.proxy,
    required this.proxyHost,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'tunnel': tunnel,
        'proxy': proxy,
        if (proxyHost != null) 'proxy_host': proxyHost,
        'at': at.toIso8601String(),
      };

  factory _Mine.fromJson(Map<String, dynamic> json) => _Mine(
        tunnel: json['tunnel'] as bool? ?? false,
        proxy: json['proxy'] as bool? ?? false,
        proxyHost: json['proxy_host'] as String?,
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime(1970),
      );
}
