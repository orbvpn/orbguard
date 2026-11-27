// What Home says, worked out from real signals only.
//
// A pure function: the last check, the guard states and the privacy score go
// in; the moment, the ring's gaps, the six shield states and the words come
// out. No I/O and no clock of its own, so every sentence Home can show is
// covered by a test.
//
// The honesty rules live here, in one place:
//  - nothing reads as clear before a check has run
//  - the ring opens only for something FOUND; a thing that is merely not set
//    up lowers the score and nothing else
//  - a shield is on only when one of its guards is verified active, and a
//    shield this device cannot run is never shown as on
//  - the ring is "live" only while something watches on its own
//  - every count and every time comes from a stored event
library;

import 'guard_status_controller.dart';
import 'privacy_score_engine.dart';

/// Which of Home's three faces is showing.
enum HomeMoment {
  /// No check has run yet.
  fresh,

  /// Checked, and nothing found is waiting.
  clear,

  /// Something found is waiting for the user.
  gap,
}

/// How one shield stands right now.
enum ShieldState {
  /// One of its guards is verified active.
  on,

  /// It found something that needs the user.
  care,

  /// This device cannot run it.
  limited,

  /// It can run here and is not turned on.
  off,
}

/// The six shields, each with its station on the dial around the ring
/// (degrees clockwise from twelve o'clock).
enum Shield {
  spyware(
    angle: 330,
    name: 'Spyware & Pegasus',
    guards: ['spyware_watch', 'malware_scan'],
    finding: 'resolve_threats',
  ),
  watching(
    angle: 30,
    name: 'Who’s watching you',
    guards: ['firewall'],
    finding: 'review_apps',
  ),
  scam(
    angle: 90,
    name: 'Scam shield',
    guards: ['sms_filter'],
  ),
  identity(
    angle: 150,
    name: 'Identity & breach',
    guards: ['breach'],
    finding: 'fix_breaches',
  ),
  hiddenVpn(
    angle: 210,
    name: 'Hidden VPN & proxy',
    guards: ['hidden_vpn'],
    finding: 'review_vpn',
  ),
  secureCall(
    angle: 270,
    name: 'Secure call',
    guards: ['secure_call'],
  );

  const Shield({
    required this.angle,
    required this.name,
    required this.guards,
    this.finding,
  });

  /// Where it sits around the ring, and where the ring opens for it.
  final double angle;

  /// The one name this shield goes by, everywhere in the app.
  final String name;

  /// Ids of the guards whose real state decides whether it is on.
  final List<String> guards;

  /// Id of the score factor that means this shield FOUND something.
  final String? finding;
}

/// One thing found that is waiting for the user: a gap in the ring.
class HomeGap {
  const HomeGap({
    required this.shield,
    required this.factor,
    required this.title,
    required this.detail,
  });

  /// The shield that found it. The ring opens toward this shield.
  final Shield shield;

  /// The score factor behind it: its id routes the fix, its points are real.
  final ScoreFactor factor;

  final String title;
  final String detail;

  String get gain => 'Closing it adds ${factor.points} to your score';
}

class HomeBrief {
  const HomeBrief._({
    required this.moment,
    required this.score,
    required this.headline,
    required this.proof,
    required this.action,
    required this.gaps,
    required this.severe,
    required this.shields,
    required this.shieldsKnown,
    required this.live,
    required this.still,
    required this.allClear,
  });

  final HomeMoment moment;

  /// 0 to 1000, or null until a check has run: a number before any check
  /// would be a verdict nobody reached.
  final int? score;

  /// A check has run on this device.
  bool get checked => score != null;

  final String headline;

  /// The line of evidence under the headline, when there is any.
  final String? proof;

  /// Label of Home's one action, or null when a gap owns the action.
  final String? action;

  /// Things found, biggest first. Empty unless [moment] is [HomeMoment.gap].
  final List<HomeGap> gaps;

  /// A critical or high finding: said plainly, not counted as a gap.
  final bool severe;

