// Renders real widgets to PNG files so the look can be checked by eye, with the
// bundled fonts and icons, without booting a device.
//
// This is a tool, not a check: it asserts nothing about pixels and is skipped
// unless a folder is named. Run it from app/ with
//
//   flutter test test/visual --dart-define=RENDER_DIR=/absolute/folder
//
// Final proof of a screen is still the app on a simulator or device; these
// frames are for fast iteration on spacing, type and colour.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/duotone_icon.dart';
import 'package:orbguard/presentation/widgets/glass_bottom_nav.dart';
import 'package:orbguard/screens/home/orb_home_screen.dart';
import 'package:orbguard/services/habit/protection_streak_controller.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/check_run.dart';
import 'package:orbguard/services/home/guard_status_controller.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/services/security/device_scan_service.dart';
import 'package:orbguard/widgets/home/orb_ring.dart';

import '../support/real_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final GlobalKey _shot = GlobalKey();

/// Mounts [child] on the kit's bed at [size] logical pixels, in one theme.
/// Every test that mounts must end with [_save].
Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  required Size size,
  required bool dark,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
  addTearDown(() => AppColors.uiBrightness = Brightness.dark);
  // Tests paint shadows as flat blocks unless told otherwise. [_save] puts the
  // flag back, because the framework checks it before a test may end.
  debugDisableShadows = false;

  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          backgroundColor: Brand.bg,
          body: Stack(
              children: [const BrandBed(), Positioned.fill(child: child)]),
        ),
      ),
    ),
  );
}

/// Writes the mounted frame to `RENDER_DIR/name.png`. Pass [last] false to
/// keep rendering more frames in the same test.
Future<void> _save(WidgetTester tester, String name, {bool last = true}) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final ByteData? png =
        await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
  if (last) debugDisableShadows = true;
}

// ── Home frames ─────────────────────────────────────────────────────────────

/// The moment every Home frame is drawn at.
final DateTime _clock = DateTime(2026, 11, 23, 21, 40);

GuardStatus _g(String id, GuardState state) =>
    GuardStatus(id: id, name: id, state: state, detail: '');

/// What an iPhone really reports: no firewall and no app scan there, and the
/// breach and hidden VPN checks not run yet.
List<GuardStatus> _iphone({bool dailyCheckup = true, bool alerts = true}) => [
      _g('spyware_watch',
          dailyCheckup ? GuardState.active : GuardState.actionNeeded),
      _g('firewall', GuardState.unavailable),
      _g('sms_filter', GuardState.active),
      _g('malware_scan', GuardState.unavailable),
      _g('alerts', alerts ? GuardState.active : GuardState.actionNeeded),
      _g('breach', GuardState.actionNeeded),
      _g('hidden_vpn', GuardState.actionNeeded),
      _g('secure_call', GuardState.active),
    ];

/// An Android phone with the firewall running.
List<GuardStatus> _android() => [
      _g('spyware_watch', GuardState.active),
      _g('firewall', GuardState.active),
      _g('sms_filter', GuardState.active),
      _g('malware_scan', GuardState.active),
      _g('alerts', GuardState.active),
      _g('breach', GuardState.active),
      _g('hidden_vpn', GuardState.actionNeeded),
      _g('secure_call', GuardState.active),
    ];

class _HomeCase {
  const _HomeCase(
    this.name, {
    required this.guards,
    this.score,
    this.threats = 0,
    this.checksRun,
    this.streak = 0,
    this.blocked,
    this.breachAt,
    this.initial,
    this.check,
    this.platform = TargetPlatform.iOS,
    this.breached,
  });

  /// A check in progress, shown in place.
  final CheckRun? check;
  final TargetPlatform platform;

  /// Watched addresses with an open breach, or null when none was checked.
  final int? breached;

  final String name;
  final List<GuardStatus> guards;
  final int? score;
  final int threats;
  final int? checksRun;
  final int streak;
  final int? blocked;
  final DateTime? breachAt;
  final String? initial;
}

/// One phone screen, 390 by 844, with the notch and home indicator insets of
/// a current iPhone and the real bottom bar over it.
class _Phone extends StatelessWidget {
  const _Phone({
    required this.child,
    this.size = _Phone.standard,
    this.insets = const EdgeInsets.only(top: 54, bottom: 34),
    this.platform = TargetPlatform.iOS,
  });

  static const Size standard = Size(390, 844);

