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

  group('the seven rules behind the number', () {
    const PrivacySignals whole = PrivacySignals(
      daysSinceScan: 1,
      guardsActive: 5,
      guardsAvailable: 5,
      breachedAccounts: 0,
      riskyPermissionApps: 0,
      unknownVpnActive: false,
      notificationsGranted: true,
    );

    test('are the rubric, in order, with their ceilings', () {
      final PrivacyScore r = engine.compute(whole);

      expect(r.rules.map((x) => x.id), [
        'installed',
        'recent',
        'clean',
        'shields',
        'breach',
        'alerts',
        'audit'
      ]);
      expect(r.rules.map((x) => x.max), [200, 200, 150, 250, 100, 50, 50]);
      expect(r.rules.map((x) => x.label), [
        'OrbGuard is installed',
        'Checked in the last 7 days',
        'No spyware found in your last check',
        'Shields are on',
        'No breached accounts',
        'Alerts can reach you',
        'No apps with spyware-style access',
      ]);
      expect(r.rules.every((x) => x.earned == x.max), isTrue);
      expect(r.penalty, 0);
    });

    test('always add up to the score, less the penalty', () {
      const List<PrivacySignals> cases = [
        PrivacySignals(guardsAvailable: 5),
        whole,
        PrivacySignals(
            daysSinceScan: 12,
            openThreats: 2,
            guardsActive: 2,
            guardsAvailable: 5,
            breachedAccounts: 1,
            riskyPermissionApps: 3,
            unknownVpnActive: true),
        PrivacySignals(
            daysSinceScan: 40,
            guardsActive: 3,
            guardsAvailable: 4,
            appAuditPossible: false,
            alertsPossible: false),
      ];
      for (final PrivacySignals s in cases) {
        final PrivacyScore r = engine.compute(s);
        final int sum = r.rules.fold(0, (a, x) => a + x.earned);
        expect(r.value, sum - r.penalty);
        for (final ScoreRule x in r.rules) {
          expect(x.earned, inInclusiveRange(0, x.max), reason: x.id);
        }
      }
    });

    test('a rule with points missing names the fix that earns them', () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          openThreats: 1,
          guardsActive: 2,
          guardsAvailable: 5,
          breachedAccounts: 1,
          riskyPermissionApps: 2));

      String? fix(String id) => r.rules.firstWhere((x) => x.id == id).factorId;
      expect(fix('installed'), isNull);
      expect(fix('recent'), isNull);
      expect(fix('clean'), 'resolve_threats');
      expect(fix('shields'), 'enable_guards');
      expect(fix('breach'), 'fix_breaches');
      expect(fix('alerts'), 'enable_alerts');
      expect(fix('audit'), 'review_apps');
    });

    test('apps to review cost the audit points, not the spyware points', () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          guardsActive: 5,
          guardsAvailable: 5,
          breachedAccounts: 0,
          riskyPermissionApps: 2,
          notificationsGranted: true));

      expect(r.value, 950);
      expect(r.rules.firstWhere((x) => x.id == 'clean').earned, 150);
      expect(r.rules.firstWhere((x) => x.id == 'audit').earned, 0);
      expect(r.factors.single.id, 'review_apps');
      expect(r.factors.single.points, 50);
    });

    test('spyware found costs the spyware points and nothing else', () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          openThreats: 1,
          guardsActive: 5,
          guardsAvailable: 5,
          breachedAccounts: 0,
          riskyPermissionApps: 0,
          notificationsGranted: true));

      expect(r.value, 850);
      expect(r.factors.single.id, 'resolve_threats');
      expect(r.factors.single.points, 150);
    });

    // A firewall that is off, or apps with no signature: something to fix,
    // not a sign of spyware.
    test('minor findings cost fifty of the spyware points', () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          openThreats: 1,
          minorThreatsOnly: true,
          guardsActive: 5,
          guardsAvailable: 5,
          breachedAccounts: 0,
          riskyPermissionApps: 0,
          notificationsGranted: true));

      expect(r.value, 950);
      expect(r.rules.firstWhere((x) => x.id == 'clean').earned, 100);
      expect(r.factors.single.id, 'resolve_threats');
      expect(r.factors.single.points, 50);
      expect(r.factors.single.label, 'Fix 1 thing your check found');
    });

    test('an iPhone is given the audit points, and the rule says so', () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          guardsActive: 3,
          guardsAvailable: 3,
          breachedAccounts: 0,
          notificationsGranted: true,
          appAuditPossible: false));

      final ScoreRule audit = r.rules.firstWhere((x) => x.id == 'audit');
      expect(audit.earned, 50);
      expect(audit.waived, isTrue);
      expect(r.value, 1000);
      expect(r.factors, isEmpty);
    });

    test('where the audit can run, its points wait for a check that ran it',
        () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          guardsActive: 5,
          guardsAvailable: 5,
          breachedAccounts: 0,
          notificationsGranted: true));

      final ScoreRule audit = r.rules.firstWhere((x) => x.id == 'audit');
      expect(audit.earned, 0);
      expect(audit.waived, isFalse);
      expect(audit.factorId, 'run_check');
      expect(r.value, 950);
    });

    test('a device that cannot deliver alerts is given the alert points', () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          guardsActive: 3,
          guardsAvailable: 3,
          breachedAccounts: 0,
          riskyPermissionApps: 0,
          alertsPossible: false));

      final ScoreRule alerts = r.rules.firstWhere((x) => x.id == 'alerts');
      expect(alerts.earned, 50);
      expect(alerts.waived, isTrue);
      expect(r.factors.map((f) => f.id), isNot(contains('enable_alerts')));
      expect(r.value, 1000);
    });

    test('an unconfirmed VPN or proxy is a penalty of fifty, named plainly',
        () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          guardsActive: 5,
          guardsAvailable: 5,
          breachedAccounts: 0,
          riskyPermissionApps: 0,
          unknownVpnActive: true,
          notificationsGranted: true));

      expect(r.penalty, 50);
      expect(r.value, 950);
      final ScoreFactor f = r.factors.single;
      expect(f.id, 'review_vpn');
      expect(f.label, 'Confirm the VPN or proxy on this device');
    });

    test('no label holds a dash or a middle dot', () {
      final PrivacyScore r = engine.compute(const PrivacySignals(
          daysSinceScan: 40,
          openThreats: 2,
          guardsActive: 1,
          guardsAvailable: 5,
          breachedAccounts: 2,
          riskyPermissionApps: 2,
          unknownVpnActive: true));
      final String words = [
        ...r.rules.map((x) => x.label),
        ...r.factors.map((x) => x.label),
      ].join(' ');
      expect(words, isNot(matches(RegExp('[\u2014\u2013\u00b7]'))));
    });
  });

  test('score is always clamped to 0–1000', () {
    const s = PrivacySignals(unknownVpnActive: true); // base − penalty + nothing
    final r = engine.compute(s);
    expect(r.value, inInclusiveRange(0, 1000));
  });
}