  /// All six shields, in dial order.
  final Map<Shield, ShieldState> shields;

  /// False until the guards have answered once. Until then every shield
  /// reads [ShieldState.off], which says "not known yet", not "turned off".
  final bool shieldsKnown;

  /// Something is watching on its own right now.
  final bool live;

  /// Checked, and nothing is watching on its own.
  final bool still;

  /// A recent check that could look deep found nothing, and nothing found
  /// is waiting: the one case Home says no signs of being watched.
  final bool allClear;

  /// Guards that keep watching without being asked. The others are tools that
  /// wait to be used, and a tool that waits is not a watch.
  static const Set<String> _watchers = {'spyware_watch', 'firewall'};

  /// A check older than this no longer earns its full score, and no longer
  /// speaks for today.
  static const int _freshDays = 7;

  /// Below this, a clean check could not see enough to call anything clear
  /// (the "attention" band of the verdict score).
  static const int _deepEnough = 70;

  /// At or below this with something found, the finding is critical or high.
  static const int _severeAt = 45;

  /// The findings a check of the device makes. The others (a breach, a VPN)
  /// are found some other way, and claim no check time.
  static const Set<String> _foundByCheck = {'resolve_threats', 'review_apps'};

  /// The one gap that is a question to the person rather than a finding.
  static const String _question = 'review_vpn';

  factory HomeBrief.from({
    required bool hasScanned,
    required int verdictScore,
    required DateTime? lastScanAt,
    required int? checksRun,
    required int openThreats,
    int appsToReview = 0,
    int breachedAccounts = 0,
    required PrivacyScore score,
    required List<GuardStatus> guards,
    required bool guardsResolved,
    required DateTime now,
    required String deviceNoun,
  }) {
    final List<HomeGap> gaps = [
      for (final HomeGap gap
          in _gaps(score, openThreats, appsToReview, breachedAccounts))
        // Whose VPN it is is a question, not a finding, and most often the
        // answer is "mine". Until the first check has run Home has one job,
        // to get it run, so the question waits for that check's results.
        if (hasScanned || gap.factor.id != _question) gap,
    ];
    final Set<Shield> opened = {for (final g in gaps) g.shield};
    final Map<Shield, ShieldState> shields = {
      for (final s in Shield.values)
        s: opened.contains(s) ? ShieldState.care : _state(s, guards),
    };

    final bool live = guards
        .any((g) => g.state == GuardState.active && _watchers.contains(g.id));
    final bool still = hasScanned && guardsResolved && !live;
    final bool severe = hasScanned &&
        openThreats + appsToReview > 0 &&
        verdictScore <= _severeAt;
    final String? checked = lastScanAt == null ? null : ago(lastScanAt, now);

    final HomeMoment moment = gaps.isNotEmpty
        ? HomeMoment.gap
        : hasScanned
            ? HomeMoment.clear
            : HomeMoment.fresh;

    final String headline;
    String? proof;
    String? action;
    bool allClear = false;
    switch (moment) {
      case HomeMoment.fresh:
        headline = 'Let’s check your $deviceNoun.';
        proof = 'One tap. The check runs on this $deviceNoun.';
        action = 'Run my first check';
      case HomeMoment.gap:
        headline = severe
            ? 'Your $deviceNoun needs attention.'
            : '${_counted(gaps.length)} to close.';
        // A check time is claimed only when the check is what found it.
        if (gaps.length == 1 &&
            _foundByCheck.contains(gaps.single.factor.id) &&
            checked != null) {
          proof = 'Found in your last check, $checked.';
        }
      case HomeMoment.clear:
        final bool old = now.difference(lastScanAt ?? now).inDays > _freshDays;
        final bool shallow = verdictScore < _deepEnough;
        allClear = !old && !shallow;
        headline = old
            ? 'Nothing found last time.'
            : shallow
                ? 'Nothing found so far.'
                : 'No signs you’re being watched.';
        if (still) {
          proof = 'Nothing is on watch between checks.';
        } else if (old) {
          proof = 'Last check was $checked. Time for a fresh one.';
        } else if (shallow) {
          proof =
              'The last check could not look deep. Allow more access to be sure.';
        } else if (checksRun != null && checksRun > 0) {
          proof = '$checksRun check${checksRun == 1 ? '' : 's'} ran $checked, '
              'all clean';
        } else {
          proof = 'Checked $checked. Nothing found.';
        }
        action = 'Check now';
    }

    return HomeBrief._(
      moment: moment,
      score: hasScanned ? score.value : null,
      headline: headline,
      proof: proof,
      action: action,
      gaps: gaps,
      severe: severe,
      shields: shields,
      shieldsKnown: guardsResolved,
      live: live,
      still: still,
      allClear: allClear,
    );
  }

