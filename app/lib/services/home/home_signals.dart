// What Home knows, gathered into the score engine's signals.
//
// A pure function, so the one rule that matters here is covered by a test:
// a thing found by a check is counted once. A finding about the device itself
// is spyware to resolve (the Spyware shield, 150 points). A finding about
// another app is an app to review (Who's watching you, 50 points). Counting
// one finding under both would open two gaps for one thing and make "closing
// it adds N" untrue.
library;

import 'check_plan.dart';
import 'home_brief.dart';
import 'privacy_score_engine.dart';

abstract final class HomeSignals {
  /// [threatCount], [findings] and [stagesRan] are the latest check as the
  /// verdict stored it. [findings] may be empty although [threatCount] is not
  /// (the list could not be kept): the count then stands as spyware, and
  /// which of them were apps is not known.
  static PrivacySignals gather({
    required int verdictScore,
    required DateTime? lastScanAt,
    required int threatCount,
    required List<Map<String, dynamic>> findings,
    required List<String>? stagesRan,
    required int guardsActive,
    required int guardsAvailable,
    required bool alertsOn,
    required bool alertsPossible,
    required bool appAuditPossible,
    required int? breachedAccounts,
    required bool? unknownVpnActive,
    required DateTime now,
  }) {
    final bool checked = lastScanAt != null;
    final bool listKept = findings.length == threatCount;

    // Findings about other apps, and the apps they are about. One app flagged
    // by two checks is one app to review.
    final List<Map<String, dynamic>> aboutApps = !listKept
        ? const []
        : [
            for (final Map<String, dynamic> f in findings)
              if (CheckPlan.shieldOf(f) == Shield.watching) f,
          ];
    final Set<Object> apps = {for (final f in aboutApps) _appOf(f)};

    // The audit's answer is a number only when a check really ran it and the
    // list of what it found is still there to count.
    final bool auditRan = (stagesRan ?? const <String>[])
        .any((stage) => CheckPlan.byStage(stage).shield == Shield.watching);
    final int? appsToReview =
        checked && appAuditPossible && listKept && auditRan
            ? apps.length
            : null;

    return PrivacySignals(
      lastScanScore: verdictScore,
      daysSinceScan: checked ? now.difference(lastScanAt).inDays : null,
      openThreats: threatCount - aboutApps.length,
      guardsActive: guardsActive,
      guardsAvailable: guardsAvailable,
      breachedAccounts: breachedAccounts,
      riskyPermissionApps: appsToReview,
      unknownVpnActive: unknownVpnActive,
      notificationsGranted: alertsOn,
      appAuditPossible: appAuditPossible,
      alertsPossible: alertsPossible,
    );
  }

  /// What tells one app from another in a finding: the package it names, or
  /// failing that the finding itself.
  static Object _appOf(Map<String, dynamic> finding) {
    final Object? path = finding['path'];
    if (path is String && path.isNotEmpty) return path;
    return finding['id'] ?? finding;
  }
}
