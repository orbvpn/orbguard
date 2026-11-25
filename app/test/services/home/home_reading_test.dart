// Home and the shell read the same sources the same way: one reading gives
// the score, the brief and what the results sheet may say.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/home/check_results.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/home_reading.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';

final DateTime _now = DateTime(2026, 11, 25, 10);

Future<LastScanVerdictController> _checked({
  List<Map<String, dynamic>> findings = const [],
  List<String> ran = const ['Network connections', 'File system'],
  List<String> failed = const [],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final LastScanVerdictController verdict = LastScanVerdictController();
  await verdict.load();
  await verdict.recordScan(
    threats: findings,
    coveragePercent: 90,
    now: _now.subtract(const Duration(hours: 1)),
    checksRun: ran.length,
    stagesRan: ran,
    stagesFailed: failed,
  );
  return verdict;
}

Future<GuardStatusController> _guards() async {
  final GuardStatusController guards = GuardStatusController(probes: [
    () async => const GuardStatus(
        id: 'spyware_watch',
        name: 'Daily check',
        state: GuardState.active,
        detail: ''),
    () async => const GuardStatus(
        id: 'alerts', name: 'Alerts', state: GuardState.active, detail: ''),
  ]);
  await guards.refresh();
  return guards;
}

HomeReading _read(
  LastScanVerdictController verdict,
  GuardStatusController guards, {
  int? breached = 0,
  bool? vpn = false,
  TargetPlatform platform = TargetPlatform.iOS,
}) =>
    HomeReading.of(
      verdict: verdict,
      guards: guards,
      breachedAccounts: breached,
      unknownVpnActive: vpn,
      platform: platform,
      now: _now,
      deviceNoun: 'iPhone',
    );

void main() {
  test('a clean check on an iPhone with everything on reads 1000, all clear',
      () async {
    final HomeReading r = _read(await _checked(), await _guards());

    expect(r.score.value, 1000);
    expect(r.brief.moment, HomeMoment.clear);
    expect(r.brief.gaps, isEmpty);
  });

  test('before any check there is no score and nothing to report', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final LastScanVerdictController verdict = LastScanVerdictController();
    await verdict.load();

    final HomeReading r = _read(verdict, await _guards());

    expect(r.brief.moment, HomeMoment.fresh);
    expect(r.brief.score, isNull);
  });

  test('a breach and an unconfirmed VPN open two gaps, the bigger first',
      () async {
    final HomeReading r =
        _read(await _checked(), await _guards(), breached: 1, vpn: true);

    expect(r.score.value, 850);
    expect(
        r.brief.gaps.map((g) => g.factor.id), ['fix_breaches', 'review_vpn']);
  });

  test('not known is never read as safe', () async {
    final HomeReading r =
        _read(await _checked(), await _guards(), breached: null, vpn: null);

    // No answer on breaches: the hundred is not earned, and nothing is
    // claimed as found either.
    expect(r.score.value, 900);
    expect(r.brief.gaps, isEmpty);
  });

  test('the results name what the check found and the gaps still open',
      () async {
    final LastScanVerdictController verdict = await _checked(
      findings: [
        {
          'id': 'f1',
          'name': 'Spyware traces in a system folder',
          'severity': 'HIGH',
          'stage': 'File system',
        },
      ],
      failed: const ['Memory'],
    );
    final HomeReading r = _read(verdict, await _guards(), breached: 1);

    final CheckResults results = r.results(verdict);

    expect(results.things.single.title, 'Spyware traces in a system folder');
    expect(results.clean.map((s) => s.stage), ['Network connections']);
    expect(results.failed.map((s) => s.stage), ['Memory']);
    expect(results.otherGaps.single.factor.id, 'fix_breaches');
  });
}
