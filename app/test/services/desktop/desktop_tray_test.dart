// The tray icon on a Windows or Linux computer.
//
// The rules these tests hold:
//  - the menu says what Home says, in Home's words, and offers Check now,
//    Open OrbGuard and Quit OrbGuard; before any glance it says nothing
//  - it names no plan, no price and no store, and is written without
//    dashes or arrows
//  - the icon shows the ring's state, and a picture exists for every state
//    the ring can be in, at every size each tray asks for
//  - the window hides on close only once the icon is up; Quit really quits
//  - a click opens the window; Check now opens it and runs Home's check
//  - nothing goes in a tray on the Mac, a phone, or a computer without one

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/services/desktop/desktop_tray.dart';
import 'package:orbguard/services/home/glance.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';

import '../../support/desktop_fakes.dart';

final DateTime _now = DateTime(2026, 11, 25, 9, 41);

GuardStatus _guard(String id, GuardState state) =>
    GuardStatus(id: id, name: id, state: state, detail: '');

/// A glance worked out the way the shell works one out, on a computer.
Glance _glance({
  bool checked = true,
  Duration since = const Duration(hours: 2),
  int openThreats = 0,
  int breachedAccounts = 0,
  bool watching = true,
  DateTime? now,
}) {
  final DateTime at = now ?? _now;
  final DateTime? last = checked ? at.subtract(since) : null;
  final PrivacySignals signals = PrivacySignals(
    lastScanScore: 92,
    daysSinceScan: since.inDays,
    openThreats: openThreats,
    guardsActive: 3,
    guardsAvailable: 3,
    breachedAccounts: breachedAccounts,
    riskyPermissionApps: 0,
    unknownVpnActive: false,
    notificationsGranted: true,
  );
  final HomeBrief brief = HomeBrief.from(
    hasScanned: checked,
    verdictScore: checked ? 92 : -1,
    lastScanAt: last,
    checksRun: checked ? 6 : null,
    openThreats: openThreats,
    breachedAccounts: breachedAccounts,
    score: const PrivacyScoreEngine().compute(signals),
    guards: [
      _guard('spyware_watch',
          watching ? GuardState.active : GuardState.actionNeeded),
      _guard('breach', watching ? GuardState.active : GuardState.actionNeeded),
      _guard('alerts', GuardState.active),
    ],
    guardsResolved: true,
    now: at,
    deviceNoun: 'computer',
  );
  return Glance.from(brief: brief, lastScanAt: last);
}

List<String?> _labels(List<TrayItem> items) =>
    [for (final TrayItem i in items) i.isSeparator ? '-' : i.label];

/// The sizes inside a .ico, from its directory.
List<int> _icoSizes(Uint8List bytes) {
  final ByteData data = ByteData.sublistView(bytes);
  expect(data.getUint16(0, Endian.little), 0, reason: 'reserved');
  expect(data.getUint16(2, Endian.little), 1, reason: 'an icon, not a cursor');
  final int count = data.getUint16(4, Endian.little);
  return [
    for (int i = 0; i < count; i++)
      bytes[6 + 16 * i] == 0 ? 256 : bytes[6 + 16 * i],
  ];
}

/// The width and height of a PNG, from its header.
(int, int) _pngSize(Uint8List bytes) {
  expect(bytes.sublist(1, 4), 'PNG'.codeUnits);
  final ByteData data = ByteData.sublistView(bytes);
  return (data.getUint32(16), data.getUint32(20));
}

