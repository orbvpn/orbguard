// The Privacy Score — the home's engagement engine (P4.1).
//
// A 0–1000 meter in the spirit of McAfee's Protection Score, with one hard
// difference: EVERY point maps to a genuine, verifiable signal. The engine
// is a pure function from [PrivacySignals] (gathered from real sources:
// the last scan verdict, guard states, breach results, permissions) to a
// [PrivacyScore] — no I/O, no clock, fully deterministic and testable.
//
// The factor list IS the "N things to fix" surface: each factor names the
// exact action and the exact points it's worth, so the score never nags
// vaguely and never lies. When a new breach or threat appears the score
// visibly DROPS — loss aversion working for the user's safety, backed by a
// real event.
library;

/// Everything the engine may consider. `null` consistently means
/// "not checked yet / unknown" — which is scored as an action to take,
/// never silently treated as safe.
class PrivacySignals {
  /// 0–100 verdict of the latest local scan, or -1 if never scanned. Not
  /// scored here: the rules read what was found ([openThreats],
  /// [riskyPermissionApps]). Home's wording reads it.
  final int lastScanScore;

  /// Days since the latest scan, or null if never scanned.
  final int? daysSinceScan;

  /// What the latest check found on the device itself. Apps found by the
  /// audit of other apps are counted in [riskyPermissionApps] instead, never
  /// in both.
  final int openThreats;

  /// True when every one of [openThreats] is minor: a setting to change or
  /// something to look at (a low severity finding), not a sign of spyware.
  /// They then cost [PrivacyScoreEngine] a third of the rule, not all of it.
  final bool minorThreatsOnly;

  /// Guards currently active vs available on THIS platform
  /// (unavailable guards are excluded from both numbers — iOS is never
  /// penalized for what iOS forbids).
  final int guardsActive;
  final int guardsAvailable;

  /// Breached accounts from the latest dark-web check, or null if the
  /// user has never run one.
  final int? breachedAccounts;

  /// Apps whose permission combinations match surveillance patterns
  /// (e.g. reads texts AND records screen), or null when unaudited.
  final int? riskyPermissionApps;

  /// True when a VPN or proxy is active that the person has not confirmed as
  /// theirs. Null when the check has not run.
  final bool? unknownVpnActive;

  /// Whether threat alerts can actually reach the user.
  final bool notificationsGranted;

  const PrivacySignals({
    this.lastScanScore = -1,
    this.daysSinceScan,
    this.openThreats = 0,
    this.minorThreatsOnly = false,
    this.guardsActive = 0,
    this.guardsAvailable = 0,
    this.breachedAccounts,
    this.riskyPermissionApps,
    this.unknownVpnActive,
    this.notificationsGranted = false,
    this.appAuditPossible = true,
    this.alertsPossible = true,
  });

  /// Whether this device lets an app look at the other apps on it. An iPhone
  /// does not, so there the audit points are given: nobody is marked down
  /// for something the system forbids.
  final bool appAuditPossible;

  /// Whether this device can deliver an alert at all. Where it cannot, the
  /// alert points are given for the same reason.
  final bool alertsPossible;
}

/// One line of the rubric: what it is, what it is worth, what was earned.
/// The seven of them add up to the score.
class ScoreRule {
  const ScoreRule({
    required this.id,
    required this.label,
    required this.earned,
    required this.max,
    this.waived = false,
    this.factorId,
  });

  final String id;

  /// The rule as a fact that is true at full points.
  final String label;

  final int earned;
  final int max;

  /// The points were given because this device cannot do the thing at all.
  final bool waived;

  /// Id of the fix that would earn the missing points, or null when the rule
  /// is at full points.
  final String? factorId;

  bool get full => earned >= max;
}

/// One concrete "fix this to earn N points" item.
class ScoreFactor {
  final String id;
  final String label;

  /// Points recoverable by completing this action.
  final int points;

  const ScoreFactor({required this.id, required this.label, required this.points});
}

class PrivacyScore {
  /// 0–1000.
  final int value;

  /// Plain-English band for the meter chip.
  final String band;

  /// What to fix, highest-value first. Empty at a perfect score.
  final List<ScoreFactor> factors;

  const PrivacyScore({
    required this.value,
    required this.band,
    required this.factors,
    this.rules = const [],
    this.penalty = 0,
  });

  /// The rubric, line by line, in a fixed order. Their earned points, less
  /// [penalty], are [value].
  final List<ScoreRule> rules;

  /// Points taken off on top of the rules: 50 while a VPN or proxy is active
  /// that the person has not confirmed as theirs. Otherwise 0.
  final int penalty;
}

/// Pure rubric. Seven rules whose ceilings add up to 1000:
///   installed 200, recent check 200, no spyware found 150, shields on 250,
///   no breached accounts 100, alerts can reach you 50, app audit clean 50.
/// A VPN or proxy the person has not confirmed takes 50 off on top.
///
/// One thing found costs one rule, so "closing it adds N" is always true:
/// spyware costs the 150, apps to review cost the 50, never both. When all
/// a check found on the device is minor (a firewall that is off, apps with no
/// signature), it costs 50 of the 150, not all of it.
class PrivacyScoreEngine {
  const PrivacyScoreEngine();

  static const int _base = 200;
  static const int _recency = 200;
  static const int _clean = 150;
  static const int _minor = 50;
  static const int _guards = 250;
  static const int _breach = 100;
  static const int _alerts = 50;
  static const int _audit = 50;
  static const int _vpnPenalty = 50;

