/// The sheet a finished check opens: what it found, what ran clean, what
/// this device cannot run and what broke.
///
/// It draws [CheckResults] and adds nothing of its own. A check the device
/// forbids and a check that broke are named apart and never counted as
/// passed, and no count is written when the record does not hold one.
/// Pressing a thing or a gap opens its fix over this sheet, which stays
/// open; Done closes it.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/theme/glass_theme.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_rows.dart';
import '../../presentation/widgets/pressable.dart';
import '../../services/home/check_plan.dart';
import '../../services/home/check_results.dart';
import '../../services/home/home_brief.dart';
import '../../utils/host_platform.dart';
import '../sale/credit_line.dart';
import '../shields/shield_look.dart';
import 'orb_ring.dart';
import 'share_card.dart';

class ResultsSheet extends StatelessWidget {
  const ResultsSheet({
    super.key,
    required this.results,
    required this.onOpenThing,
    required this.onOpenGap,
    this.platform,
    this.checkedToday = false,
  });

  final CheckResults results;
  final void Function(FoundThing thing) onOpenThing;
  final void Function(HomeGap gap) onOpenGap;

  /// The device the words are for. Defaults to the one this runs on.
  final TargetPlatform? platform;

  /// The check ran today, so its result may be shared as today's.
  final bool checkedToday;

  static Future<void> show(
    BuildContext context, {
    required CheckResults results,
    required void Function(FoundThing) onOpenThing,
    required void Function(HomeGap) onOpenGap,
    TargetPlatform? platform,
    bool checkedToday = false,
  }) =>
      showAppSheet<void>(
        context,
        heightFactor: 0.94,
        child: ResultsSheet(
          results: results,
          onOpenThing: onOpenThing,
          onOpenGap: onOpenGap,
          platform: platform,
          checkedToday: checkedToday,
        ),
      );

  // ── Words ────────────────────────────────────────────────────────────────

  static String _ranClean(int n) =>
      n == 1 ? '1 check ran clean.' : '$n checks ran clean.';

  static String _count(int n) => switch (n) {
        1 => 'One',
        2 => 'Two',
        3 => 'Three',
        4 => 'Four',
        _ => '$n',
      };

  static String _stillOpen(int n) =>
      n == 1 ? 'One gap is still open.' : '${_count(n)} gaps are still open.';

  /// A check broke, or none ran at all: whatever was found, the device was
  /// not looked over in full, so nothing here may read as clear.
  bool get _partial =>
      results.failed.isNotEmpty ||
      (results.stagesKnown && results.clean.isEmpty && results.things.isEmpty);

  String get _title {
    final int k = results.things.length;
    if (k == 1) return 'Your check found 1 thing';
    if (k > 1) return 'Your check found $k things';
    if (_partial) {
      return results.clean.isEmpty
          ? 'Nothing was checked'
          : 'Nothing found so far';
    }
    return results.otherGaps.isEmpty ? 'All clear' : 'Checks are clean';
  }

  String? get _line {
    final int n = results.clean.length;
    final int broke = results.failed.length;
    final List<String> said = [
      if (results.stagesKnown && n > 0) _ranClean(n),
      // Said next to the count only when nothing was found: with things
      // found, the title and the cards come first and the block below names
      // the checks that broke.
      if (results.things.isEmpty && broke > 0)
        n > 0
            ? '$broke could not run.'
            : '$broke check${broke == 1 ? '' : 's'} could not run.',
      if (results.things.isEmpty && results.otherGaps.isNotEmpty)
        _stillOpen(results.otherGaps.length),
    ];
    return said.isEmpty ? null : said.join(' ');
  }

  /// "iPhone", "this Mac", "this computer", "this phone".
  static String _placeOn(TargetPlatform? on) => switch (on) {
        TargetPlatform.iOS => 'iPhone',
        TargetPlatform.macOS => 'this Mac',
        TargetPlatform.windows || TargetPlatform.linux => 'this computer',
        TargetPlatform.android => 'this phone',
        _ => 'this device',
      };

