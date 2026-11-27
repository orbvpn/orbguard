// Mounts the shell the app ships (HomeScreen in lib/main.dart) the way it
// mounts after first-run priming, with the device's answers arriving late,
// as they do on a real phone. Tests that are about what Home starts (a check,
// a sheet, the credit gate) belong on this, not on Home alone: the wiring is
// where those go wrong.

import 'dart:convert';
import 'dart:ui' show DisplayFeature;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/main.dart';
import 'package:orbguard/permissions/special_permissions_manager.dart';
import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/providers/account_provider.dart';
import 'package:orbguard/providers/check_allowance.dart';
import 'package:orbguard/providers/darkweb_provider.dart';
import 'package:orbguard/providers/desktop_security_provider.dart';
import 'package:orbguard/providers/network_firewall_provider.dart';
import 'package:orbguard/providers/scan_credit_provider.dart';
import 'package:orbguard/providers/settings_provider.dart';
import 'package:orbguard/providers/sms_provider.dart';
import 'package:orbguard/services/habit/protection_streak_controller.dart';
import 'package:orbguard/services/desktop/desktop_tray.dart';
import 'package:orbguard/services/home/check_plan.dart';
import 'package:orbguard/services/home/check_run.dart';
import 'package:orbguard/services/home/last_scan_verdict_controller.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/services/security/device_scan_service.dart';
import 'package:orbguard/services/security/vpn_proxy_detector.dart';
import 'package:orbguard/services/security/vpn_watch.dart';

import 'sale_fakes.dart';

/// How long the device takes to say how much a check can see. On a phone
/// this answer always lands after Home's first frame.
const Duration shellAnswerDelay = Duration(milliseconds: 400);

const MethodChannel _permissions =
    MethodChannel('flutter.baseflow.com/permissions/methods');
const MethodChannel _system = MethodChannel('com.orb.guard/system');

/// The breach watch as the shell meets it in a test: nothing loaded from a
/// server, only what the test puts in with `debugLoad`.
class QuietDarkWeb extends DarkWebProvider {
  @override
  Future<void> init() async {}
}

/// A check that reports every step of [platform]'s plan, in order, and then
/// returns [findings]. On a computer the plan is its six areas. [failing]
/// steps report an error instead of a result, and [notPossible] steps that
/// this device cannot run them; [error], when set, is thrown before anything
/// runs.
CheckRunner fakeCheck({
  TargetPlatform platform = TargetPlatform.android,
  List<Map<String, dynamic>> findings = const [],
  Set<String> failing = const {},
  Set<String> notPossible = const {},
  Object? error,
}) =>
    (onProgress) async {
      final Object? e = error;
      if (e != null) throw e;
      final List<String> stages = [
        for (final CheckStep step in CheckPlan.forPlatform(platform))
          step.stage,
      ];
      for (int i = 0; i < stages.length; i++) {
        for (final bool done in const [false, true]) {
          onProgress(DeviceScanProgress(
            stageIndex: i,
            totalStages: stages.length,
            stageName: stages[i],
            stageCompleted: done,
            threatsFound: 0,
            stageError: !done
                ? null
                : failing.contains(stages[i])
                    ? 'broke'
                    : notPossible.contains(stages[i])
                        ? DeviceScanService.notSupported
                        : null,
          ));
        }
      }
      return findings;
    };

