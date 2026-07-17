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
  /// 0–100 verdict of the latest local scan, or -1 if never scanned.
  final int lastScanScore;

  /// Days since the latest scan, or null if never scanned.
  final int? daysSinceScan;

  /// Threats currently known from the latest scan.
  final int openThreats;

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

  /// True when a VPN/proxy that isn't OrbVPN is actively routing traffic.
  /// Null when the check hasn't run.
  final bool? unknownVpnActive;

  /// Whether threat alerts can actually reach the user.
  final bool notificationsGranted;

  const PrivacySignals({
    this.lastScanScore = -1,
    this.daysSinceScan,
    this.openThreats = 0,
    this.guardsActive = 0,
    this.guardsAvailable = 0,
    this.breachedAccounts,
    this.riskyPermissionApps,
    this.unknownVpnActive,
    this.notificationsGranted = false,
  });
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

  const PrivacyScore({required this.value, required this.band, required this.factors});
}

/// Pure rubric. Component ceilings (sum = 1000):
///   installed base 200 · recent checkup 200 · clean result 150 ·
///   guards on 250 · breach check clean 100 · alerts on 50 ·
///   app audit clean 50.  An active unknown VPN deducts 50 on top.
class PrivacyScoreEngine {
  const PrivacyScoreEngine();

  static const int _base = 200;
  static const int _recency = 200;
  static const int _clean = 150;
  static const int _guards = 250;
  static const int _breach = 100;
  static const int _alerts = 50;
  static const int _audit = 50;
  static const int _vpnPenalty = 50;

  PrivacyScore compute(PrivacySignals s) {
    var value = _base;
    final factors = <ScoreFactor>[];

    // Checkup recency — a stale or absent scan is the top action.
    if (s.daysSinceScan == null) {
      factors.add(const ScoreFactor(
          id: 'run_check', label: 'Run your first privacy check', points: _recency));
    } else if (s.daysSinceScan! <= 7) {
      value += _recency;
    } else if (s.daysSinceScan! <= 30) {
      value += _recency ~/ 2;
      factors.add(const ScoreFactor(
          id: 'run_check', label: 'Run a fresh privacy check', points: _recency ~/ 2));
    } else {
      factors.add(const ScoreFactor(
          id: 'run_check', label: 'Run a fresh privacy check', points: _recency));
    }

    // Result cleanliness — open threats zero this out and become the action.
    if (s.daysSinceScan != null) {
      if (s.openThreats == 0 && s.lastScanScore >= 50) {
        value += _clean;
      } else if (s.openThreats > 0) {
        factors.add(ScoreFactor(
            id: 'resolve_threats',
            label:
                'Resolve ${s.openThreats} found threat${s.openThreats == 1 ? '' : 's'}',
            points: _clean));
      } else {
        // Clean but shallow (blocked by permissions) — the guard/permission
        // factors below carry the action; grant partial credit for a clean run.
        value += _clean ~/ 2;
      }
    }

    // Guard coverage — prorated by what THIS platform genuinely offers.
    if (s.guardsAvailable > 0) {
      final earned = (_guards * s.guardsActive / s.guardsAvailable).floor();
      value += earned;
      final missing = s.guardsAvailable - s.guardsActive;
      if (missing > 0) {
        factors.add(ScoreFactor(
            id: 'enable_guards',
            label:
                'Turn on $missing more protection${missing == 1 ? '' : 's'}',
            points: _guards - earned));
      }
    }

    // Breach exposure — unknown is an action, hits are a bigger action.
    if (s.breachedAccounts == null) {
      factors.add(const ScoreFactor(
          id: 'check_breaches',
          label: 'Check your email against known breaches',
          points: _breach));
    } else if (s.breachedAccounts == 0) {
      value += _breach;
    } else {
      factors.add(ScoreFactor(
          id: 'fix_breaches',
          label:
              'Secure ${s.breachedAccounts} breached account${s.breachedAccounts == 1 ? '' : 's'}',
          points: _breach));
    }

    // Alerts reachable.
    if (s.notificationsGranted) {
      value += _alerts;
    } else {
      factors.add(const ScoreFactor(
          id: 'enable_alerts',
          label: 'Turn on alerts so threats reach you instantly',
          points: _alerts));
    }

    // Spyware-pattern app audit (null = folded into running a check).
    if (s.riskyPermissionApps != null) {
      if (s.riskyPermissionApps == 0) {
        value += _audit;
      } else {
        factors.add(ScoreFactor(
            id: 'review_apps',
            label:
                'Review ${s.riskyPermissionApps} app${s.riskyPermissionApps == 1 ? '' : 's'} with spyware-pattern access',
            points: _audit));
      }
    }

    // Active unknown VPN — a live interception risk, deducted on top.
    if (s.unknownVpnActive == true) {
      value -= _vpnPenalty;
      factors.add(const ScoreFactor(
          id: 'review_vpn',
          label: 'Review the unknown VPN routing your traffic',
          points: _vpnPenalty));
    }

    factors.sort((a, b) => b.points.compareTo(a.points));
    final clamped = value.clamp(0, 1000);
    return PrivacyScore(value: clamped, band: _band(clamped), factors: factors);
  }

  static String _band(int v) {
    if (v >= 850) return 'Excellent';
    if (v >= 700) return 'Good';
    if (v >= 450) return 'Fair';
    return 'Needs work';
  }
}
