// The Today card's record. Every row is an event that was stored when it
// happened; the card never fills itself in. These tests hold that a row
// exists only for a real event, that a time is shown only when one was
// recorded, and that the day's timeline marks nothing that did not happen
// today.

import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/home/home_today.dart';

final _now = DateTime(2026, 11, 23, 21, 40);

HomeToday _today({
  DateTime? lastScanAt,
  int threats = 0,
  int? blocked,
  DateTime? breachAt,
  int streak = 0,
}) =>
    HomeToday.from(
      lastScanAt: lastScanAt,
      threatCount: threats,
      blockedToday: blocked,
      breachCheckedAt: breachAt,
      streakDays: streak,
      now: _now,
    );

void main() {
  test('with nothing recorded it says so, and marks nothing', () {
    final today = _today();

    expect(today.events, isEmpty);
    expect(today.marks, isEmpty);
    expect(today.empty, 'Nothing yet. Your first check starts the record.');
  });

  test('a check that ran today is listed and marked at its hour', () {
    final today = _today(lastScanAt: DateTime(2026, 11, 23, 19, 30));

    expect(today.label, 'Today');
    expect(today.events.single.kind, HomeEventKind.check);
    expect(today.events.single.text, 'Privacy check ran, nothing found');
    expect(today.events.single.at, DateTime(2026, 11, 23, 19, 30));
    expect(today.events.single.since, isNull,
        reason: 'an event from today shows its clock time');
    expect(today.marks, [19.5]);
    expect(today.empty, isNull);
  });

  test('what the check found is counted as found', () {
    String row(int threats) =>
        _today(lastScanAt: DateTime(2026, 11, 23, 19, 30), threats: threats)
            .events
            .single
            .text;

    expect(row(1), 'Privacy check ran, found 1 thing');
    expect(row(2), 'Privacy check ran, found 2 things');
  });

  test('an older check is the latest news, and stays off today’s timeline', () {
    final today = _today(lastScanAt: DateTime(2026, 11, 20, 8));

    expect(today.label, 'Latest');
    expect(today.events.single.since, '3 days ago');
    expect(today.marks, isEmpty);
  });

  test('blocked domains are counted for today with no made-up time', () {
    final today = _today(blocked: 12);

    expect(today.label, 'Today');
    expect(today.events.single.kind, HomeEventKind.blocked);
    expect(today.events.single.text,
        '12 tracker and surveillance domains blocked');
    expect(today.events.single.at, isNull);
    expect(today.marks, isEmpty);
  });

  test('one blocked domain reads as one', () {
    expect(_today(blocked: 1).events.single.text,
        '1 tracker or surveillance domain blocked');
  });

  test('nothing blocked is not an event', () {
    expect(_today(blocked: 0).events, isEmpty);
  });

  test('the running count leads, then events newest first', () {
    final today = _today(
      breachAt: DateTime(2026, 11, 23, 9, 15),
      lastScanAt: DateTime(2026, 11, 23, 19, 30),
      blocked: 4,
    );

    expect([for (final e in today.events) e.kind],
        [HomeEventKind.blocked, HomeEventKind.check, HomeEventKind.breach]);
    expect(today.marks, [9.25, 19.5], reason: 'marks run left to right');
  });

  test('a breach check is listed for what it did', () {
    final today = _today(breachAt: DateTime(2026, 11, 23, 9, 15));

    expect(today.events.single.text, 'Email checked against breach records');
  });

  test('a streak is mentioned from its second day', () {
    expect(_today(streak: 0).aside, isNull);
    expect(_today(streak: 1).aside, isNull);
    expect(_today(streak: 3).aside, '3 days in a row');
  });

  test('a time later than now is not drawn on today', () {
    final today = _today(lastScanAt: DateTime(2026, 11, 23, 23, 0));

    expect(today.marks, isEmpty,
        reason: 'a clock that moved back must not put a mark in the future');
  });
}
