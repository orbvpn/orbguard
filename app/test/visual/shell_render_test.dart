// Renders the REAL app shell to PNG files: lib/main.dart's HomeScreen with
// the bed, the tab bar and each Guard tab, in both themes.
//
// flagship_render_test draws Home on its own. This one mounts the shell that
// ships, wired to real providers, so what it draws is what the app's Dart
// layer draws. What it cannot show is anything native: the host is a Mac with
// no plugins, so every guard reads what a Mac with nothing granted would
// report, and no check can run.
//
// Skipped unless RENDER_DIR is set:
//
//   flutter test test/visual/shell_render_test.dart \
//       --dart-define=RENDER_DIR=/absolute/folder

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/main.dart';
import 'package:orbguard/permissions/special_permissions_manager.dart';
import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/theme/glass_theme.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/network_firewall_provider.dart';
import 'package:orbguard/providers/settings_provider.dart';
import 'package:orbguard/providers/sms_provider.dart';
import 'package:orbguard/services/habit/protection_streak_controller.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';

import '../support/real_fonts.dart';

const String _dir = String.fromEnvironment('RENDER_DIR');
final GlobalKey _shot = GlobalKey();

const Size _phone = Size(390, 844);
const EdgeInsets _insets = EdgeInsets.only(top: 54, bottom: 34);

Future<void> _save(WidgetTester tester, String name) async {
  final boundary =
      _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_dir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

/// Lets queued platform calls and prefs loads finish, then draws.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 120));
  }
  // The host has no plugins; a call to one that the app does not guard lands
  // here instead of failing the render.
  while (tester.takeException() != null) {}
}

void main() {
  final bool enabled = _dir.isNotEmpty;

  setUpAll(() async {
    if (enabled) await loadRealFonts();
  });

  for (final bool dark in [true, false]) {
    final String theme = dark ? 'dark' : 'light';

    testWidgets('the shell, $theme', skip: !enabled, (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      // Notification permission: granted, the one answer that lets the bell
      // show its settled state. Everything else is left unanswered.
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('com.orb.guard/system'),
        (call) async => call.method == 'checkRootAccess'
            ? <String, Object>{'hasRoot': false, 'method': 'Standard'}
            : null,
      );

      final DateTime now = DateTime.now();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'onboarding_complete': true,
        'permissions_primed': true,
        'first_check_done': true,
        // Keeps the automatic check from starting during the render.
        'auto_scan_last_at': now.millisecondsSinceEpoch,
        // A clean manual check two hours ago.
        'verdict_score': 92,
        'verdict_at_iso':
            now.subtract(const Duration(hours: 2)).toIso8601String(),
        'verdict_coverage_pct': 90,
        'verdict_threat_count': 0,
        'verdict_checks_run': 5,
      });
      specialPermissions = SpecialPermissionsManager();

      tester.view.physicalSize = _phone * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding =
          FakeViewPadding(top: _insets.top * 3, bottom: _insets.bottom * 3);
      tester.view.viewPadding =
          FakeViewPadding(top: _insets.top * 3, bottom: _insets.bottom * 3);
      addTearDown(tester.view.reset);
      AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
      debugDisableShadows = false;

      await tester.pumpWidget(
        RepaintBoundary(
          key: _shot,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SettingsProvider()..init()),
              ChangeNotifierProvider(
                  create: (_) => ProtectionStreakController()..load()),
              ChangeNotifierProvider(
                  create: (_) => LastScanVerdictController()..load()),
              ChangeNotifierProvider(create: (_) => AccountProvider()),
              ChangeNotifierProvider(create: (_) => NetworkFirewallProvider()),
              ChangeNotifierProvider(create: (_) => SmsProvider()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: (dark ? AppTheme.dark : AppTheme.light)
                  .copyWith(platform: TargetPlatform.iOS),
              builder: (context, child) => GlassGradientBackground(
                isDark: dark,
                child: child ?? const SizedBox.shrink(),
              ),
              home: const HomeScreen(),
            ),
          ),
        ),
      );
      await _settle(tester);
      await _save(tester, 'shell-home-$theme');

      // Check is left out: on the host it is the desktop scanner, which is a
      // different screen from the phone's.
      for (final String tab in const ['Protect', 'Me']) {
        await tester.tap(find.bySemanticsLabel(tab).last);
        await _settle(tester);
        await _save(tester, 'shell-${tab.toLowerCase()}-$theme');
      }

      debugDisableShadows = true;
    });
  }
}
