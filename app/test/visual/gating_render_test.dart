// Renders what the scan-credit gate shows someone who is out of free checks,
// on a phone, a Mac and a Windows PC, in dark and light, with the bundled
// fonts and icons. Each picture is opened by the gate itself, so it is the
// sheet that person would really get. A tool, not a check: skipped unless a
// folder is named.
//
//   flutter test test/visual/gating_render_test.dart \
//     --dart-define=RENDER_DIR=/absolute/folder

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/app_sheet.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/scan_credits/scan_gate.dart';

import '../support/real_fonts.dart';
import '../support/sale_fakes.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final GlobalKey _shot = GlobalKey();

/// One person at the gate, and the screen they are on.
class _Case {
  const _Case(this.name, this.platform, {required this.signedIn});

  final String name;
  final TargetPlatform platform;
  final bool signedIn;

  bool get phone =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  /// A phone screen, or a desktop window.
  Size get screen => phone ? const Size(390, 844) : const Size(1100, 760);
}

const List<_Case> _cases = [
  // A phone: signed in, no credits left.
  _Case('android-out-of-credits', TargetPlatform.android, signedIn: true),
  _Case('mac-signed-out', TargetPlatform.macOS, signedIn: false),
  _Case('mac-signed-in', TargetPlatform.macOS, signedIn: true),
  _Case('windows-signed-out', TargetPlatform.windows, signedIn: false),
  _Case('windows-signed-in', TargetPlatform.windows, signedIn: true),
];

Future<void> _render(WidgetTester tester, _Case c, {required bool dark}) async {
  tester.view.physicalSize = c.screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
  addTearDown(() => AppColors.uiBrightness = Brightness.dark);
  debugDisableShadows = false;

  // The free check is gone, and there is no credit to spend.
  final GateUser user = GateUser(signedIn: c.signedIn, platform: c.platform);

  final Widget page = Stack(children: [
    const BrandBed(),
    Builder(
      builder: (context) => Center(
        child: TextButton(
            onPressed: () => ensureScanCredit(context),
            child: const Text('open')),
      ),
    ),
  ]);

  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
      child: user.over(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            backgroundColor: Brand.bg,
            // A desktop window keeps a sheet to a centred column, as the
            // shell does.
            body: c.phone
                ? page
                : SheetHost(maxWidth: 480, maxHeightFactor: 0.9, child: page),
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
    File('$_dir/${c.name}-${dark ? 'dark' : 'light'}.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
  debugDisableShadows = true;
}

void main() {
  setUpAll(loadRealFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IapService.instance.debugSeed(available: false, products: []);
  });

  for (final bool dark in [true, false]) {
    for (final _Case c in _cases) {
      testWidgets('${c.name} ${dark ? 'dark' : 'light'}', (tester) async {
        await _render(tester, c, dark: dark);
      }, skip: _dir.isEmpty);
    }
  }
}