  static String _whyNot(TargetPlatform? on, bool one) {
    final String these = one ? 'this' : 'these';
    final String passed = one
        ? 'so it is not counted as passed.'
        : 'so they are not counted as passed.';
    return switch (on) {
      TargetPlatform.iOS => 'iOS does not let any app run $these, $passed',
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        'OrbGuard cannot run $these on a ${deviceNounFor(on)} yet, $passed',
      _ => 'This version of OrbGuard cannot run $these, $passed',
    };
  }

  static String _names(List<CheckStep> steps) =>
      '${steps.map((s) => s.name).join(', ')}.';

  /// The ring opens toward every shield with something on it. With nothing
  /// open and a check that broke, it shows the check as it went: a part for
  /// each check that ran, a hatched part for each that did not.
  OrbStatus get _ring {
    if (results.allClear && _partial) {
      return OrbStatus.checking([
        for (final CheckStep _ in results.clean) OrbSegment.done,
        for (final CheckStep _ in results.failed) OrbSegment.unavailable,
      ]);
    }
    if (results.allClear) return const OrbStatus.whole();
    final List<double> gaps = [];
    for (final Shield shield in [
      for (final FoundThing t in results.things) t.shield,
      for (final HomeGap g in results.otherGaps) g.shield,
    ]) {
      if (!gaps.contains(shield.angle)) gaps.add(shield.angle);
    }
    return OrbStatus.open(gaps);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final TargetPlatform? on = platform ?? hostPlatform();
    final String? line = _line;
    final List<CheckStep> notPossible = results.notPossible;
    final List<CheckStep> failed = results.failed;

    final List<Widget> sections = [
      if (results.things.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < results.things.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _ThingCard(
                thing: results.things[i],
                onTap: () => onOpenThing(results.things[i]),
              ),
            ],
          ],
        ),
      if (results.otherGaps.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Still open', top: 0),
            GlassRows(rows: [
              for (final HomeGap gap in results.otherGaps)
                GlassRow(
                  icon: gap.shield.icon,
                  iconColor: Brand.amberInk,
                  title: gap.title,
                  line: gap.gain,
                  onTap: () => onOpenGap(gap),
                ),
            ]),
          ],
        ),
      if (results.clean.isNotEmpty) _CleanList(steps: results.clean),
      if (notPossible.isNotEmpty)
        _DashedNote(
          title: notPossible.length == 1
              ? '1 check is not possible on ${_placeOn(on)}'
              : '${notPossible.length} checks are not possible on '
                  '${_placeOn(on)}',
          body: '${_names(notPossible)} '
              '${_whyNot(on, notPossible.length == 1)}',
        ),
      if (failed.isNotEmpty)
        _DashedNote(
          title: failed.length == 1
              ? '1 check could not run this time'
              : '${failed.length} checks could not run this time',
          body: '${_names(failed)} '
              '${failed.length == 1 ? 'It is' : 'They are'} not counted as '
              'passed. Run the check again.',
        ),
      const CreditLine(),
    ];

    // At most one lime action.
    final Widget buttons;
    void done() => Navigator.of(context).pop();
    const EdgeInsets pad = EdgeInsets.symmetric(horizontal: 12, vertical: 15);
    if (results.things.isNotEmpty || results.otherGaps.isNotEmpty) {
      final bool found = results.things.isNotEmpty;
      buttons = Row(
        children: [
          Expanded(
            child: BrandButton.secondary(
                label: 'Done', onPressed: done, padding: pad),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BrandButton(
              label: found ? 'See what to do' : 'Close the gap',
              padding: pad,
              onPressed: found
                  ? () => onOpenThing(results.things.first)
                  : () => onOpenGap(results.otherGaps.first),
            ),
          ),
        ],
      );
    } else if (checkedToday && !_partial && results.stagesKnown) {
      // An all clear from today can be shared. Done stays the lime one.
      buttons = Row(
        children: [
          Expanded(
            child: BrandButton.secondary(
              label: 'Share',
              padding: pad,
              onPressed: () => ShareSheet.show(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: BrandButton(label: 'Done', onPressed: done, padding: pad),
          ),
        ],
      );
    } else {
      buttons = BrandButton(label: 'Done', onPressed: done);
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 8),
              children: [
                Center(
                  child: ExcludeSemantics(
                    child: OrbRing(status: _ring, size: 84),
                  ),
                ),
                const SizedBox(height: 16),
                Semantics(
                  header: true,
                  child: Text(_title,
                      textAlign: TextAlign.center,
                      style: BrandText.h2(color: cs.onSurface, size: 23)),
                ),
                if (line != null) ...[
                  const SizedBox(height: 8),
                  Text(line,
                      textAlign: TextAlign.center,
                      style: BrandText.body(size: 15, color: Brand.text2)),
                ],
                const SizedBox(height: 18),
                for (int i = 0; i < sections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  sections[i],
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                22, 8, 22, 20 + MediaQuery.paddingOf(context).bottom),
            child: buttons,
          ),
        ],
      ),
    );
  }
}

