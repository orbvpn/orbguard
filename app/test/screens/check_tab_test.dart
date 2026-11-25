// The Check tab on a phone: every on-demand tool one tap away, the paste
// card on top, and the full check at the foot of the list.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/screens/check/check_tab_screen.dart';
import 'package:orbguard/screens/check/check_tools.dart';
import 'package:orbguard/screens/darkweb/darkweb_screen.dart';
import 'package:orbguard/screens/network/network_security_screen.dart';
import 'package:orbguard/screens/qr_scanner/qr_scanner_screen.dart';
import 'package:orbguard/screens/scan/apk_scan_screen.dart';
import 'package:orbguard/screens/shields/hidden_vpn_proxy_screen.dart';
import 'package:orbguard/screens/shields/secure_call_screen.dart';
import 'package:orbguard/widgets/check/paste_card.dart';

import '../support/real_fonts.dart';

void main() {
  setUpAll(loadRealFonts);

  Future<void> pump(
    WidgetTester tester, {
    TargetPlatform? platform = TargetPlatform.android,
    int count = 11,
    VoidCallback? onRun,
    double width = 390,
    double height = 1600,
    bool dark = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, height);
    addTearDown(tester.view.reset);
    AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
    addTearDown(() => AppColors.uiBrightness = Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        backgroundColor: Brand.bg,
        body: CheckTabScreen(
          onRunFullCheck: onRun ?? () {},
          fullCheckCount: count,
          platform: platform,
          analyse: (_, __) async => null,
        ),
      ),
    ));
    await tester.pump();
  }

  group('which tools a device gets', () {
    test('Android has all six', () {
      expect(CheckTool.availableOn(TargetPlatform.android), [
        CheckTool.qr,
        CheckTool.email,
        CheckTool.wifi,
        CheckTool.call,
        CheckTool.vpn,
        CheckTool.apk,
      ]);
    });

    test('an iPhone has no app file check', () {
      expect(CheckTool.availableOn(TargetPlatform.iOS), [
        CheckTool.qr,
        CheckTool.email,
        CheckTool.wifi,
        CheckTool.call,
        CheckTool.vpn,
      ]);
    });

    test('a Mac has no call check and no app file check', () {
      expect(CheckTool.availableOn(TargetPlatform.macOS), [
        CheckTool.qr,
        CheckTool.email,
        CheckTool.wifi,
        CheckTool.vpn,
      ]);
    });

    test('Windows and Linux have no camera and no Wi-Fi reader', () {
      for (final TargetPlatform p in [
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(CheckTool.availableOn(p), [CheckTool.email, CheckTool.vpn]);
      }
    });

    test('each tool opens its own real screen', () {
      expect({
        for (final CheckTool t in CheckTool.values) t: t.screen().runtimeType,
      }, {
        CheckTool.qr: QrScannerScreen,
        CheckTool.email: DarkWebScreen,
        CheckTool.wifi: NetworkSecurityScreen,
        CheckTool.call: SecureCallScreen,
        CheckTool.vpn: HiddenVpnProxyScreen,
        CheckTool.apk: ApkScanScreen,
      });
    });

    test('the breach check opens under its shield\'s name', () {
      final DarkWebScreen screen = CheckTool.email.screen() as DarkWebScreen;
      expect(screen.title, 'Identity & breach');
    });
  });

  testWidgets('heads the page and puts the paste card first', (tester) async {
    await pump(tester);
    expect(find.text('Check'), findsOneWidget);
    expect(find.text('Not sure about something? Ask.'), findsOneWidget);
    expect(find.byType(PasteCard), findsOneWidget);
    expect(find.text('QUICK CHECKS'), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(PasteCard)).dy,
      lessThan(tester.getTopLeft(find.text('QUICK CHECKS')).dy),
    );
  });

  Finder tile(CheckTool t) => find.byKey(ValueKey('tile-${t.name}'));
  Finder row(CheckTool t) => find.byKey(ValueKey('row-${t.name}'));

  testWidgets('Android: six tools, all as tiles in three full rows',
      (tester) async {
    await pump(tester, platform: TargetPlatform.android);
    for (final CheckTool t in CheckTool.values) {
      expect(tile(t), findsOneWidget, reason: t.title);
      expect(row(t), findsNothing, reason: t.title);
    }
    expect(find.text('Scan a QR code'), findsOneWidget);
    expect(find.text('Before you open it'), findsOneWidget);
    expect(find.text('Check an email'), findsOneWidget);
    expect(find.text('Known data breaches'), findsOneWidget);
    expect(find.text('Before a call'), findsOneWidget);
    expect(find.text('Hidden VPN'), findsOneWidget);
    expect(find.text('Rerouted traffic'), findsOneWidget);
    expect(find.text('Check an app file'), findsOneWidget);
    expect(find.text('Before you install'), findsOneWidget);
    expect(find.text('Fake hotspots'), findsOneWidget);
    // Two to a row.
    expect(tester.getTopLeft(tile(CheckTool.qr)).dy,
        tester.getTopLeft(tile(CheckTool.email)).dy);
    expect(tester.getTopLeft(tile(CheckTool.vpn)).dy,
        tester.getTopLeft(tile(CheckTool.apk)).dy);
  });

  testWidgets('iPhone: the fifth tool joins the list, no tile sits alone',
      (tester) async {
    await pump(tester, platform: TargetPlatform.iOS);
    for (final CheckTool t in [
      CheckTool.qr,
      CheckTool.email,
      CheckTool.wifi,
      CheckTool.call,
    ]) {
      expect(tile(t), findsOneWidget, reason: t.title);
    }
    expect(tile(CheckTool.vpn), findsNothing);
    expect(row(CheckTool.vpn), findsOneWidget);
    expect(find.text('Check an app file'), findsNothing);
    // The leftover row comes before the full check.
    expect(tester.getTopLeft(row(CheckTool.vpn)).dy,
        lessThan(tester.getTopLeft(find.text('Full privacy check')).dy));
  });

  testWidgets('desktop: only what can run there', (tester) async {
    await pump(tester, platform: TargetPlatform.macOS, count: 5);
    expect(find.text('Before a call'), findsNothing);
    expect(find.text('Check an app file'), findsNothing);
    expect(tile(CheckTool.qr), findsOneWidget);
    expect(tile(CheckTool.vpn), findsOneWidget);
    expect(find.text('All 5 checks this Mac can run'), findsOneWidget);

    await pump(tester, platform: TargetPlatform.windows, count: 5);
    expect(find.text('Scan a QR code'), findsNothing);
    expect(tile(CheckTool.email), findsOneWidget);
    expect(tile(CheckTool.vpn), findsOneWidget);
    expect(find.text('All 5 checks this computer can run'), findsOneWidget);
  });

  testWidgets('the full check sits last and starts the real check',
      (tester) async {
    int runs = 0;
    await pump(tester, count: 11, onRun: () => runs++);
    expect(find.text('All 11 checks this phone can run'), findsOneWidget);
    await tester.tap(find.text('Full privacy check'));
    await tester.pump();
    expect(runs, 1);
  });

  testWidgets('never says "All 1 checks"', (tester) async {
    await pump(tester, count: 1);
    expect(find.textContaining('All 1 '), findsNothing);
    expect(find.text('The one check this phone can run'), findsOneWidget);
  });

  testWidgets('a tool opens its screen as a sheet', (tester) async {
    await pump(tester, platform: TargetPlatform.iOS);
    await tester.tap(find.text('Hidden VPN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(HiddenVpnProxyScreen), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('keeps one column no wider than 480 on a wide screen',
      (tester) async {
    await pump(tester, width: 900);
    final Rect card = tester.getRect(find.byType(PasteCard));
    expect(card.width, lessThanOrEqualTo(480));
    expect(card.center.dx, closeTo(450, 1));
  });

  testWidgets('pads the foot so the last row clears the tab bar',
      (tester) async {
    await pump(tester, height: 700);
    final ListView list = tester.widget(find.byType(ListView));
    final EdgeInsets pad = list.padding! as EdgeInsets;
    expect(pad.top, 8);
    expect(pad.bottom, 16 + 78);
  });

  for (final bool dark in [true, false]) {
    for (final double width in [390.0, 320.0]) {
      for (final TargetPlatform p in [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ]) {
        testWidgets(
            'fits at ${width.toInt()} wide, ${dark ? 'dark' : 'light'}, '
            '${p.name}', (tester) async {
          await pump(tester, width: width, dark: dark, platform: p);
          expect(tester.takeException(), isNull);
          for (final RenderParagraph para
              in tester.allRenderObjects.whereType<RenderParagraph>()) {
            expect(para.didExceedMaxLines, isFalse,
                reason: 'cut off: "${para.text.toPlainText()}"');
          }
        });
      }
    }
  }
}
