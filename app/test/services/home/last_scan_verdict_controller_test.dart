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
}
