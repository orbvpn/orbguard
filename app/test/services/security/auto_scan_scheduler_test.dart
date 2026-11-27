// A scheduled check leaves the same trace a check the person starts does:
// a verdict Home can read, with what ran, what could not, and what broke.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/check_run.dart';
import 'package:orbguard/services/home/computer_check.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/services/security/auto_scan_scheduler.dart';
import 'package:orbguard/services/security/device_scan_service.dart';

DeviceScanProgress _start(int i, String name) => DeviceScanProgress(
    stageIndex: i,
    totalStages: 6,
    stageName: name,
    stageCompleted: false,
    threatsFound: 0);

DeviceScanProgress _end(int i, String name, {String? error, int found = 0}) =>
    DeviceScanProgress(
        stageIndex: i,
        totalStages: 6,
        stageName: name,
        stageCompleted: true,
        threatsFound: found,
        stageError: error);

/// An engine run on an iPhone: four checks run, one finds something, one is
/// not possible here and one breaks.
Future<List<Map<String, dynamic>>> _iphoneScan(
    DeviceScanProgressCallback onProgress) async {
  const List<String> clean = ['Running processes', 'File system', 'Memory'];
  int i = 0;
  onProgress(_start(i, 'Network connections'));
  onProgress(_end(i++, 'Network connections', found: 1));
  for (final String s in clean) {
    onProgress(_start(i, s));
    onProgress(_end(i++, s, found: 1));
  }
  onProgress(_start(i, 'App databases'));
  onProgress(_end(i++, 'App databases', error: DeviceScanService.notSupported));
  onProgress(_start(i, 'Certificate analysis'));
  onProgress(_end(i++, 'Certificate analysis', error: 'channel broke'));
  return [
    {'severity': 'HIGH', 'stage': 'Network connections', 'name': 'x'},
  ];
}

void main() {
  final List<String> notified = [];

  AutoScanScheduler scheduler(CheckRunner scan) => AutoScanScheduler.forTest(
        scan: scan,
        android: false,
        notify: ({required int threatsFound, required int duration}) async =>
            notified.add('$threatsFound'),
      );

  setUp(() {
    notified.clear();
    // Due, and not held to Wi-Fi, so the test needs no connectivity plugin.
    SharedPreferences.setMockInitialValues({'scan_wifi': false});
  });

  Future<LastScanVerdictController> stored() async {
    final LastScanVerdictController c = LastScanVerdictController();
    await c.load();
    return c;
  }

  test('records the verdict of a scheduled check, stage by stage', () async {
    await scheduler(_iphoneScan).runIfDue();

    final LastScanVerdictController v = await stored();
    expect(v.hasScanned, isTrue);
    expect(v.threatCount, 1);
    expect(v.checksRun, 4);
    expect(v.stagesRan, [
      'Network connections',
      'Running processes',
      'File system',
      'Memory',
    ]);
    expect(v.stagesNotPossible, ['App databases']);
    expect(v.stagesFailed, ['Certificate analysis']);
    expect(notified, ['1']);
  });

  test('records into the app\'s own controller when the app gave it one',
      () async {
    final LastScanVerdictController app = LastScanVerdictController();
    await app.load();
    int heard = 0;
    app.addListener(() => heard++);

    final AutoScanScheduler s = scheduler(_iphoneScan)
      ..verdict = app
      ..coverage = () => 80;
    await s.runIfDue();

    expect(heard, greaterThan(0));
    expect(app.hasScanned, isTrue);
    expect(app.checksRun, 4);
    expect(app.coveragePercent, 80);
  });

  test('with no coverage from the app, keeps the last one the app measured',
      () async {
    SharedPreferences.setMockInitialValues({
      'scan_wifi': false,
      'verdict_at_iso': '2026-11-24T09:00:00.000',
      'verdict_coverage_pct': 65,
    });
    await scheduler(_iphoneScan).runIfDue();
    expect((await stored()).coveragePercent, 65);
  });

  test('with no coverage ever measured, claims only the base 25', () async {
    await scheduler(_iphoneScan).runIfDue();
    expect((await stored()).coveragePercent, 25);
  });

  test('a check that ran nothing records nothing', () async {
    await scheduler((onProgress) async {
      onProgress(_start(0, 'Memory'));
      onProgress(_end(0, 'Memory', error: DeviceScanService.notSupported));
      return const [];
    }).runIfDue();

    expect((await stored()).hasScanned, isFalse);
    expect(notified, isEmpty);
  });

  test('a check the engine could not run records nothing', () async {
    await scheduler(
            (_) async => throw DeviceScanUnavailableException('no engine here'))
        .runIfDue();

    expect((await stored()).hasScanned, isFalse);
    // Still stamped, so it is not retried every cycle.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('auto_scan_last_at'), isNotNull);
  });

  test('a check that broke records nothing and is tried again', () async {
    await scheduler((_) async => throw StateError('boom')).runIfDue();

    expect((await stored()).hasScanned, isFalse);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('auto_scan_last_at'), isNull);
  });

  test('on a computer, a scheduled check runs its six areas and keeps their '
      'coverage', () async {
    // The app hands over its own check for a computer, the one Home runs.
    final List<String> areas = [
      for (final CheckStep s in CheckPlan.computer) s.stage,
    ];
    final AutoScanScheduler computer = scheduler((onProgress) async {
      for (int i = 0; i < areas.length; i++) {
        onProgress(_start(i, areas[i]));
        onProgress(_end(i, areas[i],
            error: areas[i] == 'Code signing'
                ? DeviceScanService.notSupported
                : null));
      }
      return const [];
    })
      ..plan = CheckPlan.computer
      ..coverageOf = ComputerCheck.coverageOf
      // The phone figure the app also hands over is not this check's.
      ..coverage = (() => 35);
    await computer.runIfDue();

    final LastScanVerdictController v = await stored();
    expect(v.checksRun, 5);
    expect(v.stagesNotPossible, ['Code signing']);
    expect(v.stagesFailed, isEmpty,
        reason: 'every area of the plan reported, so none went silent');
    expect(v.coveragePercent, 83,
        reason: 'five of the six areas ran; a phone figure is not used');
  });

  test('a later load sees a verdict another isolate wrote', () async {
    // On Android the scheduled check runs in WorkManager's isolate, whose
    // writes the app's cached preferences do not see until they reload.
    final LastScanVerdictController app =
        LastScanVerdictController(prefs: await SharedPreferences.getInstance());
    await app.load();
    expect(app.hasScanned, isFalse);

    // The store underneath changes without this isolate's cache knowing.
    SharedPreferences.setMockInitialValues({
      'verdict_score': 70,
      'verdict_at_iso': '2026-11-25T03:00:00.000',
      'verdict_threat_count': 0,
    });
    await app.load();
    expect(app.hasScanned, isTrue);
    expect(app.score, 70);
  });
}
