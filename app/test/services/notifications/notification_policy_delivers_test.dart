import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/notifications/notification_policy.dart';

/// P3.4 live send-path gate. `deliversNow` is what `NotificationService` calls
/// for unsolicited security alerts: it adds ONE rule on top of the full
/// `shouldNotify` discipline — a `critical` alert ALWAYS delivers, because a
/// frequency cap / cooldown / the criticalOnly setting must never silently
/// suppress a critical security alert.
void main() {
  final now = DateTime(2026, 7, 17, 9);

  test('a critical delivers even after the daily cap is spent', () async {
    // criticalOnly OFF so a high is eligible to spend the cap first.
    SharedPreferences.setMockInitialValues({'notif_critical_only': false});
    final p = NotificationPolicy();
    await p.load();

    // One high alert spends the default daily cap (1).
    expect(
      p.deliversNow(
          severity: AlertSeverity.high,
          category: 'threat',
          actionable: true,
          now: now),
      isTrue,
    );
    await p.recordSent('threat', now);

    // A second non-critical is now capped…
    expect(
      p.deliversNow(
          severity: AlertSeverity.high,
          category: 'breach',
          actionable: true,
          now: now),
      isFalse,
    );
    // …but a critical still gets through.
    expect(
      p.deliversNow(
          severity: AlertSeverity.critical,
          category: 'breach',
          actionable: true,
          now: now),
      isTrue,
    );
  });

  test('a critical delivers even inside a same-category cooldown', () async {
    SharedPreferences.setMockInitialValues({});
    final p = NotificationPolicy();
    await p.load();

    await p.recordSent('threat', now); // start the 24h cooldown for 'threat'
    final soon = now.add(const Duration(hours: 1));
    expect(
      p.deliversNow(
          severity: AlertSeverity.critical,
          category: 'threat',
          actionable: true,
          now: soon),
      isTrue,
    );
  });

  test('non-criticals still obey the full discipline', () async {
    SharedPreferences.setMockInitialValues({}); // criticalOnly defaults true
    final p = NotificationPolicy();
    await p.load();

    // Default criticalOnly=true → a high does NOT deliver…
    expect(
      p.deliversNow(
          severity: AlertSeverity.high,
          category: 'x',
          actionable: true,
          now: now),
      isFalse,
    );
    // …medium never delivers…
    expect(
      p.deliversNow(
          severity: AlertSeverity.medium,
          category: 'x',
          actionable: true,
          now: now),
      isFalse,
    );
    // …and a critical always does.
    expect(
      p.deliversNow(
          severity: AlertSeverity.critical,
          category: 'x',
          actionable: true,
          now: now),
      isTrue,
    );
  });
}
