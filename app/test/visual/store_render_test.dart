// Renders the store screenshots: five frames, each a caption over a real
// screen of the shell, for the App Store (1290 by 2796) and Google Play
// (1080 by 2160), in both themes.
//
// Every screen is the real shell (lib/main.dart's HomeScreen) mounted through
// the same harness the shell tests use, with the real fonts. Nobody is signed
// in, so no account name or address is in any frame.
//
// Skipped unless RENDER_DIR is set:
//
//   flutter test test/visual/store_render_test.dart \
//       --dart-define=RENDER_DIR=/absolute/folder

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';

import '../support/real_fonts.dart';
import '../support/shell_harness.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');

/// One store's frame: the canvas, and the phone whose screen goes in it.
class _Store {
  const _Store(this.name, this.canvas, this.platform, this.screen, this.insets);

  final String name;

  /// Logical size of the finished frame; it is saved at three times this.
  final Size canvas;
  final TargetPlatform platform;
  final Size screen;
  final EdgeInsets insets;
}

const List<_Store> _stores = [
  _Store('appstore', Size(430, 932), TargetPlatform.iOS, Size(430, 932),
      EdgeInsets.only(top: 59, bottom: 34)),
  _Store('play', Size(360, 720), TargetPlatform.android, Size(412, 915),
      EdgeInsets.only(top: 36, bottom: 16)),
];

const List<String> _captions = [
  'Know if you’re being watched.',
  'One tap. A clear answer.',
  'See the gap. Close it.',
  'Six shields that report back.',
  'Honest about its limits.',
];

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 120));
  }
  while (tester.takeException() != null) {}
}

/// The screen as it is now, at three times its logical size.
Future<ui.Image> _grab(WidgetTester tester, GlobalKey shot) async {
  await tester.pump(const Duration(milliseconds: 400));
  final boundary =
      shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  late ui.Image image;
  await tester.runAsync(() async {
    image = await boundary.toImage(pixelRatio: 3);
  });
  return image;
}

