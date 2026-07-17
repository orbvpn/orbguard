// Notification discipline policy — the single gate deciding whether a
// real-time alert is allowed to reach the user.
//
// OrbGuard's whole point is respecting the user's attention (see
// app/CLAUDE.md): we notify ONLY when an event is rare, high-severity, and
// something the user can actually act on — plus at most one scheduled
// weekly summary. Never promotional, never a nag.
//
// This class knows NOTHING about how notifications are actually delivered
// (no flutter_local_notifications call, no OS scheduler) — it is pure
// policy + its own persistence, so it can be dropped in ahead of, or
// independent from, the real send pipeline. The intended integration is:
//
//   if (policy.shouldNotify(severity: .., category: .., actionable: .., now: DateTime.now())) {
//     await realNotificationSender.show(...);   // whatever actually pings the OS
//     await policy.recordSent(category, DateTime.now());
//   }
//
// Persistence is fully self-contained: every key lives under its own
// `notif_`-prefixed namespace private to this class —
// `notif_critical_only` / `notif_weekly_summary` / `notif_summary_weekday` /
// `notif_last_<category>_iso` / `notif_sent_log_iso`. These are distinct
// from the pre-existing `notif_push` / `notif_threats` / `notif_breaches` /
// `notif_scan` / `notif_sound` / `notif_vibration` / `notif_quiet*` keys
// already owned by SettingsProvider/NotificationService — no collisions.
library;

import 'package:shared_preferences/shared_preferences.dart';

/// How serious/urgent a candidate alert is. Only [high] and [critical] are
/// ever eligible for a real-time notification — see
/// [NotificationPolicy.shouldNotify]. `info`/`low`/`medium` NEVER qualify,
/// regardless of any setting.
enum AlertSeverity { info, low, medium, high, critical }

/// The notification-discipline gate. Holds:
///  - settings: [criticalOnly], [weeklySummaryEnabled], [summaryWeekday];
///  - send bookkeeping: per-category last-sent (for the cooldown) and a
///    rolling send log (for the global daily cap).
///
/// Call [load] once (e.g. in a screen's `initState`) before using
/// [shouldNotify] or [nextWeeklySummary] — both are synchronous and only
/// see whatever [load] populated; they never touch SharedPreferences
/// directly so they stay deterministic and testable with a fixed `now`.
class NotificationPolicy {
  /// Minimum spacing between two alerts in the SAME category. Default 24h.
  final Duration cooldown;

  /// Max alerts allowed, across ALL categories combined, within a trailing
  /// [cooldown]-sized window. Default 1 — i.e. "at most one alert per day,
  /// period" on top of the per-category cooldown.
  final int dailyCap;

  NotificationPolicy({
    this.cooldown = const Duration(hours: 24),
    this.dailyCap = 1,
  });

  // ---- settings (persisted) ----
  bool _criticalOnly = true;
  bool _weeklySummaryEnabled = true;
  int _summaryWeekday = DateTime.monday;

  // ---- send bookkeeping (persisted) ----
  final Map<String, DateTime> _lastSentByCategory = {};
  List<DateTime> _sentLog = [];

  static const String _kCriticalOnly = 'notif_critical_only';
  static const String _kWeeklySummary = 'notif_weekly_summary';
  static const String _kSummaryWeekday = 'notif_summary_weekday';
  static const String _kSentLog = 'notif_sent_log_iso';
  static const String _lastPrefix = 'notif_last_';
  static const String _lastSuffix = '_iso';

  static String _lastKeyFor(String category) =>
      '$_lastPrefix$category$_lastSuffix';

  /// Loads settings + send history from SharedPreferences into memory.
  /// Safe to call again later to pick up changes made elsewhere (e.g. a
  /// different instance's [recordSent]).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    _criticalOnly = prefs.getBool(_kCriticalOnly) ?? true;
    _weeklySummaryEnabled = prefs.getBool(_kWeeklySummary) ?? true;
    _summaryWeekday = prefs.getInt(_kSummaryWeekday) ?? DateTime.monday;

