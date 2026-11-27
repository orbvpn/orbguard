// The shell keeps the tray icon on a Windows or Linux computer saying what
// Home says, and answers its Check now the way it answers the menu bar's.
//
// The rules these tests hold:
//  - the tray is told the glance the menu bar is told: the ring's state,
//    and Home's words with the time of the check
//  - when the reading changes, the tray follows
//  - Check now from the tray brings the window forward and does exactly
//    what Check now from the menu bar does, on the same shell
//  - closing the window hides it while the icon is up; Quit really quits

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/desktop/desktop_tray.dart';

import '../support/desktop_fakes.dart';
import '../support/shell_harness.dart';

const MethodChannel _glance = MethodChannel('com.orb.guard/glance');
const Size _desk = Size(1180, 760);

/// The menu bar's side of the glance channel, answered so the shell can
/// talk to it.
void _quietGlance() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_glance, (call) async => null);
  addTearDown(() => messenger.setMockMethodCallHandler(_glance, null));
}

/// The menu bar presses its Check now.
Future<void> _menuBarCheckNow() async {
  const MethodCodec codec = StandardMethodCodec();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
    _glance.name,
    codec.encodeMethodCall(const MethodCall('checkNow')),
    (_) {},
  );
}

/// Lets the start-up probes that do real work (not fake time) finish, so
/// the shell is ready for a check the same way on every mount.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The same frames after either Check now. A press in the tray lands between
/// frames, so the first frame after it may not have seen it yet.
Future<void> _afterCheckNow(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Every piece of text on screen, without the ones that hold a number, so
/// two shells mounted moments apart can be compared.
List<String> _screen() => [
      for (final Element e in find.byType(Text).evaluate())
        if ((e.widget as Text).data case final String s)
          if (!s.contains(RegExp(r'\d'))) s,
    ];

DesktopTray _tray(FakeTray tray, FakeWindow window) => DesktopTray(
      platform: TargetPlatform.windows,
      tray: tray,
      window: window,
      use24h: () => true,
      shade: () => Brightness.dark,
      scale: () => 1,
    );

void main() {
  testWidgets('the tray says what Home says', (tester) async {
    _quietGlance();
    final FakeTray tray = FakeTray();
    final FakeWindow window = FakeWindow();
    final ShellUnderTest shell = await mountShell(tester,
        platform: TargetPlatform.windows,
        size: _desk,
        checked: true,
        autoCheckSpent: true,
        desktopTray: _tray(tray, window));

    expect(tray.icon, 'assets/tray/windows/dark/open.ico');
    final DateTime at = shell.verdict.lastScanAt!;
    expect(
        tray.status,
        'All clear. Checked '
        '${TrayMenu.checkedWhen(at, now: DateTime.now(), use24h: true)}');
    expect(tray.tip, 'OrbGuard. ${tray.status}');
    expect(tray.commands, ['Check now', 'Open OrbGuard', 'Quit OrbGuard']);
    expect(window.kept, isTrue, reason: 'close hides while the icon is up');

    await unmountShell(tester);
    expect(tray.removed, isTrue, reason: 'the icon goes with the shell');
    expect(window.kept, isFalse);
  });

  testWidgets('the tray follows the reading when it changes', (tester) async {
    _quietGlance();
    final FakeTray tray = FakeTray();
    final ShellUnderTest shell = await mountShell(tester,
        platform: TargetPlatform.windows,
        size: _desk,
        autoCheckSpent: true,
        desktopTray: _tray(tray, FakeWindow()));
    expect(tray.icon, 'assets/tray/windows/dark/fresh.ico');
    expect(tray.status, 'Not checked yet');

    await shell.verdict.recordScan(
      threats: const [
        {
          'type': 'spyware',
          'name': 'Stalkerware',
          'path': 'x',
          'severity': 'HIGH',
        },
      ],
      coveragePercent: 90,
      now: DateTime.now(),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tray.icon, 'assets/tray/windows/dark/open-330.ico');
    expect(tray.status, isNot(startsWith('All clear')));

    await unmountShell(tester);
  });

  testWidgets(
      'Check now from the tray brings the window forward and does what the '
      'menu bar\'s Check now does', (tester) async {
    _quietGlance();

    // The menu bar's Check now, on one shell.
    await mountShell(tester,
        platform: TargetPlatform.windows, size: _desk, autoCheckSpent: true);
    await _settle(tester);
    final List<String> before = _screen();
    await _menuBarCheckNow();
    await _afterCheckNow(tester);
    final List<String> fromMenuBar = _screen();
    // Whatever Check now opened finishes its own start-up before the shell
    // goes, not during the next one.
    await _settle(tester);
    await finishCheck(tester);
    await unmountShell(tester);
    expect(fromMenuBar, isNot(before), reason: 'Check now did something');

    // The tray's Check now, on the same shell.
    final FakeTray tray = FakeTray();
    final FakeWindow window = FakeWindow();
    await mountShell(tester,
        platform: TargetPlatform.windows,
        size: _desk,
        autoCheckSpent: true,
        desktopTray: _tray(tray, window));
    await _settle(tester);
    window.close();
    expect(window.hidden, isTrue);
    expect(_screen(), before);

    tray.press(TrayCommand.checkNow);
    await _afterCheckNow(tester);
    expect(window.hidden, isFalse);
    expect(window.broughtForward, 1);
    expect(_screen(), fromMenuBar);

    await _settle(tester);
    await finishCheck(tester);
    await unmountShell(tester);
  });

  testWidgets('Quit from the tray quits', (tester) async {
    _quietGlance();
    final FakeTray tray = FakeTray();
    final FakeWindow window = FakeWindow();
    await mountShell(tester,
        platform: TargetPlatform.linux,
        size: _desk,
        checked: true,
        autoCheckSpent: true,
        desktopTray: DesktopTray(
          platform: TargetPlatform.linux,
          tray: tray,
          window: window,
          use24h: () => true,
          shade: () => Brightness.dark,
          scale: () => 1,
        ));
    expect(tray.icon, 'assets/tray/linux/dark/open-22.png');

    tray.press(TrayCommand.quit);
    await tester.pump();
    expect(tray.removed, isTrue);
    expect(window.kept, isFalse);
    expect(window.ended, isTrue);

    await unmountShell(tester);
  });

  testWidgets('the Mac shell puts nothing in a tray', (tester) async {
    _quietGlance();
    final FakeTray tray = FakeTray();
    final FakeWindow window = FakeWindow();
    await mountShell(tester,
        platform: TargetPlatform.macOS,
        size: _desk,
        checked: true,
        autoCheckSpent: true,
        desktopTray: DesktopTray(
          platform: TargetPlatform.macOS,
          tray: tray,
          window: window,
        ));
    expect(tray.calls, isEmpty);
    expect(window.calls, isEmpty);

    await unmountShell(tester);
  });
}
