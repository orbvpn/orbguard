import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/notifications/notification_policy.dart';

/// Phase 3.4 — notification discipline: the app pings the user only for
/// rare + high-severity + actionable events (max once per category per 24h,
/// max once per day total across all categories), plus one opt-in weekly
/// summary. These tests pin down the exact shouldNotify/recordSent/
/// nextWeeklySummary contract using fixed DateTimes (no wall-clock reads).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // 2026-07-13 is a Monday.
  final t0 = DateTime(2026, 7, 13, 9, 0);

  group('shouldNotify — severity gate', () {
    test('never notifies for info/low/medium, regardless of actionability',
        () async {
      final policy = NotificationPolicy();
      await policy.load();

      for (final severity in [
        AlertSeverity.info,
        AlertSeverity.low,
        AlertSeverity.medium,
      ]) {
        expect(
          policy.shouldNotify(
            severity: severity,
            category: 'threat',
            actionable: true,
            now: t0,
          ),
          isFalse,
          reason: '$severity must never notify',
        );
      }
    });

    test('false for a high-severity event that is not actionable', () async {
      final policy = NotificationPolicy();
      await policy.load();

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.high,
          category: 'threat',
          actionable: false,
          now: t0,
        ),
        isFalse,
      );
    });

    test('true for a genuine actionable critical event', () async {
      final policy = NotificationPolicy();
      await policy.load();

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0,
        ),
        isTrue,
      );
    });

    test(
        'high severity is blocked by default (criticalOnly=true) even when '
        'actionable', () async {
      final policy = NotificationPolicy();
      await policy.load();
      expect(policy.criticalOnly, isTrue, reason: 'default is critical-only');

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.high,
          category: 'threat',
          actionable: true,
          now: t0,
        ),
        isFalse,
      );
    });

    test('high severity is admitted once criticalOnly is turned off',
        () async {
      final policy = NotificationPolicy();
      await policy.load();
      await policy.setCriticalOnly(false);

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.high,
          category: 'threat',
          actionable: true,
          now: t0,
        ),
        isTrue,
      );
    });
  });

  group('shouldNotify — cooldown + daily cap', () {
    test('the same category cannot notify again immediately (cooldown)',
        () async {
      final policy = NotificationPolicy();
      await policy.load();

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0,
        ),
        isTrue,
      );
      await policy.recordSent('threat', t0);

      // Moments later, same category, same day: blocked by cooldown.
      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('the category notifies again once the cooldown has fully elapsed',
        () async {
      final policy = NotificationPolicy();
      await policy.load();
      await policy.recordSent('threat', t0);

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0.add(const Duration(hours: 24, minutes: 1)),
        ),
        isTrue,
      );
    });

    test(
        'a hard global cap of 1/day blocks a DIFFERENT category the same '
        'day', () async {
      final policy = NotificationPolicy();
      await policy.load();

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0,
        ),
        isTrue,
      );
      await policy.recordSent('threat', t0);

      // A different category, well outside ITS OWN cooldown window (it has
      // never sent before) — still blocked by the GLOBAL daily cap.
      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'breach',
          actionable: true,
          now: t0.add(const Duration(hours: 2)),
        ),
        isFalse,
        reason: 'global cap is 1/day across ALL categories',
      );
    });

    test('the global cap resets once the window has elapsed', () async {
      final policy = NotificationPolicy();
      await policy.load();
      await policy.recordSent('threat', t0);

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'breach',
          actionable: true,
          now: t0.add(const Duration(hours: 25)),
        ),
        isTrue,
      );
    });

    test(
        'shouldNotify never auto-records — repeated calls stay true until '
        'recordSent is called', () async {
      final policy = NotificationPolicy();
      await policy.load();

      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0,
        ),
        isTrue,
      );
      // Calling it again without recordSent must still be true (pure query,
      // no hidden side effects).
      expect(
        policy.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0.add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });
  });

  group('settings persistence', () {
    test('criticalOnly/weeklySummaryEnabled/summaryWeekday default correctly',
        () async {
      final policy = NotificationPolicy();
      await policy.load();
      expect(policy.criticalOnly, isTrue);
      expect(policy.weeklySummaryEnabled, isTrue);
      expect(policy.summaryWeekday, DateTime.monday);
    });

    test('setters persist across a freshly-loaded instance', () async {
      final policy = NotificationPolicy();
      await policy.load();
      await policy.setCriticalOnly(false);
      await policy.setWeeklySummaryEnabled(false);
      await policy.setSummaryWeekday(DateTime.friday);

      final reloaded = NotificationPolicy();
      await reloaded.load();
      expect(reloaded.criticalOnly, isFalse);
      expect(reloaded.weeklySummaryEnabled, isFalse);
      expect(reloaded.summaryWeekday, DateTime.friday);
    });

    test('cooldown/cap bookkeeping survives a restart', () async {
      final policy = NotificationPolicy();
      await policy.load();
      await policy.recordSent('threat', t0);

      final reloaded = NotificationPolicy();
      await reloaded.load();
      expect(
        reloaded.shouldNotify(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: t0.add(const Duration(minutes: 1)),
        ),
        isFalse,
        reason: 'cooldown must be honored after a fresh load',
      );
    });
  });

  group('nextWeeklySummary', () {
    test('returns the configured weekday, strictly after now', () async {
      final policy = NotificationPolicy();
      await policy.load(); // default weekday = Monday

      // t0 is itself a Monday: the next occurrence must be NEXT Monday, not
      // today (there is no time-of-day, so "in the future" always rolls
      // forward a full week when today already matches).
      final next = policy.nextWeeklySummary(t0);
      expect(next.weekday, DateTime.monday);
      expect(next.isAfter(t0), isTrue);
      expect(next.difference(DateTime(t0.year, t0.month, t0.day)).inDays, 7);
    });

    test('computes the correct forward distance from a mid-week date',
        () async {
      final policy = NotificationPolicy();
      await policy.load();
      await policy.setSummaryWeekday(DateTime.friday);

      final wednesday = DateTime(2026, 7, 15); // Wed
      final next = policy.nextWeeklySummary(wednesday);
      expect(next.weekday, DateTime.friday);
      expect(next.isAfter(wednesday), isTrue);
      expect(next.difference(wednesday).inDays, 2);
    });
  });
}
