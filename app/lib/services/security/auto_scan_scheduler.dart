// Auto-Scan Scheduler
//
// Makes the "Auto Scan" settings real. A periodic on-device security scan runs
// when it is due (per `scan_freq`), honoring the `scan_wifi` (Wi-Fi-only)
// constraint. It self-throttles via a persisted timestamp, so the same entry
// point is safe to call from anywhere:
//   - Foreground catch-up on app launch/resume (all platforms).
//   - The device agent's existing Android WorkManager cycle (runHeadlessCycle)
//     calls runIfDue(), giving true background scans on Android without a
//     second background task.
//
// iOS/desktop have no guaranteed OS background window, so there the scan runs
// on the next launch/resume when it is due — the honest limit of app-side
// scheduling.
//
// A scheduled check leaves the same trace as one the person starts: it runs
// through [CheckRun] (with no pacing) and records its verdict with
// [LastScanVerdictController], so Home learns that it ran, what ran, what
// could not and what broke. In the foreground the app hands over its own
// controller ([verdict]) and its coverage figure ([coverage]). In the
// WorkManager isolate neither exists: the verdict goes to the same stored
// keys, and the app sees it the next time its controller loads.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/platform_info.dart';
import '../home/check_plan.dart';
import '../home/check_run.dart';
import '../home/last_scan_verdict_controller.dart';
import '../notifications/notification_service.dart';
import 'device_scan_service.dart';

/// Tells the person a scheduled check finished.
typedef ScanCompleteNotifier = Future<void> Function(
    {required int threatsFound, required int duration});

class AutoScanScheduler {
  AutoScanScheduler._()
      : _scan = null,
        _android = null,
        _notify = null;

  /// A scheduler with its engine, platform and notice stood in for.
  @visibleForTesting
  AutoScanScheduler.forTest({
    required CheckRunner scan,
    required bool android,
    required ScanCompleteNotifier notify,
  })  : _scan = scan,
        _android = android,
        _notify = notify;

  static final AutoScanScheduler instance = AutoScanScheduler._();

  final CheckRunner? _scan;
  final bool? _android;
  final ScanCompleteNotifier? _notify;

  /// The app's own verdict controller, so Home hears a scheduled check the
  /// moment it is recorded. Null in a background isolate, and until the app
  /// sets it: then the verdict is written to the same stored keys through a
  /// controller of its own.
  LastScanVerdictController? verdict;

  /// The app's coverage figure (0 to 100), the same one a check the person
  /// starts records. Null in a background isolate: then the last figure the
  /// app recorded is kept, or the base 25 when it never recorded one.
  int Function()? coverage;

  /// The app's own check, where it is not the phone engine: on a computer,
  /// the six areas Home's check runs, so a scheduled check leaves the same
  /// record as one the person starts. Null in a background isolate and on a
  /// phone.
  CheckRunner? engine;

  /// The steps [engine] runs. Null is the phone plan.
  List<CheckStep>? plan;

  /// The coverage of one finished check, where it depends on what ran (a
  /// computer's share of its six areas). Takes the place of [coverage].
  int Function(CheckOutcome outcome)? coverageOf;

  /// What the app's coverage starts from before any permission adds to it,
  /// as `_calculateDetectionCapability` in lib/main.dart counts it.
  static const int baseCoverage = 25;

  /// Timestamp (ms since epoch) of the last automatic scan attempt.
  static const _kLastAutoScanKey = 'auto_scan_last_at';

  /// Guards against overlapping runs within a single isolate. Cross-isolate
  /// throttling is handled by the persisted timestamp.
  bool _running = false;

