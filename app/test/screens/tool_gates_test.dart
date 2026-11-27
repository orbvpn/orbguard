// Every on-demand tool starts its check through the scan-credit gate.
//
// For each tool these tests stand a counter in for the real check and press
// the button that starts it, as three people:
//
//   * a subscriber: the check runs, nothing is counted;
//   * someone signed out whose free check is gone: sign-in is asked for and
//     the check does NOT run;
//   * someone signed in with a credit: one credit is spent, one check runs.
//
// Opening a screen, and what it loads to show itself, costs nothing.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/models/api/sms_analysis.dart';
import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/widgets/duotone_icon.dart';
import 'package:orbguard/providers/darkweb_provider.dart';
import 'package:orbguard/providers/forensics_provider.dart';
import 'package:orbguard/providers/identity_protection_provider.dart';
import 'package:orbguard/providers/network_provider.dart';
import 'package:orbguard/providers/qr_provider.dart';
import 'package:orbguard/providers/rogue_ap_provider.dart';
import 'package:orbguard/providers/scam_detection_provider.dart';
import 'package:orbguard/providers/social_media_provider.dart';
import 'package:orbguard/screens/account/login_screen.dart';
import 'package:orbguard/screens/darkweb/darkweb_screen.dart';
import 'package:orbguard/screens/forensics/forensics_screen.dart';
import 'package:orbguard/screens/identity/identity_protection_screen.dart';
import 'package:orbguard/screens/network/network_security_screen.dart';
import 'package:orbguard/screens/qr_scanner/qr_scanner_screen.dart';
import 'package:orbguard/screens/rogue_ap/rogue_ap_screen.dart';
import 'package:orbguard/screens/scam/scam_detection_screen.dart';
import 'package:orbguard/screens/scan/apk_scan_screen.dart';
import 'package:orbguard/screens/shields/hidden_vpn_proxy_screen.dart';
import 'package:orbguard/screens/shields/secure_call_screen.dart';
import 'package:orbguard/screens/social_media/social_media_screen.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/services/security/apk_file_scanner.dart';
import 'package:orbguard/services/security/secure_call_check.dart';
import 'package:orbguard/services/security/vpn_proxy_detector.dart';
import 'package:orbguard/services/security/vpn_watch.dart';

import '../support/real_fonts.dart';
import '../support/sale_fakes.dart';

// ── Stand-ins for the checks ────────────────────────────────────────────────

class _Scam extends ScamDetectionProvider {
  int runs = 0;
  @override
  Future<void> init() async {}
  @override
  Future<ScamAnalysisResult?> analyzeText(String text) async {
    runs++;
    return null;
  }

  @override
  Future<ScamAnalysisResult?> analyzeUrl(String url) async {
    runs++;
    return null;
  }

  @override
  Future<PhoneReputation?> checkPhone(String phoneNumber) async {
    runs++;
    return null;
  }
}

class _Forensics extends ForensicsProvider {
  int runs = 0;
  @override
  Future<void> init() async {}
  @override
  Future<ForensicAnalysisResult?> runFullAnalysis({
    String? shutdownLog,
    String? logcatData,
  }) async {
    runs++;
    return null;
  }
}

class _DarkWeb extends DarkWebProvider {
  int emails = 0;
  int passwords = 0;
  int refreshes = 0;

  /// One address is watched, so "check again" has something to check.
  @override
  List<MonitoredAsset> get assets => [
        MonitoredAsset(
          id: 'a1',
          type: AssetType.email,
          value: 'someone@example.com',
          addedAt: DateTime(2026, 11, 1),
        ),
      ];

  @override
  Future<void> init() async {}
  @override
  Future<BreachCheckResult?> checkEmail(String email) async {
    emails++;
    return null;
  }

  @override
  Future<PasswordBreachResult?> checkPassword(String password) async {
    passwords++;
    return null;
  }

  @override
  Future<void> refreshAssets() async {
    refreshes++;
  }
}

class _Network extends NetworkProvider {
  int scans = 0;
  int dns = 0;
  int reads = 0;
  @override
  Future<void> refreshNetworkInfo() async {
    reads++;
  }

  @override
  Future<void> scanNetworks() async {
    scans++;
  }

  @override
  Future<void> runDnsCheck() async {
    dns++;
  }
}

class _Qr extends QrProvider {
  int runs = 0;
  @override
  Future<void> init() async {}
  @override
  Future<QrScanResult?> scanQrCode(
    String content, {
    String? contentType,
    double? latitude,
    double? longitude,
  }) async {
    runs++;
    return null;
  }
}

// The older screens the menu still opens.

class _RogueAp extends RogueAPProvider {
  int scans = 0;

  /// Whether the screen asked for a scan as it opened.
  bool? scanOnOpen;

