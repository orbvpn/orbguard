/// OrbHomeScreen — Home, built around the ring.
///
/// One screen answers one question, "am I being watched?", with one drawing
/// (the ring and its six shields), one sentence, one line of proof and one
/// lime action. Under it, Today lists what OrbGuard really did.
///
/// The screen works nothing out for itself. [HomeBrief] and [HomeToday] turn
/// the injected controllers into what is shown, and they are where the
/// honesty rules live: no score before a check, a gap only for something
/// found, a shield on only when a guard is verified active, motion only while
/// something watches. This widget performs no I/O of its own; the shell wires
/// the real sources and tests inject fakes.
///
/// A check runs here, in place. While [OrbHomeScreen.check] is running the
/// ring turns into one segment per check, the hole counts them, and the list
/// of checks takes the place of the action. Every step shown is one the
/// engine reported.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/balanced_text.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/pressable.dart';
import '../../services/habit/protection_streak_controller.dart';
import '../../services/home/check_plan.dart';
import '../../services/home/check_run.dart';
import '../../services/home/guard_status_controller.dart';
import '../../services/home/home_brief.dart';
import '../../services/home/home_reading.dart';
import '../../services/home/home_today.dart';
import '../../services/home/last_scan_verdict_controller.dart';
import '../../services/home/privacy_score_engine.dart';
import '../../utils/host_platform.dart';
import '../../widgets/home/care_card.dart';
import '../../widgets/home/orb_hero.dart';
import '../../widgets/home/orb_ring.dart';
import '../../widgets/home/score_sheet.dart';
import '../../widgets/home/today_card.dart';

class OrbHomeScreen extends StatelessWidget {
  const OrbHomeScreen({
    super.key,
    required this.onRunCheck,
    required this.verdict,
    required this.guardsController,
    this.streak,
    this.onShieldTap,
    this.onFactorTap,
    this.onAlertsTap,
    this.onAccountTap,
    this.onTrustTap,
    this.accountInitial,
    this.blockedTodayCount,
    this.breachLastChecked,
    this.check,
    this.onResultsTap,
    this.breachedAccounts,
    this.unknownVpnActive,
    this.platform,
    this.clock,
  });

  /// The record of the last check on the Today card was pressed: show that
  /// check's results again.
  final VoidCallback? onResultsTap;

  /// The check that runs on Home. While it is running, Home shows it.
  final CheckRun? check;

  /// Watched email addresses with a breach still open, or null when no
  /// address has been checked. Read on every build: the shell rebuilds Home
  /// when its source changes.
  final int? Function()? breachedAccounts;

  /// Whether a VPN or proxy is active that the person has not confirmed as
  /// theirs, or null when that could not be checked.
  final bool? Function()? unknownVpnActive;

  /// The platform, for what this device can and cannot do. Defaults to the
  /// one the app runs on.
  final TargetPlatform? platform;

  /// Starts the real check. Home's one lime action, until a gap owns it.
  final VoidCallback onRunCheck;

  /// Verdict of the latest check on this device.
  final LastScanVerdictController verdict;

  /// Real guard states. They alone decide which shields are on.
  final GuardStatusController guardsController;

  /// Consecutive days with a check, for the note on the Today card.
  final ProtectionStreakController? streak;

  /// A shield on the orbit was pressed.
  final void Function(Shield shield)? onShieldTap;

  /// A fix was chosen, from the gap card or the score sheet.
  final void Function(String factorId)? onFactorTap;

  final VoidCallback? onAlertsTap;
  final VoidCallback? onAccountTap;
  final VoidCallback? onTrustTap;

  /// First letter of the signed-in person's name, or null when signed out.
  final String? accountInitial;

  /// Domains the firewall really blocked today, or null with no source.
  final int Function()? blockedTodayCount;

  /// When the email was last checked against breach records, if ever.
  final DateTime? Function()? breachLastChecked;