  /// How long ago, the way a person would say it.
  static String ago(DateTime then, DateTime now) {
    final Duration d = now.difference(then);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) {
      return d.inHours == 1 ? '1 hour ago' : '${d.inHours} hours ago';
    }
    // From a day back, count calendar days, so "yesterday" means yesterday.
    final int days = DateTime.utc(now.year, now.month, now.day)
        .difference(DateTime.utc(then.year, then.month, then.day))
        .inDays;
    return days <= 1 ? 'yesterday' : '$days days ago';
  }

  /// The factors that mean something was FOUND, as gaps, biggest first.
  ///
  /// The words say what happened and what the person can do, and never more
  /// than is known: a VPN is "active", not "spying", until they say whose it
  /// is.
  static List<HomeGap> _gaps(PrivacyScore score, int openThreats,
      int appsToReview, int breachedAccounts) {
    final List<HomeGap> gaps = [];
    for (final ScoreFactor factor in score.factors) {
      for (final Shield shield in Shield.values) {
        if (shield.finding != factor.id) continue;
        final (String title, String detail) = switch (factor.id) {
          'resolve_threats' => (
              'Your last check found $openThreats '
                  'thing${openThreats == 1 ? '' : 's'}',
              openThreats == 1
                  ? 'See what it is and how to remove it.'
                  : 'See what they are and how to remove them.',
            ),
          'review_apps' => (
              'Your last check found $appsToReview '
                  'app${appsToReview == 1 ? '' : 's'} to review',
              appsToReview == 1
                  ? 'See which app and what it can reach.'
                  : 'See which apps and what they can reach.',
            ),
          'review_vpn' => (
              'A VPN or proxy is active',
              'If it is yours, tell OrbGuard. If it is not, turn it off.',
            ),
          'fix_breaches' => (
              breachedAccounts <= 1
                  ? 'Your email was in a data breach'
                  : '$breachedAccounts of your emails were in data breaches',
              'See what leaked and what to change.',
            ),
          _ => (factor.label, 'See what it is and what to do.'),
        };
        gaps.add(HomeGap(
            shield: shield, factor: factor, title: title, detail: detail));
      }
    }
    return gaps
      ..sort((a, b) {
        final int byPoints = b.factor.points.compareTo(a.factor.points);
        return byPoints != 0
            ? byPoints
            : a.shield.index.compareTo(b.shield.index);
      });
  }

  static ShieldState _state(Shield shield, List<GuardStatus> guards) {
    final Iterable<GuardState> states =
        guards.where((g) => shield.guards.contains(g.id)).map((g) => g.state);
    if (states.contains(GuardState.active)) return ShieldState.on;
    if (states.contains(GuardState.actionNeeded)) return ShieldState.off;
    if (states.contains(GuardState.unavailable)) return ShieldState.limited;
    return ShieldState.off;
  }

  static String _counted(int gaps) => switch (gaps) {
        1 => 'One gap',
        2 => 'Two gaps',
        3 => 'Three gaps',
        4 => 'Four gaps',
        _ => '$gaps gaps',
      };
}
