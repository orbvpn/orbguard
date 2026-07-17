// Live guard states for the home control panel (P4.1).
//
// Each named guard (Spyware watch, Firewall, SMS filter, …) resolves to a
// REAL state from a probe — a permission that's granted, a service that's
// running, a setting that's on. Nothing here is hardcoded "protected":
// a guard is `active` only when its probe verifies it, `actionNeeded` when
// the user can turn it on (the tile becomes the in-context permission ask),
// and `unavailable` when THIS platform genuinely can't offer it (excluded
// from score math — iOS is never penalized for what iOS forbids).
library;

import 'package:flutter/foundation.dart';

enum GuardState { active, actionNeeded, unavailable }

class GuardStatus {
  final String id;
  final String name;
  final GuardState state;

  /// One honest line: what's running, or the specific thing to do.
  final String detail;

  const GuardStatus({
    required this.id,
    required this.name,
    required this.state,
    required this.detail,
  });
}

/// Async probe resolving one guard's real state right now.
typedef GuardProbe = Future<GuardStatus> Function();

/// Aggregates guard probes into the list the home renders and the counts
/// the privacy score consumes. Probes are injected so platforms compose
/// and tests are deterministic.
class GuardStatusController extends ChangeNotifier {
  GuardStatusController({required List<GuardProbe> probes}) : _probes = probes;

  final List<GuardProbe> _probes;
  List<GuardStatus> _guards = const [];
  bool _loading = false;

  List<GuardStatus> get guards => _guards;
  bool get loading => _loading;

  /// Guards verified running now.
  int get activeCount =>
      _guards.where((g) => g.state == GuardState.active).length;

  /// Guards this platform can offer (active + actionNeeded).
  int get availableCount =>
      _guards.where((g) => g.state != GuardState.unavailable).length;

  /// Re-resolve every probe. A probe that throws yields an honest
  /// action-needed row rather than a fake healthy one.
  Future<void> refresh() async {
    _loading = true;
    notifyListeners();

    final results = await Future.wait(_probes.map((p) async {
      try {
        return await p();
      } catch (_) {
        return const GuardStatus(
          id: 'unknown',
          name: 'Protection check',
          state: GuardState.actionNeeded,
          detail: "Couldn't verify — tap to check",
        );
      }
    }));

    _guards = results;
    _loading = false;
    notifyListeners();
  }
}

/// The standard guard set, built from real sources the shell wires in.
/// Every getter is a genuine live read — see each guard's comment for the
/// honest basis of its `active` state.
class GuardProbes {
  /// Daily-checkup guard: active when auto-scan is on.
  static GuardProbe spywareWatch({required Future<bool> Function() autoScanOn}) =>
      () async {
        final on = await autoScanOn();
        return GuardStatus(
          id: 'spyware_watch',
          name: 'Spyware watch',
          state: on ? GuardState.active : GuardState.actionNeeded,
          detail: on ? 'Daily checkup on' : 'Turn on the daily checkup',
        );
      };

  /// Android DNS firewall: active only while the VpnService is enabled.
  /// [supported] false (iOS/desktop v1) → honestly unavailable.
  static GuardProbe firewall({
    required bool supported,
    required Future<bool> Function() enabled,
  }) =>
      () async {
        if (!supported) {
          return const GuardStatus(
            id: 'firewall',
            name: 'Tracker firewall',
            state: GuardState.unavailable,
            detail: 'Not available on this device',
          );
        }
        final on = await enabled();
        return GuardStatus(
          id: 'firewall',
          name: 'Tracker firewall',
          state: on ? GuardState.active : GuardState.actionNeeded,
          detail: on ? 'Blocking surveillance domains' : 'Tap to turn on',
        );
      };

  /// Scam-text filter: active when the SMS permission is genuinely granted
  /// (Android). iOS enablement lives in Settings and can't be queried —
  /// pass [supported] false there rather than pretending.
  static GuardProbe smsFilter({
    required bool supported,
    required Future<bool> Function() granted,
  }) =>
      () async {
        if (!supported) {
          return const GuardStatus(
            id: 'sms_filter',
            name: 'Scam text filter',
            state: GuardState.unavailable,
            detail: 'Not available on this device',
          );
        }
        final ok = await granted();
        return GuardStatus(
          id: 'sms_filter',
          name: 'Scam text filter',
          state: ok ? GuardState.active : GuardState.actionNeeded,
          detail: ok ? 'Screening incoming texts' : 'Allow SMS access to enable',
        );
      };

  /// Threat alerts: active when notification permission is granted.
  static GuardProbe alerts({required Future<bool> Function() granted}) =>
      () async {
        final ok = await granted();
        return GuardStatus(
          id: 'alerts',
          name: 'Instant alerts',
          state: ok ? GuardState.active : GuardState.actionNeeded,
          detail: ok ? 'Armed' : 'Allow notifications to enable',
        );
      };

  /// Breach monitor: active once an address has been checked; a hit count
  /// > 0 stays active (monitoring works!) with the honest detail.
  static GuardProbe breachMonitor(
          {required Future<int?> Function() breachedAccounts}) =>
      () async {
        final hits = await breachedAccounts();
        if (hits == null) {
          return const GuardStatus(
            id: 'breach',
            name: 'Breach monitor',
            state: GuardState.actionNeeded,
            detail: 'Add your email to start watching',
          );
        }
        return GuardStatus(
          id: 'breach',
          name: 'Breach monitor',
          state: GuardState.active,
          detail: hits == 0 ? 'No exposure found' : '$hits account(s) exposed',
        );
      };

  /// Hidden-VPN watch: reflects the latest real check.
  static GuardProbe hiddenVpn({required Future<bool?> Function() unknownVpnActive}) =>
      () async {
        final active = await unknownVpnActive();
        if (active == null) {
          return const GuardStatus(
            id: 'hidden_vpn',
            name: 'Hidden VPN watch',
            state: GuardState.actionNeeded,
            detail: 'Run a check to verify your traffic',
          );
        }
        return GuardStatus(
          id: 'hidden_vpn',
          name: 'Hidden VPN watch',
          state: GuardState.active,
          detail: active ? 'Unknown VPN detected — review it' : 'Traffic looks clean',
        );
      };
}
