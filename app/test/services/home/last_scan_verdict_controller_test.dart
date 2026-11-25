import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/home/last_scan_verdict_controller.dart';

/// P4.1 — the stuck-verdict fix. The home verdict must come from the user's
/// latest REAL scan: clean+covered reads protected, threats drag it down,
/// and a clean-but-shallow scan can never fake "protected".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Map<String, dynamic> threat(String sev) => {'severity': sev};

  group('computeScore rubric', () {
    test('clean + full coverage → excellent band (≥90)', () {
      expect(
        LastScanVerdictController.computeScore(threats: [], coveragePercent: 90),
        greaterThanOrEqualTo(90),
      );
    });

    test('clean + mid coverage → good band (70–89)', () {
      final s = LastScanVerdictController.computeScore(
          threats: [], coveragePercent: 60);
      expect(s, inInclusiveRange(70, 89));
    });

    test('clean but shallow coverage caps in attention band — never "protected"',
        () {
      final s = LastScanVerdictController.computeScore(
          threats: [], coveragePercent: 25);
      expect(s, inInclusiveRange(50, 69));
    });

    test('a critical finding always lands at-risk (<50), even at full coverage',
        () {
      final s = LastScanVerdictController.computeScore(
          threats: [threat('CRITICAL')], coveragePercent: 100);
      expect(s, lessThan(50));
    });

    test('a high finding also caps at-risk', () {
      final s = LastScanVerdictController.computeScore(
          threats: [threat('HIGH')], coveragePercent: 100);
      expect(s, lessThanOrEqualTo(45));
    });

    test('mediums degrade without the severe cap', () {
      final s = LastScanVerdictController.computeScore(
          threats: [threat('MEDIUM')], coveragePercent: 90);
      expect(s, inInclusiveRange(70, 89)); // 92 - 12 = 80
    });

    test('score never goes below the floor', () {
      final s = LastScanVerdictController.computeScore(
        threats: List.generate(10, (_) => threat('CRITICAL')),
        coveragePercent: 90,
      );
      expect(s, greaterThanOrEqualTo(5));
    });
  });

  test('starts not-assessed (-1) before any scan', () async {
    final c = LastScanVerdictController();
    await c.load();
    expect(c.score, -1);
    expect(c.hasScanned, isFalse);
  });

  test('recordScan persists across a fresh instance — the actual bug fix',
      () async {
    final c = LastScanVerdictController();
    await c.load();
    await c.recordScan(
      threats: const [],
      coveragePercent: 85,
      now: DateTime(2026, 7, 17, 9),
    );
    expect(c.score, greaterThanOrEqualTo(90));

    final restarted = LastScanVerdictController();
    await restarted.load();
    expect(restarted.score, c.score,
        reason: 'verdict must survive an app restart');
    expect(restarted.lastScanAt, DateTime(2026, 7, 17, 9));
    expect(restarted.coveragePercent, 85);
  });

  test('remembers how many checks the last run completed', () async {
    final c = LastScanVerdictController();
    await c.load();
    await c.recordScan(
        threats: [],
        coveragePercent: 90,
        now: DateTime(2026, 11, 23, 19, 40),
        checksRun: 5);

    final reborn = LastScanVerdictController();
    await reborn.load();
    expect(reborn.checksRun, 5);
  });

  test('a run that did not report a count leaves none to quote', () async {
    final c = LastScanVerdictController();
    await c.load();
    await c.recordScan(
        threats: [],
        coveragePercent: 90,
        now: DateTime(2026, 11, 22, 9),
        checksRun: 5);
    await c.recordScan(
        threats: [], coveragePercent: 90, now: DateTime(2026, 11, 23, 9));

    final reborn = LastScanVerdictController();
    await reborn.load();
    expect(reborn.checksRun, isNull,
        reason: 'the count of an older run must not be quoted for this one');
  });

  test('a later scan with findings pulls a good verdict down', () async {
    final c = LastScanVerdictController();
    await c.load();
    await c.recordScan(
        threats: const [], coveragePercent: 85, now: DateTime(2026, 7, 16));
    final cleanScore = c.score;

    await c.recordScan(
      threats: [threat('HIGH'), threat('MEDIUM')],
      coveragePercent: 85,
      now: DateTime(2026, 7, 17),
    );
    expect(c.score, lessThan(cleanScore));
    expect(c.score, lessThan(50));
    expect(c.threatCount, 2);
  });

  // Home's gap card says "See what it is and how to remove it." That has to
  // hold after the app was closed, and a phone closes apps all the time.
  group('which checks the last check was made of', () {
    test('is kept across a restart: ran, not possible, and broke', () async {
      final LastScanVerdictController first = LastScanVerdictController();
      await first.recordScan(
        threats: const [],
        coveragePercent: 80,
        now: DateTime(2026, 11, 25, 9),
        checksRun: 2,
        stagesRan: const ['Network connections', 'Memory'],
        stagesNotPossible: const ['App malware scan'],
        stagesFailed: const ['File system'],
      );

      final LastScanVerdictController second = LastScanVerdictController();
      await second.load();

      expect(second.stagesRan, ['Network connections', 'Memory']);
      expect(second.stagesNotPossible, ['App malware scan']);
      expect(second.stagesFailed, ['File system']);
    });

    test('is unknown, not empty, before any check', () async {
      final LastScanVerdictController c = LastScanVerdictController();
      await c.load();

      expect(c.stagesRan, isNull);
      expect(c.stagesNotPossible, isEmpty);
      expect(c.stagesFailed, isEmpty);
    });

    test('a run that named no checks does not keep an older run\'s list',
        () async {
      final LastScanVerdictController c = LastScanVerdictController();
      await c.recordScan(
        threats: const [],
        coveragePercent: 80,
        now: DateTime(2026, 11, 24),
        stagesRan: const ['Network connections'],
        stagesNotPossible: const ['App malware scan'],
      );
      await c.recordScan(
        threats: const [],
        coveragePercent: 80,
        now: DateTime(2026, 11, 25),
      );

      expect(c.stagesRan, isNull);
      expect(c.stagesNotPossible, isEmpty);

      final LastScanVerdictController again = LastScanVerdictController();
      await again.load();
      expect(again.stagesRan, isNull);
      expect(again.stagesNotPossible, isEmpty);
    });
  });

  group('what the last check found', () {
    const Map<String, dynamic> keyboard = {
      'name': 'Suspicious Keyboard App',
      'severity': 'MEDIUM',
      'description': 'Keyboard with internet access',
      'packageName': 'com.example.keys',
      'signals': ['internet', 'input method'],
    };

    test('is still there after a restart', () async {
      final c = LastScanVerdictController();
      await c.load();
      await c.recordScan(
          threats: [keyboard],
          coveragePercent: 60,
          now: DateTime(2026, 11, 25, 9));
      expect(c.findings, [keyboard]);

      final reborn = LastScanVerdictController();
      await reborn.load();
      expect(reborn.findings, [keyboard]);
    });

    test('is forgotten once a later check comes back clean', () async {
      final c = LastScanVerdictController();
      await c.load();
      await c.recordScan(
          threats: [keyboard],
          coveragePercent: 60,
          now: DateTime(2026, 11, 25, 9));
      await c.recordScan(
          threats: [], coveragePercent: 60, now: DateTime(2026, 11, 25, 10));
      expect(c.findings, isEmpty);

      final reborn = LastScanVerdictController();
      await reborn.load();
      expect(reborn.findings, isEmpty);
    });

    test('still counts when it cannot be written down', () async {
      // The scanner hands over whatever the platform sent. Something that
      // will not go into storage must cost the list, not the verdict.
      final Map<String, dynamic> odd = {
        'name': 'Odd one',
        'severity': 'HIGH',
        'seenAt': DateTime(2026, 11, 25),
      };
      final c = LastScanVerdictController();
      await c.load();
      await c.recordScan(
          threats: [odd], coveragePercent: 60, now: DateTime(2026, 11, 25, 9));
      expect(c.threatCount, 1);
      // Until the app closes it can still be shown.
      expect(c.findings, [odd]);

      final reborn = LastScanVerdictController();
      await reborn.load();
      expect(reborn.threatCount, 1);
      expect(reborn.findings, isEmpty);
    });

    test('is not trusted when it disagrees with the count', () async {
      // An install from before the list was kept has a count and no list;
      // so would a half-written record.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'verdict_score': 62,
        'verdict_at_iso': DateTime(2026, 11, 25, 9).toIso8601String(),
        'verdict_coverage_pct': 60,
        'verdict_threat_count': 2,
        'verdict_findings_json': '[{"name":"Only one","severity":"LOW"}]',
      });
      final c = LastScanVerdictController();
      await c.load();
      expect(c.threatCount, 2);
      expect(c.findings, isEmpty);
    });
  });
}
