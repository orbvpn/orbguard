import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/home/guard_status_controller.dart';

/// P4.1 — guard states must be REAL: active only when the probe verifies it,
/// unavailable guards excluded from score math, and a failing probe reads as
/// action-needed — never as a fake healthy state.
void main() {
  test('probes resolve to honest states and counts', () async {
    final c = GuardStatusController(probes: [
      GuardProbes.spywareWatch(autoScanOn: () async => true),
      GuardProbes.firewall(supported: true, enabled: () async => false),
      GuardProbes.smsFilter(supported: false, granted: () async => true),
      GuardProbes.alerts(supported: true, granted: () async => true),
      GuardProbes.breachMonitor(breachedAccounts: () async => null),
      GuardProbes.hiddenVpn(unknownVpnActive: () async => false),
    ]);
    await c.refresh();

    final byId = {for (final g in c.guards) g.id: g};
    expect(byId['spyware_watch']!.state, GuardState.active);
    expect(byId['firewall']!.state, GuardState.actionNeeded,
        reason: 'supported but off → the tile is the turn-on ask');
    expect(byId['sms_filter']!.state, GuardState.unavailable,
        reason: 'unsupported platform stays honest even if a permission reads granted');
    expect(byId['alerts']!.state, GuardState.active);
    expect(byId['breach']!.state, GuardState.actionNeeded,
        reason: 'never checked → an ask, not a fake pass');
    expect(byId['hidden_vpn']!.state, GuardState.active);
    // False means nothing unknown that this device can see, not "clean".
    expect(byId['hidden_vpn']!.detail, 'No unknown VPN or proxy seen');

    expect(c.activeCount, 3);
    expect(c.availableCount, 5, reason: 'unavailable guard excluded');
  });

  test('alerts stay unavailable on a platform with no notification backend',
      () async {
    // permission_handler_windows answers "granted" to every query, so a
    // granted permission must NOT be enough to claim alerts are armed —
    // flutter_local_notifications has no Windows implementation to deliver one.
    final c = GuardStatusController(probes: [
      GuardProbes.alerts(supported: false, granted: () async => true),
    ]);
    await c.refresh();
    expect(c.guards.single.state, GuardState.unavailable);
    expect(c.guards.single.detail, isNot(contains('Armed')));
    expect(c.availableCount, 0, reason: 'excluded from the coverage score');
  });

  test('a breach hit keeps the monitor active with the honest detail', () async {
    final c = GuardStatusController(probes: [
      GuardProbes.breachMonitor(breachedAccounts: () async => 2),
    ]);
    await c.refresh();
    expect(c.guards.single.state, GuardState.active,
        reason: 'monitoring IS working — the finding is the value');
    expect(c.guards.single.detail, contains('2'));
  });

  test('an active VPN or proxy is said plainly and asked about, not accused',
      () async {
    final c = GuardStatusController(probes: [
      GuardProbes.hiddenVpn(unknownVpnActive: () async => true),
    ]);
    await c.refresh();
    expect(c.guards.single.state, GuardState.active);
    expect(c.guards.single.detail, 'A VPN or proxy is active. Is it yours?');
  });

  test('where a VPN or proxy cannot be seen at all, the watch is unavailable',
      () async {
    int asked = 0;
    final c = GuardStatusController(probes: [
      GuardProbes.hiddenVpn(
          supported: false,
          unknownVpnActive: () async {
            asked++;
            return null;
          }),
    ]);
    await c.refresh();

    // Not "something to do": nothing the person does would turn it on, so it
    // must not hold the score down either.
    expect(c.guards.single.state, GuardState.unavailable);
    expect(c.guards.single.detail, 'Not available on this device');
    expect(c.availableCount, 0);
    expect(asked, 0);
  });

  test('a throwing probe degrades to action-needed, never fake-healthy',
      () async {
    final c = GuardStatusController(probes: [
      () async => throw StateError('native channel missing'),
    ]);
    await c.refresh();
    expect(c.guards.single.state, GuardState.actionNeeded);
    expect(c.activeCount, 0);
  });
}
