// Renders the REAL shell (lib/main.dart's HomeScreen) on every screen size
// to PNG files: a book foldable open flat, the same fold half open on a
// table, a tablet, and desktop windows on a Mac and on Windows, in both
// themes. It also renders the share sheet a clean check offers.
//
// It mounts the shell through the same harness the shell tests use, with the
// real fonts, so what it draws is what the app's Dart layer draws. Nothing
// native is in it: no plugin answers, and a check runs on a stand-in engine.
//
// Skipped unless RENDER_DIR is set:
//
//   flutter test test/visual/wide_render_test.dart \
//       --dart-define=RENDER_DIR=/absolute/folder

import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/layout/desk_shell.dart';
import 'package:orbguard/services/home/home_brief.dart';

import '../support/real_fonts.dart';
import '../support/shell_harness.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

Future<void> _save(WidgetTester tester, GlobalKey shot, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  final boundary =
      shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 120));
  }
  while (tester.takeException() != null) {}
}

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key,
    {required bool mac}) async {
  final LogicalKeyboardKey modifier =
      mac ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(modifier);
  await _settle(tester);
}

const DisplayFeature _flat = DisplayFeature(
  bounds: Rect.fromLTWH(420, 0, 0, 701),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureFlat,
);
const DisplayFeature _halfOpen = DisplayFeature(
  bounds: Rect.fromLTWH(0, 420, 701, 0),
  type: DisplayFeatureType.fold,
  state: DisplayFeatureState.postureHalfOpened,
);

void main() {
  final bool enabled = _dir.isNotEmpty;

  setUpAll(() async {
    if (enabled) await loadRealFonts();
  });

  for (final String theme in const ['dark', 'light']) {
    testWidgets('a foldable open flat, $theme', skip: !enabled, (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(841, 701),
          features: const [_flat],
          insets: const EdgeInsets.only(top: 28, bottom: 16),
          shot: shot);
      await _settle(tester);
      await _save(tester, shot, 'fold-home-$theme');

      await tester
          .tap(find.byKey(ValueKey('shield-tile-${Shield.identity.name}')));
      await _settle(tester);
      await _save(tester, shot, 'fold-shield-$theme');

      await tester.tap(find.text('Protect').first);
      await _settle(tester);
      await _save(tester, shot, 'fold-protect-$theme');

      await tester.tap(find.text('Home').first);
      await _settle(tester);
      await tester.tap(find.text('Private by design'));
      await _settle(tester);
      await _save(tester, shot, 'fold-sheet-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('a foldable checking, $theme', skip: !enabled, (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(841, 701),
          features: const [_flat],
          insets: const EdgeInsets.only(top: 28, bottom: 16),
          shot: shot);
      await tester.tap(find.text('Run my first check'));
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      await _save(tester, shot, 'fold-checking-$theme');
      await finishCheck(tester);
      await _settle(tester);
      await _save(tester, shot, 'fold-results-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('a foldable half open on a table, $theme', skip: !enabled,
        (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(701, 841),
          features: const [_halfOpen],
          insets: const EdgeInsets.only(top: 28, bottom: 16),
          shot: shot);
      await _settle(tester);
      await _save(tester, shot, 'tabletop-home-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('a tablet, $theme', skip: !enabled, (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          checked: true,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(1180, 820),
          insets: const EdgeInsets.only(top: 24, bottom: 20),
          shot: shot);
      await _settle(tester);
      await _save(tester, shot, 'tablet-home-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('a Mac window, $theme', skip: !enabled, (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          platform: TargetPlatform.macOS,
          checked: true,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(1180, 760),
          shot: shot);
      await _settle(tester);
      await _save(tester, shot, 'mac-home-$theme');

      await _key(tester, LogicalKeyboardKey.keyK, mac: true);
      await _save(tester, shot, 'mac-palette-$theme');

      await tester.tap(find.descendant(
          of: find.byType(CommandPalette),
          matching: find.text('How my score adds up')));
      await _settle(tester);
      await _save(tester, shot, 'mac-sheet-$theme');
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await _settle(tester);

      await _key(tester, LogicalKeyboardKey.digit3, mac: true);
      await _save(tester, shot, 'mac-check-$theme');

      await _key(tester, LogicalKeyboardKey.digit2, mac: true);
      await _save(tester, shot, 'mac-protect-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('a Mac window checking, $theme', skip: !enabled,
        (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          platform: TargetPlatform.macOS,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(1180, 760),
          shot: shot);
      await tester.tap(find.text('Run my first check'));
      // Part way in, one area running.
      for (int i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      await _save(tester, shot, 'mac-checking-$theme');
      await finishCheck(tester);
      await _settle(tester);
      await _save(tester, shot, 'mac-results-$theme');
      await tester.tap(find.text('Done').last);
      await _settle(tester);
      await _save(tester, shot, 'mac-checked-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('a Windows window with results, $theme', skip: !enabled,
        (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          platform: TargetPlatform.windows,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(1180, 760),
          runner: fakeCheck(
            platform: TargetPlatform.windows,
            failing: {'Network'},
            findings: const [
              {
                'id': 'desktop-extensions',
                'name': '2 browser extensions can read and change every '
                    'site you visit',
                'description': 'Grammar Helper and Coupon Finder. Remove any '
                    'you do not use or do not recognise.',
                'severity': 'LOW',
                'type': 'desktop_browser',
                'path': 'extensions',
                'stage': 'Browser',
              },
            ],
          ),
          shot: shot);
      await tester.tap(find.text('Run my first check'));
      await finishCheck(tester);
      await _settle(tester);
      await _save(tester, shot, 'windows-results-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('a Windows window, $theme', skip: !enabled, (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          platform: TargetPlatform.windows,
          checked: true,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          size: const Size(1180, 760),
          shot: shot);
      await _settle(tester);
      await _save(tester, shot, 'windows-home-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });

    testWidgets('the share sheet, $theme', skip: !enabled, (tester) async {
      debugDisableShadows = false;
      final GlobalKey shot = GlobalKey();
      await mountShell(tester,
          autoCheckSpent: true,
          themed: true,
          theme: theme,
          insets: const EdgeInsets.only(top: 54, bottom: 34),
          shot: shot);
      await tester.tap(find.text('Run my first check'));
      await finishCheck(tester);
      await _settle(tester);
      await _save(tester, shot, 'phone-results-$theme');
      await tester.tap(find.text('Share'));
      await _settle(tester);
      await _save(tester, shot, 'phone-share-$theme');
      await unmountShell(tester);
      // The binding checks this before tear-downs run.
      debugDisableShadows = true;
    });
  }
}