    _lastSentByCategory.clear();
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_lastPrefix) || !key.endsWith(_lastSuffix)) {
        continue;
      }
      final category =
          key.substring(_lastPrefix.length, key.length - _lastSuffix.length);
      final iso = prefs.getString(key);
      final parsed = iso == null ? null : DateTime.tryParse(iso);
      if (parsed != null) _lastSentByCategory[category] = parsed;
    }

    _sentLog = (prefs.getStringList(_kSentLog) ?? const <String>[])
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .toList();
  }

  // ---- the gate ----

  /// Whether a candidate alert may be shown right now. ALL of the following
  /// must hold:
  ///
  ///  1. `severity == critical`, OR (`severity == high` AND [criticalOnly]
  ///     is currently OFF). By default ([criticalOnly] true) only `critical`
  ///     qualifies — turning "Critical alerts only" off additionally admits
  ///     `high`. `info`/`low`/`medium` never qualify.
  ///  2. [actionable] is true — the user can actually do something about it.
  ///  3. The same [category] has NOT sent within [cooldown] (default 24h).
  ///  4. Fewer than [dailyCap] alerts (default 1) have been sent, across
  ///     ALL categories combined, within the trailing [cooldown] window.
  ///
  /// Pure/synchronous — a query only, it never records anything itself. On
  /// `true`, the caller MUST call [recordSent] right after actually showing
  /// the notification, or cooldown/cap accounting will drift.
  bool shouldNotify({
    required AlertSeverity severity,
    required String category,
    required bool actionable,
    required DateTime now,
  }) {
    final severityEligible = severity == AlertSeverity.critical ||
        (severity == AlertSeverity.high && !_criticalOnly);
    if (!severityEligible) return false;
    if (!actionable) return false;

    final lastForCategory = _lastSentByCategory[category];
    if (lastForCategory != null &&
        now.difference(lastForCategory) < cooldown) {
      return false;
    }

    final recentCount =
        _sentLog.where((sent) => now.difference(sent) < cooldown).length;
    if (recentCount >= dailyCap) return false;

    return true;
  }

  /// Live send-path gate. Identical to [shouldNotify] with ONE exception: a
  /// `critical` alert is ALWAYS delivered. A frequency cap, cooldown, or the
  /// [criticalOnly] setting must never suppress a critical security alert —
  /// in a security app, silently dropping "spyware found" because we already
  /// pinged today would be dangerous. Non-critical alerts still pass the full
  /// discipline ([shouldNotify]: severity/[criticalOnly], actionable, cooldown,
  /// daily cap). As with [shouldNotify], the caller MUST [recordSent] right
  /// after actually showing the notification.
  bool deliversNow({
    required AlertSeverity severity,
    required String category,
    required bool actionable,
    required DateTime now,
  }) =>
      severity == AlertSeverity.critical ||
      shouldNotify(
        severity: severity,
        category: category,
        actionable: actionable,
        now: now,
      );

  /// Records that a notification was actually shown for [category] at
  /// [now] — updates both the per-category cooldown clock and the global
  /// cap log, in memory and in SharedPreferences (so a restarted app still
  /// honors them).
  Future<void> recordSent(String category, DateTime now) async {
    _lastSentByCategory[category] = now;
    _sentLog = [..._sentLog, now]
      ..removeWhere((sent) => now.difference(sent) >= cooldown);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastKeyFor(category), now.toIso8601String());
    await prefs.setStringList(
      _kSentLog,
      _sentLog.map((sent) => sent.toIso8601String()).toList(),
    );
  }

  /// The next date the weekly summary is due, given [now] and the
  /// configured [summaryWeekday]. Always strictly after [now]: if today
  /// already IS the summary weekday, this rolls to next week rather than
  /// returning today, since there is no time-of-day component here (the
  /// caller owns scheduling the exact send time on the returned date).
  /// Result is local midnight of the target date.
  ///
  /// This does NOT consult [weeklySummaryEnabled] — it is a pure date
  /// computation; the caller decides whether to act on it.
  DateTime nextWeeklySummary(DateTime now) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    var daysAhead = (_summaryWeekday - now.weekday) % 7;
    if (daysAhead == 0) daysAhead = 7;
    return startOfToday.add(Duration(days: daysAhead));
  }

  // ---- settings getters/setters ----

  /// When true (default), only `critical`-severity events qualify in
  /// [shouldNotify]; `high` is additionally admitted once this is false.
  bool get criticalOnly => _criticalOnly;
  Future<void> setCriticalOnly(bool value) async {
    _criticalOnly = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCriticalOnly, value);
  }

  /// Whether the single scheduled weekly summary is enabled (default true).
  bool get weeklySummaryEnabled => _weeklySummaryEnabled;
  Future<void> setWeeklySummaryEnabled(bool value) async {
    _weeklySummaryEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWeeklySummary, value);
  }

  /// Day of week the summary goes out — [DateTime.monday]..[DateTime.sunday]
  /// (1..7). Defaults to [DateTime.monday].
  int get summaryWeekday => _summaryWeekday;
  Future<void> setSummaryWeekday(int weekday) async {
    assert(
      weekday >= DateTime.monday && weekday <= DateTime.sunday,
      'weekday must be DateTime.monday(1)..DateTime.sunday(7)',
    );
    _summaryWeekday = weekday;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSummaryWeekday, weekday);
  }
}
