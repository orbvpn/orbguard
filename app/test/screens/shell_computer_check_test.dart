// On a computer, Home's check runs in place, inside the ring, the way it
// does on a phone. A computer is checked in six areas, the tabs of its
// Desktop Security page, and that page stays the place for the details.
//
// The rules these tests hold:
//  - Check now runs the six areas in the ring and ends on the results sheet;
//    it does not open another page
//  - an area this computer cannot run is named as not possible, and one that
//    broke as could not run; neither is counted as passed
//  - a thing found opens its area's tab of the details
//  - Home's proof counts the checks that ran, as it does on a phone
//  - the Check tab is still the details of the six areas
//  - the first check is free; a later one a person starts passes the credit
//    gate, as on a phone, and without Premium or a credit the gate says
//    Premium is needed

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/presentation/widgets/glass_tab_page.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/desktop/desktop_security_screen.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/widgets/home/check_list.dart';
import 'package:orbguard/widgets/home/orb_hero.dart';
import 'package:orbguard/widgets/home/results_sheet.dart';
import 'package:orbguard/widgets/scan_credits/premium_sheet.dart';

import '../support/shell_harness.dart';

const Size _window = Size(1180, 760);

const List<String> _areas = [
  'Startup items',
  'Code signing',
  'Firewall',
  'Network',
  'Browser',
  'Quarantine',
];

const Map<String, dynamic> _firewallOff = {
  'id': 'desktop-firewall-off',
  'name': 'macOS Firewall is off',
  'description': 'Any app on this Mac can accept connections from other '
      'devices on your network.',
  'severity': 'LOW',
  'type': 'desktop_firewall',
  'path': 'firewall',
  'stage': 'Firewall',
};