/// One thing the check found: its name, what it is, how serious.
class _ThingCard extends StatelessWidget {
  const _ThingCard({required this.thing, required this.onTap});

  final FoundThing thing;
  final VoidCallback onTap;

  static Color _tint(String severity) => switch (severity) {
        'CRITICAL' => AppColors.severityCritical,
        'HIGH' => AppColors.severityHigh,
        'MEDIUM' => AppColors.severityMedium,
        'LOW' => AppColors.severityLow,
        _ => AppColors.severityInfo,
      };

  static String _icon(String severity) => switch (severity) {
        'CRITICAL' || 'HIGH' => AppIcons.dangerTriangle,
        'MEDIUM' => AppIcons.dangerCircle,
        _ => AppIcons.infoCircle,
      };

  @override
  Widget build(BuildContext context) {
    final String severity = '${thing.lead['severity'] ?? ''}'.toUpperCase();
    final Color tint = _tint(severity);
    final String description = '${thing.lead['description'] ?? ''}';
    final BorderRadius radius = BorderRadius.circular(GlassTheme.radiusLarge);

    return Pressable(
      onTap: onTap,
      radius: radius,
      child: BrandGlass(
        radius: GlassTheme.radiusLarge,
        elevated: false,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Container(
              key: const ValueKey('severity_mark'),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(GlassTheme.radiusSmall),
              ),
              child: Center(
                child: DuotoneIcon(_icon(severity),
                    size: 20, color: AppColors.glyphInk(tint)),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(thing.title,
                      style: BrandText.title(size: 15.5, color: Brand.text)
                          .copyWith(height: Brand.displayHeight(1.3))),
                  if (description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: BrandText.body(size: 13.5, color: Brand.text2)
                              .copyWith(height: Brand.bodyHeight(1.4))),
                    ),
                  if (thing.more > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('and ${thing.more} more',
                          style: BrandText.body(size: 12.5, color: Brand.text2)
                              .copyWith(height: Brand.bodyHeight(1.3))),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DuotoneIcon(AppIcons.chevronRight, size: 17, color: Brand.text3),
          ],
        ),
      ),
    );
  }
}

/// The checks that ran and found nothing, one row each.
class _CleanList extends StatelessWidget {
  const _CleanList({required this.steps});

  final List<CheckStep> steps;

  @override
  Widget build(BuildContext context) {
    return BrandGlass(
      radius: GlassTheme.radiusLarge,
      elevated: false,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < steps.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                border: i > 0
                    ? Border(top: BorderSide(color: Brand.hairline))
                    : null,
              ),
              child: Row(
                children: [
                  DuotoneIcon(AppIcons.checkCircle,
                      size: 18, color: Brand.limeInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(steps[i].name,
                        style: BrandText.body(size: 15, color: Brand.text)
                            .copyWith(height: Brand.bodyHeight(1.35))),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The prototype's `.cant`: a dashed outline around what was not counted.
class _DashedNote extends StatelessWidget {
  const _DashedNote({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedOutline(color: Brand.border, radius: Brand.rMd),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: BrandText.title(size: 14.5, color: Brand.text)
                    .copyWith(height: Brand.displayHeight(1.3))),
            const SizedBox(height: 4),
            Text(body,
                style: BrandText.body(size: 13.5, color: Brand.text2)
                    .copyWith(height: Brand.bodyHeight(1.45))),
          ],
        ),
      ),
    );
  }
}

class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const double _dash = 4;
  static const double _space = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final Path outline = Path()
      ..addRRect(RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5), Radius.circular(radius)));
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final ui.PathMetric metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += _dash + _space) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) =>
      old.color != color || old.radius != radius;
}
