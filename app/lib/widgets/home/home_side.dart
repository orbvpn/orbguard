/// Home's other pane, on a foldable, a tablet or a desktop window: what the
/// ring opens.
///
/// Beside Home it shows Today and the six shields. While a check runs it is
/// the list of every check, so the ring's pane keeps only the ring, the
/// verdict and the line that says what is being checked now.
///
/// It reads the same sources the ring's pane was given, at the same moment
/// and through the same [HomeReading], so the two panes can never disagree:
/// a shield's chip here says what its disc on the ring says.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_rows.dart';
import '../../presentation/widgets/page_head.dart';
import '../../presentation/widgets/pressable.dart';
import '../../screens/home/orb_home_screen.dart';
import '../../services/home/check_run.dart';
import '../../services/home/home_brief.dart';
import '../../services/home/home_reading.dart';
import '../../services/home/home_today.dart';
import '../../utils/host_platform.dart';
import '../shields/shield_look.dart';
import 'check_list.dart';
import 'today_card.dart';

class HomeSide extends StatelessWidget {
  const HomeSide({
    super.key,
    required this.home,
    this.columns = 2,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 26),
  });

  /// The Home the ring's pane draws. Its sources and its callbacks are the
  /// ones this pane uses.
  final OrbHomeScreen home;

  /// Shield tiles in a row: two in a pane, three in a desktop column.
  final int columns;

  /// Space around the page, inside the safe area the shell gives the pane.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final OrbHomeScreen home = this.home;
    return ListenableBuilder(
      listenable: Listenable.merge(
          [home.verdict, home.guardsController, home.streak, home.check]),
      builder: (context, _) {
        Theme.of(context); // Brand tokens flip with the theme
        final DateTime now = (home.clock ?? DateTime.now)();
        final String noun = deviceNounFor(home.platform ?? hostPlatform());
        final EdgeInsets safe = MediaQuery.paddingOf(context);
        final EdgeInsets pad = padding.copyWith(
          top: padding.top + safe.top,
          bottom: padding.bottom + safe.bottom,
        );

        final CheckRun? run = home.check;
        if (run != null && run.running) {
          final int running = run.states.indexOf(CheckStepState.running);
          final int next = run.states.indexOf(CheckStepState.pending);
          return ListView(
            padding: pad,
            children: [
              PageHead(
                title: 'Checking',
                subtitle: 'Only what this $noun can really run.',
              ),
              BrandGlass(
                radius: 24,
                elevated: false,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: CheckList(
                  steps: run.steps,
                  states: run.states,
                  focus: running >= 0
                      ? running
                      : next >= 0
                          ? next
                          : run.steps.length,
                  // A pane has room for every check at once.
                  rows: run.steps.length,
                ),
              ),
            ],
          );
        }

        final HomeBrief brief = HomeReading.of(
          verdict: home.verdict,
          guards: home.guardsController,
          breachedAccounts: home.breachedAccounts?.call(),
          unknownVpnActive: home.unknownVpnActive?.call(),
          platform: home.platform,
          now: now,
          deviceNoun: noun,
        ).brief;
        final HomeToday today = HomeToday.from(
          lastScanAt: home.verdict.lastScanAt,
          threatCount: home.verdict.threatCount,
          blockedToday: home.blockedTodayCount?.call(),
          breachCheckedAt: home.breachLastChecked?.call(),
          streakDays: home.streak?.currentStreak ?? 0,
          now: now,
        );

        return ListView(
          padding: pad,
          children: [
            PageHead(title: today.label, subtitle: today.aside),
            TodayCard(today: today, bare: true, onCheckTap: home.onResultsTap),
            const SectionLabel('Your shields'),
            _ShieldGrid(
              brief: brief,
              columns: columns,
              selected: home.selectedShield,
              onTap: home.onShieldTap,
            ),
          ],
        );
      },
    );
  }
}

/// The six shields as tiles, in the ring's order, each with the state its
/// disc on the ring shows.
class _ShieldGrid extends StatelessWidget {
  const _ShieldGrid({
    required this.brief,
    required this.columns,
    required this.selected,
    required this.onTap,
  });

  final HomeBrief brief;
  final int columns;
  final Shield? selected;
  final void Function(Shield shield)? onTap;

  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    const List<Shield> all = Shield.values;
    return Column(
      children: [
        for (int r = 0; r * columns < all.length; r++)
          Padding(
            padding: EdgeInsets.only(top: r == 0 ? 0 : _gap),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int c = 0; c < columns; c++) ...[
                    if (c > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: r * columns + c < all.length
                          ? _ShieldTile(
                              key: ValueKey(
                                  'shield-tile-${all[r * columns + c].name}'),
                              shield: all[r * columns + c],
                              state: brief.shields[all[r * columns + c]]!,
                              known: brief.shieldsKnown,
                              selected: all[r * columns + c] == selected,
                              onTap: onTap,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ShieldTile extends StatelessWidget {
  const _ShieldTile({
    super.key,
    required this.shield,
    required this.state,
    required this.known,
    required this.selected,
    required this.onTap,
  });

  final Shield shield;
  final ShieldState state;
  final bool known;
  final bool selected;
  final void Function(Shield shield)? onTap;

  @override
  Widget build(BuildContext context) {
    final bool care = known && state == ShieldState.care;
    final Color ink = !known
        ? Brand.text3
        : switch (state) {
            ShieldState.on => Brand.limeInk,
            ShieldState.care => Brand.amberInk,
            ShieldState.limited => Brand.text2,
            ShieldState.off => Brand.text3,
          };
    final BorderRadius radius = BorderRadius.circular(18);
    final void Function(Shield shield)? onTap = this.onTap;

    return Semantics(
      selected: selected,
      child: Pressable(
        onTap: onTap == null ? null : () => onTap(shield),
        radius: radius,
        child: BrandGlass(
          radius: 18,
          elevated: false,
          borderColor: selected ? Brand.limeInk : null,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The chip sits at the end of the icon's line, and goes under
              // the icon, whole, when the tile is too narrow for both.
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: care ? Brand.amberPill : Brand.hairline,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DuotoneIcon(shield.icon, size: 17, color: ink),
                    ),
                    if (known) ShieldChip.of(state),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                shield.name,
                style: BrandText.title(size: 14.5, color: Brand.text)
                    .copyWith(height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shield's state in one or two words, the way its disc on the ring
/// shows it: lime when it is on, amber when it found something, plain
/// otherwise.
class ShieldChip extends StatelessWidget {
  const ShieldChip({
    super.key,
    required this.text,
    required this.fill,
    required this.ink,
    this.dot = false,
  });

  factory ShieldChip.of(ShieldState state) => switch (state) {
        ShieldState.on => ShieldChip(
            text: 'On',
            fill: Brand.navActivePill,
            ink: Brand.limeInk,
            dot: true),
        ShieldState.care => ShieldChip(
            text: '1 gap',
            fill: Brand.amberPill,
            ink: Brand.amberInk,
            dot: true),
        ShieldState.limited =>
          ShieldChip(text: 'Not here', fill: Brand.hairline, ink: Brand.text2),
        ShieldState.off =>
          ShieldChip(text: 'Off', fill: Brand.hairline, ink: Brand.text2),
      };

  final String text;
  final Color fill;
  final Color ink;

  /// A small dot before the words, for a state that is live.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Brand.rPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: ink),
            ),
            const SizedBox(width: 6),
          ],
          Text(text,
              maxLines: 1,
              style: BrandText.title(size: 12, color: ink).copyWith(height: 1)),
        ],
      ),
    );
  }
}
