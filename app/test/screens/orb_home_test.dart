// The new Home: the ring, its six shields, one verdict, one action.
//
// What Home SAYS is HomeBrief's job and is tested there. These tests hold the
// wiring: that the screen shows the brief it was given real data for, that its
// one lime action goes where it says, that a ring with nothing on watch does
// not move, and that the layout survives a small phone.
//
// A live ring animates for ever, so these tests use fixed pumps and never
// pumpAndSettle.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/presentation/widgets/duotone_icon.dart';
import 'package:orbguard/screens/home/orb_home_screen.dart';
import 'package:orbguard/services/habit/protection_streak_controller.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/check_run.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/services/security/device_scan_service.dart';
import 'package:orbguard/widgets/home/orb_ring.dart';
import 'package:orbguard/widgets/home/today_card.dart';

final _now = DateTime(2026, 11, 23, 21, 40);

/// A real controller hydrated from mocked prefs. No [score]: never checked.
Future<LastScanVerdictController> _verdict({
  int? score,
  Duration since = const Duration(hours: 2),
  int threats = 0,
  int? checksRun,
  List<Map<String, dynamic>>? findings,
  List<String>? stagesRan,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (score != null) ...{
      'verdict_score': score,
      'verdict_at_iso': _now.subtract(since).toIso8601String(),
      'verdict_coverage_pct': 90,
    },
    'verdict_threat_count': findings?.length ?? threats,
    if (checksRun != null) 'verdict_checks_run': checksRun,
    if (findings != null) 'verdict_findings_json': jsonEncode(findings),
    if (stagesRan != null) 'verdict_stages_ran': stagesRan,
  });
  final controller = LastScanVerdictController();
  await controller.load();
  return controller;
}

GuardStatus _guard(String id, GuardState state) =>
    GuardStatus(id: id, name: id, state: state, detail: '');

Future<GuardStatusController> _guards(List<GuardStatus> guards) async {
  final controller = GuardStatusController(
    probes: [for (final g in guards) () async => g],
  );
  await controller.refresh();
  return controller;
}

/// The daily checkup and alerts on: a ring that is on watch.
Future<GuardStatusController> _watching() => _guards([
      _guard('spyware_watch', GuardState.active),
      _guard('sms_filter', GuardState.active),
      _guard('alerts', GuardState.active),
    ]);