  /// Run an automatic scan if auto-scan is enabled and enough time has elapsed
  /// since the last one (per `scan_freq`), honoring the Wi-Fi-only setting.
  /// Safe to call on every launch/resume and from the background isolate.
  Future<void> runIfDue() async {
    if (_running) return;

    // Device scanning needs native platform access (MethodChannels, file
    // system) — none of it exists in the browser sandbox.
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('scan_auto') ?? true)) return;

    final freqHours = (prefs.getInt('scan_freq') ?? 24).clamp(1, 24 * 7);
    final last = prefs.getInt(_kLastAutoScanKey) ?? 0;
    final elapsedMs = DateTime.now().millisecondsSinceEpoch - last;
    if (elapsedMs < Duration(hours: freqHours).inMilliseconds) return;

    // Wi-Fi-only constraint (best effort; the Android WorkManager task also
    // enforces an unmetered-network constraint at the OS level).
    if (prefs.getBool('scan_wifi') ?? true) {
      try {
        final conn = await Connectivity().checkConnectivity();
        final onWifi = conn.contains(ConnectivityResult.wifi) ||
            conn.contains(ConnectivityResult.ethernet);
        if (!onWifi) return;
      } catch (_) {
        // Connectivity unknown — skip this cycle rather than scan on cellular.
        return;
      }
    }

    await _runOnce(prefs);
  }

  Future<void> _runOnce(SharedPreferences prefs) async {
    _running = true;
    final startedAt = DateTime.now();
    // CheckRun reports an engine that could not run, and one that broke, the
    // same way (no outcome). They are told apart here, because only the first
    // is stamped: a broken run is tried again next cycle.
    final CheckRunner engine = _scan ??
        this.engine ??
        (onProgress) =>
            DeviceScanService.instance.performScan(onProgress: onProgress);
    String? unavailable;
    try {
      final CheckOutcome? outcome = await CheckRun(
        plan: plan ??
            CheckPlan.forDevice(android: _android ?? PlatformInfo.isAndroid),
        beat: Duration.zero,
        settle: Duration.zero,
      ).start((onProgress) async {
        try {
          return await engine(onProgress);
        } on DeviceScanUnavailableException catch (e) {
          unavailable = e.message;
          rethrow;
        }
      });

      if (unavailable != null) {
        // Scan engine not available on this build/platform. Record the
        // attempt so we don't retry every cycle.
        await _stamp(prefs);
        debugPrint('AutoScanScheduler: scan unavailable: $unavailable');
        return;
      }
      if (outcome == null) {
        debugPrint('AutoScanScheduler: scan failed');
        return;
      }
      await _stamp(prefs);
      // A check in which nothing ran checked nothing: Home is not told it
      // ran, and nobody is told it completed.
      if (outcome.ran.isEmpty) return;
      await _record(outcome);

      final int seconds = DateTime.now().difference(startedAt).inSeconds;
      final ScanCompleteNotifier? notify = _notify;
      if (notify != null) {
        await notify(threatsFound: outcome.findings.length, duration: seconds);
      } else {
        // Respects the "Scan Completed" notification toggle inside the
        // service.
        await NotificationService.instance.showScanCompleteNotification(
          scanType: 'Automatic',
          threatsFound: outcome.findings.length,
          duration: seconds,
        );
      }
    } catch (e) {
      debugPrint('AutoScanScheduler: scan failed: $e');
    } finally {
      _running = false;
    }
  }

  /// Records [outcome] as the latest check, the way a check the person
  /// starts is recorded.
  Future<void> _record(CheckOutcome outcome) async {
    final LastScanVerdictController target =
        verdict ?? LastScanVerdictController();
    if (verdict == null) await target.load();
    final int percent = coverageOf?.call(outcome) ??
        coverage?.call() ??
        (target.hasScanned ? target.coveragePercent : baseCoverage);
    await target.recordScan(
      threats: outcome.findings,
      coveragePercent: percent,
      now: DateTime.now(),
      checksRun: outcome.ran.length,
      stagesRan: outcome.ran,
      stagesNotPossible: outcome.notPossible,
      stagesFailed: outcome.failed,
    );
  }

  Future<void> _stamp(SharedPreferences prefs) =>
      prefs.setInt(_kLastAutoScanKey, DateTime.now().millisecondsSinceEpoch);
}