  final Widget child;
  final Size size;
  final EdgeInsets insets;
  final TargetPlatform platform;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(platform: platform),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(insets.bottom > 0 ? 46 : 8),
        child: SizedBox.fromSize(
          size: size,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: size,
              padding: insets,
              viewPadding: insets,
            ),
            child: ColoredBox(
              color: Brand.bg,
              child: Stack(
                children: [
                  const BrandBed(),
                  Positioned.fill(child: SafeArea(bottom: false, child: child)),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GlassBottomNavBar(
                      currentIndex: 0,
                      onTap: (_) {},
                      items: const [
                        NavItem(label: 'Home', iconPath: AppIcons.homeSmile),
                        NavItem(
                            label: 'Protect', iconPath: AppIcons.shieldCheck),
                        NavItem(label: 'Check', iconPath: AppIcons.search),
                        NavItem(label: 'Me', iconPath: AppIcons.userRounded),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<Widget> _home(_HomeCase c) async {
  final DateTime at = DateTime(2026, 11, 23, 19, 40);
  SharedPreferences.setMockInitialValues(<String, Object>{
    if (c.score != null) ...{
      'verdict_score': c.score!,
      'verdict_at_iso': at.toIso8601String(),
      'verdict_coverage_pct': 90,
    },
    'verdict_threat_count': c.threats,
    if (c.checksRun != null) 'verdict_checks_run': c.checksRun!,
  });
  final verdict = LastScanVerdictController();
  await verdict.load();
  final guards = GuardStatusController(
    probes: [for (final g in c.guards) () async => g],
  );
  await guards.refresh();
  final streak = ProtectionStreakController();
  for (int day = c.streak; day > 0; day--) {
    await streak.recordCheckup(at.subtract(Duration(days: day - 1)));
  }

  return OrbHomeScreen(
    onRunCheck: () {},
    verdict: verdict,
    guardsController: guards,
    streak: streak,
    onShieldTap: (_) {},
    onFactorTap: (_) {},
    onAlertsTap: () {},
    onAccountTap: () {},
    onTrustTap: () {},
    accountInitial: c.initial,
    blockedTodayCount: c.blocked == null ? null : () => c.blocked!,
    breachLastChecked: c.breachAt == null ? null : () => c.breachAt,
    check: c.check,
    breachedAccounts: () => c.breached,
    platform: c.platform,
    clock: () => _clock,
  );
}

/// A check stopped where [done] checks have finished and the next one runs.
/// The engine never returns, so the frame holds still.
CheckRun _checkAt(int done, {required bool android}) {
  final CheckRun run = CheckRun(
    plan: CheckPlan.forDevice(android: android),
    beat: Duration.zero,
    settle: Duration.zero,
  );
  late DeviceScanProgressCallback report;
  unawaited(run.start((onProgress) {
    report = onProgress;
    return Completer<List<Map<String, dynamic>>>().future;
  }));
  DeviceScanProgress at(int i, bool finished) => DeviceScanProgress(
        stageIndex: i,
        totalStages: CheckPlan.all.length,
        stageName: CheckPlan.all[i].stage,
        stageCompleted: finished,
        threatsFound: 0,
      );
  for (int i = 0; i < done; i++) {
    report(at(i, false));
    report(at(i, true));
  }
  report(at(done, false));
  return run;
}

void main() {
  final bool enabled = _dir.isNotEmpty;

  setUpAll(() async {
    if (enabled) await loadRealFonts();
  });

  for (final bool dark in [true, false]) {
    final String theme = dark ? 'dark' : 'light';

    testWidgets('ring states, $theme', skip: !enabled, (tester) async {
      Widget cell(String label, OrbStatus status, {String? hole}) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OrbRing(
                status: status,
                size: 224,
                child: hole == null
                    ? null
                    : Text(hole, style: BrandText.numeral(size: 35)),
              ),
              const SizedBox(height: 26),
              Text(label, style: BrandText.label(size: 11.5)),
            ],
          );

      await _mount(
        tester,
        dark: dark,
        size: const Size(1020, 760),
        Center(
          child: Wrap(
            spacing: 96,
            runSpacing: 64,
            alignment: WrapAlignment.center,
            children: [
              cell('WHOLE', const OrbStatus.whole(live: true), hole: '1000'),
              cell('ONE GAP', const OrbStatus.open([150], live: true),
                  hole: '900'),
              cell('TWO GAPS', const OrbStatus.open([150, 330]), hole: '750'),
              cell(
                  'CHECKING',
                  const OrbStatus.checking([
                    OrbSegment.done,
                    OrbSegment.done,
                    OrbSegment.running,
                    OrbSegment.pending,
                    OrbSegment.unavailable,
                  ])),
              cell('NEVER CHECKED', const OrbStatus.fresh()),
              cell('STILL', const OrbStatus.whole(still: true), hole: '766'),
            ],
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1750));
      await _save(tester, 'ring-states-$theme');
    });

    testWidgets('home, $theme', skip: !enabled, (tester) async {
      final cases = <_HomeCase>[
        _HomeCase('fresh', guards: _iphone(alerts: false)),
        _HomeCase('clear',
            guards: _iphone(),
            score: 92,
            checksRun: 5,
            streak: 3,
            initial: 'M'),
        _HomeCase('gap',
            guards: _iphone(), score: 68, threats: 2, initial: 'M'),
        _HomeCase('still',
            guards: _iphone(dailyCheckup: false), score: 92, initial: 'M'),
        _HomeCase('android',
            guards: _android(),
            score: 92,
            checksRun: 11,
            streak: 12,
            blocked: 37,
            breachAt: DateTime(2026, 11, 23, 9, 15),
            initial: 'M'),
      ];
      final homes = <Widget>[for (final c in cases) await _home(c)];

      await _mount(
        tester,
        dark: dark,
        size: Size(cases.length * (_Phone.standard.width + 28) + 28,
            _Phone.standard.height + 56),
        ColoredBox(
          color: Brand.surface2,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final home in homes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _Phone(child: home),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1750));
      await _save(tester, 'home-$theme');
    });

    testWidgets('home while a check runs, $theme', skip: !enabled,
        (tester) async {
      const Size small = Size(320, 568);
      const Size pixel = Size(411, 914);
      final frames = <(Widget, Size, EdgeInsets)>[
        (
          await _home(_HomeCase('iphone',
              guards: _iphone(),
              score: 92,
              initial: 'M',
              check: _checkAt(2, android: false))),
          _Phone.standard,
          const EdgeInsets.only(top: 54, bottom: 34),
        ),
        (
          await _home(_HomeCase('android',
              guards: _android(),
              score: 92,
              initial: 'M',
              platform: TargetPlatform.android,
              check: _checkAt(8, android: true))),
          pixel,
          const EdgeInsets.only(top: 32, bottom: 24),
        ),
        (
          await _home(_HomeCase('small android',
              guards: _android(),
              initial: 'M',
              platform: TargetPlatform.android,
              check: _checkAt(4, android: true))),
          small,
          const EdgeInsets.only(top: 20),
        ),
      ];

      await _mount(
        tester,
        dark: dark,
        size: Size(frames.fold<double>(28, (w, f) => w + f.$2.width + 28),
            pixel.height + 56),
        ColoredBox(
          color: Brand.surface2,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (Widget home, Size size, EdgeInsets insets)
                    in frames)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _Phone(size: size, insets: insets, child: home),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 1550));
      await _save(tester, 'home-checking-$theme');
    });

    testWidgets('home on a tall phone, $theme', skip: !enabled, (tester) async {
      const Size pixel = Size(411, 914);
      const Size max = Size(440, 956);
      final frames = <(Widget, Size, EdgeInsets)>[
        (
          await _home(_HomeCase('fresh', guards: _iphone(alerts: false))),
          pixel,
          const EdgeInsets.only(top: 32, bottom: 24),
        ),
        (
          await _home(_HomeCase('clear',
              guards: _iphone(),
              score: 92,
              checksRun: 5,
              streak: 3,
              breached: 0,
              initial: 'M')),
          pixel,
          const EdgeInsets.only(top: 32, bottom: 24),
        ),
        (
          await _home(_HomeCase('fresh', guards: _iphone(alerts: false))),
          max,
          const EdgeInsets.only(top: 62, bottom: 34),
        ),
        (
          await _home(_HomeCase('gap',
              guards: _iphone(), score: 92, breached: 1, initial: 'M')),
          max,
          const EdgeInsets.only(top: 62, bottom: 34),
        ),
      ];

      await _mount(
        tester,
        dark: dark,
        size: Size(frames.fold<double>(28, (w, f) => w + f.$2.width + 28),
            max.height + 56),
        ColoredBox(
          color: Brand.surface2,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (Widget home, Size size, EdgeInsets insets)
                    in frames)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _Phone(size: size, insets: insets, child: home),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1750));
      await _save(tester, 'home-tall-$theme');
    });

    testWidgets('home on a small phone, $theme', skip: !enabled,
        (tester) async {
      // 320 by 568 with no notch: the smallest screen the app still meets.
      const Size small = Size(320, 568);
      final cases = <_HomeCase>[
        _HomeCase('fresh', guards: _iphone(alerts: false)),
        _HomeCase('clear',
            guards: _iphone(), score: 92, checksRun: 5, initial: 'M'),
        _HomeCase('gap',
            guards: _iphone(), score: 68, threats: 2, initial: 'M'),
      ];
      final homes = <Widget>[for (final c in cases) await _home(c)];

      await _mount(
        tester,
        dark: dark,
        size: Size(cases.length * (small.width + 28) + 28, small.height + 56),
        ColoredBox(
          color: Brand.surface2,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final home in homes)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _Phone(
                      size: small,
                      insets: const EdgeInsets.only(top: 20),
                      platform: TargetPlatform.android,
                      child: home,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 1750));
      await _save(tester, 'home-small-$theme');
    });
  }
}