  /// The time, for tests. Defaults to the wall clock.
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([verdict, guardsController, streak, check]),
      builder: (context, _) {
        Theme.of(context); // Brand tokens flip with the theme
        final DateTime now = (clock ?? DateTime.now)();
        // The word for this device follows the platform Home is given, so a
        // phone-sized test on a desktop reads as a phone does.
        final String noun = deviceNounFor(platform ?? hostPlatform());
        final List<GuardStatus> guards = guardsController.guards;
        final HomeReading reading = HomeReading.of(
          verdict: verdict,
          guards: guardsController,
          breachedAccounts: breachedAccounts?.call(),
          unknownVpnActive: unknownVpnActive?.call(),
          platform: platform,
          now: now,
          deviceNoun: noun,
        );
        final PrivacyScore score = reading.score;
        final HomeBrief brief = reading.brief;
        final HomeToday today = HomeToday.from(
          lastScanAt: verdict.lastScanAt,
          threatCount: verdict.threatCount,
          blockedToday: blockedTodayCount?.call(),
          breachCheckedAt: breachLastChecked?.call(),
          streakDays: streak?.currentStreak ?? 0,
          now: now,
        );

        final GuardState? alerts = guards
            .where((g) => g.id == 'alerts')
            .map((g) => g.state)
            .firstOrNull;
        final String? action = brief.action;
        final HomeGap? gap = brief.gaps.firstOrNull;
        final int waiting = brief.gaps.length - 1;

        // The check, while one runs: what the engine has reported so far.
        final CheckRun? run = check;
        final bool checking = run != null && run.running;
        final List<CheckStep> steps = checking ? run.steps : const [];
        final List<CheckStepState> states = checking ? run.states : const [];
        final int focus = _focus(states);
        final String headline =
            checking ? 'Checking your $noun.' : brief.headline;
        final String? proof = !checking
            ? brief.proof
            : focus < steps.length
                ? steps[focus].doing
                : 'Opening your results';

        return LayoutBuilder(
          builder: (context, constraints) {
            final double reserve = GlassTheme.bottomNavClearance +
                MediaQuery.paddingOf(context).bottom;
            // One readable column, centred on a wide screen.
            final double column = math.min(constraints.maxWidth, _maxColumn);
            final double side = (constraints.maxWidth - column) / 2;
            final double room = constraints.maxHeight - reserve;
            final _Fit fit =
                _Fit.of(width: column, room: room, fresh: !verdict.hasScanned);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(side, 8, side, 16 + reserve),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: _TopRow(
                    alerts: alerts,
                    accountInitial: accountInitial,
                    // While a check runs the row keeps only the promise:
                    // nothing here should pull the eye off the check.
                    quiet: checking,
                    onTrustTap: onTrustTap,
                    onAlertsTap: onAlertsTap,
                    onAccountTap: onAccountTap,
                  ),
                ),
                // The ring glides to its place when the page under it
                // changes, so it never jumps.
                AnimatedContainer(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  height: fit.topGap,
                ),
                OrbHero(
                  brief: brief,
                  orbit: fit.orbit,
                  deviceNoun: noun,
                  checking: checking
                      ? [for (final CheckStepState s in states) _segment(s)]
                      : null,
                  ringLabel: checking
                      ? 'Checking. ${run.finished} of ${steps.length} '
                          'checks done.'
                      : brief.checked
                          ? 'Privacy score ${score.value} of 1000, '
                              '${score.band}. Show how it adds up'
                          : 'Not checked yet. Run my first check',
                  onRingTap: checking
                      ? null
                      : brief.checked
                          ? () => ScoreSheet.show(context,
                              score: score,
                              onFactorTap: onFactorTap,
                              platform: platform)
                          : onRunCheck,
                  onShieldTap: onShieldTap,
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(22, fit.headlineGap, 22, 0),
                  child: Center(
                    child: Semantics(
                      header: true,
                      child: BalancedText(headline,
                          style: BrandText.display(size: fit.headlineSize)),
                    ),
                  ),
                ),
                if (proof != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(22, fit.proofGap, 22, 0),
                    child: _Proof(
                      text: proof,
                      dot: checking
                          ? Brand.limeInk
                          : brief.moment == HomeMoment.gap
                              ? Brand.amberInk
                              : brief.moment == HomeMoment.clear && brief.live
                                  ? Brand.limeInk
                                  : null,
                    ),
                  ),
                if (checking)
                  Padding(
                    padding: EdgeInsets.fromLTRB(28, fit.actionGap, 28, 0),
                    child: _CheckList(
                      steps: steps,
                      states: states,
                      focus: focus,
                      rows: fit.listRows(room, steps.length),
                    ),
                  )
                else ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, fit.actionGap, 20, 0),
                    child: gap != null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              CareCard(
                                gap: gap,
                                onClose: onFactorTap == null
                                    ? null
                                    : () => onFactorTap!(gap.factor.id),
                              ),
                              if (waiting > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Text(
                                    '$waiting more to close after this one.',
                                    textAlign: TextAlign.center,
                                    style: BrandText.body(size: 13.5).copyWith(
                                        height: Brand.bodyHeight(1.45)),
                                  ),
                                ),
                            ],
                          )
                        : BrandButton(
                            label: action ?? 'Check now',
                            onPressed: onRunCheck,
                            borderRadius: 16,
                            padding: EdgeInsets.symmetric(
                                horizontal: 20, vertical: fit.actionPad),
                          ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(20, fit.todayGap, 20, 0),
                    child: TodayCard(today: today, onCheckTap: onResultsTap),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// The step the eye should be on: the one running, or the next to run.
  /// Past the end once every step has finished.
  static int _focus(List<CheckStepState> states) {
    final int running = states.indexOf(CheckStepState.running);
    if (running >= 0) return running;
    final int next = states.indexOf(CheckStepState.pending);
    return next >= 0 ? next : states.length;
  }

  static OrbSegment _segment(CheckStepState state) => switch (state) {
        CheckStepState.pending => OrbSegment.pending,
        CheckStepState.running => OrbSegment.running,
        CheckStepState.done => OrbSegment.done,
        CheckStepState.unavailable => OrbSegment.unavailable,
      };

  /// Home reads as one column. On a tablet or a desktop window it keeps this
  /// width and sits in the middle, instead of stretching one button across.
  static const double _maxColumn = 480;
}

