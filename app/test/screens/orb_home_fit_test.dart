// How Home spends a screen's height.
//
// The one lime action must show without scrolling, above the floating tab
// bar, on the short phones people really carry. These tests measure that with
// the REAL fonts: the Ahem test font wraps a headline into twice the lines it
// takes on a device, which would make every measurement here wrong.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/glass_theme.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/screens/home/orb_home_screen.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/widgets/home/orb_hero.dart';
import 'package:orbguard/widgets/home/orb_ring.dart';
import 'package:orbguard/widgets/home/shield_moon.dart';
import 'package:orbguard/widgets/home/today_card.dart';

import '../support/real_fonts.dart';

final _now = DateTime(2026, 11, 23, 21, 40);

Future<LastScanVerdictController> _verdict({int? score}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (score != null) ...{
      'verdict_score': score,
      'verdict_at_iso':
          _now.subtract(const Duration(hours: 2)).toIso8601String(),
      'verdict_coverage_pct': 90,
      'verdict_checks_run': 5,
    },
    'verdict_threat_count': 0,
  });
  final controller = LastScanVerdictController();
  await controller.load();
  return controller;
}

Future<GuardStatusController> _guards() async {
  final controller = GuardStatusController(
    probes: [
      for (final id in const ['spyware_watch', 'sms_filter', 'alerts'])
        () async =>
            GuardStatus(id: id, name: id, state: GuardState.active, detail: ''),
    ],
  );
  await controller.refresh();
  return controller;
}

/// Mounts Home the way the shell does: under the status bar ([top]), running
/// down to the bottom edge, with the system's bottom inset ([bottom]) reported
/// to it.
Future<void> _mount(
  WidgetTester tester, {
  required Size screen,
  required double top,
  required double bottom,
  int? score,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final verdict = await _verdict(score: score);
  final guards = await _guards();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: EdgeInsets.only(top: top, bottom: bottom)),
          child: Scaffold(
            body: SafeArea(
              bottom: false,
              child: OrbHomeScreen(
                verdict: verdict,
                guardsController: guards,
                onRunCheck: () {},
                clock: () => _now,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 80));
}

/// The y below which the floating tab bar covers the page.
double _barTop(Size screen, double bottom) =>
    screen.height - bottom - GlassTheme.bottomNavClearance;

void main() {
  setUpAll(loadRealFonts);

  // (name, screen, status bar, bottom inset)
  const phones = [
    ('an iPhone SE of 2016', Size(320, 568), 20.0, 0.0),
    ('a small Android with navigation buttons', Size(360, 640), 24.0, 48.0),
    ('an iPhone SE of 2022', Size(375, 667), 20.0, 0.0),
  ];

  for (final (name, screen, top, bottom) in phones) {
    for (final int? score in [null, 92]) {
      final String state = score == null ? 'before a check' : 'after a check';
      testWidgets('on $name, $state, the one action shows above the tab bar',
          (tester) async {
        await _mount(tester,
            screen: screen, top: top, bottom: bottom, score: score);

        expect(tester.takeException(), isNull);
        expect(
          tester.getRect(find.byType(BrandButton)).bottom,
          lessThanOrEqualTo(_barTop(screen, bottom)),
        );
      });
    }

    testWidgets('on $name every shield stays on the screen', (tester) async {
      await _mount(tester, screen: screen, top: top, bottom: bottom, score: 92);

      for (final moon in tester.widgetList(find.byType(ShieldMoon))) {
        final Rect rect = tester.getRect(find.byWidget(moon));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(screen.width));
      }
    });
  }

  group('on a tall phone', () {
    const Size pixel = Size(411, 914);
    const double top = 32, bottom = 24;

    testWidgets('before the first check the spare height is shared out',
        (tester) async {
      await _mount(tester, screen: pixel, top: top, bottom: bottom);

      // Home has little under the action before a check. Left alone, all of
      // a tall screen's spare height would pile up above the tab bar.
      // 8 of page padding and the 44 top row sit above the air.
      final double above = tester.getRect(find.byType(OrbHero)).top - top - 52;
      final double below = _barTop(pixel, bottom) -
          tester.getRect(find.byType(TodayCard)).bottom;
      expect(above, greaterThan(60), reason: 'the ring sits lower');
      expect((above - below).abs(), lessThan(20),
          reason: 'as much air above the ring as under Today');
      expect(tester.getSize(find.byType(OrbRing)), const Size(224, 224));
    });

    testWidgets('before the first check Today sits a little lower too',
        (tester) async {
      await _mount(tester, screen: pixel, top: top, bottom: bottom);

      final double gap = tester.getRect(find.byType(TodayCard)).top -
          tester.getRect(find.byType(BrandButton)).bottom;
      expect(gap, inInclusiveRange(40, 60));
    });

    testWidgets('once checked, the ring keeps its place under the top row',
        (tester) async {
      await _mount(tester, screen: pixel, top: top, bottom: bottom, score: 92);

      // 8 of page padding, the 44 top row, 12 of air.
      expect(tester.getRect(find.byType(OrbHero)).top - top, 64);
    });
  });

  testWidgets('before the first check a full-size phone has nothing to share',
      (tester) async {
    await _mount(tester, screen: const Size(390, 844), top: 54, bottom: 34);

    expect(tester.getRect(find.byType(OrbHero)).top - 54, 64);
  });

  testWidgets('on a full-size phone the ring keeps its design size',
      (tester) async {
    await _mount(tester,
        screen: const Size(390, 844), top: 54, bottom: 34, score: 92);

    expect(tester.getSize(find.byType(OrbRing)), const Size(224, 224));
  });

  testWidgets('on a tablet Home stays one readable column', (tester) async {
    await _mount(tester,
        screen: const Size(760, 1000), top: 24, bottom: 0, score: 92);

    // A button stretched across a tablet stops reading as one action.
    expect(
        tester.getSize(find.byType(BrandButton)).width, lessThanOrEqualTo(480));
  });
}
