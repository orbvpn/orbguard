// What the results sheet may say about a check.
//
// A pure function from what the verdict keeps of the latest check (its
// findings and the names of the checks that ran, could not run, or broke)
// and the gaps open on Home right now. The rules that keep the sheet true:
//
//  - Only a check that ran AND found nothing is listed as clean.
//  - A check the device forbids, and a check that broke, are named apart and
//    never counted as passed.
//  - One thing found is shown once: an app flagged by two checks is one app.
//  - The connection check is not called clean while a VPN or proxy waits to
//    be confirmed. That state belongs to the Hidden VPN shield, which shows
//    it as its own gap.
library;

import 'check_plan.dart';
import 'home_brief.dart';

/// One thing the check found: a finding about the device itself, or one app
/// with everything the check found about it.
class FoundThing {
  const FoundThing({required this.shield, required this.findings});

  /// The shield it belongs to: [Shield.spyware] for the device itself,
  /// [Shield.watching] for another app.
  final Shield shield;

  /// What was found, worst first. Never empty.
  final List<Map<String, dynamic>> findings;

  /// The finding to show and to open.
  Map<String, dynamic> get lead => findings.first;

  String get title => (lead['name'] ?? 'Something to review').toString();

  /// How many more findings sit behind [lead].
  int get more => findings.length - 1;
}

class CheckResults {
  const CheckResults._({
    required this.things,
    required this.clean,
    required this.notPossible,
    required this.failed,
    required this.otherGaps,
    required this.stagesKnown,
  });

  /// [stagesRan] is null when the record never named its checks (a check from
  /// before the app kept them): nothing is then claimed as clean.
  ///
  /// [gaps] are the gaps open on Home right now, biggest first.
  factory CheckResults.from({
    required List<Map<String, dynamic>> findings,
    required List<String>? stagesRan,
    required List<String> stagesNotPossible,
    required List<String> stagesFailed,
    required List<HomeGap> gaps,
  }) {
    // Findings about the device itself, one thing each, in the order found.
    final List<FoundThing> things = [];
    // Findings about other apps, gathered per app in the order first seen.
    final Map<Object, List<Map<String, dynamic>>> byApp = {};
    final Set<String> found = {};
    for (final Map<String, dynamic> finding in findings) {
      final Object? stage = finding['stage'];
      if (stage is String) found.add(stage);
      if (CheckPlan.shieldOf(finding) == Shield.watching) {
        byApp.putIfAbsent(_appOf(finding), () => []).add(finding);
      } else {
        things.add(FoundThing(shield: Shield.spyware, findings: [finding]));
      }
    }
    for (final List<Map<String, dynamic>> about in byApp.values) {
      about.sort((a, b) => _rank(a).compareTo(_rank(b)));
      things.add(FoundThing(shield: Shield.watching, findings: about));
    }

    final bool rerouteOpen = gaps.any((g) => g.factor.id == 'review_vpn');
    final List<CheckStep> clean = [
      for (final String stage in stagesRan ?? const <String>[])
        if (!found.contains(stage) &&
            !(rerouteOpen && stage == CheckPlan.rerouteStage))
          CheckPlan.byStage(stage),
    ];

    return CheckResults._(
      things: things,
      clean: clean,
      notPossible: [for (final s in stagesNotPossible) CheckPlan.byStage(s)],
      failed: [for (final s in stagesFailed) CheckPlan.byStage(s)],
      otherGaps: [
        for (final HomeGap gap in gaps)
          if (!_foundByCheck.contains(gap.factor.id)) gap,
      ],
      stagesKnown: stagesRan != null,
    );
  }

  /// What this check found, the device itself first, then apps to review.
  final List<FoundThing> things;

  /// Checks that ran and found nothing, in the order they ran.
  final List<CheckStep> clean;

  /// Checks this device or this build cannot run at all.
  final List<CheckStep> notPossible;

  /// Checks that should have run and did not.
  final List<CheckStep> failed;

  /// Gaps open now that this check did not find (a breach, a VPN or proxy).
  final List<HomeGap> otherGaps;

  /// Whether the record names the checks that ran.
  final bool stagesKnown;

  /// Nothing found, and nothing else waiting.
  bool get allClear => things.isEmpty && otherGaps.isEmpty;

  /// The gaps a check of the device opens. Their cards are [things].
  static const Set<String> _foundByCheck = {'resolve_threats', 'review_apps'};

  static const List<String> _worstFirst = ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW'];

  static int _rank(Map<String, dynamic> finding) {
    final int at = _worstFirst
        .indexOf((finding['severity'] ?? '').toString().toUpperCase());
    return at < 0 ? _worstFirst.length : at;
  }

  /// What tells one app from another: the package a finding names, or failing
  /// that the finding itself.
  static Object _appOf(Map<String, dynamic> finding) {
    final Object? path = finding['path'];
    if (path is String && path.isNotEmpty) return path;
    return finding['id'] ?? finding;
  }
}
