// One reading of everything Home knows.
//
// Home draws from it, and the shell reads the same thing when it opens a
// check's results or routes a fix, so the two can never disagree about the
// score, the gaps, or what a check found. A pure function of the sources it
// is given: no I/O and no clock of its own.
library;

import 'package:flutter/foundation.dart';

import '../../utils/host_platform.dart';
import 'check_results.dart';
import 'guard_status_controller.dart';
import 'home_brief.dart';
import 'home_signals.dart';
import 'last_scan_verdict_controller.dart';
import 'privacy_score_engine.dart';

class HomeReading {
  const HomeReading._({
    required this.signals,
    required this.score,
    required this.brief,
  });

  /// [breachedAccounts] and [unknownVpnActive] are null when there is no
  /// answer yet. That is "not known", which the score counts as something to
  /// do and never as safe.
  ///
  /// [platform] is the device the reading is for; null is the one the app
  /// runs on.
  factory HomeReading.of({
    required LastScanVerdictController verdict,
    required GuardStatusController guards,
    required int? breachedAccounts,
    required bool? unknownVpnActive,
    required TargetPlatform? platform,
    required DateTime now,
    required String deviceNoun,
  }) {
    final List<GuardStatus> states = guards.guards;
    final PrivacySignals signals = HomeSignals.gather(
      verdictScore: verdict.score,
      lastScanAt: verdict.lastScanAt,
      threatCount: verdict.threatCount,
      findings: verdict.findings,
      stagesRan: verdict.stagesRan,
      guardsActive: guards.activeCount,
      guardsAvailable: guards.availableCount,
      alertsOn:
          states.any((g) => g.id == 'alerts' && g.state == GuardState.active),
      // A device that cannot deliver an alert is not marked down for it.
      alertsPossible: !states
          .any((g) => g.id == 'alerts' && g.state == GuardState.unavailable),
      // Only Android lets an app look at the other apps on the device.
      appAuditPossible: (platform ?? hostPlatform()) == TargetPlatform.android,
      breachedAccounts: breachedAccounts,
      unknownVpnActive: unknownVpnActive,
      now: now,
    );
    final PrivacyScore score = const PrivacyScoreEngine().compute(signals);
    return HomeReading._(
      signals: signals,
      score: score,
      brief: HomeBrief.from(
        hasScanned: verdict.hasScanned,
        verdictScore: verdict.score,
        lastScanAt: verdict.lastScanAt,
        checksRun: verdict.checksRun,
        openThreats: signals.openThreats,
        minorThreatsOnly: signals.minorThreatsOnly,
        appsToReview: signals.riskyPermissionApps ?? 0,
        breachedAccounts: signals.breachedAccounts ?? 0,
        score: score,
        guards: states,
        guardsResolved: states.isNotEmpty,
        now: now,
        deviceNoun: deviceNoun,
      ),
    );
  }

  final PrivacySignals signals;
  final PrivacyScore score;
  final HomeBrief brief;

  /// What the results sheet may say about the latest check [verdict] keeps,
  /// with the gaps open right now.
  CheckResults results(LastScanVerdictController verdict) => CheckResults.from(
        findings: verdict.findings,
        stagesRan: verdict.stagesRan,
        stagesNotPossible: verdict.stagesNotPossible,
        stagesFailed: verdict.stagesFailed,
        gaps: brief.gaps,
      );
}
