// Renders the score and results sheets to PNG files, each state in dark and
// light at 390 wide, with the bundled fonts and icons. A tool, not a check:
// skipped unless a folder is named.
//
//   flutter test test/visual/sheets_render_test.dart \
//     --dart-define=RENDER_DIR=/absolute/folder

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/services/home/check_results.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';
import 'package:orbguard/widgets/home/results_sheet.dart';
import 'package:orbguard/widgets/home/score_sheet.dart';

import '../support/real_fonts.dart';
import '../support/sale_fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final GlobalKey _shot = GlobalKey();

Future<void> _render(
  WidgetTester tester,
  String name,
  Future<void> Function(BuildContext) open, {
  required bool dark,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
  addTearDown(() => AppColors.uiBrightness = Brightness.dark);
  debugDisableShadows = false;

  final FakeSaleAccount account = FakeSaleAccount(loggedIn: true);
  final SaleCredits credits = SaleCredits(account: account, balance: 3);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>.value(value: account),
          ChangeNotifierProvider<ScanCreditProvider>.value(
              value: credits.provider),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            backgroundColor: Brand.bg,
            body: Stack(children: [
              const BrandBed(),
              Builder(
                builder: (context) => Center(
                  child: TextButton(
                      onPressed: () => open(context),
                      child: const Text('open')),
                ),
              ),
            ]),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  for (int i = 0; i < 4; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 300));
  }
  final RenderRepaintBoundary boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final ByteData? png =
        await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name-${dark ? 'dark' : 'light'}.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

const PrivacyScoreEngine _engine = PrivacyScoreEngine();

HomeGap _gap(Shield shield, String id, int points, String title) => HomeGap(
      shield: shield,
      factor: ScoreFactor(id: id, label: id, points: points),
      title: title,
      detail: '',
    );

const List<String> _all = [
  'Network connections',
  'Running processes',
  'File system',
  'App databases',
  'Memory',
  'Certificate analysis',
  'Permission abuse',
  'Accessibility abuse',
  'Keylogger detection',
  'Location stalkers',
  'App malware scan',
];

void main() {
  setUpAll(loadRealFonts);

  final Map<String, (PrivacyScore, TargetPlatform)> scores = {
    'score-perfect': (
      _engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          guardsActive: 4,
          guardsAvailable: 4,
          breachedAccounts: 0,
          riskyPermissionApps: 0,
          unknownVpnActive: false,
          notificationsGranted: true)),
      TargetPlatform.android,
    ),
    'score-gaps': (
      _engine.compute(const PrivacySignals(
          daysSinceScan: 12,
          guardsActive: 2,
          guardsAvailable: 4,
          breachedAccounts: 1,
          riskyPermissionApps: 0,
          unknownVpnActive: true,
          notificationsGranted: true)),
      TargetPlatform.android,
    ),
    'score-iphone-waived': (
      _engine.compute(const PrivacySignals(
          daysSinceScan: 1,
          guardsActive: 3,
          guardsAvailable: 3,
          breachedAccounts: 0,
          unknownVpnActive: false,
          notificationsGranted: true,
          appAuditPossible: false)),
      TargetPlatform.iOS,
    ),
  };

  final HomeGap breach = _gap(
      Shield.identity, 'fix_breaches', 100, 'Your email was in a data breach');
  final Map<String, (CheckResults, TargetPlatform)> results = {
    'results-all-clear': (
      CheckResults.from(
          findings: const [],
          stagesRan: _all,
          stagesNotPossible: const [],
          stagesFailed: const [],
          gaps: const []),
      TargetPlatform.android,
    ),
    // Two checks broke: the sheet may not call the rest "All clear".
    'results-part-ran': (
      CheckResults.from(
          findings: const [],
          stagesRan: _all.sublist(0, _all.length - 2),
          stagesNotPossible: const [],
          stagesFailed: _all.sublist(_all.length - 2),
          gaps: const []),
      TargetPlatform.android,
    ),
    'results-gap-open': (
      CheckResults.from(
          findings: const [],
          stagesRan: _all.sublist(0, 5),
          stagesNotPossible: _all.sublist(5),
          stagesFailed: const [],
          gaps: [breach]),
      TargetPlatform.iOS,
    ),
    'results-found': (
      CheckResults.from(findings: const [
        {
          'id': 'f1',
          'name': 'Spyware traces in a system folder',
          'description': 'Files that match a known spyware kit.',
          'severity': 'HIGH',
          'stage': 'File system',
        },
        {
          'id': 'a1',
          'name': 'A keyboard you added can send what you type',
          'description': 'It can read every key you press.',
          'severity': 'MEDIUM',
          'path': 'com.example.fastkeys',
          'stage': 'Keylogger detection',
        },
        {
          'id': 'a2',
          'name': 'A keyboard you added can send what you type',
          'description': 'It asked for full network access.',
          'severity': 'LOW',
          'path': 'com.example.fastkeys',
          'stage': 'Permission abuse',
        },
      ], stagesRan: [
        for (final String s in _all)
          if (s != 'Memory') s,
      ], stagesNotPossible: const [], stagesFailed: const [
        'Memory'
      ], gaps: [
        breach
      ]),
      TargetPlatform.android,
    ),
  };

  for (final bool dark in [true, false]) {
    for (final MapEntry<String, (PrivacyScore, TargetPlatform)> c
        in scores.entries) {
      testWidgets('${c.key} ${dark ? 'dark' : 'light'}', (tester) async {
        await _render(
            tester,
            c.key,
            (ctx) => ScoreSheet.show(ctx,
                score: c.value.$1, onFactorTap: (_) {}, platform: c.value.$2),
            dark: dark);
      }, skip: _dir.isEmpty);
    }
    for (final MapEntry<String, (CheckResults, TargetPlatform)> c
        in results.entries) {
      testWidgets('${c.key} ${dark ? 'dark' : 'light'}', (tester) async {
        await _render(
            tester,
            c.key,
            (ctx) => ResultsSheet.show(ctx,
                results: c.value.$1,
                onOpenThing: (_) {},
                onOpenGap: (_) {},
                platform: c.value.$2),
            dark: dark);
      }, skip: _dir.isEmpty);
    }
  }
}