  @override
  Future<void> initialize({bool scan = true}) async {
    scanOnOpen = scan;
  }

  @override
  Future<void> scanForAPs() async {
    scans++;
  }
}

class _Identity extends IdentityProtectionProvider {
  int scans = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanAllAssets() async {
    scans++;
  }
}

class _Social extends SocialMediaProvider {
  int scans = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scanAllAccounts() async {
    scans++;
  }
}

/// The refresh action in a screen's header.
final Finder _refresh = find
    .byWidgetPredicate((w) => w is DuotoneIcon && w.icon == AppIcons.refresh);

SecureCallPosture _posture() => SecureCallPosture(
      checkedAt: DateTime(2026, 11, 28),
      items: const [
        SecureCallCheckItem(
          id: CallCheckId.screenCapture,
          title: 'Screen recording or mirroring',
          question: 'Is your screen being recorded or shared right now?',
          status: CallCheckStatus.clear,
          detail: 'Nothing is recording or sharing the screen.',
        ),
      ],
    );

// ── The three people ────────────────────────────────────────────────────────

GateUser _subscriber() => GateUser.subscriber();
GateUser _signedOut() => GateUser();
GateUser _withCredit() => GateUser(signedIn: true, credits: 1);

/// Mounts a tool's screen for [user] and hands back how many checks ran.
typedef _Mount = Future<int Function()> Function(
    WidgetTester tester, GateUser user);

Future<void> _pump(
  WidgetTester tester,
  GateUser user,
  Widget screen, {
  List<SingleChildWidget> extra = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [...user.providers, ...extra],
    child: MaterialApp(theme: AppTheme.dark, home: screen),
  ));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _tap(WidgetTester tester, Finder what) async {
  await tester.ensureVisible(what);
  await tester.pump();
  await tester.tap(what);
  await _settle(tester);
}

