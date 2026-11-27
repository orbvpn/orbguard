// The shell on a foldable, a fold half open on a table, and a desktop window.
//
// The rules these tests hold:
//  - unfolded, the ring keeps the left pane and the tab bar stays under it;
//    Today and the shields take the right pane
//  - a shield opens in the right pane, not over the ring, and the ring marks
//    it; going back returns the pane to Today
//  - a tab shows in the right pane, and the ring stays where it is
//  - a sheet opens in the right pane, so nothing lies across the fold
//  - half open on a table, the ring stands in the top half, and the rest,
//    with the tab bar, lies in the bottom half
//  - a desktop window has a sidebar in place of the tab bar, answers Cmd K
//    and Cmd 1 to 4, and opens its sheets as one centred column
//  - only the Mac build leads to the plans

import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/layout/desk_shell.dart';
import 'package:orbguard/presentation/layout/shell_form.dart';
import 'package:orbguard/presentation/widgets/glass_bottom_nav.dart';
import 'package:orbguard/screens/darkweb/darkweb_screen.dart';
import 'package:orbguard/screens/home/orb_home_screen.dart';
import 'package:orbguard/screens/settings/settings_screen.dart';
import 'package:orbguard/screens/shields/shields_screen.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/widgets/home/home_side.dart';
import 'package:orbguard/widgets/home/score_sheet.dart';
import 'package:orbguard/widgets/home/shield_moon.dart';

import '../support/shell_harness.dart';

/// A book-style foldable, open flat: a 841 by 701 screen folded down the
/// middle.
const Size _open = Size(841, 701);
const DisplayFeature _flat = DisplayFeature(
  bounds: Rect.fromLTWH(420, 0, 0, 701),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);

/// The same fold turned on its side and half open, standing on a table.
const Size _standing = Size(701, 841);
const DisplayFeature _halfOpen = DisplayFeature(
  bounds: Rect.fromLTWH(0, 420, 701, 0),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

const Size _window = Size(1180, 760);

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key,
    {required bool mac}) async {
  final LogicalKeyboardKey modifier =
      mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await _settle(tester);
}

Finder _inPalette(String text) =>
    find.descendant(of: find.byType(CommandPalette), matching: find.text(text));

Iterable<Shield> _marked(WidgetTester tester) => tester
    .widgetList<ShieldMoon>(find.byType(ShieldMoon))
    .where((m) => m.selected)
    .map((m) => m.shield);