Future<void> _press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Lets the side pane and the sheets settle after a tap.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets("Mac: Home's check runs in the ring, in six areas",
      (tester) async {
    final ShellUnderTest shell = await mountShell(tester,
        autoCheckSpent: true, platform: TargetPlatform.macOS, size: _window);

    await _press(tester, 'Run my first check');

    expect(find.text('Checking your Mac.'), findsOneWidget);
    expect(find.byType(DesktopSecurityScreen), findsNothing,
        reason: 'the check runs here, not on another page');
    expect(find.text('Enable deeper scanning'), findsNothing,
        reason: 'a computer is not asked for phone permissions');
    // One ring segment per area, and the side pane lists all six.
    expect(tester.widget<OrbHero>(find.byType(OrbHero)).checking,
        hasLength(6));
    final Finder list = find.byType(CheckList);
    for (final String area in _areas) {
      expect(find.descendant(of: list, matching: find.text(area)),
          findsOneWidget,
          reason: area);
    }

    await finishCheck(tester);

    expect(find.byType(ResultsSheet), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('6 checks ran clean.'), findsOneWidget);
    expect(shell.verdict.stagesRan, [
      for (final CheckStep s in CheckPlan.computer) s.stage,
    ]);
    expect(shell.verdict.checksRun, 6);
    expect(shell.verdict.coveragePercent, 100);

    await _press(tester, 'Done');
    await _settle(tester);

    // Home's line of proof counts them the way a phone does.
    expect(find.text('6 checks ran just now, all clean'), findsOneWidget);
    expect(find.text('No signs you’re being watched.'), findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets(
      'Windows: an area it cannot run is not possible, one that broke could '
      'not run, and neither passed', (tester) async {
    final ShellUnderTest shell = await mountShell(
      tester,
      autoCheckSpent: true,
      platform: TargetPlatform.windows,
      size: _window,
      runner: fakeCheck(
        platform: TargetPlatform.windows,
        notPossible: {'Code signing'},
        failing: {'Network'},
      ),
    );

    await _press(tester, 'Run my first check');
    expect(find.text('Checking your computer.'), findsOneWidget);
    await finishCheck(tester);

    expect(find.text('All clear'), findsNothing);
    expect(find.text('Nothing found so far'), findsOneWidget);
    expect(find.text('4 checks ran clean. 1 could not run.'), findsOneWidget);
    expect(find.text('1 check is not possible on this computer'),
        findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('1 check could not run this time'),
      200,
      scrollable: find
          .descendant(
              of: find.byType(ResultsSheet), matching: find.byType(Scrollable))
          .first,
    );
    expect(find.text('1 check could not run this time'), findsOneWidget);
    expect(shell.verdict.stagesNotPossible, ['Code signing']);
    expect(shell.verdict.stagesFailed, ['Network']);
    // Four of the six areas ran.
    expect(shell.verdict.coveragePercent, 67);

    await unmountShell(tester);
  });

  testWidgets('a thing found opens its own tab of the details',
      (tester) async {
    await mountShell(tester,
        autoCheckSpent: true,
        platform: TargetPlatform.macOS,
        size: _window,
        runner: fakeCheck(
            platform: TargetPlatform.macOS, findings: [_firewallOff]));

    await _press(tester, 'Run my first check');
    await finishCheck(tester);

    expect(find.text('Your check found 1 thing'), findsOneWidget);
    expect(find.text('5 checks ran clean.'), findsOneWidget);

    await _press(tester, 'macOS Firewall is off');
    expect(find.widgetWithText(BrandButton, 'See details'), findsOneWidget);

    await _press(tester, 'See details');
    await _settle(tester);

    expect(find.byType(ResultsSheet), findsNothing);
    expect(find.byType(DesktopSecurityScreen), findsOneWidget);
    expect(
        tester.widget<GlassTabPage>(find.byType(GlassTabPage)).initialIndex, 2,
        reason: 'Firewall is the third tab');

    await unmountShell(tester);
  });

  // The free tier is the same on a computer as on a phone: the first check
  // is free, each later one a person starts costs one scan credit.
  testWidgets('a later check on a computer passes the credit gate first',
      (tester) async {
    await mountShell(tester,
        checked: true,
        autoCheckSpent: true,
        platform: TargetPlatform.macOS,
        size: _window);

    await _press(tester, 'Check now');

    // Signed out, so the gate says Premium is needed before any check runs;
    // a computer has no credits sheet of its own.
    expect(find.byType(PremiumSheet), findsOneWidget);
    expect(find.text('Checking your Mac.'), findsNothing);

    // Turning the gate down runs no check.
    Navigator.of(tester.element(find.byType(PremiumSheet))).pop();
    await _settle(tester);
    expect(find.text('Checking your Mac.'), findsNothing);

    await unmountShell(tester);
  });

  testWidgets('with a credit, a later check on a computer spends it and runs',
      (tester) async {
    final ShellUnderTest shell = await mountShell(tester,
        checked: true,
        autoCheckSpent: true,
        signedIn: true,
        credits: 3,
        platform: TargetPlatform.windows,
        size: _window);

    await _press(tester, 'Check now');

    expect(find.text('Checking your computer.'), findsOneWidget);
    expect(shell.sale.api.balance, 2);

    await unmountShell(tester);
  });

  testWidgets('the first check on a computer is free', (tester) async {
    final ShellUnderTest shell = await mountShell(tester,
        autoCheckSpent: true, platform: TargetPlatform.macOS, size: _window);

    await _press(tester, 'Run my first check');

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Checking your Mac.'), findsOneWidget);
    expect(shell.sale.api.balance, 3);

    await unmountShell(tester);
  });

  testWidgets('the Check tab is still the details of the six areas',
      (tester) async {
    await mountShell(tester,
        checked: true,
        autoCheckSpent: true,
        platform: TargetPlatform.macOS,
        size: _window);

    await _press(tester, 'Check');
    await _settle(tester);

    expect(find.byType(DesktopSecurityScreen), findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets('a phone-sized window on a Mac runs the same six', (tester) async {
    final ShellUnderTest shell = await mountShell(tester,
        autoCheckSpent: true, platform: TargetPlatform.macOS);

    await _press(tester, 'Run my first check');
    expect(find.text('Checking your Mac.'), findsOneWidget);
    await finishCheck(tester);

    expect(find.text('6 checks ran clean.'), findsOneWidget);
    expect(shell.verdict.stagesRan, hasLength(6));

    await unmountShell(tester);
  });
}
