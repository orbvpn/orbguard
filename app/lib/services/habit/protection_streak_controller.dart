/// Protection streak controller — Phase 3.3 habit loop.
///
/// Tracks a positive "days protected" streak driven by periodic checkups
/// (e.g. completing a device scan from [StreakCard]'s host screen). This is
/// deliberately a REWARD loop, never a guilt loop:
///  - a missed day quietly starts a fresh streak — there is no "streak
///    lost!" framing, no red/danger coloring anywhere, no nagging;
///  - the best streak ever reached is always preserved and surfaced, so a
///    gap never erases the user's past progress;
///  - [isCheckupDueThisWeek] is purely informational (it powers a single
///    calm nudge line in the UI) — it never blocks or repeats a warning.
///
/// Fully self-contained: this controller owns its OWN SharedPreferences keys
/// (all prefixed `streak_`) so it can be dropped into the app without
/// touching `SettingsProvider` or any other controller/provider. Time is
/// always supplied by the caller (never `DateTime.now()` internally), so
/// behavior is deterministic and unit-testable.
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProtectionStreakController extends ChangeNotifier {
  /// [prefs] is optional — inject a pre-configured instance (e.g. in tests,
  /// right after `SharedPreferences.setMockInitialValues(...)`) or omit it
  /// and let [load]/[recordCheckup] resolve the singleton themselves.
  ProtectionStreakController({SharedPreferences? prefs}) : _prefs = prefs;

  SharedPreferences? _prefs;
  bool _hydrated = false;

  // Own keys — all prefixed `streak_` per the habit-loop persistence
  // contract, independent of every other provider/controller's namespace.
  static const String _kLastCheckupIso = 'streak_last_checkup_iso';
  static const String _kCurrent = 'streak_current';
  static const String _kBest = 'streak_best';

  DateTime? _lastCheckup;
  int _current = 0;
  int _best = 0;

  /// Current consecutive-calendar-day "days protected" streak.
  int get currentStreak => _current;

  /// Best streak ever recorded. Preserved across gaps/resets — never
  /// decreases.
  int get bestStreak => _best;

  /// Instant of the last recorded checkup, or null if there has never been
  /// one.
  DateTime? get lastCheckup => _lastCheckup;

  /// Hydrates state from persisted storage. Safe to call more than once;
  /// each call re-reads from prefs (e.g. after another instance of this
  /// controller elsewhere in the app persisted a newer value).
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final iso = _prefs!.getString(_kLastCheckupIso);
    _lastCheckup = iso != null ? DateTime.tryParse(iso) : null;
    _current = _prefs!.getInt(_kCurrent) ?? 0;
    _best = _prefs!.getInt(_kBest) ?? 0;
    _hydrated = true;
    notifyListeners();
  }

  /// Records a checkup at [now] — the core streak logic. Compares by
  /// CALENDAR DAY only (time-of-day is ignored):
  ///  - never checked before, or a gap of more than one day since the last
  ///    checkup: [currentStreak] resets to 1 — a fresh, no-guilt start;
  ///  - the last checkup was exactly the previous calendar day:
  ///    [currentStreak] extends by 1;
  ///  - the last checkup was already today (or [now] does not fall after
  ///    it): no change — a second checkup the same day never double-counts;
  ///  - [bestStreak] always tracks the highest [currentStreak] ever reached.
  Future<void> recordCheckup(DateTime now) async {
    // Defensive: if the caller forgot to `load()` first, hydrate now so we
    // never clobber a persisted `best`/`current` with fresh-instance zeros.
    if (!_hydrated) await load();

    final today = _dayNumber(now);
    final lastDay = _lastCheckup == null ? null : _dayNumber(_lastCheckup!);

    if (lastDay == null) {
      _current = 1;
    } else {
      final gap = today - lastDay;
      if (gap <= 0) {
        // Same calendar day already recorded (or a clock regression) — no
        // double-count.
      } else if (gap == 1) {
        _current += 1;
      } else {
        // Gap of 2+ days — quietly start over, no "loss" messaging.
        _current = 1;
      }
    }

    _lastCheckup = now;
    if (_current > _best) _best = _current;

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kLastCheckupIso, now.toIso8601String());
    await _prefs!.setInt(_kCurrent, _current);
    await _prefs!.setInt(_kBest, _best);

    notifyListeners();
  }

  /// Whole calendar days between the last checkup and [now], or null if
  /// there has never been a checkup.
  int? daysSinceLastCheckup(DateTime now) {
    final last = _lastCheckup;
    if (last == null) return null;
    return _dayNumber(now) - _dayNumber(last);
  }

  /// True when a weekly checkup is "due" — never checked, or 7+ calendar
  /// days since the last one. Purely informational (drives one calm nudge
  /// line in the UI) — never blocks, alarms, or repeats.
  bool isCheckupDueThisWeek(DateTime now) {
    final days = daysSinceLastCheckup(now);
    return days == null || days >= 7;
  }

  /// Whole-day index (days since the epoch), computed via UTC so day-gap
  /// arithmetic is exact and immune to the 23h/25h days that plain
  /// local-time `DateTime.difference` can produce across a DST transition.
  static int _dayNumber(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
}