void main() {
  group('unfolded', () {
    testWidgets('the ring keeps the left pane; Today and the shields the right',
        (tester) async {
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          size: _open,
          features: const [_flat]);

      expect(tester.widget<OrbHomeScreen>(find.byType(OrbHomeScreen)).layout,
          HomeLayout.pane);
      expect(tester.getRect(find.byType(OrbHomeScreen)).right,
          lessThanOrEqualTo(420));
      expect(tester.getRect(find.byType(GlassBottomNavBar)).right,
          lessThanOrEqualTo(420));
      expect(tester.getRect(find.byType(HomeSide)).left,
          greaterThanOrEqualTo(420));
      expect(find.text('Today'), findsOneWidget);
      for (final Shield s in Shield.values) {
        expect(find.byKey(ValueKey('shield-tile-${s.name}')), findsOneWidget);
      }
      expect(tester.takeException(), isNull);

      await unmountShell(tester);
    });

    testWidgets('a shield opens in the right pane and the ring marks it',
        (tester) async {
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          size: _open,
          features: const [_flat]);

      await tester
          .tap(find.byKey(ValueKey('shield-tile-${Shield.identity.name}')));
      await _settle(tester);

      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getRect(find.byType(DarkWebScreen)).left,
          greaterThanOrEqualTo(420));
      expect(_marked(tester), [Shield.identity]);
      // The ring is still there, where it was.
      expect(tester.getRect(find.byType(OrbHomeScreen)).right,
          lessThanOrEqualTo(420));

      // The page's own back button pops the pane it is in.
      Navigator.of(tester.element(find.byType(DarkWebScreen))).pop();
      await _settle(tester);

      expect(find.byType(DarkWebScreen), findsNothing);
      expect(find.byType(HomeSide), findsOneWidget);
      expect(_marked(tester), isEmpty);

      await unmountShell(tester);
    });

    testWidgets('a tab shows in the right pane, beside the ring',
        (tester) async {
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          size: _open,
          features: const [_flat]);

      await tester.tap(find.text('Protect'));
      await _settle(tester);

      expect(tester.getRect(find.byType(ShieldsScreen)).left,
          greaterThanOrEqualTo(420));
      expect(find.byType(OrbHomeScreen), findsOneWidget);
      expect(find.byType(HomeSide), findsNothing);

      await unmountShell(tester);
    });

    testWidgets('a sheet opens in the right pane, clear of the fold',
        (tester) async {
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          size: _open,
          features: const [_flat]);

      await tester.tap(find.text('Private by design'));
      await _settle(tester);

      final Rect sheet = tester.getRect(find
          .descendant(
              of: find.byType(BottomSheet), matching: find.byType(Material))
          .first);
      expect(sheet.left, greaterThanOrEqualTo(420));
      expect(sheet.right, lessThanOrEqualTo(841));

      await unmountShell(tester);
    });
  });

  group('half open on a table', () {
    testWidgets('the ring stands in the top half, the rest lies in the bottom',
        (tester) async {
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          size: _standing,
          features: const [_halfOpen]);

      expect(tester.widget<OrbHomeScreen>(find.byType(OrbHomeScreen)).layout,
          HomeLayout.stand);
      expect(tester.getRect(find.byType(OrbHomeScreen)).bottom,
          lessThanOrEqualTo(420));
      expect(
          tester.getRect(find.byType(HomeSide)).top, greaterThanOrEqualTo(420));
      expect(tester.getRect(find.byType(GlassBottomNavBar)).top,
          greaterThanOrEqualTo(420));
      expect(tester.takeException(), isNull);

      await unmountShell(tester);
    });
  });

  group('a desktop window', () {
    testWidgets('has a sidebar in place of the tab bar', (tester) async {
      await mountShell(tester,
          platform: TargetPlatform.macOS,
          checked: true,
          autoCheckSpent: true,
          size: _window);

      expect(find.byType(DeskSidebar), findsOneWidget);
      expect(find.byType(GlassBottomNavBar), findsNothing);
      expect(tester.widget<OrbHomeScreen>(find.byType(OrbHomeScreen)).layout,
          HomeLayout.desk);
      final Rect ring = tester.getRect(find.byType(OrbHomeScreen));
      expect(ring.left, DeskSidebar.width);
      expect(ring.width, ShellForm.ringColumn);
      expect(tester.getRect(find.byType(HomeSide)).left,
          greaterThanOrEqualTo(ring.right));
      expect(find.byWidgetPredicate((w) => w is Keycap && w.label == '⌘K'),
          findsOneWidget);
      // A Mac window's content runs under a clear title bar, so the app
      // draws the bar.
      expect(find.byType(DeskTitleBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      await unmountShell(tester);
    });

    testWidgets('Cmd K opens the palette, and a command runs from it',
        (tester) async {
      await mountShell(tester,
          platform: TargetPlatform.macOS,
          checked: true,
          autoCheckSpent: true,
          size: _window);

      await _press(tester, LogicalKeyboardKey.keyK, mac: true);

      expect(find.byType(CommandPalette), findsOneWidget);
      for (final String label in const [
        'Check now',
        'Check a link or message',
        'Open Protect',
        'How my score adds up',
        'Go unlimited',
        'Switch appearance',
      ]) {
        expect(_inPalette(label), findsOneWidget, reason: label);
      }

      await tester.enterText(find.byType(TextField), 'prot');
      await tester.pump();
      expect(_inPalette('Check now'), findsNothing);
      expect(_inPalette('Open Protect'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);

      expect(find.byType(CommandPalette), findsNothing);
      expect(find.byType(ShieldsScreen), findsOneWidget);

      await unmountShell(tester);
    });

    testWidgets('a sheet is one column in the middle of the window',
        (tester) async {
      await mountShell(tester,
          platform: TargetPlatform.macOS,
          checked: true,
          autoCheckSpent: true,
          size: _window);

      await _press(tester, LogicalKeyboardKey.keyK, mac: true);
      await tester.tap(_inPalette('How my score adds up'));
      await _settle(tester);

      expect(find.byType(ScoreSheet), findsOneWidget);
      // The sheet's own surface, inside the full-width place it rises in.
      final Rect sheet = tester.getRect(find
          .descendant(
              of: find.byType(BottomSheet), matching: find.byType(Material))
          .first);
      expect(sheet.width, 480);
      expect(sheet.center.dx, closeTo(_window.width / 2, 1));
      expect(sheet.height, lessThanOrEqualTo(_window.height * 0.9));

      await unmountShell(tester);
    });

    testWidgets('Cmd and a number open that tab', (tester) async {
      await mountShell(tester,
          platform: TargetPlatform.macOS,
          checked: true,
          autoCheckSpent: true,
          size: _window);

      await _press(tester, LogicalKeyboardKey.digit2, mac: true);
      expect(find.byType(ShieldsScreen), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.digit4, mac: true);
      expect(find.byType(SettingsScreen), findsOneWidget);

      await _press(tester, LogicalKeyboardKey.digit1, mac: true);
      expect(find.byType(HomeSide), findsOneWidget);

      await unmountShell(tester);
    });

    testWidgets('on Windows it says Ctrl and never leads to the plans',
        (tester) async {
      await mountShell(tester,
          platform: TargetPlatform.windows,
          checked: true,
          autoCheckSpent: true,
          size: _window);

      expect(find.text('Ctrl K'), findsOneWidget);
      expect(find.text('Go unlimited'), findsNothing);
      // Windows keeps its own title bar.
      expect(find.byType(DeskTitleBar), findsNothing);

      await _press(tester, LogicalKeyboardKey.keyK, mac: false);
      expect(find.byType(CommandPalette), findsOneWidget);
      expect(_inPalette('Go unlimited'), findsNothing);
      expect(_inPalette('Check now'), findsOneWidget);

      await unmountShell(tester);
    });
  });
}
