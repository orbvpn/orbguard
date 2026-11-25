import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/home/check_results.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';

/// What the results sheet may say about a check: only what really ran is
/// counted, and one thing found is shown once.
void main() {
  const List<String> five = [
    'Network connections',
    'Running processes',
    'File system',
    'App databases',
    'Memory',
  ];
  const List<String> six = [
    'Certificate analysis',
    'Permission abuse',
    'Accessibility abuse',
    'Keylogger detection',
    'Location stalkers',
    'App malware scan',
  ];

  HomeGap gap(Shield shield, String factorId, int points) => HomeGap(
        shield: shield,
        factor: ScoreFactor(id: factorId, label: factorId, points: points),
        title: factorId,
        detail: '',
      );

  CheckResults results({
    List<Map<String, dynamic>> findings = const [],
    List<String>? ran = const [...five, ...six],
    List<String> notPossible = const [],
    List<String> failed = const [],
    List<HomeGap> gaps = const [],
  }) =>
      CheckResults.from(
        findings: findings,
        stagesRan: ran,
        stagesNotPossible: notPossible,
        stagesFailed: failed,
        gaps: gaps,
      );

  test('a clean check lists every check that ran, in the order they ran', () {
    final CheckResults r = results();

    expect(r.clean.map((s) => s.stage), [...five, ...six]);
    expect(r.clean.first.name, 'Connection interception');
    expect(r.things, isEmpty);
    expect(r.allClear, isTrue);
    expect(r.stagesKnown, isTrue);
  });

  test('a check that found something is not listed as clean', () {
    final CheckResults r = results(findings: [
      {'id': 'f1', 'name': 'Spyware trace', 'stage': 'File system'},
    ]);

    expect(r.clean.map((s) => s.stage), isNot(contains('File system')));
    expect(r.clean, hasLength(10));
    expect(r.things.single.shield, Shield.spyware);
    expect(r.things.single.title, 'Spyware trace');
    expect(r.allClear, isFalse);
  });

  test('one app flagged by two checks is one thing, led by the worse finding',
      () {
    final CheckResults r = results(findings: [
      {
        'id': 'a',
        'name': 'Reads your location often',
        'severity': 'LOW',
        'path': 'com.example.watcher',
        'stage': 'Location stalkers',
      },
      {
        'id': 'b',
        'name': 'Can read your screen',
        'severity': 'HIGH',
        'path': 'com.example.watcher',
        'stage': 'Accessibility abuse',
      },
    ]);

    final FoundThing thing = r.things.single;
    expect(thing.shield, Shield.watching);
    expect(thing.title, 'Can read your screen');
    expect(thing.findings, hasLength(2));
    expect(thing.more, 1);
    expect(
        r.clean.map((s) => s.stage),
        isNot(anyOf(
            contains('Location stalkers'), contains('Accessibility abuse'))));
  });

  test('spyware comes before apps to review', () {
    final CheckResults r = results(findings: [
      {
        'id': 'k',
        'name': 'Keyboard',
        'path': 'com.k',
        'stage': 'Keylogger detection'
      },
      {'id': 'm', 'name': 'Tampering', 'stage': 'Memory'},
    ]);

    expect(r.things.map((t) => t.shield), [Shield.spyware, Shield.watching]);
  });

  test('checks this device forbids and checks that broke are named apart', () {
    final CheckResults r = results(
      ran: five.take(4).toList(),
      notPossible: six,
      failed: ['Memory'],
    );

    expect(r.clean.map((s) => s.stage), five.take(4));
    expect(r.notPossible.map((s) => s.stage), six);
    expect(r.notPossible.first.name, 'Untrusted certificates');
    expect(r.failed.single.name, 'Memory tampering');
  });

  test('a record that never named its checks claims no clean checks', () {
    final CheckResults r = results(ran: null);

    expect(r.stagesKnown, isFalse);
    expect(r.clean, isEmpty);
  });

  test(
      'the connection check is not called clean while a VPN or proxy waits '
      'to be confirmed', () {
    final CheckResults r = results(
      gaps: [gap(Shield.hiddenVpn, 'review_vpn', 50)],
    );

    expect(r.clean.map((s) => s.stage), isNot(contains('Network connections')));
    expect(r.clean, hasLength(10));
    expect(r.otherGaps.single.shield, Shield.hiddenVpn);
    expect(r.allClear, isFalse);
  });

  test('gaps the check did not find are listed apart from what it found', () {
    final CheckResults r = results(
      findings: [
        {'id': 'f1', 'name': 'Spyware trace', 'stage': 'File system'},
      ],
      gaps: [
        gap(Shield.spyware, 'resolve_threats', 150),
        gap(Shield.identity, 'fix_breaches', 100),
      ],
    );

    expect(r.things, hasLength(1));
    expect(r.otherGaps.map((g) => g.factor.id), ['fix_breaches']);
  });

  test('a finding kept from before findings named their check is spyware', () {
    final CheckResults r = results(
      findings: [
        {'id': 'old', 'name': 'Something'},
      ],
      ran: null,
    );

    expect(r.things.single.shield, Shield.spyware);
  });
}