DesktopTray _tray({
  required FakeTray tray,
  required FakeWindow window,
  TargetPlatform platform = TargetPlatform.windows,
  DateTime Function()? clock,
  Brightness Function()? shade,
}) =>
    DesktopTray(
      platform: platform,
      tray: tray,
      window: window,
      clock: clock ?? () => _now,
      use24h: () => true,
      shade: shade ?? () => Brightness.dark,
      scale: () => 1,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the menu', () {
    test('before any glance: only Open OrbGuard and Quit OrbGuard', () {
      expect(_labels(TrayMenu.of(null, now: _now, use24h: true)),
          ['Open OrbGuard', '-', 'Quit OrbGuard']);
    });

    test('never checked: Home says so, and offers the check', () {
      final List<TrayItem> menu =
          TrayMenu.of(_glance(checked: false), now: _now, use24h: true);
      expect(_labels(menu), [
        'Not checked yet',
        '-',
        'Check now',
        'Open OrbGuard',
        '-',
        'Quit OrbGuard',
      ]);
      expect(menu.first.enabled, isFalse, reason: 'the status only says');
      expect([
        for (final TrayItem i in menu) i.command
      ], [
        null,
        null,
        TrayCommand.checkNow,
        TrayCommand.open,
        null,
        TrayCommand.quit,
      ]);
    });

    test('all clear, with the time of the check in the reader\'s format', () {
      final Glance g = _glance();
      expect(TrayMenu.statusLine(g, now: _now, use24h: true),
          'All clear. Checked 07:41');
      expect(TrayMenu.statusLine(g, now: _now, use24h: false),
          'All clear. Checked 7:41 AM');
    });

    test('something found: Home\'s headline, without its full stop', () {
      final Glance g = _glance(openThreats: 1);
      expect(g.moment, HomeMoment.gap);
      final String headline = g.headline;
      expect(headline.endsWith('.'), isTrue);
      expect(TrayMenu.statusLine(g, now: _now, use24h: true),
          '${headline.substring(0, headline.length - 1)}. Checked 07:41');
    });

    test('an older check says how many days ago, in Home\'s words', () {
      expect(
          TrayMenu.checkedWhen(DateTime(2026, 11, 24, 23, 50),
              now: _now, use24h: true),
          'yesterday');
      expect(
          TrayMenu.checkedWhen(DateTime(2026, 11, 22, 8),
              now: _now, use24h: true),
          '3 days ago');
    });

    test('once the reading is stale it stops saying all clear', () {
      final Glance g = _glance();
      final DateTime later = _now.add(const Duration(days: 8));
      expect(TrayMenu.statusLine(g, now: later, use24h: true),
          'Nothing found last time. Checked 8 days ago');
    });

    test('the tooltip names the app, then says the status', () {
      expect(TrayMenu.toolTip(null, now: _now, use24h: true), 'OrbGuard');
      expect(TrayMenu.toolTip(_glance(), now: _now, use24h: true),
          'OrbGuard. All clear. Checked 07:41');
    });

    test('no plan, price or store, and no dash, arrow or middle dot', () {
      final RegExp sale = RegExp(
          r'plan|price|premium|subscri|upgrade|trial|\$|€|£|store|play|'
          r'microsoft|apple|google|amazon|snap',
          caseSensitive: false);
      final RegExp marks = RegExp('[—–→←↑↓⇒⇐·]');
      final List<Glance?> glances = [
        null,
        _glance(checked: false),
        _glance(),
        _glance(watching: false),
        _glance(openThreats: 2, breachedAccounts: 1),
        _glance(since: const Duration(days: 9)),
      ];
      for (final Glance? g in glances) {
        for (final bool h24 in const [true, false]) {
          final List<String> words = [
            TrayMenu.toolTip(g, now: _now, use24h: h24),
            for (final TrayItem i in TrayMenu.of(g, now: _now, use24h: h24))
              if (!i.isSeparator) i.label!,
          ];
          for (final String w in words) {
            expect(sale.hasMatch(w), isFalse, reason: w);
            expect(marks.hasMatch(w), isFalse, reason: w);
          }
        }
      }
    });
  });

  group('the icon', () {
    test('shows the ring\'s state', () {
      expect(TrayIcon.keyFor(null), 'logo');
      expect(TrayIcon.keyFor(_glance(checked: false)), 'fresh');
      expect(TrayIcon.keyFor(_glance()), 'open');
      expect(TrayIcon.keyFor(_glance(watching: false)), 'still');
      expect(TrayIcon.keyFor(_glance(openThreats: 1)), 'open-330');
      expect(TrayIcon.keyFor(_glance(openThreats: 1, breachedAccounts: 1)),
          'open-150-330');
    });

    test('a stale reading keeps its ring, as the menu bar ring does', () {
      expect(TrayIcon.keyFor(_glance(since: const Duration(days: 9))),
          TrayIcon.keyFor(_glance()));
    });

    test('the ring opens where the shields that can find something sit', () {
      expect(TrayIcon.stations, [30, 150, 210, 330]);
      // Two of each kind of ring for every set of stations, and the two
      // that have no band.
      expect(TrayIcon.keys.length, 2 + 2 * 16);
      expect(TrayIcon.keys.toSet().length, TrayIcon.keys.length);
    });

    test('a gap off every station is drawn at the nearest one', () {
      final Glance g = _glance(openThreats: 1);
      final Map<String, Object?> map = g.toMap();
      expect(map['gaps'], [330.0]);
      expect(TrayIcon.keys, contains(TrayIcon.keyFor(g)));
    });

    test('Windows takes one .ico; Linux the PNG nearest its panel size', () {
      expect(
          TrayIcon.asset('open-330',
              platform: TargetPlatform.windows, shade: Brightness.dark),
          'assets/tray/windows/dark/open-330.ico');
      expect(
          TrayIcon.asset('fresh',
              platform: TargetPlatform.linux, shade: Brightness.light),
          'assets/tray/linux/light/fresh-22.png');
      expect(TrayIcon.linuxSize(1), 22);
      expect(TrayIcon.linuxSize(1.1), 24);
      expect(TrayIcon.linuxSize(1.5), 32);
      expect(TrayIcon.linuxSize(2), 32);
    });

    test('a picture exists for every state, shade and size', () {
      final List<String> missing = [];
      for (final String key in TrayIcon.keys) {
        for (final Brightness shade in Brightness.values) {
          final File ico = File(TrayIcon.asset(key,
              platform: TargetPlatform.windows, shade: shade));
          if (!ico.existsSync()) {
            missing.add(ico.path);
          } else {
            expect(_icoSizes(ico.readAsBytesSync()), TrayIcon.windowsSizes,
                reason: ico.path);
          }
          for (final int size in TrayIcon.linuxSizes) {
            final File png = File(TrayIcon.asset(key,
                platform: TargetPlatform.linux,
                shade: shade,
                scale: size / 22));
            if (!png.existsSync()) {
              missing.add(png.path);
            } else {
              expect(_pngSize(png.readAsBytesSync()), (size, size),
                  reason: png.path);
            }
          }
        }
      }
      expect(missing, isEmpty);
    });

    test('the pictures are among the app\'s assets', () {
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      for (final String dir in const [
        'assets/tray/windows/dark/',
        'assets/tray/windows/light/',
        'assets/tray/linux/dark/',
        'assets/tray/linux/light/',
      ]) {
        expect(pubspec, contains('- $dir'));
      }
    });
  });

  group('the window', () {
    test('close hides it only on a computer whose tray shows the icon', () {
      for (final TargetPlatform p in TargetPlatform.values) {
        expect(DesktopTray.closeHides(platform: p, iconShown: false), isFalse);
      }
      expect(
          DesktopTray.closeHides(
              platform: TargetPlatform.windows, iconShown: true),
          isTrue);
      expect(
          DesktopTray.closeHides(
              platform: TargetPlatform.linux, iconShown: true),
          isTrue);
      // The Mac keeps running from its own menu bar ring, natively.
      expect(
          DesktopTray.closeHides(
              platform: TargetPlatform.macOS, iconShown: true),
          isFalse);
    });
  });

  group('the tray', () {
    testWidgets('goes in with its icon first, then the close button hides',
        (tester) async {
      final FakeTray tray = FakeTray();
      final FakeWindow window = FakeWindow();
      final DesktopTray t = _tray(tray: tray, window: window);
      await t.start();

      expect(tray.calls, ['canShow', 'setIcon', 'setToolTip', 'setMenu']);
      expect(window.calls, ['attach', 'keepOnClose(true)']);
      expect(tray.icon, 'assets/tray/windows/dark/logo.ico');
      expect(tray.status, isNull);
      expect(tray.commands, ['Open OrbGuard', 'Quit OrbGuard']);
      expect(t.iconShown, isTrue);

      expect(window.close(), isFalse, reason: 'kept');
      expect(window.hidden, isTrue);

      t.dispose();
    });

    testWidgets('follows the glance, and is told only what changed',
        (tester) async {
      final FakeTray tray = FakeTray();
      final FakeWindow window = FakeWindow();
      final DesktopTray t = _tray(tray: tray, window: window);
      await t.start();

      t.show(_glance(openThreats: 1));
      await tester.pump();
      expect(tray.icon, 'assets/tray/windows/dark/open-330.ico');
      expect(tray.status, endsWith('Checked 07:41'));
      expect(tray.tip, 'OrbGuard. ${tray.status}');
      expect(tray.commands, ['Check now', 'Open OrbGuard', 'Quit OrbGuard']);

      final int before = tray.calls.length;
      t.show(_glance(openThreats: 1));
      await tester.pump();
      expect(tray.calls.length, before, reason: 'nothing changed');

      t.show(_glance());
      await tester.pump();
      expect(tray.icon, 'assets/tray/windows/dark/open.ico');
      expect(tray.status, 'All clear. Checked 07:41');

      t.dispose();
    });

    testWidgets('a lighter taskbar gets the light picture', (tester) async {
      Brightness shade = Brightness.dark;
      final FakeTray tray = FakeTray();
      final DesktopTray t = DesktopTray(
        platform: TargetPlatform.linux,
        tray: tray,
        window: FakeWindow(),
        clock: () => _now,
        use24h: () => true,
        shade: () => shade,
        scale: () => 2,
      );
      await t.start();
      t.show(_glance());
      await tester.pump();
      expect(tray.icon, 'assets/tray/linux/dark/open-32.png');

      shade = Brightness.light;
      t.didChangePlatformBrightness();
      await tester.pump();
      expect(tray.icon, 'assets/tray/linux/light/open-32.png');

      t.dispose();
    });

    testWidgets('at midnight, today\'s time becomes a day', (tester) async {
      DateTime now = DateTime(2026, 11, 25, 23, 0);
      final FakeTray tray = FakeTray();
      final DesktopTray t =
          _tray(tray: tray, window: FakeWindow(), clock: () => now);
      await t.start();
      t.show(_glance(now: now, since: const Duration(hours: 1)));
      await tester.pump();
      expect(tray.status, 'All clear. Checked 22:00');

      now = DateTime(2026, 11, 26, 0, 0, 1);
      await tester.pump(const Duration(hours: 1, seconds: 1));
      expect(tray.status, 'All clear. Checked yesterday');

      t.dispose();
    });

    testWidgets('a click brings the window forward', (tester) async {
      final FakeTray tray = FakeTray();
      final FakeWindow window = FakeWindow();
      final DesktopTray t = _tray(tray: tray, window: window);
      await t.start();
      window.close();
      expect(window.hidden, isTrue);

      tray.click();
      await tester.pump();
      expect(window.hidden, isFalse);
      expect(window.broughtForward, 1);

      t.dispose();
    });

    testWidgets('a right click opens the menu, its words made true for now',
        (tester) async {
      DateTime now = _now;
      final FakeTray tray = FakeTray();
      final DesktopTray t =
          _tray(tray: tray, window: FakeWindow(), clock: () => now);
      await t.start();
      t.show(_glance());
      await tester.pump();
      tray.calls.clear();

      now = DateTime(2026, 11, 26, 7);
      tray.rightClick();
      await tester.pump();
      expect(tray.calls, ['setToolTip', 'setMenu', 'popUpMenu']);
      expect(tray.status, 'All clear. Checked yesterday');

      t.dispose();
    });

    testWidgets('Check now brings the window forward, then runs the check',
        (tester) async {
      final FakeTray tray = FakeTray();
      final FakeWindow window = FakeWindow();
      final DesktopTray t = _tray(tray: tray, window: window)
        ..onCheckNow = () => window.calls.add('check');
      await t.start();
      t.show(_glance());
      await tester.pump();
      window.calls.clear();

      tray.press(TrayCommand.checkNow);
      await tester.pump();
      expect(window.calls, ['bringForward', 'check']);

      tray.press(TrayCommand.open);
      await tester.pump();
      expect(window.broughtForward, 2);

      t.dispose();
    });

    testWidgets('Quit takes the icon out and really quits', (tester) async {
      final FakeTray tray = FakeTray();
      final FakeWindow window = FakeWindow();
      final DesktopTray t = _tray(tray: tray, window: window);
      await t.start();

      tray.press(TrayCommand.quit);
      await tester.pump();
      expect(tray.removed, isTrue);
      expect(window.calls.skip(2), ['keepOnClose(false)', 'quit']);
      expect(window.ended, isTrue);

      t.dispose();
    });

    testWidgets('without a tray to show it, nothing goes in and close quits',
        (tester) async {
      final FakeTray tray = FakeTray(shows: false);
      final FakeWindow window = FakeWindow();
      final DesktopTray t =
          _tray(tray: tray, window: window, platform: TargetPlatform.linux);
      await t.start();
      t.show(_glance());
      await tester.pump();

      expect(tray.calls, ['canShow']);
      expect(window.kept, isFalse);
      expect(t.iconShown, isFalse);
      expect(window.close(), isTrue, reason: 'it closes, so the app quits');
      expect(window.hidden, isFalse);

      t.dispose();
    });

    testWidgets('an icon that fails to go in leaves close as it was',
        (tester) async {
      final FakeTray tray = FakeTray(failsIcon: true);
      final FakeWindow window = FakeWindow();
      final DesktopTray t = _tray(tray: tray, window: window);
      await t.start();

      expect(window.kept, isFalse);
      expect(window.close(), isTrue);
      expect(window.hidden, isFalse);

      t.dispose();
    });

    testWidgets('nothing goes in a tray on the Mac or a phone', (tester) async {
      for (final TargetPlatform p in const [
        TargetPlatform.macOS,
        TargetPlatform.iOS,
        TargetPlatform.android,
      ]) {
        final FakeTray tray = FakeTray();
        final FakeWindow window = FakeWindow();
        final DesktopTray t = _tray(tray: tray, window: window, platform: p);
        await t.start();
        t.show(_glance());
        await tester.pump();
        expect(tray.calls, isEmpty, reason: p.name);
        expect(window.calls, isEmpty, reason: p.name);
        t.dispose();
      }
    });

    testWidgets('when the shell goes, the icon goes and close closes again',
        (tester) async {
      final FakeTray tray = FakeTray();
      final FakeWindow window = FakeWindow();
      final DesktopTray t = _tray(tray: tray, window: window);
      await t.start();
      t.dispose();
      await tester.pump();

      expect(tray.removed, isTrue);
      expect(window.kept, isFalse);
    });
  });
}