/// How Home spends a screen's height.
///
/// On a tall phone everything takes its design size. On a short one the type
/// and the gaps tighten first, and then the ring gives up size, so the one
/// action still shows above the tab bar without scrolling.
class _Fit {
  const _Fit._({
    required this.tight,
    required this.orbit,
    this.drop = 0,
    this.ease = 0,
  });

  /// [width] is the column's width; [room] is the height between the top of
  /// the page and the tab bar. [fresh] says no check has run yet.
  factory _Fit.of({
    required double width,
    required double room,
    bool fresh = false,
  }) {
    final double byWidth = OrbHero.orbitForWidth(width);
    const _Fit roomy = _Fit._(tight: false, orbit: 0);
    if (room >= roomy._around + 2 * byWidth) {
      if (!fresh) return _Fit._(tight: false, orbit: byWidth);
      // Before the first check Home has little under its action: a headline
      // of one line and an empty Today card. On a tall phone the whole spare
      // height would sit in one block above the tab bar. Past what the design
      // size leaves there, it is shared out: most of it above the ring, a
      // little between the action and Today, the rest where it was.
      final double used = roomy._around -
          12 -
          roomy.headlineSize * 1.12 +
          2 * byWidth +
          _freshBelow;
      final double share = math.max(0, room - used - _designSpare);
      return _Fit._(
        tight: false,
        orbit: byWidth,
        drop: math.min(share * 0.62, 120),
        ease: math.min(share * 0.2, 28),
      );
    }
    const _Fit snug = _Fit._(tight: true, orbit: 0);
    return _Fit._(
      tight: true,
      orbit: ((room - snug._around) / 2).clamp(OrbHero.minOrbit, byWidth),
    );
  }

  /// The screen is short: type and gaps are a step tighter.
  final bool tight;

  /// Radius of the shields' orbit.
  final double orbit;

  /// Extra air above the ring, and between the action and Today. See
  /// [_Fit.of].
  final double drop;
  final double ease;

  /// What sits under the action before the first check: the gap and the
  /// empty Today card.
  static const double _freshBelow = 22 + 88;

  /// The air the design size (390 by 844) leaves under Today before the
  /// first check. Only height beyond it is shared out.
  static const double _designSpare = 44;

  double get topGap => (tight ? 6 : 12) + drop;
  double get todayGap => 22 + ease;
  double get headlineSize => tight ? 24 : 28;
  double get headlineGap => tight ? 10 : 14;
  double get proofGap => tight ? 8 : 10;
  double get actionGap => tight ? 16 : 22;

  /// Padding above and below the action's label: a 56 button, or 52.
  double get actionPad => tight ? 15 : 17;

  /// How many of a check's [count] steps the list shows at once: as many as
  /// fit between the proof line and the tab bar, and never fewer than two,
  /// so the step running now always shows with the one that follows it.
  int listRows(double room, int count) {
    final double above = 8 +
        44 +
        topGap +
        OrbHero.heightFor(orbit) +
        headlineGap +
        headlineSize * 1.12 +
        proofGap +
        20 +
        actionGap;
    final int fits = ((room - above - 12) / _CheckList.rowHeight).floor();
    return math.min(count, math.max(2, fits));
  }