/// A caption over a screen that runs off the bottom edge, on the brand bed.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.caption,
    required this.screen,
    required this.canvas,
    required this.store,
  });

  final String caption;
  final ui.Image screen;
  final Size canvas;
  final _Store store;

  @override
  Widget build(BuildContext context) {
    final double w = canvas.width;
    final double shotWidth = w * 0.8;
    final double shotHeight = shotWidth * screen.height / screen.width;
    final double top = canvas.height * 0.25;
    final double radius = shotWidth * 0.11;
    return SizedBox.fromSize(
      size: canvas,
      child: ColoredBox(
        color: Brand.bg,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const BrandBed(),
            Positioned(
              left: w * 0.09,
              right: w * 0.09,
              top: canvas.height * 0.07,
              height: top - canvas.height * 0.07,
              child: Center(
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: BrandText.display(size: w * 0.088, color: Brand.text)
                      .copyWith(height: 1.08),
                ),
              ),
            ),
            Positioned(
              left: (w - shotWidth) / 2,
              top: top,
              width: shotWidth,
              height: shotHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: Brand.shadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: Brand.glassBorder, width: 1.2),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                            child: RawImage(image: screen, fit: BoxFit.fill)),
                        // The phone's own status bar, which a screen drawn
                        // in a test does not have.
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height:
                              store.insets.top * shotWidth / store.screen.width,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            child: SizedBox(
                              width: store.screen.width,
                              height: store.insets.top,
                              child: CustomPaint(
                                painter: _StatusBar(
                                  ios: store.platform == TargetPlatform.iOS,
                                  ink: Brand.text,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A phone's status bar at 9:41: the time, signal, Wi-Fi and a full
/// battery, laid out the way iOS or Android lays them out.
class _StatusBar extends CustomPainter {
  const _StatusBar({required this.ios, required this.ink});

  final bool ios;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = ink;
    final Paint line = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke;
    final double mid = ios ? size.height * 0.52 : size.height / 2;

    final TextPainter time = TextPainter(
      text: TextSpan(
        text: '9:41',
        style: BrandText.body(
                size: ios ? 17 : 14,
                weight: ios ? FontWeight.w600 : FontWeight.w500,
                color: ink)
            .copyWith(height: 1, letterSpacing: ios ? -0.2 : 0.1),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double timeX = ios ? 76 - time.width / 2 : 30;
    time.paint(canvas, Offset(timeX, mid - time.height / 2));

    // Right side, painted from the right edge inwards.
    double x = size.width - (ios ? 34 : 30);

    // Battery.
    if (ios) {
      const double bw = 25, bh = 12;
      final Rect body = Rect.fromLTWH(x - bw - 2, mid - bh / 2, bw, bh);
      line
        ..strokeWidth = 1
        ..color = ink.withValues(alpha: 0.4);
      canvas.drawRRect(
          RRect.fromRectAndRadius(body, const Radius.circular(3.6)), line);
      canvas.drawRRect(
          RRect.fromRectAndRadius(body.deflate(2), const Radius.circular(2)),
          fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(body.right + 1, mid - 2, 1.5, 4),
              const Radius.circular(1)),
          Paint()..color = ink.withValues(alpha: 0.4));
      x = body.left - 6;
    } else {
      const double bw = 8, bh = 14;
      final Rect body = Rect.fromLTWH(x - bw, mid - bh / 2 + 1, bw, bh - 1);
      canvas.drawRRect(
          RRect.fromRectAndRadius(body, const Radius.circular(1.5)), fill);
      canvas.drawRect(
          Rect.fromLTWH(body.center.dx - 2, body.top - 1.5, 4, 1.5), fill);
      x = body.left - 6;
    }

    // Wi-Fi: three arcs and a dot, the widest on top.
    {
      const double r = 8;
      final Offset c = Offset(x - r, mid + (ios ? 5 : 5));
      line
        ..color = ink
        ..strokeWidth = 1.9
        ..strokeCap = StrokeCap.round;
      for (final double k in const [1.0, 0.64]) {
        canvas.drawArc(Rect.fromCircle(center: c, radius: r * k), -2.36, 1.57,
            false, line);
      }
      canvas.drawCircle(c.translate(0, -1.6), 1.7, fill);
      x = c.dx - r - 6;
    }

    // Signal: four bars, rising.
    {
      const double bar = 3, gap = 1.6;
      for (int i = 3; i >= 0; i--) {
        final double h = 4 + i * 2.4;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromLTWH(x - bar, mid + 5.5 - h, bar, h),
                const Radius.circular(0.8)),
            fill);
        x -= bar + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_StatusBar old) => old.ios != ios || old.ink != ink;
}

Future<void> _compose(WidgetTester tester, _Store store, String theme,
    List<ui.Image> screens) async {
  final bool dark = theme == 'dark';
  tester.view.physicalSize = store.canvas * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.resetPadding();
  tester.view.resetViewPadding();
  tester.view.resetDisplayFeatures();
  AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
  addTearDown(() => AppColors.uiBrightness = Brightness.dark);

  for (int i = 0; i < screens.length; i++) {
    final GlobalKey shot = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Material(
        type: MaterialType.transparency,
        child: Center(
          child: RepaintBoundary(
            key: shot,
            child: _Frame(
                caption: _captions[i],
                screen: screens[i],
                canvas: store.canvas,
                store: store),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    final boundary =
        shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_dir/${store.name}-${i + 1}-$theme.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(data!.buffer.asUint8List());
      image.dispose();
    });
  }
}

void main() {
  final bool enabled = _dir.isNotEmpty;

  setUpAll(() async {
    if (enabled) await loadRealFonts();
  });

  for (final _Store store in _stores) {
    for (final String theme in const ['dark', 'light']) {
      testWidgets('${store.name}, $theme', skip: !enabled, (tester) async {
        debugDisableShadows = false;
        final List<ui.Image> screens = [];

        // 2. One tap, a clear answer: the first check, run from Home.
        GlobalKey shot = GlobalKey();
        await mountShell(tester,
            autoCheckSpent: true,
            themed: true,
            theme: theme,
            platform: store.platform,
            size: store.screen,
            insets: store.insets,
            shot: shot);
        await tester.tap(find.text('Run my first check'));
        await finishCheck(tester);
        await _settle(tester);
        final ui.Image results = await _grab(tester, shot);
        await unmountShell(tester);

        // 1, 3, 4 and 5 from a phone checked two hours ago.
        shot = GlobalKey();
        await mountShell(tester,
            checked: true,
            autoCheckSpent: true,
            themed: true,
            theme: theme,
            platform: store.platform,
            size: store.screen,
            insets: store.insets,
            shot: shot);
        await _settle(tester);
        screens
          ..add(await _grab(tester, shot))
          ..add(results);

        await tester.tap(find.bySemanticsLabel(RegExp(r'^Privacy score')));
        await _settle(tester);
        screens.add(await _grab(tester, shot));
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await _settle(tester);

        await tester.tap(find.text('Protect').last);
        await _settle(tester);
        screens.add(await _grab(tester, shot));

        await tester.tap(find.text('Home').last);
        await _settle(tester);
        await tester.tap(find.text('Private by design'));
        await _settle(tester);
        screens.add(await _grab(tester, shot));
        await unmountShell(tester);

        await _compose(tester, store, theme, screens);
        for (final ui.Image s in screens) {
          s.dispose();
        }
        // The binding checks this before tear-downs run.
        debugDisableShadows = true;
      });
    }
  }
}
