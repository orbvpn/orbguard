// A check runs on Home, in place, and ends on a sheet that says only what
// happened. These tests hold the shell to that, since the wiring between
// the engine, the record and the sheets is where it goes wrong.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/screens/check/check_tab_screen.dart';
import 'package:orbguard/screens/desktop/desktop_security_screen.dart';
import 'package:orbguard/screens/home/orb_home_screen.dart';
import 'package:orbguard/services/security/device_scan_service.dart';
import 'package:orbguard/widgets/home/results_sheet.dart';

import '../support/shell_harness.dart';

final Finder _checking = find.textContaining('Checking your');

const Map<String, dynamic> _keyboard = {
  'id': 'k1',
  'name': 'A keyboard you added can send what you type',
  'description': 'It can read every key you press.',
  'severity': 'MEDIUM',
  'type': 'app_risk',
  'path': 'com.example.keys',
  'stage': 'Keylogger detection',
};

Future<void> _press(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('a check runs on Home and ends on its results', (tester) async {
    final ShellUnderTest shell = await mountShell(tester, autoCheckSpent: true);

    await _press(tester, 'Run my first check');

    expect(_checking, findsOneWidget);
    expect(find.byKey(const ValueKey('check-list')), findsOneWidget);
    expect(find.text('Run my first check'), findsNothing);

    await finishCheck(tester);

    expect(_checking, findsNothing);
    expect(find.byType(ResultsSheet), findsOneWidget);
    expect(find.text('All clear'), findsOneWidget);
    expect(find.text('11 checks ran clean.'), findsOneWidget);
    expect(shell.verdict.hasScanned, isTrue);
    expect(shell.verdict.stagesRan, hasLength(11));
    expect(shell.verdict.stagesFailed, isEmpty);

    await unmountShell(tester);
  });

  testWidgets('a thing the check found says what to do about it',
      (tester) async {
    await mountShell(tester,
        autoCheckSpent: true, runner: fakeCheck(findings: [_keyboard]));

    await _press(tester, 'Run my first check');
    await finishCheck(tester);

    expect(find.text('Your check found 1 thing'), findsOneWidget);

    await _press(tester, 'A keyboard you added can send what you type');

    // Its own sheet, over the results: what it is, and the one real step.
    expect(find.text('It can read every key you press.'), findsWidgets);
    expect(
        find.widgetWithText(BrandButton, 'Open app settings'), findsOneWidget);
    expect(find.byType(ResultsSheet), findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets('a check that broke in part is not called all clear',
      (tester) async {
    final ShellUnderTest shell = await mountShell(tester,
        autoCheckSpent: true,
        runner: fakeCheck(failing: {'Memory', 'File system'}));

    await _press(tester, 'Run my first check');
    await finishCheck(tester);

    expect(find.text('All clear'), findsNothing);
    expect(find.text('Nothing found so far'), findsOneWidget);
    expect(find.text('9 checks ran clean. 2 could not run.'), findsOneWidget);
    expect(shell.verdict.stagesFailed, ['File system', 'Memory']);

    await unmountShell(tester);
  });

  testWidgets('a check that could not run says so and records nothing',
      (tester) async {
    final ShellUnderTest shell = await mountShell(tester,
        autoCheckSpent: true,
        runner: fakeCheck(error: DeviceScanUnavailableException('no engine')));

    await _press(tester, 'Run my first check');
    await finishCheck(tester);

    expect(find.text('The check could not run'), findsOneWidget);
    expect(find.byType(ResultsSheet), findsNothing);
    expect(shell.verdict.hasScanned, isFalse,
        reason: 'nothing was checked, so nothing may read as checked');

    await unmountShell(tester);
  });

  testWidgets('a VPN that is up is a gap of its own, not a thing found',
      (tester) async {
    await mountShell(tester, autoCheckSpent: true, tunnel: true);

    await _press(tester, 'Run my first check');
    await finishCheck(tester);

    expect(find.text('Checks are clean'), findsOneWidget);
    // The connection check is not called clean while the tunnel is
    // unconfirmed, so ten of the eleven are.
    expect(find.text('10 checks ran clean. One gap is still open.'),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(ResultsSheet),
            matching: find.text('A VPN or proxy is active')),
        findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets('the record on Today reopens the last results', (tester) async {
    await mountShell(tester, autoCheckSpent: true);
    await _press(tester, 'Run my first check');
    await finishCheck(tester);
    await _press(tester, 'Done');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(ResultsSheet), findsNothing);

    // The record sits low on the page, behind the tab bar until scrolled.
    await tester.drag(find.byType(OrbHomeScreen), const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 300));
    await _press(tester, 'Privacy check ran, nothing found');
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(ResultsSheet), findsOneWidget);
    expect(find.text('11 checks ran clean.'), findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets('on a phone the Check tab is the tools page, with no bar over it',
      (tester) async {
    await mountShell(tester, checked: true, autoCheckSpent: true);

    await _press(tester, 'Check');

    expect(find.byType(CheckTabScreen), findsOneWidget);
    expect(find.text('Tap to start a check'), findsNothing);
    expect(find.text('OrbGuard'), findsNothing,
        reason: 'the page has its own heading; the old bar is gone');

    await unmountShell(tester);
  });

  testWidgets('Protect and Me carry their own headings too', (tester) async {
    await mountShell(tester, checked: true, autoCheckSpent: true);

    await _press(tester, 'Protect');
    expect(find.text('OrbGuard'), findsNothing);

    await _press(tester, 'Me');
    expect(find.text('OrbGuard'), findsNothing);

    await unmountShell(tester);
  });

  testWidgets("on a computer Home's check opens the Check tab", (tester) async {
    await mountShell(tester,
        autoCheckSpent: true, platform: TargetPlatform.macOS);

    await _press(tester, 'Run my first check');

    // The computer's own check lives on the Check tab. Home starts no phone
    // check here and asks for no phone permissions.
    expect(_checking, findsNothing);
    expect(find.text('Enable deeper scanning'), findsNothing);
    expect(find.byType(DesktopSecurityScreen), findsOneWidget);

    await unmountShell(tester);
  });

  testWidgets('on a computer no check starts by itself', (tester) async {
    await mountShell(tester, platform: TargetPlatform.macOS);

    expect(_checking, findsNothing);
    expect(find.text('Enable deeper scanning'), findsNothing);
    expect(find.text('Run my first check'), findsOneWidget);

    await unmountShell(tester);
  });
}
