import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/home/privacy_score_engine.dart';

/// P4.1 — the real-signal 0–1000 privacy score. Every point must map to a
/// genuine signal; unknowns are actions, never assumed safe; new breaches
/// and threats visibly DROP the score.
void main() {
  const engine = PrivacyScoreEngine();

  test('fresh install: low score, and the factor list IS the setup path', () {
    const s = PrivacySignals(guardsAvailable: 5);
    final r = engine.compute(s);

    expect(r.value, 200, reason: 'base only — nothing verified yet');
    expect(r.band, 'Needs work');
    final ids = r.factors.map((f) => f.id).toList();
    expect(ids, contains('run_check'));
    expect(ids, contains('enable_guards'));
    expect(ids, contains('check_breaches'));
    expect(ids, contains('enable_alerts'));
  });

  test('fully protected device reaches a truthful maximum', () {
    const s = PrivacySignals(
      lastScanScore: 92,
      daysSinceScan: 1,
      openThreats: 0,
      guardsActive: 5,
      guardsAvailable: 5,
      breachedAccounts: 0,
      riskyPermissionApps: 0,
      unknownVpnActive: false,
      notificationsGranted: true,
    );
    final r = engine.compute(s);
    expect(r.value, 1000);
    expect(r.band, 'Excellent');
    expect(r.factors, isEmpty);
  });

  test('a new breach DROPS the score and becomes a named action', () {
    const before = PrivacySignals(
      lastScanScore: 92, daysSinceScan: 1, guardsActive: 4, guardsAvailable: 5,
      breachedAccounts: 0, riskyPermissionApps: 0, notificationsGranted: true,
    );
    const after = PrivacySignals(
      lastScanScore: 92, daysSinceScan: 1, guardsActive: 4, guardsAvailable: 5,
      breachedAccounts: 2, riskyPermissionApps: 0, notificationsGranted: true,
    );
    final rb = engine.compute(before);
    final ra = engine.compute(after);
    expect(ra.value, lessThan(rb.value));
    final fix = ra.factors.firstWhere((f) => f.id == 'fix_breaches');
    expect(fix.label, contains('2 breached accounts'));
  });

  test('open threats zero the cleanliness credit and lead the fix list', () {
    const s = PrivacySignals(
      lastScanScore: 30, daysSinceScan: 0, openThreats: 3,
      guardsActive: 5, guardsAvailable: 5,
      breachedAccounts: 0, riskyPermissionApps: 0, notificationsGranted: true,
    );
    final r = engine.compute(s);
    expect(r.factors.first.id, 'resolve_threats',
        reason: 'factors sort by points; threats are worth the most here');
    expect(r.factors.first.label, contains('3 found threats'));
  });

  test('stale scan (>30d) forfeits recency and asks for a fresh check', () {
    const s = PrivacySignals(
      lastScanScore: 92, daysSinceScan: 45, guardsActive: 5, guardsAvailable: 5,
      breachedAccounts: 0, riskyPermissionApps: 0, notificationsGranted: true,
    );
    final r = engine.compute(s);
    expect(r.factors.map((f) => f.id), contains('run_check'));
  });

  test('unknown VPN active deducts and names the review action', () {
    const clean = PrivacySignals(
      lastScanScore: 92, daysSinceScan: 1, guardsActive: 5, guardsAvailable: 5,
      breachedAccounts: 0, riskyPermissionApps: 0,
      unknownVpnActive: false, notificationsGranted: true,
    );
    const vpn = PrivacySignals(
      lastScanScore: 92, daysSinceScan: 1, guardsActive: 5, guardsAvailable: 5,
      breachedAccounts: 0, riskyPermissionApps: 0,
      unknownVpnActive: true, notificationsGranted: true,
    );
    expect(engine.compute(vpn).value, engine.compute(clean).value - 50);
    expect(engine.compute(vpn).factors.map((f) => f.id), contains('review_vpn'));
  });

  test('guard credit prorates by platform availability — iOS is not penalized',
      () {
    // 3 of 3 available guards on (an iOS-like platform)…
    const ios = PrivacySignals(
      lastScanScore: 92, daysSinceScan: 1, guardsActive: 3, guardsAvailable: 3,
      breachedAccounts: 0, riskyPermissionApps: 0, notificationsGranted: true,
    );
    // …scores guard-credit identically to 5 of 5 on Android.
    const android = PrivacySignals(
      lastScanScore: 92, daysSinceScan: 1, guardsActive: 5, guardsAvailable: 5,
      breachedAccounts: 0, riskyPermissionApps: 0, notificationsGranted: true,
    );
    expect(engine.compute(ios).value, engine.compute(android).value);
  });

  test('score is always clamped to 0–1000', () {
    const s = PrivacySignals(unknownVpnActive: true); // base − penalty + nothing
    final r = engine.compute(s);
    expect(r.value, inInclusiveRange(0, 1000));
  });
}