  /// Height of everything from the top of the page to the foot of the action,
  /// apart from the orbit itself: the top row, a headline of two lines, one
  /// line of proof, the action, the gaps between them, and a little air above
  /// the tab bar.
  double get _around =>
      8 +
      44 +
      topGap +
      OrbHero.heightFor(0) +
      headlineGap +
      2 * headlineSize * 1.12 +
      proofGap +
      20 +
      actionGap +
      (2 * actionPad + 22) +
      12;
}

/// Home's own top row: the trust chip, the alerts bell and the account.
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.alerts,
    required this.accountInitial,
    required this.onTrustTap,
    required this.onAlertsTap,
    required this.onAccountTap,
    this.quiet = false,
  });

  /// State of the alerts guard, or null until the guards have answered.
  final GuardState? alerts;
  final String? accountInitial;

  /// Only the trust chip shows.
  final bool quiet;
  final VoidCallback? onTrustTap;
  final VoidCallback? onAlertsTap;
  final VoidCallback? onAccountTap;

  @override
  Widget build(BuildContext context) {
    final String? initial = accountInitial;
    // No bell where no alert could ever be delivered, and none shown before
    // the guards have answered: a bell must not promise what is not known.
    // It is in the tree from the first frame all the same, unseen and out of
    // reach, so its drawing is loaded and the disc never shows without it.
    final bool bell = alerts != GuardState.unavailable;
    final bool known = alerts != null;
    final bool alertsOff = alerts == GuardState.actionNeeded;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Pressable(
                onTap: onTrustTap,
                child: Container(
                  height: 32,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsetsDirectional.only(start: 10, end: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Brand.rPill),
                    border: Border.all(color: Brand.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DuotoneIcon(AppIcons.lockKeyhole,
                          size: 15, color: Brand.limeInk),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Private by design',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.body(
                            size: 12,
                            weight: FontWeight.w500,
                          ).copyWith(height: 1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (bell && !quiet)
            IgnorePointer(
              ignoring: !known,
              child: ExcludeSemantics(
                excluding: !known,
                child: AnimatedOpacity(
                  opacity: known ? 1 : 0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  child: _RoundButton(
                    label: alertsOff
                        ? 'Alerts are off. Turn on alerts'
                        : 'Alerts are on',
                    onTap: onAlertsTap,
                    badge: alertsOff,
                    child:
                        DuotoneIcon(AppIcons.bell, size: 19, color: Brand.text),
                  ),
                ),
              ),
            ),
          if (!quiet) ...[
            const SizedBox(width: 6),
            _RoundButton(
              label: 'Account',
              onTap: onAccountTap,
              child: initial == null
                  ? DuotoneIcon(AppIcons.userRounded,
                      size: 19, color: Brand.text)
                  : Text(initial,
                      style: BrandText.heading(size: 15).copyWith(height: 1)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A 40 glass disc in a 44 press target. The account is not an action, so it
/// is glass like the bell: lime stays with the one button.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.label,
    required this.onTap,
    required this.child,
    this.badge = false,
  });

  final String label;
  final VoidCallback? onTap;
  final Widget child;

  /// A small amber dot: this needs the user.
  final bool badge;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: SizedBox.square(
        dimension: 44,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Brand.glassFill,
                border: Border.all(color: Brand.glassBorder),
              ),
              child: child,
            ),
            if (badge)
              Positioned(
                top: 10,
                right: 11,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Brand.amber,
                    border: Border.all(color: Brand.bg, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The line of evidence under the headline, with a small dot when it speaks
/// for something live (lime) or for something found (amber).
class _Proof extends StatelessWidget {
  const _Proof({required this.text, this.dot});

  final String text;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final Color? dot = this.dot;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (dot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 9),
        ],
        Flexible(
          child: BalancedText(
            text,
            style: BrandText.body(size: 14, weight: FontWeight.w500)
                .copyWith(height: Brand.bodyHeight(1.42)),
          ),
        ),
      ],
    );
  }
}

/// The checks of the check that is running, one row each.
///
/// The list is as tall as the screen allows and no taller. When it cannot
/// show every check at once it follows the one running now, so nobody has to
/// scroll to see where the check is.
class _CheckList extends StatefulWidget {
  const _CheckList({
    required this.steps,
    required this.states,
    required this.focus,
    required this.rows,
  });

  static const double rowHeight = 38;

  final List<CheckStep> steps;
  final List<CheckStepState> states;

  /// Index of the step to keep in view.
  final int focus;

  /// How many rows show at once.
  final int rows;

  @override
  State<_CheckList> createState() => _CheckListState();
}

class _CheckListState extends State<_CheckList> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the running step one row above the foot of the list.
  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final double height = widget.rows * _CheckList.rowHeight;
      final double want = ((widget.focus + 2) * _CheckList.rowHeight - height)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      if ((want - _scroll.offset).abs() < 0.5) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scroll.jumpTo(want);
      } else {
        _scroll.animateTo(want,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _follow();
    final bool all = widget.rows >= widget.steps.length;
    final Widget list = SingleChildScrollView(
      controller: _scroll,
      // The list moves itself. A drag here would only fight it.
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          for (int i = 0; i < widget.steps.length; i++)
            _CheckRow(step: widget.steps[i], state: widget.states[i]),
        ],
      ),
    );

    return SizedBox(
      key: const ValueKey('check-list'),
      height: widget.rows * _CheckList.rowHeight,
      child: all
          ? list
          : ListenableBuilder(
              listenable: _scroll,
              builder: (context, child) {
                // Rows fade out at an edge that has more behind it.
                final bool has =
                    _scroll.hasClients && _scroll.position.hasContentDimensions;
                final bool above = has && _scroll.offset > 0.5;
                final bool below = !has ||
                    _scroll.offset < _scroll.position.maxScrollExtent - 0.5;
                return ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.16, 0.84, 1],
                    colors: [
                      above ? Colors.transparent : Brand.bg,
                      Brand.bg,
                      Brand.bg,
                      below ? Colors.transparent : Brand.bg,
                    ],
                  ).createShader(bounds),
                  child: child,
                );
              },
              child: list,
            ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.step, required this.state});

  final CheckStep step;
  final CheckStepState state;

  @override
  Widget build(BuildContext context) {
    final bool waiting = state == CheckStepState.pending;
    final bool failed = state == CheckStepState.unavailable;
    return Semantics(
      label: '${step.name}, ${switch (state) {
        CheckStepState.pending => 'waiting',
        CheckStepState.running => 'checking now',
        CheckStepState.done => 'done',
        CheckStepState.unavailable => 'could not run',
      }}',
      excludeSemantics: true,
      child: SizedBox(
        height: _CheckList.rowHeight,
        child: Row(
          children: [
            _CheckMark(state: state),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                step.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BrandText.body(
                  size: 14.5,
                  color: waiting ? Brand.text2 : Brand.text,
                ).copyWith(height: 1.2),
              ),
            ),
            if (failed)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 10),
                child: Text(
                  'Could not run',
                  maxLines: 1,
                  style: BrandText.body(size: 12.5, color: Brand.amberInk)
                      .copyWith(height: 1.2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The 18 mark at the head of a row: an empty circle while the step waits, a
/// turning lime arc while it runs, a lime disc with a tick once it is done,
/// and an amber circle when it could not run.
class _CheckMark extends StatefulWidget {
  const _CheckMark({required this.state});

  final CheckStepState state;

  @override
  State<_CheckMark> createState() => _CheckMarkState();
}

class _CheckMarkState extends State<_CheckMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_CheckMark old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// The arc turns only while this step runs, and not at all for someone who
  /// asked for less motion.
  void _sync() {
    final bool turn = widget.state == CheckStepState.running &&
        !MediaQuery.disableAnimationsOf(context);
    if (turn && !_turn.isAnimating) {
      _turn.repeat();
    } else if (!turn && _turn.isAnimating) {
      _turn.stop();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget mark = switch (widget.state) {
      CheckStepState.pending => _circle(Brand.border),
      CheckStepState.unavailable => _circle(Brand.amberInk),
      CheckStepState.running => RotationTransition(
          turns: _turn,
          child: CustomPaint(painter: _ArcPainter(Brand.limeInk)),
        ),
      CheckStepState.done => DecoratedBox(
          decoration:
              const BoxDecoration(shape: BoxShape.circle, color: Brand.lime),
          child: CustomPaint(painter: _TickPainter(Brand.onLime)),
        ),
    };
    return SizedBox.square(dimension: 18, child: mark);
  }

  static Widget _circle(Color color) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
      );
}

/// Three quarters of a circle, so its turning shows.
class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(
      (Offset.zero & size).deflate(0.75),
      0,
      math.pi * 1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.color != color;
}

class _TickPainter extends CustomPainter {
  const _TickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width, h = size.height;
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.29, h * 0.52)
        ..lineTo(w * 0.44, h * 0.67)
        ..lineTo(w * 0.72, h * 0.36),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}
