// The Today card's record: what OrbGuard really did, most recent first.
//
// Pure, like HomeBrief. Every row is an event that was stored when it
// happened (the last check, the firewall's count for today, the last breach
// check). Nothing here is estimated or filled in: no event, no row; no
// recorded time, no time shown; and the day's timeline marks only what
// happened today.
library;

import 'home_brief.dart';

enum HomeEventKind {
  /// A privacy check ran.
  check,

  /// The firewall blocked tracker or surveillance domains today.
  blocked,

  /// The email was checked against breach records.
  breach,
}

class HomeEvent {
  const HomeEvent({
    required this.kind,
    required this.text,
    this.at,
    this.since,
  });

  final HomeEventKind kind;
  final String text;

  /// When it happened, or null for a count that has no single moment.
  final DateTime? at;

  /// "yesterday", "3 days ago": set only when it did not happen today.
  /// An event from today shows the clock time of [at] instead.
  final String? since;
}

class HomeToday {
  const HomeToday._({
    required this.label,
    required this.aside,
    required this.events,
    required this.marks,
    required this.nowHour,
    required this.empty,
  });

  /// "Today" when something happened today, otherwise "Latest".
  final String label;

  /// A short note beside the label, when there is something true to note.
  final String? aside;

  final List<HomeEvent> events;

  /// Hour of day (0 to 24) of each timed event that happened today, in order.
  final List<double> marks;

  /// Where now sits on the same 0 to 24 scale.
  final double nowHour;

  /// What the card says when there are no events at all.
  final String? empty;

  factory HomeToday.from({
    required DateTime? lastScanAt,
    required int threatCount,
    required int? blockedToday,
    required DateTime? breachCheckedAt,
    required int streakDays,
    required DateTime now,
  }) {
    bool isToday(DateTime t) =>
        t.year == now.year && t.month == now.month && t.day == now.day;

    HomeEvent timed(HomeEventKind kind, String text, DateTime at) => HomeEvent(
          kind: kind,
          text: text,
          at: at,
          since: isToday(at) ? null : HomeBrief.ago(at, now),
        );

    final List<HomeEvent> timedEvents = [
      if (lastScanAt != null)
        timed(
          HomeEventKind.check,
          threatCount == 0
              ? 'Privacy check ran, nothing found'
              : 'Privacy check ran, found $threatCount '
                  'thing${threatCount == 1 ? '' : 's'}',
          lastScanAt,
        ),
      if (breachCheckedAt != null)
        timed(HomeEventKind.breach, 'Email checked against breach records',
            breachCheckedAt),
    ]..sort((a, b) => b.at!.compareTo(a.at!));

    final int blocked = blockedToday ?? 0;
    final List<HomeEvent> events = [
      if (blocked > 0)
        HomeEvent(
          kind: HomeEventKind.blocked,
          text: blocked == 1
              ? '1 tracker or surveillance domain blocked'
              : '$blocked tracker and surveillance domains blocked',
        ),
      ...timedEvents,
    ];

    double hour(DateTime t) => t.hour + t.minute / 60;
    final List<double> marks = [
      for (final e in timedEvents)
        if (isToday(e.at!) && !e.at!.isAfter(now)) hour(e.at!),
    ]..sort();

    final bool anythingToday =
        blocked > 0 || timedEvents.any((e) => isToday(e.at!));

    return HomeToday._(
      label: anythingToday || events.isEmpty ? 'Today' : 'Latest',
      aside: streakDays >= 2 ? '$streakDays days in a row' : null,
      events: events,
      marks: marks,
      nowHour: hour(now),
      empty: events.isEmpty
          ? 'Nothing yet. Your first check starts the record.'
          : null,
    );
  }
}
