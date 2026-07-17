import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/services/habit/protection_streak_controller.dart';
import 'package:orbguard/widgets/habit/streak_card.dart';

/// P3.3 — the habit-loop card. The zero-state must read as an INVITATION (never
/// a loss/warning), and an active streak must show the current count plus the
/// always-visible best. Guard Home only mounts this card once a streak exists,
/// so these two states are the whole visible contract.
void main() {
  Widget host(ProtectionStreakController c, DateTime now) => MaterialApp(
        home: Scaffold(body: StreakCard(controller: c, now: now)),
      );

  testWidgets('zero state invites and shows no day count', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProtectionStreakController();
    await c.load();

    await tester.pumpWidget(host(c, DateTime(2026, 7, 17)));
    await tester.pump();

    expect(find.text('Start your streak — run a checkup'), findsOneWidget);
    expect(find.textContaining('protected'), findsNothing);
  });

  testWidgets('active streak shows current count and best', (tester) async {
    SharedPreferences.setMockInitialValues({
      'streak_current': 5,
      'streak_best': 7,
      'streak_last_checkup_iso': DateTime(2026, 7, 17).toIso8601String(),
    });
    final c = ProtectionStreakController();
    await c.load();

    await tester.pumpWidget(host(c, DateTime(2026, 7, 17)));
    await tester.pump();

    expect(find.text('5 days protected'), findsOneWidget);
    expect(find.text('Best streak: 7 days'), findsOneWidget);
  });
}