  PrivacyScore compute(PrivacySignals s) {
    final factors = <ScoreFactor>[];
    final rules = <ScoreRule>[];
    final bool checked = s.daysSinceScan != null;

    void rule(String id, String label, int earned, int max,
        {bool waived = false, String? fix}) {
      rules.add(ScoreRule(
        id: id,
        label: label,
        earned: earned,
        max: max,
        waived: waived,
        factorId: earned >= max ? null : fix,
      ));
    }

    rule('installed', 'OrbGuard is installed', _base, _base);

    // Check recency: a stale or absent check is the top action.
    final int recent;
    if (!checked) {
      recent = 0;
      factors.add(const ScoreFactor(
          id: 'run_check', label: 'Run your first privacy check', points: _recency));
    } else if (s.daysSinceScan! <= 7) {
      recent = _recency;
    } else if (s.daysSinceScan! <= 30) {
      recent = _recency ~/ 2;
      factors.add(const ScoreFactor(
          id: 'run_check', label: 'Run a fresh privacy check', points: _recency ~/ 2));
    } else {
      recent = 0;
      factors.add(const ScoreFactor(
          id: 'run_check', label: 'Run a fresh privacy check', points: _recency));
    }
    rule('recent', 'Checked in the last 7 days', recent, _recency,
        fix: 'run_check');

    // What the last check found on the device itself.
    final int clean;
    if (!checked) {
      clean = 0;
    } else if (s.openThreats == 0) {
      clean = _clean;
    } else if (s.minorThreatsOnly) {
      clean = _clean - _minor;
      factors.add(ScoreFactor(
          id: 'resolve_threats',
          label:
              'Fix ${s.openThreats} thing${s.openThreats == 1 ? '' : 's'} your check found',
          points: _minor));
    } else {
      clean = 0;
      factors.add(ScoreFactor(
          id: 'resolve_threats',
          label:
              'Resolve ${s.openThreats} found threat${s.openThreats == 1 ? '' : 's'}',
          points: _clean));
    }
    rule('clean', 'No spyware found in your last check', clean, _clean,
        fix: checked ? 'resolve_threats' : 'run_check');

    // Shields: prorated by what THIS device offers.
    int shields = 0;
    if (s.guardsAvailable > 0) {
      shields = (_guards * s.guardsActive / s.guardsAvailable).floor();
      final int missing = s.guardsAvailable - s.guardsActive;
      if (missing > 0) {
        factors.add(ScoreFactor(
            id: 'enable_guards',
            label: 'Turn on $missing more protection${missing == 1 ? '' : 's'}',
            points: _guards - shields));
      }
    }
    rule('shields', 'Shields are on', shields, _guards, fix: 'enable_guards');

    // Breaches: not known is something to do, a hit is something found.
    final int breach;
    final String breachFix;
    if (s.breachedAccounts == null) {
      breach = 0;
      breachFix = 'check_breaches';
      factors.add(const ScoreFactor(
          id: 'check_breaches',
          label: 'Check your email against known breaches',
          points: _breach));
    } else if (s.breachedAccounts == 0) {
      breach = _breach;
      breachFix = 'check_breaches';
    } else {
      breach = 0;
      breachFix = 'fix_breaches';
      factors.add(ScoreFactor(
          id: 'fix_breaches',
          label:
              'Secure ${s.breachedAccounts} breached account${s.breachedAccounts == 1 ? '' : 's'}',
          points: _breach));
    }
    rule('breach', 'No breached accounts', breach, _breach, fix: breachFix);

    // Alerts.
    final int alerts;
    if (!s.alertsPossible || s.notificationsGranted) {
      alerts = _alerts;
    } else {
      alerts = 0;
      factors.add(const ScoreFactor(
          id: 'enable_alerts',
          label: 'Turn on alerts so threats reach you instantly',
          points: _alerts));
    }
    rule('alerts', 'Alerts can reach you', alerts, _alerts,
        waived: !s.alertsPossible, fix: 'enable_alerts');

    // The audit of other apps. Where it can run, its points wait for a check
    // that ran it (no factor of its own: running a check is the fix).
    final int audit;
    String auditFix = 'run_check';
    if (!s.appAuditPossible || s.riskyPermissionApps == 0) {
      audit = _audit;
    } else if (s.riskyPermissionApps == null) {
      audit = 0;
    } else {
      audit = 0;
      auditFix = 'review_apps';
      factors.add(ScoreFactor(
          id: 'review_apps',
          label:
              'Review ${s.riskyPermissionApps} app${s.riskyPermissionApps == 1 ? '' : 's'} with spyware-style access',
          points: _audit));
    }
    rule('audit', 'No apps with spyware-style access', audit, _audit,
        waived: !s.appAuditPossible, fix: auditFix);

    // A VPN or proxy nobody has confirmed: taken off on top of the rules.
    int penalty = 0;
    if (s.unknownVpnActive == true) {
      penalty = _vpnPenalty;
      factors.add(const ScoreFactor(
          id: 'review_vpn',
          label: 'Confirm the VPN or proxy on this device',
          points: _vpnPenalty));
    }

    factors.sort((a, b) => b.points.compareTo(a.points));
    final int value = (rules.fold<int>(0, (sum, r) => sum + r.earned) - penalty)
        .clamp(0, 1000);
    return PrivacyScore(
      value: value,
      band: _band(value),
      factors: factors,
      rules: rules,
      penalty: penalty,
    );
  }

  static String _band(int v) {
    if (v >= 850) return 'Excellent';
    if (v >= 700) return 'Good';
    if (v >= 450) return 'Fair';
    return 'Needs work';
  }
}
