import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/check_run.dart';
import 'package:orbguard/services/security/device_scan_service.dart';

/// A check as Home shows it: one step per check that can run, each moved
/// only by what the engine really reported.
void main() {
  const List<String> engineOrder = [
    'Network connections',
    'Running processes',
    'File system',
    'App databases',
    'Memory',
    'Certificate analysis',
    'Permission abuse',
    'Accessibility abuse',
    'Keylogger detection',
    'Location stalkers',
    'App malware scan',
  ];

  /// An engine that reports every stage, with the given outcomes. A stage
  /// maps to null when it ran, or to the engine's words for why it did not.
  CheckRunner engine({
    Map<String, String?> errors = const {},
    List<Map<String, dynamic>> findings = const [],
  }) =>
      (onProgress) async {
        for (int i = 0; i < engineOrder.length; i++) {
          final String stage = engineOrder[i];
          onProgress(DeviceScanProgress(
            stageIndex: i,
            totalStages: engineOrder.length,
            stageName: stage,
            stageCompleted: false,
            threatsFound: 0,
          ));
          onProgress(DeviceScanProgress(
            stageIndex: i,
            totalStages: engineOrder.length,
            stageName: stage,
            stageCompleted: true,
            threatsFound: 0,
            stageError: errors[stage],
          ));
        }
        return findings;
      };

  /// What an iPhone's engine answers for the six checks iOS forbids.
  const Map<String, String?> iphone = {
    'Certificate analysis': 'not supported on this device',
    'Permission abuse': 'not supported on this device',
    'Accessibility abuse': 'not supported on this device',
    'Keylogger detection': 'not supported on this device',
    'Location stalkers': 'not supported on this device',
    'App malware scan': 'not supported on this device',
  };

  CheckRun run({required bool android}) => CheckRun(
        plan: CheckPlan.forDevice(android: android),
        beat: Duration.zero,
        settle: Duration.zero,
      );

  test('before a check, every step waits and nothing is running', () {
    final CheckRun check = run(android: false);

    expect(check.running, isFalse);
    expect(check.steps, hasLength(5));
    expect(check.states, everyElement(CheckStepState.pending));
    expect(check.finished, 0);
    expect(check.current, isNull);
  });

  test('an Android check runs eleven steps and reports each as run', () async {
    final CheckRun check = run(android: true);

    final CheckOutcome? outcome = await check.start(engine());

    expect(outcome!.ran, engineOrder);
    expect(outcome.notPossible, isEmpty);
    expect(outcome.failed, isEmpty);
    expect(check.states, everyElement(CheckStepState.done));
    expect(check.running, isFalse);
  });

  test('an iPhone check counts five as run and names six as not possible',
      () async {
    final CheckRun check = run(android: false);

    final CheckOutcome? outcome = await check.start(engine(errors: iphone));

    expect(outcome!.ran, engineOrder.take(5));
    expect(outcome.notPossible, engineOrder.skip(5));
    expect(outcome.failed, isEmpty);
    // The ring never grew a segment for a check that cannot run.
    expect(check.steps, hasLength(5));
    expect(check.states, everyElement(CheckStepState.done));
  });

  test('a check that should run and breaks is not counted as run', () async {
    final CheckRun check = run(android: true);

    final CheckOutcome? outcome = await check
        .start(engine(errors: {'Memory': 'PlatformException(boom)'}));

    expect(outcome!.ran, isNot(contains('Memory')));
    expect(outcome.failed, ['Memory']);
    expect(outcome.notPossible, isEmpty);
    expect(check.states[4], CheckStepState.unavailable);
  });

  test('a planned check this build cannot run is named as not possible',
      () async {
    final CheckRun check = run(android: true);

    final CheckOutcome? outcome = await check.start(
        engine(errors: {'App malware scan': 'unavailable on this build'}));

    expect(outcome!.notPossible, ['App malware scan']);
    expect(outcome.failed, isEmpty);
    expect(check.states.last, CheckStepState.unavailable);
  });

  test('checks that ran clean leave out the ones that found something',
      () async {
    final CheckRun check = run(android: true);

    final CheckOutcome? outcome = await check.start(engine(findings: [
      {'id': 'k1', 'stage': 'Keylogger detection', 'severity': 'MEDIUM'},
    ]));

    expect(outcome!.findings, hasLength(1));
    expect(outcome.ran, contains('Keylogger detection'));
    expect(outcome.ranClean, isNot(contains('Keylogger detection')));
    expect(outcome.ranClean, hasLength(10));
  });

  test('a step is running between its start and its result', () async {
    final CheckRun check = run(android: false);
    final List<String> seen = [];
    check.addListener(() {
      seen.add('${check.finished}:${check.current?.stage ?? 'none'}');
    });

    await check.start(engine(errors: iphone));

    expect(
        seen,
        containsAllInOrder([
          '0:Network connections',
          '1:none',
          '1:Running processes',
          '4:Memory',
          '5:none',
        ]));
  });

  test('a check the engine cannot run at all gives no outcome, and says so',
      () async {
    final CheckRun check = run(android: true);

    final CheckOutcome? outcome = await check.start(
        (_) async => throw DeviceScanUnavailableException('no engine here'));

    expect(outcome, isNull);
    expect(check.failure, 'no engine here');
    expect(check.running, isFalse);
    expect(check.states, everyElement(CheckStepState.pending));
  });

  test('a check that outlives its screen ends quietly', () async {
    final Completer<void> hold = Completer<void>();
    final CheckRun check = CheckRun(
      plan: CheckPlan.forDevice(android: true),
      beat: Duration.zero,
      settle: Duration.zero,
    );
    final Future<CheckOutcome?> running = check.start((onProgress) async {
      await hold.future;
      return engine()(onProgress);
    });

    // The screen goes away while the engine is still working.
    check.dispose();
    hold.complete();

    // The engine's reports land on a check nobody is listening to. That
    // must not throw.
    final CheckOutcome? outcome = await running;
    expect(outcome, isNotNull);
  });

  test('a second check cannot start while one is running', () async {
    final CheckRun check = run(android: false);
    final Completer<List<Map<String, dynamic>>> held = Completer();
    int started = 0;

    final Future<CheckOutcome?> first = check.start((_) {
      started++;
      return held.future;
    });
    final CheckOutcome? second = await check.start((_) async {
      started++;
      return const [];
    });

    expect(second, isNull);
    expect(started, 1);
    held.complete(const []);
    await first;
  });

  test('a new check starts from a clean slate', () async {
    final CheckRun check = run(android: false);
    await check.start(engine(errors: {...iphone, 'Memory': 'boom'}));
    expect(check.states[4], CheckStepState.unavailable);

    // The first thing a new check shows is every step waiting again.
    List<CheckStepState>? atStart;
    check.addListener(() => atStart ??= check.states);
    await check.start(engine(errors: iphone));

    expect(atStart, everyElement(CheckStepState.pending));
    expect(check.states, everyElement(CheckStepState.done));
  });

  test('a check the plan did not expect is added once it has really run',
      () async {
    final CheckRun check = run(android: false);

    // An iPhone whose engine, one day, can read certificates.
    final Map<String, String?> errors = {...iphone}
      ..remove('Certificate analysis');
    final CheckOutcome? outcome = await check.start(engine(errors: errors));

    expect(outcome!.ran, contains('Certificate analysis'));
    expect(check.steps.map((s) => s.stage), contains('Certificate analysis'));
    expect(check.states, everyElement(CheckStepState.done));
  });

  // A widget test only for its clock: time moves when the test says so.
  testWidgets('each step stays on screen for a beat, however fast the engine',
      (tester) async {
    final CheckRun check = CheckRun(
      plan: CheckPlan.forDevice(android: false),
      beat: const Duration(milliseconds: 300),
      settle: const Duration(milliseconds: 500),
    );
    CheckOutcome? outcome;
    unawaited(check.start(engine(errors: iphone)).then((o) => outcome = o));

    await tester.pump(const Duration(milliseconds: 100));
    expect(check.current?.stage, 'Network connections');
    expect(check.finished, 0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(check.finished, 1);
    expect(check.current?.stage, 'Running processes');

    // Five steps of 300 each, then the whole ring is held for 500.
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(check.finished, 5);
    expect(check.running, isTrue);
    expect(outcome, isNull);

    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(check.running, isFalse);
    expect(outcome, isNotNull);
  });
}