Future<void> _mount(
  WidgetTester tester, {
  required LastScanVerdictController verdict,
  required GuardStatusController guards,
  Size size = const Size(390, 844),
  VoidCallback? onRunCheck,
  void Function(Shield)? onShieldTap,
  void Function(String)? onFactorTap,
  VoidCallback? onAlertsTap,
  VoidCallback? onAccountTap,
  VoidCallback? onTrustTap,
  String? accountInitial,
  ProtectionStreakController? streak,
  int? blockedToday,
  DateTime? breachCheckedAt,
  CheckRun? check,
  int? breachedAccounts,
  bool? unknownVpnActive,
  VoidCallback? onResultsTap,
  TargetPlatform platform = TargetPlatform.iOS,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: OrbHomeScreen(
          verdict: verdict,
          guardsController: guards,
          onRunCheck: onRunCheck ?? () {},
          onShieldTap: onShieldTap,
          onFactorTap: onFactorTap,
          onAlertsTap: onAlertsTap,
          onAccountTap: onAccountTap,
          onTrustTap: onTrustTap,
          accountInitial: accountInitial,
          streak: streak,
          blockedTodayCount: blockedToday == null ? null : () => blockedToday,
          breachLastChecked:
              breachCheckedAt == null ? null : () => breachCheckedAt,
          check: check,
          onResultsTap: onResultsTap,
          breachedAccounts: () => breachedAccounts,
          unknownVpnActive: () => unknownVpnActive,
          platform: platform,
          clock: () => _now,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  group('before the first check', () {
    // The words follow the platform Home is given, not the machine the code
    // happens to run on: a phone-sized test on a desktop host must read as a
    // phone does.
    testWidgets('names the device by the platform it is given', (tester) async {
      await _mount(tester,
          verdict: await _verdict(),
          guards: await _watching(),
          platform: TargetPlatform.android);

      expect(find.text('Let’s check your phone.'), findsOneWidget);
    });

    testWidgets('Home invites a check and shows no score', (tester) async {
      await _mount(tester,
          verdict: await _verdict(), guards: await _watching());

      expect(find.text('Let’s check your phone.'), findsOneWidget);
      expect(find.text('Not checked yet'), findsOneWidget);
      expect(find.text('privacy score'), findsNothing);
      expect(find.text('Nothing yet. Your first check starts the record.'),
          findsOneWidget);
    });

    testWidgets('the one action starts the first check', (tester) async {
      int runs = 0;
      await _mount(tester,
          verdict: await _verdict(),
          guards: await _watching(),
          onRunCheck: () => runs++);

      await tester.tap(find.widgetWithText(BrandButton, 'Run my first check'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(runs, 1);
    });

    testWidgets('pressing the ring starts it too', (tester) async {
      int runs = 0;
      await _mount(tester,
          verdict: await _verdict(),
          guards: await _watching(),
          onRunCheck: () => runs++);

      await tester.tap(find.byType(OrbRing));
      await tester.pump(const Duration(milliseconds: 200));

      expect(runs, 1);
    });
  });

  group('after a clean check', () {
    testWidgets('the ring carries the real score and the proof line',
        (tester) async {
      await _mount(tester,
          verdict: await _verdict(score: 92, checksRun: 5),
          guards: await _watching());

      expect(find.text('No signs you’re being watched.'), findsOneWidget);
      expect(find.text('5 checks ran 2 hours ago, all clean'), findsOneWidget);
      expect(find.text('privacy score'), findsOneWidget);
      // 200 installed + 200 recent + 150 clean + 250 guards + 50 alerts + the
      // 50 an iPhone is given for the audit it forbids; the breach check has
      // never run, so its 100 are still on the table.
      expect(find.text('900'), findsOneWidget);
    });

    testWidgets('the one action runs another check', (tester) async {
      int runs = 0;
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          onRunCheck: () => runs++);

      await tester.tap(find.widgetWithText(BrandButton, 'Check now'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(runs, 1);
    });

    testWidgets('pressing the ring shows what would raise the score',
        (tester) async {
      String? factor;
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          onFactorTap: (id) => factor = id);

      await tester.tap(find.byType(OrbRing));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('How your score adds up'), findsOneWidget);
      // The rule the unknown breaches leave short, with the fix behind it.
      expect(find.text('No breached accounts'), findsOneWidget);

      await tester.tap(find.text('No breached accounts'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(factor, 'check_breaches');
      expect(find.text('How your score adds up'), findsNothing,
          reason: 'the sheet gets out of the way of the fix');
    });

    testWidgets('today lists the check that ran', (tester) async {
      await _mount(tester,
          verdict: await _verdict(score: 92), guards: await _watching());

      expect(find.text('Privacy check ran, nothing found'), findsOneWidget);
    });

    testWidgets('today shows what the shell really recorded', (tester) async {
      // A tall screen, so the whole Today card is built without scrolling.
      final verdict = await _verdict(score: 92);
      final streak = ProtectionStreakController();
      for (int daysAgo = 2; daysAgo >= 0; daysAgo--) {
        await streak.recordCheckup(_now.subtract(Duration(days: daysAgo)));
      }
      await _mount(tester,
          size: const Size(390, 1400),
          verdict: verdict,
          guards: await _watching(),
          streak: streak,
          blockedToday: 37,
          breachCheckedAt: DateTime(2026, 11, 23, 9, 15));

      expect(find.text('37 tracker and surveillance domains blocked'),
          findsOneWidget);
      expect(find.text('Email checked against breach records'), findsOneWidget);
      expect(find.text('3 days in a row'), findsOneWidget);
    });
  });

  group('with something found', () {
    testWidgets('the gap card owns the one lime action', (tester) async {
      String? factor;
      int runs = 0;
      await _mount(tester,
          verdict: await _verdict(score: 68, threats: 2),
          guards: await _watching(),
          onRunCheck: () => runs++,
          onFactorTap: (id) => factor = id);

      expect(find.text('One gap to close.'), findsOneWidget);
      expect(find.text('Your last check found 2 things'), findsOneWidget);
      expect(find.text('Closing it adds 150 to your score'), findsOneWidget);
      expect(find.byType(BrandButton), findsOneWidget,
          reason: 'one lime action per screen');

      await tester.tap(find.widgetWithText(BrandButton, 'Close the gap'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(factor, 'resolve_threats');
      expect(runs, 0);
    });
  });

  group('the six shields', () {
    testWidgets('each is a button that says its name and its state',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _guards([
            _guard('spyware_watch', GuardState.active),
            _guard('firewall', GuardState.unavailable),
            _guard('sms_filter', GuardState.actionNeeded),
          ]),
          onShieldTap: (_) {});

      expect(
        tester.getSemantics(find.bySemanticsLabel('Spyware & Pegasus, on')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(find.bySemanticsLabel('Who’s watching you, limited on this phone'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Scam shield, off'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(', (on|off|limited|needs you)')),
          findsNWidgets(6));
      handle.dispose();
    });

    testWidgets('pressing one opens that shield', (tester) async {
      final handle = tester.ensureSemantics();
      Shield? opened;
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          onShieldTap: (s) => opened = s);

      await tester.tap(find.bySemanticsLabel('Scam shield, on'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(opened, Shield.scam);
      handle.dispose();
    });
  });

  group('the record of the last check', () {
    testWidgets('pressing the check row on Today reopens its results',
        (tester) async {
      final handle = tester.ensureSemantics();
      int opened = 0;
      await _mount(tester,
          size: const Size(390, 1200),
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          onResultsTap: () => opened++);

      await tester.tap(find.bySemanticsLabel(
          RegExp(r'^Privacy check ran, nothing found.*Show the results$')));
      await tester.pump(const Duration(milliseconds: 200));

      expect(opened, 1);
      handle.dispose();
    });

    testWidgets('with nowhere to open, the row is not a button',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _mount(tester,
          size: const Size(390, 1200),
          verdict: await _verdict(score: 92),
          guards: await _watching());

      expect(find.text('Privacy check ran, nothing found'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Show the results')), findsNothing);
      handle.dispose();
    });
  });

  group('the top row', () {
    testWidgets('the bell asks for alerts while they are off', (tester) async {
      final handle = tester.ensureSemantics();
      int asks = 0;
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _guards([
            _guard('spyware_watch', GuardState.active),
            _guard('alerts', GuardState.actionNeeded),
          ]),
          onAlertsTap: () => asks++);

      await tester.tap(find.bySemanticsLabel('Alerts are off. Turn on alerts'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(asks, 1);
      handle.dispose();
    });

    testWidgets('the bell is ready before the guards answer, and hidden',
        (tester) async {
      final handle = tester.ensureSemantics();
      final GuardStatusController guards = GuardStatusController(
        probes: [() async => _guard('alerts', GuardState.active)],
      );
      await _mount(tester, verdict: await _verdict(score: 92), guards: guards);

      // Mounted from the first frame, so its drawing is loaded by the time
      // it shows: the disc never appears a frame before its icon.
      final Finder bell = find.byWidgetPredicate(
          (w) => w is DuotoneIcon && w.icon == AppIcons.bell);
      double opacity() => tester
          .widget<AnimatedOpacity>(find
              .ancestor(of: bell, matching: find.byType(AnimatedOpacity))
              .first)
          .opacity;
      expect(bell, findsOneWidget);
      expect(opacity(), 0);
      expect(find.bySemanticsLabel(RegExp('^Alerts')), findsNothing,
          reason: 'a bell must not promise what is not known');

      await guards.refresh();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(opacity(), 1);
      expect(find.bySemanticsLabel('Alerts are on'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('no bell where alerts cannot be delivered', (tester) async {
      final handle = tester.ensureSemantics();
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _guards([
            _guard('spyware_watch', GuardState.active),
            _guard('alerts', GuardState.unavailable),
          ]));

      expect(find.bySemanticsLabel(RegExp('^Alerts')), findsNothing);
      handle.dispose();
    });

    testWidgets('the trust chip and the account button report their taps',
        (tester) async {
      final handle = tester.ensureSemantics();
      int trust = 0, account = 0;
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          accountInitial: 'M',
          onTrustTap: () => trust++,
          onAccountTap: () => account++);

      await tester.tap(find.text('Private by design'));
      await tester.tap(find.bySemanticsLabel('Account'));
      await tester.pump(const Duration(milliseconds: 200));

      expect(trust, 1);
      expect(account, 1);
      expect(find.text('M'), findsOneWidget);
      handle.dispose();
    });
  });

  group('motion is earned', () {
    testWidgets('with a watcher on, the ring is alive', (tester) async {
      await _mount(tester,
          verdict: await _verdict(score: 92), guards: await _watching());

      expect(tester.binding.hasScheduledFrame, isTrue);
    });

    testWidgets('with nothing on watch, nothing on Home moves', (tester) async {
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _guards([
            _guard('spyware_watch', GuardState.actionNeeded),
            _guard('sms_filter', GuardState.active),
          ]));

      expect(find.text('Nothing is on watch between checks.'), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  testWidgets('everything fits a small phone', (tester) async {
    await _mount(tester,
        size: const Size(320, 568),
        verdict: await _verdict(score: 68, threats: 2),
        guards: await _watching());

    expect(tester.takeException(), isNull);
    expect(find.text('Your last check found 2 things'), findsOneWidget);
  });

  group('what the ring opens for', () {
    testWidgets('a breach the app knows about opens it toward Identity',
        (tester) async {
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          breachedAccounts: 1);

      expect(find.text('One gap to close.'), findsOneWidget);
      expect(find.text('Your email was in a data breach'), findsOneWidget);
      expect(find.text('Closing it adds 100 to your score'), findsOneWidget);
    });

    testWidgets('a clean breach check earns its hundred', (tester) async {
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          breachedAccounts: 0);

      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('a VPN or proxy nobody confirmed opens it toward Hidden VPN',
        (tester) async {
      String? fix;
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          breachedAccounts: 0,
          unknownVpnActive: true,
          onFactorTap: (id) => fix = id);

      expect(find.text('A VPN or proxy is active'), findsOneWidget);
      await tester.tap(find.widgetWithText(BrandButton, 'Close the gap'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(fix, 'review_vpn');
    });

    testWidgets('an app the last check flagged opens it toward Who is watching',
        (tester) async {
      await _mount(
        tester,
        platform: TargetPlatform.android,
        verdict: await _verdict(
          score: 80,
          findings: [
            {
              'id': 'keyboard_com.example.fastkeys',
              'name': 'A keyboard you added can send what you type',
              'severity': 'MEDIUM',
              'path': 'com.example.fastkeys',
              'stage': 'Keylogger detection',
            },
          ],
          stagesRan: CheckPlan.all.map((s) => s.stage).toList(),
        ),
        guards: await _watching(),
        breachedAccounts: 0,
      );

      expect(
          find.text('Your last check found 1 app to review'), findsOneWidget);
      expect(find.text('Closing it adds 50 to your score'), findsOneWidget);
      // 1000 less the audit's 50: the spyware points are untouched.
      expect(find.text('950'), findsOneWidget);
    });

    testWidgets('on Android the audit points wait for a check that ran it',
        (tester) async {
      await _mount(tester,
          platform: TargetPlatform.android,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          breachedAccounts: 0);

      expect(find.text('950'), findsOneWidget);
    });
  });

  group('while a check runs', () {
    const int total = 11;

    DeviceScanProgress progress(int index, {required bool done}) =>
        DeviceScanProgress(
          stageIndex: index,
          totalStages: total,
          stageName: CheckPlan.all[index].stage,
          stageCompleted: done,
          threatsFound: 0,
        );

    /// A check on an iPhone whose engine is driven by the test.
    Future<
        ({
          CheckRun check,
          DeviceScanProgressCallback report,
          Completer<List<Map<String, dynamic>>> engine,
        })> start(WidgetTester tester, {bool android = false}) async {
      final CheckRun check = CheckRun(
        plan: CheckPlan.forDevice(android: android),
        beat: Duration.zero,
        settle: Duration.zero,
      );
      final Completer<List<Map<String, dynamic>>> engine = Completer();
      late DeviceScanProgressCallback report;
      unawaited(check.start((onProgress) {
        report = onProgress;
        return engine.future;
      }));
      return (check: check, report: report, engine: engine);
    }

    testWidgets('Home shows it in place of the action', (tester) async {
      final run = await start(tester);
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          check: run.check);
      run.report(progress(0, done: false));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Checking your phone.'), findsOneWidget);
      expect(find.text('Looking for interception'), findsOneWidget);
      expect(find.text('0/5', findRichText: true), findsOneWidget);
      expect(find.text('checks'), findsOneWidget);
      expect(find.byType(BrandButton), findsNothing);
      expect(find.byType(TodayCard), findsNothing);
      for (final CheckStep step in CheckPlan.forDevice(android: false)) {
        expect(find.text(step.name), findsOneWidget);
      }

      final OrbStatus status =
          tester.widget<OrbRing>(find.byType(OrbRing)).status;
      expect(status.segments, [
        OrbSegment.running,
        OrbSegment.pending,
        OrbSegment.pending,
        OrbSegment.pending,
        OrbSegment.pending,
      ]);

      run.engine.complete(const []);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('each finished check lights its segment and moves the count',
        (tester) async {
      final run = await start(tester);
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          check: run.check);
      run.report(progress(0, done: false));
      run.report(progress(0, done: true));
      run.report(progress(1, done: false));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('1/5', findRichText: true), findsOneWidget);
      expect(find.text('Checking for injected code'), findsOneWidget);
      final OrbStatus status =
          tester.widget<OrbRing>(find.byType(OrbRing)).status;
      expect(status.segments.take(2), [OrbSegment.done, OrbSegment.running]);
      expect(find.bySemanticsLabel('Checking. 1 of 5 checks done.'),
          findsOneWidget);

      run.engine.complete(const []);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('the top row keeps only the promise', (tester) async {
      final run = await start(tester);
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          accountInitial: 'M',
          check: run.check);

      expect(find.text('Private by design'), findsOneWidget);
      expect(find.bySemanticsLabel('Account'), findsNothing);
      expect(find.bySemanticsLabel('Alerts are on'), findsNothing);

      run.engine.complete(const []);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('pressing the ring does nothing until the check is done',
        (tester) async {
      int runs = 0;
      final run = await start(tester);
      await _mount(tester,
          verdict: await _verdict(),
          guards: await _watching(),
          onRunCheck: () => runs++,
          check: run.check);

      await tester.tap(find.byType(OrbRing), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(runs, 0);

      run.engine.complete(const []);
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('when the check ends Home is itself again', (tester) async {
      final run = await start(tester);
      await _mount(tester,
          verdict: await _verdict(score: 92),
          guards: await _watching(),
          check: run.check);
      expect(find.byType(BrandButton), findsNothing);

      run.engine.complete(const []);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Checking your phone.'), findsNothing);
      expect(find.widgetWithText(BrandButton, 'Check now'), findsOneWidget);
      expect(find.byType(TodayCard), findsOneWidget);
    });

    for (final (String name, Size size) in const [
      ('a tall phone', Size(390, 844)),
      ('a short phone', Size(320, 568)),
    ]) {
      testWidgets('eleven checks fit $name without overflow', (tester) async {
        final run = await start(tester, android: true);
        await _mount(tester,
            size: size,
            platform: TargetPlatform.android,
            verdict: await _verdict(score: 92),
            guards: await _watching(),
            check: run.check);
        for (int i = 0; i < 9; i++) {
          run.report(progress(i, done: false));
          run.report(progress(i, done: true));
        }
        run.report(progress(9, done: false));
        // One frame to start the list moving, one to begin its clock, one to
        // let it arrive.
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        expect(find.text('9/11', findRichText: true), findsOneWidget);
        // The list has followed the check: the one running now is on screen,
        // above the tab bar.
        final Rect row = tester.getRect(find.text('Location tracking'));
        final Rect list =
            tester.getRect(find.byKey(const ValueKey('check-list')));
        expect(row.top, greaterThanOrEqualTo(list.top));
        expect(row.bottom, lessThanOrEqualTo(list.bottom));

        run.engine.complete(const []);
        await tester.pump(const Duration(milliseconds: 50));
      });
    }
  });
}
