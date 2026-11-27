/// The Today card: a strip of the day with a mark at each thing that really
/// happened, and the same events as rows underneath. It draws [HomeToday] and
/// adds nothing of its own.
library;

import 'package:flutter/material.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/pressable.dart';
import '../../services/home/home_today.dart';

class TodayCard extends StatelessWidget {
  const TodayCard({
    super.key,
    required this.today,
    this.onCheckTap,
    this.bare = false,
  });

  final HomeToday today;

  /// For a pane whose own head already says "Today": the card's label and
  /// its note are left out, so neither is printed twice.
  final bool bare;

  /// Opens the results of the check a row records. With none, that row is
  /// plain text.
  final VoidCallback? onCheckTap;

  static String _icon(HomeEventKind kind) => switch (kind) {
        HomeEventKind.check => AppIcons.searchBug,
        HomeEventKind.blocked => AppIcons.shieldNetwork,
        HomeEventKind.breach => AppIcons.userId,
      };

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // repaint with the theme
    final String? aside = today.aside;
    final String? empty = today.empty;
    final bool strip = today.label == 'Today' && today.marks.isNotEmpty;

    return BrandGlass(
      radius: 24,
      elevated: false,
      padding: EdgeInsets.fromLTRB(18, bare ? 12 : 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!bare)
            Row(
              children: [
                Expanded(
                  child: Text(today.label.toUpperCase(),
                      style: BrandText.label(size: 11.5)),
                ),
                if (aside != null)
                  Text(aside,
                      style: BrandText.body(size: 13.5).copyWith(height: 1.2)),
              ],
            ),
          if (empty != null)
            Padding(
              padding: EdgeInsets.only(top: bare ? 4 : 10, bottom: 6),
              child: Text(empty, style: BrandText.body(size: 15)),
            ),
          if (strip)
            Padding(
              padding: EdgeInsets.fromLTRB(2, bare ? 6 : 14, 2, 0),
              child: _DayStrip(marks: today.marks, now: today.nowHour),
            ),
          if (today.events.isNotEmpty) SizedBox(height: strip ? 6 : 4),
          for (int i = 0; i < today.events.length; i++)
            _EventRow(
              event: today.events[i],
              icon: _icon(today.events[i].kind),
              divided: i > 0,
              onTap: today.events[i].kind == HomeEventKind.check
                  ? onCheckTap
                  : null,
            ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.icon,
    required this.divided,
    this.onTap,
  });

  final HomeEvent event;
  final String icon;
  final bool divided;

  /// Set when the row opens something.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime? at = event.at;
    // A recorded time from today reads as a clock time, in the reader's own
    // format. Anything older says how long ago. A running count has no single
    // moment, so it shows none.
    final String? when = event.since ??
        (at == null
            ? null
            : MaterialLocalizations.of(context).formatTimeOfDay(
                TimeOfDay.fromDateTime(at),
                alwaysUse24HourFormat:
                    MediaQuery.alwaysUse24HourFormatOf(context),
              ));

    final VoidCallback? open = onTap;
    final Widget row = Container(
      // A row that opens something is a full 44 press target.
      constraints: BoxConstraints(minHeight: open == null ? 0 : 44),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: Brand.hairline)) : null,
      ),
      child: Row(
        children: [
          DuotoneIcon(icon, size: 17, color: Brand.limeInk),
          const SizedBox(width: 10),
          Expanded(
            child: Text(event.text,
                style: BrandText.body(size: 13.5, color: Brand.text)
                    .copyWith(height: Brand.bodyHeight(1.3))),
          ),
          if (when != null) ...[
            const SizedBox(width: 10),
            Text(when, style: BrandText.mono(size: 11.5)),
          ],
          if (open != null) ...[
            const SizedBox(width: 4),
            DuotoneIcon(AppIcons.chevronRight, size: 16, color: Brand.text3),
          ],
        ],
      ),
    );
    if (open == null) return row;
    return Pressable(
      onTap: open,
      radius: BorderRadius.circular(Brand.rSm),
      semanticLabel:
          [event.text, if (when != null) when, 'Show the results'].join('. '),
      child: row,
    );
  }
}

/// Midnight to midnight as one hairline: a lime mark where something
/// happened, and a needle at now.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.marks, required this.now});

  final List<double> marks;
  final double now;

  @override
  Widget build(BuildContext context) {
    final TextStyle axis =
        BrandText.mono(size: 10, weight: FontWeight.w400).copyWith(height: 1);
    return ExcludeSemantics(
      child: SizedBox(
        height: 38,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DayPainter(
                  marks: marks,
                  now: now,
                  line: Brand.hairline,
                  mark: Brand.limeInk,
                  needle: Brand.text,
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final String hour in const [
                    '00',
                    '06',
                    '12',
                    '18',
                    '24'
                  ])
                    Text(hour, style: axis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayPainter extends CustomPainter {
  const _DayPainter({
    required this.marks,
    required this.now,
    required this.line,
    required this.mark,
    required this.needle,
  });

  final List<double> marks;
  final double now;
  final Color line;
  final Color mark;
  final Color needle;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double hour) => hour.clamp(0, 24) / 24 * size.width;

    canvas.drawRect(Rect.fromLTWH(0, 11, size.width, 1), Paint()..color = line);

    final Paint tick = Paint()..color = mark;
    for (final double hour in marks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x(hour) - 1.5, 4, 3, 14), const Radius.circular(1)),
        tick,
      );
    }

    final double nx = x(now);
    canvas.drawRect(Rect.fromLTWH(nx - 0.5, 0, 1, 22),
        Paint()..color = needle.withValues(alpha: 0.55));
    canvas.drawCircle(Offset(nx, 0), 3, Paint()..color = needle);
  }

  @override
  bool shouldRepaint(_DayPainter old) =>
      old.now != now ||
      old.line != line ||
      old.mark != mark ||
      old.needle != needle ||
      old.marks.length != marks.length ||
      !Iterable<int>.generate(marks.length)
          .every((i) => old.marks[i] == marks[i]);
}
