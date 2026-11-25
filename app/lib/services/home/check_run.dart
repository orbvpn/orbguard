// A running check, as Home shows it.
//
// The engine (`DeviceScanService`) reports each stage as it starts and as it
// ends. This turns those reports into the steps Home draws: one ring segment
// and one row per check that can run on this device, and afterwards an
// account of what ran, what could not, and what broke.
//
// Honesty rules:
//  - a step moves only on a report from the engine; nothing here invents
//    progress
//  - a check that could not run is never counted as run
//  - a check that cannot run on this device never gets a ring segment, and is
//    named afterwards as not possible
//
// One thing is added: pace. An engine can finish a stage in a few thousandths
// of a second, too fast to read. Each step that shows is therefore held for a
// beat before its own result is shown. Nothing is shown that did not happen,
// and nothing is shown before it happened; real results are only replayed at
// a speed a person can follow.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../security/device_scan_service.dart';
import 'check_plan.dart';

/// Runs the real check, reporting each stage through [onProgress], and
/// completes with what it found.
typedef CheckRunner = Future<List<Map<String, dynamic>>> Function(
    DeviceScanProgressCallback onProgress);

/// Where one step of a check stands.
enum CheckStepState {
  /// Not reached yet.
  pending,

  /// Running now.
  running,

  /// Ran.
  done,

  /// Could not run. Drawn hatched, never as done.
  unavailable,
}

/// What a finished check established. Checks are named by the engine's stage
/// names, in the order they ran; `CheckPlan.byStage` gives the words.
@immutable
class CheckOutcome {
  const CheckOutcome({
    required this.findings,
    required this.ran,
    required this.notPossible,
    required this.failed,
  });

  /// What was found, each finding carrying the `stage` that found it.
  final List<Map<String, dynamic>> findings;

  /// Checks that ran, whether or not they found something.
  final List<String> ran;

  /// Checks this device, or this build, does not let OrbGuard run.
  final List<String> notPossible;

  /// Checks that should have run and broke this time.
  final List<String> failed;

  /// Checks that ran and found nothing.
  List<String> get ranClean {
    final Set<Object?> found = {for (final f in findings) f['stage']};
    return [
      for (final String stage in ran)
        if (!found.contains(stage)) stage,
    ];
  }
}

class CheckRun extends ChangeNotifier {
  CheckRun({
    required List<CheckStep> plan,
    this.beat = const Duration(milliseconds: 320),
    this.settle = const Duration(milliseconds: 600),
  }) : _plan = List.unmodifiable(plan) {
    _reset();
  }

  final List<CheckStep> _plan;

  /// How long a step shows as running before its result may show.
  final Duration beat;

  /// How long the finished ring is held before the check is over.
  final Duration settle;

  late List<CheckStep> _steps;
  late List<CheckStepState> _states;
  bool _running = false;
  String? _failure;

  final List<String> _ran = [];
  final List<String> _notPossible = [];
  final List<String> _failed = [];

  /// Reports from the engine that have not been shown yet.
  final Queue<DeviceScanProgress> _waiting = Queue<DeviceScanProgress>();
  bool _showing = false;
  Future<void> _shown = Future<void>.value();

  /// Set once the screen that showed this check has gone. The engine may
  /// still be working then: its reports are taken, and nobody is told.
  bool _gone = false;

  @override
  void notifyListeners() {
    if (!_gone) super.notifyListeners();
  }

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  bool get running => _running;

  /// The steps of this check: one ring segment and one row each.
  List<CheckStep> get steps => List.unmodifiable(_steps);

  /// The state of each of [steps], in the same order.
  List<CheckStepState> get states => List.unmodifiable(_states);

  /// How many steps have a result so far.
  int get finished => _states
      .where((s) => s == CheckStepState.done || s == CheckStepState.unavailable)
      .length;

  /// The step running now, if one is.
  CheckStep? get current {
    final int at = _states.indexOf(CheckStepState.running);
    return at < 0 ? null : _steps[at];
  }

  /// Why the last check could not run at all, in the engine's words, or null.
  /// Then nothing was checked and nothing may be reported as clear.
  String? get failure => _failure;

  /// Runs a check through [runner]. Completes with its outcome, or with null
  /// when a check is already running or the engine could not run at all (see
  /// [failure]).
  Future<CheckOutcome?> start(CheckRunner runner) async {
    if (_running) return null;
    _reset();
    _running = true;
    _failure = null;
    notifyListeners();

    final List<Map<String, dynamic>> findings;
    try {
      findings = await runner(_hear);
    } on DeviceScanUnavailableException catch (e) {
      return _fail(e.message);
    } on Object catch (e) {
      return _fail('$e');
    }

    // Everything the engine reported has been shown before the check ends.
    while (_showing) {
      await _shown;
    }

    // A step the engine never reported on did not run.
    bool silent = false;
    for (int i = 0; i < _states.length; i++) {
      if (_states[i] == CheckStepState.pending ||
          _states[i] == CheckStepState.running) {
        _states[i] = CheckStepState.unavailable;
        _failed.add(_steps[i].stage);
        silent = true;
      }
    }
    if (silent) notifyListeners();

    if (settle > Duration.zero) await Future<void>.delayed(settle);
    _running = false;
    notifyListeners();
    return CheckOutcome(
      findings: List.unmodifiable(findings),
      ran: List.unmodifiable(_ran),
      notPossible: List.unmodifiable(_notPossible),
      failed: List.unmodifiable(_failed),
    );
  }

  CheckOutcome? _fail(String why) {
    _waiting.clear();
    _reset();
    _running = false;
    _failure = why;
    notifyListeners();
    return null;
  }

  void _reset() {
    _steps = List.of(_plan);
    _states = List.filled(_plan.length, CheckStepState.pending, growable: true);
    _ran.clear();
    _notPossible.clear();
    _failed.clear();
  }

  /// A report from the engine. Shown in order, at a pace a person can read.
  void _hear(DeviceScanProgress report) {
    _waiting.add(report);
    if (_showing) return;
    _showing = true;
    _shown = _show();
  }

  Future<void> _show() async {
    try {
      while (_waiting.isNotEmpty) {
        final DeviceScanProgress report = _waiting.removeFirst();
        final bool started = _apply(report) && !report.stageCompleted;
        if (started && beat > Duration.zero) {
          await Future<void>.delayed(beat);
        }
      }
    } finally {
      _showing = false;
    }
  }

  /// Applies one report. True when it changed what is on screen.
  bool _apply(DeviceScanProgress report) {
    final int at = _steps.indexWhere((s) => s.stage == report.stageName);

    if (!report.stageCompleted) {
      // A check this device is not expected to run gets no segment unless it
      // turns out to run after all.
      if (at < 0) return false;
      _states[at] = CheckStepState.running;
      notifyListeners();
      return true;
    }

    final String? error = report.stageError;
    final bool ran = error == null;
    final bool cannot = error == DeviceScanService.notSupported ||
        error == DeviceScanService.notInBuild;
    (ran ? _ran : (cannot ? _notPossible : _failed)).add(report.stageName);

    if (at >= 0) {
      _states[at] = ran ? CheckStepState.done : CheckStepState.unavailable;
    } else if (ran) {
      _steps.add(CheckPlan.byStage(report.stageName));
      _states.add(CheckStepState.done);
    } else {
      return false;
    }
    notifyListeners();
    return true;
  }
}
