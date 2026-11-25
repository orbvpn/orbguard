// What Home says, worked out from real signals only.
//
// HomeBrief is a pure function: last check, guard states and the privacy score
// go in; the moment, the ring's gaps, the six shield states and the words come
// out. These tests hold the honesty contract of the new Home:
//  - nothing is "clear" before a check has run
//  - a gap opens only for something FOUND, never for something not set up
//  - a shield is "on" only when one of its guards is verified active
//  - every sentence counts only what really happened

import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';

final _now = DateTime(2026, 11, 23, 21, 40);

GuardStatus _guard(String id, GuardState state) =>
    GuardStatus(id: id, name: id, state: state, detail: '');

/// Every guard this build knows, all verified active.
List<GuardStatus> _allOn() => [
      for (final id in const [
        'spyware_watch',
        'malware_scan',
        'firewall',
        'sms_filter',
        'breach',
        'hidden_vpn',
        'secure_call',
        'alerts',
      ])
        _guard(id, GuardState.active),
    ];

PrivacyScore _score(PrivacySignals signals) =>
    const PrivacyScoreEngine().compute(signals);

/// A clean check two hours ago with every signal good: the engine's 1000.
const _cleanSignals = PrivacySignals(
  lastScanScore: 92,
  daysSinceScan: 0,
  openThreats: 0,
  guardsActive: 8,
  guardsAvailable: 8,
  breachedAccounts: 0,
  riskyPermissionApps: 0,
  unknownVpnActive: false,
  notificationsGranted: true,
);

HomeBrief _brief({
  bool hasScanned = true,
  int verdictScore = 92,
  Duration since = const Duration(hours: 2),
  int? checksRun,
  PrivacySignals signals = _cleanSignals,
  List<GuardStatus>? guards,
  bool guardsResolved = true,
  String noun = 'phone',
}) =>
    HomeBrief.from(
      hasScanned: hasScanned,
      verdictScore: hasScanned ? verdictScore : -1,
      lastScanAt: hasScanned ? _now.subtract(since) : null,
      checksRun: checksRun,
      openThreats: signals.openThreats,
      appsToReview: signals.riskyPermissionApps ?? 0,
      breachedAccounts: signals.breachedAccounts ?? 0,
      score: _score(signals),
      guards: guards ?? _allOn(),
      guardsResolved: guardsResolved,
      now: _now,
      deviceNoun: noun,
    );

/// Clean signals with one thing changed.
PrivacySignals _signals({
  int lastScanScore = 92,
  int openThreats = 0,
  int? breachedAccounts = 0,
  int? riskyPermissionApps = 0,
  bool? unknownVpnActive = false,
}) =>
    PrivacySignals(
      lastScanScore: lastScanScore,
      daysSinceScan: 0,
      openThreats: openThreats,
      guardsActive: 8,
      guardsAvailable: 8,
      breachedAccounts: breachedAccounts,
      riskyPermissionApps: riskyPermissionApps,
      unknownVpnActive: unknownVpnActive,
      notificationsGranted: true,
    );

