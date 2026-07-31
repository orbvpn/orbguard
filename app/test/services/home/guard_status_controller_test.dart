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
    expect(byId['hidden_vpn']!.detail, contains('clean'));

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

  test('a detected unknown VPN reads active-with-warning, not silent', () async {
    final c = GuardStatusController(probes: [
      GuardProbes.hiddenVpn(unknownVpnActive: () async => true),
    ]);
    await c.refresh();
    expect(c.guards.single.detail.toLowerCase(), contains('review'));
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
