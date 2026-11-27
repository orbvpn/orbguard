// Home on a wide screen: the ring keeps a pane of its own, and what it
// opens takes the other.
//
// The rules these tests hold:
//  - in a pane, Home is the ring, the verdict and the one action; Today and
//    the shields live in the other pane, so nothing is shown twice
//  - while a check runs, the list of checks is in the other pane, and Home
//    keeps only the line that says what is being checked now
//  - on a desktop window the sidebar holds the brand and the account, so
//    Home has no top row of its own
//  - the side pane's shields say exactly what the ring's shields say, in the
//    same words, and a shield that is open is marked on both
//  - the side pane's Today card does not print "Today" under a head that
//    already says it

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/screens/home/orb_home_screen.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/check_run.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/services/security/device_scan_service.dart';
import 'package:orbguard/widgets/home/home_side.dart';
import 'package:orbguard/widgets/home/orb_hero.dart';
import 'package:orbguard/widgets/home/shield_moon.dart';
import 'package:orbguard/widgets/home/today_card.dart';

final _now = DateTime(2026, 11, 23, 21, 40);

Future<LastScanVerdictController> _verdict({int? score}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (score != null) ...{
      'verdict_score': score,
      'verdict_at_iso':
          _now.subtract(const Duration(hours: 2)).toIso8601String(),
      'verdict_coverage_pct': 90,
      'verdict_checks_run': 11,
      'verdict_findings_json': jsonEncode(const []),
    },
    'verdict_threat_count': 0,
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

/// One shield of each state: on, off, not possible here.
Future<GuardStatusController> _mixed() => _guards([
      _guard('spyware_watch', GuardState.active),
      _guard('firewall', GuardState.actionNeeded),
      _guard('sms_filter', GuardState.active),
      _guard('breach', GuardState.active),
      _guard('hidden_vpn', GuardState.active),
      _guard('secure_call', GuardState.unavailable),
      _guard('alerts', GuardState.active),
    ]);

OrbHomeScreen _home({
  required LastScanVerdictController verdict,
  required GuardStatusController guards,
  HomeLayout layout = HomeLayout.column,
  CheckRun? check,
  int? breachedAccounts,
  Shield? selected,
  void Function(Shield)? onShieldTap,
}) =>
    OrbHomeScreen(
      verdict: verdict,
      guardsController: guards,
      onRunCheck: () {},
      onShieldTap: onShieldTap,
      check: check,
      layout: layout,
      selectedShield: selected,
      breachedAccounts: () => breachedAccounts,
      unknownVpnActive: () => false,
      blockedTodayCount: () => 23,
      platform: TargetPlatform.android,
      clock: () => _now,
    );

Future<void> _mount(WidgetTester tester, Widget child,
    {Size size = const Size(420, 700)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump(const Duration(milliseconds: 80));
}

/// A check whose engine the test drives.
({CheckRun check, void Function(int, {required bool done}) report}) _running() {
  final CheckRun check = CheckRun(
    plan: CheckPlan.forDevice(android: true),
    beat: Duration.zero,
    settle: Duration.zero,
  );
  late DeviceScanProgressCallback onProgress;
  unawaited(check.start((report) {
    onProgress = report;
    return Completer<List<Map<String, dynamic>>>().future;
  }));
  return (
    check: check,
    report: (int i, {required bool done}) => onProgress(DeviceScanProgress(
          stageIndex: i,
          totalStages: CheckPlan.all.length,
          stageName: CheckPlan.all[i].stage,
          stageCompleted: done,
          threatsFound: 0,
        )),
  );
}

void main() {
  group('Home in a pane', () {
    testWidgets('is the ring, the verdict and the action, with no Today',
        (tester) async {
      await _mount(
          tester,
          _home(
            verdict: await _verdict(score: 92),
            guards: await _mixed(),
            layout: HomeLayout.pane,
          ));
      expect(find.text('Private by design'), findsOneWidget);
      expect(find.byType(BrandButton), findsOneWidget);
      expect(find.byType(TodayCard), findsNothing);
    });

    testWidgets('while a check runs it keeps only the line of what runs',
        (tester) async {
      final run = _running();
      await _mount(
          tester,
          _home(
            verdict: await _verdict(score: 92),
            guards: await _mixed(),
            layout: HomeLayout.pane,
            check: run.check,
          ));
      run.report(0, done: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Checking your phone.'), findsOneWidget);
      expect(find.text(CheckPlan.forDevice(android: true).first.doing),
          findsOneWidget);
      expect(find.byKey(const ValueKey('check-list')), findsNothing);
    });

    testWidgets('marks the shield that is open on the other pane',
        (tester) async {
      await _mount(
          tester,
          _home(
            verdict: await _verdict(score: 92),
            guards: await _mixed(),
            layout: HomeLayout.pane,
            selected: Shield.identity,
          ));
      final Iterable<ShieldMoon> moons =
          tester.widgetList<ShieldMoon>(find.byType(ShieldMoon));
      expect(moons.where((m) => m.selected).map((m) => m.shield),
          [Shield.identity]);
    });
  });

  group('Home half open on a table', () {
    testWidgets('the ring stands beside the verdict, with no Today',
        (tester) async {
      await _mount(
          tester,
          _home(
            verdict: await _verdict(score: 92),
            guards: await _mixed(),
            layout: HomeLayout.stand,
          ),
          size: const Size(701, 420));
      final Rect ring = tester.getRect(find.byType(OrbHero));
      final Rect verdict =
          tester.getRect(find.text('No signs you’re being watched.'));
      expect(ring.right, lessThanOrEqualTo(verdict.left));
      expect(verdict.center.dy, closeTo(ring.center.dy, 80));
      expect(find.byType(BrandButton), findsOneWidget);
      expect(find.byType(TodayCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('on a narrow screen it stacks, as in a pane', (tester) async {
      await _mount(
          tester,
          _home(
            verdict: await _verdict(score: 92),
            guards: await _mixed(),
            layout: HomeLayout.stand,
          ),
          size: const Size(412, 457));
      final Rect ring = tester.getRect(find.byType(OrbHero));
      final Rect verdict =
          tester.getRect(find.text('No signs you’re being watched.'));
      expect(ring.bottom, lessThanOrEqualTo(verdict.top));
      expect(tester.takeException(), isNull);
    });
  });

  group('Home in a desktop window', () {
    testWidgets('has no top row: the sidebar holds the account',
        (tester) async {
      await _mount(
          tester,
          _home(
            verdict: await _verdict(score: 92),
            guards: await _mixed(),
            layout: HomeLayout.desk,
          ),
          size: const Size(440, 700));
      expect(find.text('Private by design'), findsNothing);
      expect(find.byType(BrandButton), findsOneWidget);
      expect(find.byType(TodayCard), findsNothing);
    });
  });

  group('the side pane', () {
    testWidgets('shows Today without saying it twice', (tester) async {
      final OrbHomeScreen home = _home(
          verdict: await _verdict(score: 92), guards: await _mixed());
      await _mount(tester, HomeSide(home: home));
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('TODAY'), findsNothing);
      expect(find.byType(TodayCard), findsOneWidget);
      expect(find.text('23 tracker and surveillance domains blocked'),
          findsOneWidget);
    });

    testWidgets('lists the six shields in the ring\'s own words',
        (tester) async {
      final OrbHomeScreen home = _home(
        verdict: await _verdict(score: 92),
        guards: await _mixed(),
        breachedAccounts: 1,
      );
      await _mount(tester, HomeSide(home: home), size: const Size(420, 1100));
      for (final Shield s in Shield.values) {
        expect(find.text(s.name), findsOneWidget);
      }
      Finder chipOf(Shield s) => find.descendant(
          of: find.byKey(ValueKey('shield-tile-${s.name}')),
          matching: find.byType(ShieldChip));
      String said(Shield s) => tester.widget<ShieldChip>(chipOf(s)).text;
      expect(said(Shield.spyware), 'On');
      expect(said(Shield.watching), 'Off');
      expect(said(Shield.identity), '1 gap');
      expect(said(Shield.secureCall), 'Not here');
    });

    testWidgets('three to a row in a desktop column, every tile fits',
        (tester) async {
      final OrbHomeScreen home = _home(
        verdict: await _verdict(score: 92),
        guards: await _mixed(),
        breachedAccounts: 1,
      );
      await _mount(tester, HomeSide(home: home, columns: 3),
          size: const Size(516, 900));
      expect(tester.takeException(), isNull);
      // A chip with no room beside its icon goes under it, whole.
      for (final Shield s in Shield.values) {
        expect(find.byKey(ValueKey('shield-tile-${s.name}')), findsOneWidget);
      }
    });

    testWidgets('a shield opens where it is pressed', (tester) async {
      Shield? opened;
      final OrbHomeScreen home = _home(
        verdict: await _verdict(score: 92),
        guards: await _mixed(),
        onShieldTap: (s) => opened = s,
      );
      await _mount(tester, HomeSide(home: home), size: const Size(420, 1100));
      await tester.tap(find.text(Shield.scam.name));
      expect(opened, Shield.scam);
    });

    testWidgets('while a check runs, it is the list of every check',
        (tester) async {
      final run = _running();
      final OrbHomeScreen home = _home(
        verdict: await _verdict(score: 92),
        guards: await _mixed(),
        check: run.check,
      );
      await _mount(tester, HomeSide(home: home), size: const Size(420, 900));
      run.report(0, done: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Checking'), findsOneWidget);
      expect(find.text('Only what this phone can really run.'), findsOneWidget);
      for (final CheckStep step in CheckPlan.forDevice(android: true)) {
        expect(find.text(step.name), findsOneWidget);
      }
      expect(find.byType(TodayCard), findsNothing);
    });
  });
}