/// The three tests every tool gets. [start] presses what starts its check.
void _gated(
  String tool, {
  required _Mount mount,
  required Future<void> Function(WidgetTester tester) start,
}) {
  group(tool, () {
    testWidgets('a subscriber: the check runs and nothing is counted',
        (tester) async {
      final GateUser user = _subscriber();
      final int Function() runs = await mount(tester, user);
      expect(runs(), 0, reason: 'opening the screen is not a check');

      await start(tester);

      expect(runs(), 1);
      expect(user.spent, 0);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets(
        'free check gone, signed out: sign-in is asked for, nothing runs',
        (tester) async {
      final GateUser user = _signedOut();
      final int Function() runs = await mount(tester, user);

      await start(tester);

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(runs(), 0);
    });

    testWidgets('signed in with a credit: one credit, one check',
        (tester) async {
      final GateUser user = _withCredit();
      final int Function() runs = await mount(tester, user);
      expect(runs(), 0, reason: 'opening the screen is not a check');
      expect(user.spent, 0, reason: 'opening the screen costs nothing');

      await start(tester);

      expect(runs(), 1);
      expect(user.sale.api.balance, 0);
    });
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRealFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    IapService.instance.debugSeed(available: false, products: []);
  });

  _gated(
    'the Scam shield',
    mount: (tester, user) async {
      final _Scam scam = _Scam();
      await _pump(tester, user, const ScamDetectionScreen(), extra: [
        ChangeNotifierProvider<ScamDetectionProvider>.value(value: scam)
      ]);
      return () => scam.runs;
    },
    start: (tester) async {
      await tester.enterText(
          find.widgetWithText(TextField, 'Paste suspicious message or text...'),
          'Your parcel is on hold');
      await tester.pump();
      await _tap(tester, find.text('Analyze for Scams'));
    },
  );

  _gated(
    'the Spyware shield (forensics)',
    mount: (tester, user) async {
      final _Forensics forensics = _Forensics();
      await _pump(tester, user, const ForensicsScreen(), extra: [
        ChangeNotifierProvider<ForensicsProvider>.value(value: forensics)
      ]);
      return () => forensics.runs;
    },
    start: (tester) => _tap(tester, find.text('Full Forensic Scan')),
  );

  _gated(
    'the email breach check',
    mount: (tester, user) async {
      final _DarkWeb darkWeb = _DarkWeb();
      await _pump(tester, user, const DarkWebScreen(), extra: [
        ChangeNotifierProvider<DarkWebProvider>.value(value: darkWeb)
      ]);
      return () => darkWeb.emails;
    },
    start: (tester) async {
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Enter email address'),
          'someone@example.com');
      await tester.pump();
      await _tap(tester, find.text('Check for Breaches'));
    },
  );

  _gated(
    'checking every watched address again',
    mount: (tester, user) async {
      final _DarkWeb darkWeb = _DarkWeb();
      await _pump(tester, user, const DarkWebScreen(), extra: [
        ChangeNotifierProvider<DarkWebProvider>.value(value: darkWeb)
      ]);
      return () => darkWeb.refreshes;
    },
    start: (tester) => _tap(tester, _refresh),
  );

  _gated(
    'the Wi-Fi check',
    mount: (tester, user) async {
      final _Network network = _Network();
      await _pump(tester, user, const NetworkSecurityScreen(), extra: [
        ChangeNotifierProvider<NetworkProvider>.value(value: network)
      ]);
      return () => network.scans;
    },
    start: (tester) => _tap(tester, find.text('Scan Networks')),
  );

  _gated(
    'the before-a-call check',
    mount: (tester, user) async {
      int runs = 0;
      await _pump(tester, user, SecureCallScreen(check: () async {
        runs++;
        return _posture();
      }));
      // A subscriber's check starts with the screen; that one is not the
      // press these tests are about.
      final int atOpen = runs;
      return () => runs - atOpen;
    },
    start: (tester) => _tap(
        tester,
        find.byWidgetPredicate((w) =>
            w is Text &&
            (w.data == 'Check my device' ||
                w.data == 'Check my device again'))),
  );

  _gated(
    'the app file check',
    mount: (tester, user) async {
      int runs = 0;
      await _pump(
          tester,
          user,
          ApkScanScreen(
            pick: () async => const ['/downloads/app.apk'],
            scan: (paths) async {
              runs++;
              return const <ApkScanResult>[];
            },
          ));
      return () => runs;
    },
    start: (tester) => _tap(tester, find.text('Choose an APK to check')),
  );

  _gated(
    'a QR code typed in',
    mount: (tester, user) async {
      final _Qr qr = _Qr();
      await _pump(tester, user, const QrScannerScreen(cameraOnOpen: false),
          extra: [ChangeNotifierProvider<QrProvider>.value(value: qr)]);
      return () => qr.runs;
    },
    start: (tester) async {
      await tester.enterText(
          find.widgetWithText(
              TextField, 'Paste URL, text, or any QR content...'),
          'https://example.com/pay');
      await tester.pump();
      await _tap(tester, find.text('Analyze'));
    },
  );

  _gated(
    'the rogue access point scan (menu)',
    mount: (tester, user) async {
      final _RogueAp rogue = _RogueAp();
      await _pump(tester, user, const RogueAPScreen(),
          extra: [ChangeNotifierProvider<RogueAPProvider>.value(value: rogue)]);
      return () => rogue.scans;
    },
    start: (tester) => _tap(tester, _refresh),
  );

  group('the rogue access point scan, on opening', () {
    Future<_RogueAp> open(WidgetTester tester, GateUser user) async {
      final _RogueAp rogue = _RogueAp();
      await _pump(tester, user, const RogueAPScreen(),
          extra: [ChangeNotifierProvider<RogueAPProvider>.value(value: rogue)]);
      return rogue;
    }

    testWidgets('a subscriber: it scans with the screen', (tester) async {
      expect((await open(tester, _subscriber())).scanOnOpen, isTrue);
    });

    testWidgets('anyone else: nothing is scanned, and nothing is called safe',
        (tester) async {
      final _RogueAp rogue = await open(tester, _withCredit());

      expect(rogue.scanOnOpen, isFalse);
      await tester.tap(find.text('Threats'));
      await _settle(tester);
      expect(find.text('Not scanned yet'), findsOneWidget);
      expect(find.text('Your WiFi environment appears safe'), findsNothing);
    });
  });

  _gated(
    'the identity scan (menu)',
    mount: (tester, user) async {
      final _Identity identity = _Identity();
      await _pump(tester, user, const IdentityProtectionScreen(), extra: [
        ChangeNotifierProvider<IdentityProtectionProvider>.value(
            value: identity)
      ]);
      return () => identity.scans;
    },
    start: (tester) => _tap(tester, _refresh),
  );

  _gated(
    'the social account scan (menu)',
    mount: (tester, user) async {
      final _Social social = _Social();
      await _pump(tester, user, const SocialMediaScreen(), extra: [
        ChangeNotifierProvider<SocialMediaProvider>.value(value: social)
      ]);
      return () => social.scans;
    },
    start: (tester) => _tap(tester, _refresh),
  );

  group('the hidden VPN check', () {
    const MethodChannel channel = MethodChannel(VpnProxyDetector.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    late int scans;

    setUp(() {
      scans = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'scanNetwork':
            scans++;
            return {'threats': <Map<String, dynamic>>[]};
          case 'getInstalledApps':
            return {'apps': <Map<String, dynamic>>[]};
        }
        return null;
      });
    });
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    VpnWatch watch() => VpnWatch(
          detector: VpnProxyDetector(
              platform: TargetPlatform.android, environment: const {}),
          prefs: SharedPreferences.getInstance,
        );

    Future<void> open(WidgetTester tester, GateUser user, VpnWatch w) async {
      await _pump(tester, user,
          HiddenVpnProxyScreen(watch: w, ownFirewallOn: () => false));
      await _settle(tester);
    }

    testWidgets('a subscriber: it looks as the screen opens', (tester) async {
      final GateUser user = _subscriber();
      await open(tester, user, watch());

      expect(scans, 1);
      expect(find.text('Check again'), findsOneWidget);

      await _tap(tester, find.text('Check again'));
      expect(scans, 2);
      expect(user.spent, 0);
    });

    testWidgets(
        'nothing known yet, not subscribed: the screen waits to be asked',
        (tester) async {
      final GateUser user = _withCredit();
      await open(tester, user, watch());

      expect(scans, 0);
      expect(user.spent, 0);
      expect(find.text('Check now'), findsOneWidget);

      await _tap(tester, find.text('Check now'));

      expect(scans, 1);
      expect(user.sale.api.balance, 0);
      expect(find.text('Check again'), findsOneWidget);
    });

    testWidgets('free check gone, signed out: sign-in is asked for, no look',
        (tester) async {
      await open(tester, _signedOut(), watch());

      await _tap(tester, find.text('Check now'));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(scans, 0);
    });

    testWidgets(
        'what the watch already saw is shown for nothing; '
        'looking again is the check', (tester) async {
      // Home asks the watch by itself. That look is never counted.
      final VpnWatch w = watch();
      await tester.runAsync(() => w.unknownVpnActive(ownFirewallOn: false));
      expect(scans, 1);

      final GateUser user = _withCredit();
      await open(tester, user, w);

      expect(scans, 1, reason: 'no new look on opening');
      expect(user.spent, 0);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('Check now'), findsNothing);

      await _tap(tester, find.text('Check again'));

      expect(scans, 2);
      expect(user.sale.api.balance, 0);
    });
  });

  group('the before-a-call check, on opening', () {
    testWidgets('a subscriber: it runs with the screen', (tester) async {
      int runs = 0;
      await _pump(tester, _subscriber(), SecureCallScreen(check: () async {
        runs++;
        return _posture();
      }));

      expect(runs, 1);
      expect(find.text('Check my device again'), findsOneWidget);
    });

    testWidgets('anyone else: nothing runs until they ask', (tester) async {
      int runs = 0;
      final GateUser user = _withCredit();
      await _pump(tester, user, SecureCallScreen(check: () async {
        runs++;
        return _posture();
      }));

      expect(runs, 0);
      expect(user.spent, 0);
      expect(find.text('Check my device'), findsOneWidget);
      // What it is, and the honest part, are there to read first.
      expect(find.textContaining('This checks your device, not the call'),
          findsOneWidget);
      expect(find.text('THE HONEST PART'), findsOneWidget);
    });
  });

  group('the app file check', () {
    testWidgets('no file picked: nothing is checked and nothing is spent',
        (tester) async {
      int runs = 0;
      final GateUser user = _withCredit();
      await _pump(
          tester,
          user,
          ApkScanScreen(
            pick: () async => const [],
            scan: (paths) async {
              runs++;
              return const <ApkScanResult>[];
            },
          ));

      await _tap(tester, find.text('Choose an APK to check'));

      expect(runs, 0);
      expect(user.spent, 0);
      expect(find.text('No APK selected. Pick a .apk file to check it.'),
          findsOneWidget);
    });
  });

  group('the Wi-Fi check', () {
    testWidgets('the DNS check is a check too', (tester) async {
      final _Network network = _Network();
      await _pump(tester, _signedOut(), const NetworkSecurityScreen(), extra: [
        ChangeNotifierProvider<NetworkProvider>.value(value: network)
      ]);

      await tester.tap(find.text('DNS'));
      await _settle(tester);
      await _tap(tester, find.text('Run DNS Hijack Check'));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(network.dns, 0);
    });
  });

  group('the email breach check', () {
    testWidgets('a password lookup is a check too', (tester) async {
      final _DarkWeb darkWeb = _DarkWeb();
      await _pump(tester, _signedOut(), const DarkWebScreen(), extra: [
        ChangeNotifierProvider<DarkWebProvider>.value(value: darkWeb)
      ]);

      await tester.tap(find.text('Password'));
      await _settle(tester);
      await tester.enterText(
          find.widgetWithText(TextField, 'Enter password to check'), 'hunter2');
      await tester.pump();
      await _tap(tester, find.text('Check Password'));

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(darkWeb.passwords, 0);
    });
  });
}
