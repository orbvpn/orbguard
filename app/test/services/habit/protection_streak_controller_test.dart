import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/habit/protection_streak_controller.dart';

/// Phase 3.3 habit loop — streak logic is a pure reward loop: gaps quietly
/// reset `current` (never "punish"), `best` is preserved forever, and the
/// weekly nudge is informational only. Fixed DateTimes throughout so
/// day-gap arithmetic is fully deterministic.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('recordCheckup', () {
    test('consecutive calendar-day calls increment the current streak',
        () async {
      final c = ProtectionStreakController();
      await c.load();

      await c.recordCheckup(DateTime(2026, 1, 1, 9));
      expect(c.currentStreak, 1);

      await c.recordCheckup(DateTime(2026, 1, 2, 8));
      expect(c.currentStreak, 2);

      await c.recordCheckup(DateTime(2026, 1, 3, 23));
      expect(c.currentStreak, 3);
      expect(c.bestStreak, 3);
    });

    test('a second call the same calendar day does not double-count',
        () async {
      final c = ProtectionStreakController();
      await c.load();

      await c.recordCheckup(DateTime(2026, 1, 1, 8));
      expect(c.currentStreak, 1);

      await c.recordCheckup(DateTime(2026, 1, 1, 20)); // later, same day
      expect(c.currentStreak, 1,
          reason: 'same-day checkup must not double-count');
      expect(c.bestStreak, 1);
    });

    test('a gap of more than one day resets current to 1 but preserves best',
        () async {
      final c = ProtectionStreakController();
      await c.load();

      await c.recordCheckup(DateTime(2026, 1, 1));
      await c.recordCheckup(DateTime(2026, 1, 2));
      await c.recordCheckup(DateTime(2026, 1, 3));
      expect(c.currentStreak, 3);
      expect(c.bestStreak, 3);

      // Exactly a 2-day gap (skips Jan 4) — pins the ">1 day" boundary.
      await c.recordCheckup(DateTime(2026, 1, 5));
      expect(c.currentStreak, 1,
          reason: 'a gap should reset current, not accumulate');
      expect(c.bestStreak, 3, reason: 'best must survive the gap/reset');
    });

    test('current and best persist across a fresh controller instance',
        () async {
      final c = ProtectionStreakController();
      await c.load();
      await c.recordCheckup(DateTime(2026, 1, 1));
      await c.recordCheckup(DateTime(2026, 1, 2));

      final restarted = ProtectionStreakController();
      await restarted.load();
      expect(restarted.currentStreak, 2);
      expect(restarted.bestStreak, 2);
    });
  });

  group('isCheckupDueThisWeek / daysSinceLastCheckup', () {
    test('due is true and days-since is null when never checked', () async {
      final c = ProtectionStreakController();
      await c.load();

      expect(c.isCheckupDueThisWeek(DateTime(2026, 1, 1)), isTrue);
      expect(c.daysSinceLastCheckup(DateTime(2026, 1, 1)), isNull);
    });

    test('due is false at day 3 since the last checkup', () async {
      final c = ProtectionStreakController();
      await c.load();
      await c.recordCheckup(DateTime(2026, 1, 1));

      expect(c.daysSinceLastCheckup(DateTime(2026, 1, 4)), 3);
      expect(c.isCheckupDueThisWeek(DateTime(2026, 1, 4)), isFalse);
    });

    test('due is true once 7+ days have elapsed since the last checkup',
        () async {
      final c = ProtectionStreakController();
      await c.load();
      await c.recordCheckup(DateTime(2026, 1, 1));

      expect(c.daysSinceLastCheckup(DateTime(2026, 1, 8)), 7);
      expect(c.isCheckupDueThisWeek(DateTime(2026, 1, 8)), isTrue);
    });
  });
}