void main() {
  group('a VPN that is up before the first check', () {
    // Whose VPN it is is a question, and most often the answer is "mine".
    // Until the first check has run, Home has one job: get that check run.
    // The question waits for its results. (A breach is a fact, and does not
    // wait: see "a finding counts even before the first device check".)
    const PrivacySignals up = PrivacySignals(
      guardsActive: 8,
      guardsAvailable: 8,
      breachedAccounts: 0,
      unknownVpnActive: true,
      notificationsGranted: true,
    );

    test('does not take Home over', () {
      final HomeBrief b = _brief(hasScanned: false, signals: up);

      expect(b.moment, HomeMoment.fresh);
      expect(b.gaps, isEmpty);
      expect(b.action, 'Run my first check');
      expect(b.score, isNull);
      expect(b.shields.values, isNot(contains(ShieldState.care)));
    });

    test('is a gap once a check has run', () {
      final HomeBrief b = _brief(signals: _signals(unknownVpnActive: true));

      expect(b.moment, HomeMoment.gap);
      expect(b.gaps.single.factor.id, 'review_vpn');
      expect(b.shields[Shield.hiddenVpn], ShieldState.care);
    });
  });

  group('a clean check', () {
    test('closes the circle and carries the engine score', () {
      final brief = _brief();

      expect(brief.moment, HomeMoment.clear);
      expect(brief.score, 1000);
      expect(brief.headline, 'No signs you’re being watched.');
      expect(brief.gaps, isEmpty);
      expect(brief.severe, isFalse);
    });

    test('the proof line counts the checks that ran, when known', () {
      expect(_brief(checksRun: 5).proof, '5 checks ran 2 hours ago, all clean');
      expect(_brief(checksRun: 1).proof, '1 check ran 2 hours ago, all clean');
    });

    test('without a count the proof line claims only what is stored', () {
      expect(_brief().proof, 'Checked 2 hours ago. Nothing found.');
    });

    test('time since the check reads the way a person would say it', () {
      String proof(Duration since) => _brief(since: since).proof!;

      expect(proof(const Duration(seconds: 20)),
          'Checked just now. Nothing found.');
      expect(proof(const Duration(minutes: 5)),
          'Checked 5 min ago. Nothing found.');
      expect(proof(const Duration(minutes: 61)),
          'Checked 1 hour ago. Nothing found.');
      expect(proof(const Duration(hours: 30)),
          'Checked yesterday. Nothing found.');
      expect(
          proof(const Duration(days: 3)), 'Checked 3 days ago. Nothing found.');
    });

    test('a check older than a week asks for a fresh one', () {
      final brief = _brief(since: const Duration(days: 9));

      expect(brief.moment, HomeMoment.clear);
      expect(brief.headline, 'Nothing found last time.',
          reason: 'a check from last week does not speak for today');
      expect(brief.proof, 'Last check was 9 days ago. Time for a fresh one.');
    });

    test('a clean but shallow check never reads as all clear', () {
      final brief = _brief(verdictScore: 55);

      expect(brief.moment, HomeMoment.clear);
      expect(brief.headline, 'Nothing found so far.');
      expect(brief.proof,
          'The last check could not look deep. Allow more access to be sure.');
    });
  });

  group('gaps', () {
    test('things found by the check open the ring toward the spyware shield',
        () {
      final brief = _brief(
        verdictScore: 68,
        signals: const PrivacySignals(
          lastScanScore: 68,
          daysSinceScan: 0,
          openThreats: 2,
          guardsActive: 8,
          guardsAvailable: 8,
          breachedAccounts: 0,
          riskyPermissionApps: 0,
          unknownVpnActive: false,
          notificationsGranted: true,
        ),
      );

      expect(brief.moment, HomeMoment.gap);
      expect(brief.headline, 'One gap to close.');
      expect(brief.gaps.single.shield, Shield.spyware);
      expect(brief.gaps.single.factor.id, 'resolve_threats');
      expect(brief.gaps.single.factor.points, 150);
      expect(brief.shields[Shield.spyware], ShieldState.care);
      expect(brief.proof, 'Found in your last check, 2 hours ago.');
      expect(brief.score, 850);
    });

    test('a critical finding is named plainly, not as a gap count', () {
      final brief = _brief(
        verdictScore: 45,
        signals: const PrivacySignals(
          lastScanScore: 45,
          daysSinceScan: 0,
          openThreats: 1,
          guardsActive: 8,
          guardsAvailable: 8,
          breachedAccounts: 0,
          riskyPermissionApps: 0,
          unknownVpnActive: false,
          notificationsGranted: true,
        ),
      );

      expect(brief.severe, isTrue);
      expect(brief.headline, 'Your phone needs attention.');
      expect(brief.gaps.single.shield, Shield.spyware);
    });

    test('a finding that is not severe is counted calmly', () {
      final brief = _brief(
        verdictScore: 80,
        signals: _signals(lastScanScore: 80, openThreats: 1),
      );

      expect(brief.severe, isFalse);
      expect(brief.headline, 'One gap to close.');
    });

    test('each kind of finding opens toward its own shield, biggest first', () {
      final brief = _brief(
        signals: const PrivacySignals(
          lastScanScore: 92,
          daysSinceScan: 0,
          openThreats: 0,
          guardsActive: 8,
          guardsAvailable: 8,
          breachedAccounts: 1,
          riskyPermissionApps: 2,
          unknownVpnActive: true,
          notificationsGranted: true,
        ),
      );

      expect(brief.moment, HomeMoment.gap);
      expect(brief.headline, 'Three gaps to close.');
      expect(brief.gaps.first.shield, Shield.identity,
          reason: 'the breach is worth the most points');
      expect(brief.gaps.map((g) => g.shield).toSet(),
          {Shield.identity, Shield.hiddenVpn, Shield.watching});
      expect(brief.shields[Shield.identity], ShieldState.care);
      expect(brief.shields[Shield.hiddenVpn], ShieldState.care);
      expect(brief.shields[Shield.watching], ShieldState.care);
      expect(brief.proof, isNull,
          reason: 'no check found these, so no check time is claimed');
    });

    test('the card for a finding says how many things, and what closing earns',
        () {
      final one = _brief(
        verdictScore: 80,
        signals: _signals(lastScanScore: 80, openThreats: 1),
      ).gaps.single;
      final two = _brief(
        verdictScore: 68,
        signals: _signals(lastScanScore: 68, openThreats: 2),
      ).gaps.single;

      expect(one.title, 'Your last check found 1 thing');
      expect(one.detail, 'See what it is and how to remove it.');
      expect(two.title, 'Your last check found 2 things');
      expect(two.detail, 'See what they are and how to remove them.');
      expect(two.gain, 'Closing it adds 150 to your score');
    });

    test('a VPN or proxy nobody confirmed is stated, not accused', () {
      final gap = _brief(signals: _signals(unknownVpnActive: true)).gaps.single;

      expect(gap.shield, Shield.hiddenVpn);
      expect(gap.title, 'A VPN or proxy is active');
      expect(gap.detail,
          'If it is yours, tell OrbGuard. If it is not, turn it off.');
      expect(gap.gain, 'Closing it adds 50 to your score');
    });

    test('apps found by the check open the ring toward Who is watching', () {
      final brief = _brief(
        verdictScore: 80,
        signals: _signals(lastScanScore: 80, riskyPermissionApps: 1),
      );
      final HomeGap gap = brief.gaps.single;

      expect(gap.shield, Shield.watching);
      expect(brief.shields[Shield.watching], ShieldState.care);
      expect(brief.shields[Shield.spyware], isNot(ShieldState.care));
      expect(gap.title, 'Your last check found 1 app to review');
      expect(gap.detail, 'See which app and what it can reach.');
      expect(gap.gain, 'Closing it adds 50 to your score');
      expect(brief.proof, 'Found in your last check, 2 hours ago.');
      expect(brief.headline, 'One gap to close.');
    });

    test('several apps are counted, in the plural', () {
      final HomeGap gap = _brief(
        verdictScore: 68,
        signals: _signals(lastScanScore: 68, riskyPermissionApps: 3),
      ).gaps.single;

      expect(gap.title, 'Your last check found 3 apps to review');
      expect(gap.detail, 'See which apps and what they can reach.');
    });

    test('a severe app finding is named plainly too', () {
      final brief = _brief(
        verdictScore: 45,
        signals: _signals(lastScanScore: 45, riskyPermissionApps: 1),
      );

      expect(brief.severe, isTrue);
      expect(brief.headline, 'Your phone needs attention.');
    });

    test('a breach is named as what happened', () {
      final HomeGap one =
          _brief(signals: _signals(breachedAccounts: 1)).gaps.single;
      final HomeGap two =
          _brief(signals: _signals(breachedAccounts: 2)).gaps.single;

      expect(one.shield, Shield.identity);
      expect(one.title, 'Your email was in a data breach');
      expect(one.detail, 'See what leaked and what to change.');
      expect(one.gain, 'Closing it adds 100 to your score');
      expect(two.title, '2 of your emails were in data breaches');
    });

    test('spyware and apps found by one check are two gaps, counted once each',
        () {
      final brief = _brief(
        verdictScore: 45,
        signals:
            _signals(lastScanScore: 45, openThreats: 1, riskyPermissionApps: 2),
      );

      expect(
          brief.gaps.map((g) => g.shield), [Shield.spyware, Shield.watching]);
      expect(brief.gaps.map((g) => g.factor.points), [150, 50]);
      expect(brief.score, 800);
    });

    test('a finding counts even before the first device check', () {
      final brief = _brief(
        hasScanned: false,
        signals: const PrivacySignals(
          guardsActive: 2,
          guardsAvailable: 5,
          breachedAccounts: 1,
        ),
      );

      expect(brief.moment, HomeMoment.gap,
          reason: 'a known breach is not hidden behind an invitation');
      expect(brief.gaps.single.shield, Shield.identity);
      expect(brief.proof, isNull);
    });

    test('something not set up yet lowers the score but opens no gap', () {
      final brief = _brief(
        guards: [
          _guard('spyware_watch', GuardState.active),
          _guard('breach', GuardState.actionNeeded),
          _guard('alerts', GuardState.actionNeeded),
        ],
        signals: const PrivacySignals(
          lastScanScore: 92,
          daysSinceScan: 0,
          openThreats: 0,
          guardsActive: 1,
          guardsAvailable: 3,
          breachedAccounts: null,
          notificationsGranted: false,
        ),
      );

      expect(brief.moment, HomeMoment.clear);
      expect(brief.gaps, isEmpty);
      expect(brief.score, lessThan(1000));
      expect(brief.headline, 'No signs you’re being watched.');
    });
  });

  group('the one action', () {
    test('before the first check it starts the first check', () {
      expect(_brief(hasScanned: false).action, 'Run my first check');
    });

    test('after a clean check it offers another', () {
      expect(_brief().action, 'Check now');
    });

    test('with a gap open the action belongs to the gap, not to Home', () {
      final brief = _brief(signals: _signals(breachedAccounts: 1));

      expect(brief.action, isNull);
    });
  });

  group('shields', () {
    test('a shield is on only when one of its guards is verified active', () {
      final brief = _brief(
        guards: [
          _guard('spyware_watch', GuardState.actionNeeded),
          _guard('malware_scan', GuardState.active),
          _guard('sms_filter', GuardState.actionNeeded),
          _guard('breach', GuardState.active),
        ],
      );

      expect(brief.shields[Shield.spyware], ShieldState.on,
          reason: 'the app scan is active even with the daily checkup off');
      expect(brief.shields[Shield.scam], ShieldState.off);
      expect(brief.shields[Shield.identity], ShieldState.on);
    });

    test('a shield this device cannot fully run shows as limited, never on',
        () {
      final brief = _brief(
        guards: [
          _guard('spyware_watch', GuardState.active),
          _guard('firewall', GuardState.unavailable),
          _guard('secure_call', GuardState.unavailable),
        ],
      );

      expect(brief.shields[Shield.watching], ShieldState.limited);
      expect(brief.shields[Shield.secureCall], ShieldState.limited);
    });

    test('a shield with no word from its guards is off, not assumed on', () {
      final brief = _brief(guards: const []);

      expect(brief.shields, hasLength(6));
      expect(brief.shields.values, everyElement(ShieldState.off));
      expect(brief.live, isFalse);
    });

    test('all six are always stationed, in dial order', () {
      final brief = _brief();

      expect(brief.shields.keys.toList(), Shield.values);
      expect([for (final s in Shield.values) s.angle],
          [330, 30, 90, 150, 210, 270]);
    });
  });

  group('live and still', () {
    test('the ring is live when a guard is verified active', () {
      expect(_brief().live, isTrue);
      expect(_brief().still, isFalse);
    });

    test('checked but nothing on watch: the ring goes still and says so', () {
      final brief = _brief(
        guards: [_guard('spyware_watch', GuardState.actionNeeded)],
      );

      expect(brief.live, isFalse);
      expect(brief.still, isTrue);
      expect(brief.proof, 'Nothing is on watch between checks.');
    });

    test('a shield that only waits to be used does not put the ring on watch',
        () {
      final brief = _brief(
        guards: [
          _guard('malware_scan', GuardState.active),
          _guard('sms_filter', GuardState.active),
          _guard('secure_call', GuardState.active),
          _guard('alerts', GuardState.active),
        ],
      );

      expect(brief.shields[Shield.scam], ShieldState.on,
          reason: 'it is ready the moment a text is pasted');
      expect(brief.live, isFalse,
          reason: 'ready to be used is not the same as watching');
      expect(brief.still, isTrue);
    });

    test('the daily checkup or the firewall puts the ring on watch', () {
      expect(_brief(guards: [_guard('spyware_watch', GuardState.active)]).live,
          isTrue);
      expect(
          _brief(guards: [_guard('firewall', GuardState.active)]).live, isTrue);
    });

    test('until the guards have answered, nothing is called still', () {
      final brief = _brief(guards: const [], guardsResolved: false);

      expect(brief.live, isFalse);
      expect(brief.still, isFalse,
          reason: 'not knowing yet is not the same as nothing on watch');
      expect(brief.proof, 'Checked 2 hours ago. Nothing found.');
    });

    test('before the first check the ring is dotted, not still', () {
      final brief = _brief(
        hasScanned: false,
        guards: [_guard('spyware_watch', GuardState.actionNeeded)],
      );

      expect(brief.still, isFalse);
    });
  });
}
