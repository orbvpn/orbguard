// P4.2 — the living control-panel home. Guards the honesty contract:
// the hero never claims monitoring without a verified-active guard, the
// score is the engine's real output, unavailable guards are hidden, and the
// activity feed never fabricates numbers.
//
// The live states run repeating animations (pulse orb, blinking dot), so
// these tests use fixed pumps — never pumpAndSettle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/screens/home/control_panel_home_screen.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';
import 'package:orbguard/widgets/home/pulse_orb.dart';

/// Hydrates a real [LastScanVerdictController] from mocked prefs. Passing no
/// [score] leaves the never-scanned state (score −1).
Future<LastScanVerdictController> makeVerdict({
  int? score,
  DateTime? at,
  int threats = 0,
  int coverage = 0,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (score != null) 'verdict_score': score,
    if (at != null) 'verdict_at_iso': at.toIso8601String(),
    'verdict_threat_count': threats,
    'verdict_coverage_pct': coverage,
  });
  final controller = LastScanVerdictController();
  await controller.load();
  return controller;
}

/// A [GuardStatusController] resolved from inline fake probes.
Future<GuardStatusController> makeGuards(List<GuardStatus> guards) async {
  final controller = GuardStatusController(
    probes: [for (final g in guards) () async => g],
  );
  await controller.refresh();
  return controller;
}

GuardStatus guard(String id, String name, GuardState state,
        [String detail = 'detail line']) =>
    GuardStatus(id: id, name: name, state: state, detail: detail);

/// Mounts the screen on a tall surface so the whole list builds, then pumps
/// a couple of fixed frames (live animations forbid pumpAndSettle).
Future<void> mountScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  testWidgets(
      'never scanned + no active guards → invite headline, no live claim',
      (tester) async {
    final verdict = await makeVerdict(); // score -1, never scanned
    final guards = await makeGuards([
      guard('spyware_watch', 'Spyware watch', GuardState.actionNeeded,
          'Turn on the daily checkup'),
    ]);

    await mountScreen(
      tester,
      ControlPanelHomeScreen(
        onRunCheck: () {},
        verdict: verdict,
        guardsController: guards,
      ),
    );

    expect(find.text("Let's check your phone"), findsOneWidget);
    expect(find.textContaining('Monitoring live'), findsNothing,
        reason: 'no verified-active guard → no live claim');
    expect(find.byType(LiveDot), findsNothing,
        reason: 'the dot only exists when something real runs');
    expect(
        find.text('Protection is off — set up your guards'), findsOneWidget);
  });

  testWidgets('clean recent scan + an active guard → watched-free + live line',
      (tester) async {
    final verdict = await makeVerdict(
      score: 92,
      at: DateTime.now().subtract(const Duration(hours: 2)),
      threats: 0,
      coverage: 90,
    );
    final guards = await makeGuards([
      guard('spyware_watch', 'Spyware watch', GuardState.active,
          'Daily checkup on'),
    ]);

    await mountScreen(
      tester,
      ControlPanelHomeScreen(
        onRunCheck: () {},
        verdict: verdict,
        guardsController: guards,
      ),
    );

    expect(find.text("You're not being watched"), findsOneWidget);
    expect(find.textContaining('Monitoring live'), findsOneWidget);
    expect(find.byType(LiveDot), findsOneWidget);
  });

  testWidgets('guard grid: On chip, Set up chip, unavailable tiles hidden',
      (tester) async {
    final verdict = await makeVerdict();
    final guards = await makeGuards([
      guard('spyware_watch', 'Spyware watch', GuardState.active,
          'Daily checkup on'),
      guard('firewall', 'Tracker firewall', GuardState.actionNeeded,
          'Tap to turn on'),
      guard('sms_filter', 'Scam text filter', GuardState.unavailable,
          'Not available on this device'),
    ]);

    final tapped = <String>[];
    await mountScreen(
      tester,
      ControlPanelHomeScreen(
        onRunCheck: () {},
        verdict: verdict,
        guardsController: guards,
        onGuardTap: tapped.add,
      ),
    );

    expect(find.text('On'), findsOneWidget);
    expect(find.text('+ Set up'), findsOneWidget);
    expect(find.text('Spyware watch'), findsOneWidget);
    expect(find.text('Tracker firewall'), findsOneWidget);
    expect(find.text('Scam text filter'), findsNothing,
        reason: 'unavailable guards must not render');

    await tester.tap(find.text('Tracker firewall'));
    await tester.pump(const Duration(milliseconds: 40));
    expect(tapped, ['firewall']);
  });

  testWidgets('score card renders the engine value and the things-to-fix row',
      (tester) async {
    const signals = PrivacySignals(
      lastScanScore: 92,
      daysSinceScan: 1,
      openThreats: 0,
      guardsActive: 1,
      guardsAvailable: 3,
      breachedAccounts: 2,
      riskyPermissionApps: 0,
      notificationsGranted: true,
    );
    final expected = const PrivacyScoreEngine().compute(signals);
    expect(expected.factors, hasLength(2),
        reason: 'fixture sanity: enable_guards + fix_breaches');

    final verdict = await makeVerdict();
    final guards = await makeGuards([
      guard('spyware_watch', 'Spyware watch', GuardState.active,
          'Daily checkup on'),
    ]);

    final factorTaps = <String>[];
    await mountScreen(
      tester,
      ControlPanelHomeScreen(
        onRunCheck: () {},
        verdict: verdict,
        guardsController: guards,
        signalsOverride: () => signals,
        onFactorTap: factorTaps.add,
      ),
    );

    expect(find.text('${expected.value}'), findsOneWidget);
    expect(find.text('/ 1000'), findsOneWidget);
    expect(find.text('2 things to fix — tap to see'), findsOneWidget);

    // Expand the inline factor list and tap the top factor through.
    await tester.tap(find.text('2 things to fix — tap to see'));
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('Turn on 2 more protections'), findsOneWidget);
    expect(find.text('+167 pts'), findsOneWidget);

    await tester.tap(find.text('Turn on 2 more protections'));
    await tester.pump(const Duration(milliseconds: 40));
    expect(factorTaps, ['enable_guards']);
  });

  testWidgets('feed: honest empty line when no data exists', (tester) async {
    final verdict = await makeVerdict();
    final guards = await makeGuards([
      guard('spyware_watch', 'Spyware watch', GuardState.actionNeeded,
          'Turn on the daily checkup'),
    ]);

    await mountScreen(
      tester,
      ControlPanelHomeScreen(
        onRunCheck: () {},
        verdict: verdict,
        guardsController: guards,
      ),
    );

    expect(find.text('Activity will appear here as your guards run'),
        findsOneWidget);
    expect(find.textContaining('blocked'), findsNothing,
        reason: 'no counting source → no count line, ever');
  });

  testWidgets('feed: real blocked count and breach-check line render',
      (tester) async {
    final verdict = await makeVerdict();
    final guards = await makeGuards([
      guard('firewall', 'Tracker firewall', GuardState.active,
          'Blocking surveillance domains'),
    ]);

    await mountScreen(
      tester,
      ControlPanelHomeScreen(
        onRunCheck: () {},
        verdict: verdict,
        guardsController: guards,
        blockedTodayCount: () => 214,
        breachLastChecked: () =>
            DateTime.now().subtract(const Duration(hours: 3)),
      ),
    );

    expect(find.textContaining('214'), findsOneWidget);
    expect(find.textContaining('tracker & surveillance domains blocked'),
        findsOneWidget);
    expect(find.textContaining('Email checked against breach records'),
        findsOneWidget);
    expect(find.text('Activity will appear here as your guards run'),
        findsNothing);
  });
}