/// Lets a check started in the shell run to its end and its results open.
Future<void> finishCheck(WidgetTester tester) async {
  // Each step is held for a beat, then the finished ring for a moment.
  for (int i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pump(const Duration(milliseconds: 600));
}

/// Mounts the shell for someone who finished priming, signed out.
///
/// [checked] seeds a clean check from two hours ago. [found] seeds a check
/// from two hours ago that found these things. [autoCheckSpent] says the one
/// automatic first check already had its turn. [freeCheckUsed] says the free
/// check a person starts is gone; left out, it is gone when a check was
/// seeded, as if that person started it. [keepFound] is whether the
/// list itself was kept; an install from before it was kept has only the
/// count.
///
/// [platform] is the device the shell is drawn for. [runner] stands in for
/// the scan engine; left out, a check that reports every step clean.
/// [tunnel] says a VPN tunnel is up when the shell looks. [signedIn] mounts
/// a signed-in person with [credits] scan credits. [size] is the window in
/// logical pixels and [features] the folds and hinges the system reports.
/// [insets] are the system's bars, in logical pixels. [theme] ('dark' or
/// 'light') is the appearance saved in settings; set it with [themed].
/// [shot] wraps the whole app in a boundary a render can draw from.
/// [desktopTray] is the tray icon on a Windows or Linux computer, built on
/// stand-ins (test/support/desktop_fakes.dart); left out, there is none.
Future<ShellUnderTest> mountShell(
  WidgetTester tester, {
  bool checked = false,
  bool autoCheckSpent = false,
  bool? freeCheckUsed,
  List<Map<String, dynamic>> found = const [],
  bool keepFound = true,
  TargetPlatform platform = TargetPlatform.android,
  CheckRunner? runner,
  bool tunnel = false,
  bool signedIn = false,
  double credits = 3,
  bool themed = false,
  Size size = const Size(390, 844),
  List<DisplayFeature> features = const [],
  EdgeInsets insets = EdgeInsets.zero,
  String? theme,
  GlobalKey? shot,
  DesktopTray? desktopTray,
}) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    _permissions,
    (call) async => call.method == 'checkPermissionStatus' ? 1 : null,
  );
  // Enough access for a check to be worth running (coverage 50 of 100), but
  // answered late.
  messenger.setMockMethodCallHandler(_system, (call) async {
    if (call.method == 'scanNetwork') {
      return <String, Object>{
        'threats': [
          if (tunnel)
            <String, Object>{
              'type': 'network',
              'name': 'Active VPN Connection Detected',
              'path': 'VPN',
              'severity': 'MEDIUM',
            },
        ],
      };
    }
    if (call.method != 'checkRootAccess') return null;
    await Future<void>.delayed(shellAnswerDelay);
    return <String, Object>{'hasRoot': true, 'method': 'Root'};
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(_permissions, null);
    messenger.setMockMethodCallHandler(_system, null);
  });

  final DateTime now = DateTime.now();
  final String twoHoursAgo =
      now.subtract(const Duration(hours: 2)).toIso8601String();
  SharedPreferences.setMockInitialValues(<String, Object>{
    'onboarding_complete': true,
    'permissions_primed': true,
    if (autoCheckSpent) 'first_check_done': true,
    if (freeCheckUsed ?? (checked || found.isNotEmpty))
      CheckAllowance.prefsKey: true,
    // Keeps the scheduled background check out of these tests.
    'auto_scan_last_at': now.millisecondsSinceEpoch,
    if (theme != null) 'app_theme_mode': theme,
    if (found.isNotEmpty) ...<String, Object>{
      'verdict_score': LastScanVerdictController.computeScore(
          threats: found, coveragePercent: 60),
      'verdict_at_iso': twoHoursAgo,
      'verdict_coverage_pct': 60,
      'verdict_threat_count': found.length,
      if (keepFound) 'verdict_findings_json': jsonEncode(found),
    } else if (checked) ...<String, Object>{
      'verdict_score': 92,
      'verdict_at_iso': twoHoursAgo,
      'verdict_coverage_pct': 90,
      'verdict_threat_count': 0,
    },
  });
  specialPermissions = SpecialPermissionsManager();

  // The app mounts the shell only once its settings and the last verdict
  // have loaded.
  final SettingsProvider settings = SettingsProvider();
  final LastScanVerdictController verdict = LastScanVerdictController();
  await tester.runAsync(() async {
    await settings.init();
    await verdict.load();
  });

  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.displayFeatures = features;
  if (insets != EdgeInsets.zero) {
    final FakeViewPadding bars = FakeViewPadding(
      left: insets.left * 3,
      top: insets.top * 3,
      right: insets.right * 3,
      bottom: insets.bottom * 3,
    );
    tester.view.padding = bars;
    tester.view.viewPadding = bars;
  }
  addTearDown(tester.view.reset);

  final AccountProvider account =
      signedIn ? FakeSaleAccount(loggedIn: true) : AccountProvider();
  final SaleCredits sale = SaleCredits(account: account, balance: credits);
  final QuietDarkWeb darkWeb = QuietDarkWeb();
  IapService.instance.debugSeed(available: false, products: []);

  final Widget home = HomeScreen(
    platform: platform,
    checkRunner: runner ?? fakeCheck(platform: platform),
    vpnWatch: VpnWatch(detector: VpnProxyDetector(platform: platform)),
    desktopTray: desktopTray,
  );
  if (themed) addTearDown(() => AppColors.uiBrightness = Brightness.dark);

  final Widget app = MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsProvider>.value(value: settings),
      ChangeNotifierProvider<LastScanVerdictController>.value(value: verdict),
      ChangeNotifierProvider(create: (_) => ProtectionStreakController()),
      ChangeNotifierProvider<AccountProvider>.value(value: account),
      ChangeNotifierProvider<ScanCreditProvider>.value(value: sale.provider),
      ChangeNotifierProvider<IapService>.value(value: IapService.instance),
      // The real allowance, over the same stored values: the free check is
      // there until a check is on record or one was let through.
      ChangeNotifierProvider(create: (_) => CheckAllowance(platform: platform)),
      ChangeNotifierProvider<DarkWebProvider>.value(value: darkWeb),
      ChangeNotifierProvider(create: (_) => NetworkFirewallProvider()),
      ChangeNotifierProvider(create: (_) => SmsProvider()),
      ChangeNotifierProvider(create: (_) => DesktopSecurityProvider()),
    ],
    child: themed
        // The app's own theming: both themes, the mode from settings, and
        // the brand tokens told which one is showing.
        ? Consumer<SettingsProvider>(
            builder: (context, settings, _) => MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: settings.themeMode,
              builder: (context, child) {
                AppColors.syncWith(context);
                return child ?? const SizedBox.shrink();
              },
              home: home,
            ),
          )
        : MaterialApp(debugShowCheckedModeBanner: false, home: home),
  );
  await tester
      .pumpWidget(shot == null ? app : RepaintBoundary(key: shot, child: app));
  // First frame: the device has not answered yet.
  await tester.pump();
  // The answer lands, and whatever it starts gets time to open.
  await tester.pump(shellAnswerDelay * 2);
  await tester.pump(const Duration(milliseconds: 500));
  return ShellUnderTest(
      verdict: verdict, darkWeb: darkWeb, sale: sale, settings: settings);
}

/// What a test may read or change once the shell is up.
class ShellUnderTest {
  const ShellUnderTest({
    required this.verdict,
    required this.darkWeb,
    required this.sale,
    required this.settings,
  });

  final LastScanVerdictController verdict;
  final QuietDarkWeb darkWeb;
  final SaleCredits sale;
  final SettingsProvider settings;
}

/// Takes the shell down and lets what it started run out.
Future<void> unmountShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(minutes: 2));
}
