// Renders the Full Forensic Scan steps sheet to PNG files, for Android and
// for an iPhone, each in dark and light at 390 wide, with the bundled fonts
// and icons. A tool, not a check: skipped unless a folder is named.
//
//   flutter test test/visual/forensics_render_test.dart \
//     --dart-define=RENDER_DIR=/absolute/folder

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/app_sheet.dart';
import 'package:orbguard/screens/forensics/forensic_guide_sheet.dart';

import '../support/real_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final GlobalKey _shot = GlobalKey();

Future<void> _render(
  WidgetTester tester,
  String name,
  ForensicGuide guide, {
  required bool dark,
}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
  addTearDown(() => AppColors.uiBrightness = Brightness.dark);
  debugDisableShadows = false;

  await tester.pumpWidget(
    RepaintBoundary(
      key: _shot,
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
                  onPressed: () => showAppSheet<bool>(
                    context,
                    child: ForensicGuideSheet(guide: guide),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ]),
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

void main() {
  setUpAll(loadRealFonts);

  final Map<String, ForensicGuide> guides = {
    'full-scan-android': ForensicGuide.android,
    'full-scan-iphone': ForensicGuide.iphone,
  };

  for (final MapEntry<String, ForensicGuide> guide in guides.entries) {
    for (final bool dark in const [true, false]) {
      testWidgets('${guide.key} ${dark ? 'dark' : 'light'}', (tester) async {
        await _render(tester, guide.key, guide.value, dark: dark);
      }, skip: _dir.isEmpty);
    }
  }
}
