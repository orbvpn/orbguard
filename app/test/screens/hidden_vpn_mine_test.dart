// The Hidden VPN & proxy screen asks once whether an active VPN or proxy is
// the person's own, and lets them take it back. It answers the same VpnWatch
// Home reads.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/screens/shields/hidden_vpn_proxy_screen.dart';
import 'package:orbguard/services/security/vpn_proxy_detector.dart';
import 'package:orbguard/services/security/vpn_watch.dart';

import '../support/real_fonts.dart';
import '../support/sale_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadRealFonts);

  const channel = MethodChannel(VpnProxyDetector.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late bool tunnel;
  late String? proxyHost;
  late bool? metaOwnFirewall;
  late bool? metaOrbVpn;
  late String? macOwner;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tunnel = false;
    proxyHost = null;
    metaOwnFirewall = null;
    metaOrbVpn = null;
    macOwner = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'scanNetwork':
          return {
            'threats': [
              if (tunnel)
                {
                  'type': 'network',
                  'name': 'Active VPN Connection Detected',
                  'path': 'VPN',
                  'metadata': {
                    if (metaOwnFirewall != null) 'ownFirewall': metaOwnFirewall,
                    if (metaOrbVpn != null) 'orbVpnInstalled': metaOrbVpn,
                  },
                },
              if (proxyHost != null)
                {
                  'id': 'net_proxy_1',
                  'type': 'network',
                  'name': 'HTTP proxy configured',
                  'path': proxyHost,
                },
            ],
          };
        case 'getInstalledApps':
          return {'apps': <Map<String, dynamic>>[]};
        case 'networkReroute':
          return {
            'tunnels': [
              if (tunnel)
                {
                  'name': 'utun4',
                  'addresses': ['10.8.0.2'],
                  if (macOwner != null) 'owner': macOwner,
                },
            ],
            'proxy': {if (proxyHost != null) 'https': proxyHost},
          };
      }
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  VpnWatch watchFor(TargetPlatform platform) => VpnWatch(
        detector: VpnProxyDetector(platform: platform, environment: const {}),
        prefs: SharedPreferences.getInstance,
      );

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 2000);
    addTearDown(tester.view.reset);
    // A subscriber: the screen looks as it opens, and looking again costs
    // nothing. What a look costs everyone else is in tool_gates_test.dart.
    await tester.pumpWidget(GateUser.subscriber()
        .over(MaterialApp(theme: AppTheme.dark, home: screen)));
    // Past the checking spinner (it loops, so no pumpAndSettle).
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> tapAndWait(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  List<String> visible(WidgetTester tester) => [
        for (final p in tester.allRenderObjects.whereType<RenderParagraph>())
          p.text.toPlainText(),
      ];

  testWidgets(
      'an unanswered tunnel offers "This VPN is mine", then the calm state',
      (tester) async {
    tunnel = true;
    final w = watchFor(TargetPlatform.android);
    await pump(
        tester, HiddenVpnProxyScreen(watch: w, ownFirewallOn: () => false));

    expect(find.text('A VPN or proxy is active'), findsOneWidget);
    expect(find.text('This VPN is mine'), findsOneWidget);
    expect(find.text('You told OrbGuard this one is yours.'), findsNothing);

    await tapAndWait(tester, 'This VPN is mine');

    expect(await w.saidItIsMine, isTrue);
    expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
    expect(find.text('This VPN is mine'), findsNothing);
    expect(find.text('You told OrbGuard this one is yours.'), findsOneWidget);
    expect(find.text('It is not mine any more'), findsOneWidget);
    // The one lime action is unchanged.
    expect(find.text('Check again'), findsOneWidget);

    await tapAndWait(tester, 'It is not mine any more');

    expect(await w.saidItIsMine, isFalse);
    expect(find.text('This VPN is mine'), findsOneWidget);
    expect(find.text('You told OrbGuard this one is yours.'), findsNothing);
  });

  testWidgets('on a Mac the tunnel and the proxy are both really checked',
      (tester) async {
    tunnel = true;
    proxyHost = 'proxy.example.net:8443';
    await pump(
        tester, HiddenVpnProxyScreen(watch: watchFor(TargetPlatform.macOS)));

    final String said = visible(tester).join(' ');
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Active at proxy.example.net:8443'), findsOneWidget);
    expect(said, isNot(contains('wired')));
    expect(said, isNot(contains('environment variables')));
    // Named as it is written, in a sentence too.
    expect(said, isNot(contains('this mac')));
  });

  testWidgets('on a Mac, a tunnel OrbVPN brought up is OrbVPN, unasked',
      (tester) async {
    tunnel = true;
    macOwner = 'com.orb.vpn';
    final w = watchFor(TargetPlatform.macOS);
    await pump(tester, HiddenVpnProxyScreen(watch: w));

    expect(
        find.text('The VPN that is active is OrbVPN, so OrbGuard treats it '
            'as yours.'),
        findsOneWidget);
    expect(find.text('This VPN is mine'), findsNothing);
    expect(await w.unknownVpnActive(ownFirewallOn: false), isFalse);
  });

  testWidgets("on a Mac, another app's tunnel is still asked about",
      (tester) async {
    tunnel = true;
    macOwner = 'com.wireguard.macos';
    final w = watchFor(TargetPlatform.macOS);
    await pump(tester, HiddenVpnProxyScreen(watch: w));

    expect(find.text('This VPN is mine'), findsOneWidget);
    expect(await w.unknownVpnActive(ownFirewallOn: false), isTrue);
  });

  testWidgets('only a proxy active reads "This proxy is mine"', (tester) async {
    proxyHost = '10.0.0.9:8080';
    await pump(
        tester, HiddenVpnProxyScreen(watch: watchFor(TargetPlatform.iOS)));

    expect(find.text('This proxy is mine'), findsOneWidget);
    expect(find.text('This VPN is mine'), findsNothing);
    expect(find.text('Active at 10.0.0.9:8080'), findsOneWidget);
  });

  testWidgets("OrbGuard's own firewall is named, with nothing to answer",
      (tester) async {
    tunnel = true;
    await pump(
        tester,
        HiddenVpnProxyScreen(
            watch: watchFor(TargetPlatform.android),
            ownFirewallOn: () => true));

    expect(find.text('This VPN is mine'), findsNothing);
    expect(find.text('This tunnel is OrbGuard’s own tracker firewall.'),
        findsOneWidget);
  });

  testWidgets('genuine OrbVPN installed: the tunnel is shown, nothing is asked',
      (tester) async {
    tunnel = true;
    metaOwnFirewall = false;
    metaOrbVpn = true;
    await pump(
        tester,
        HiddenVpnProxyScreen(
            watch: watchFor(TargetPlatform.android),
            ownFirewallOn: () => false));

    expect(find.text('A VPN or proxy is active'), findsOneWidget);
    expect(find.text('Active'),
        findsOneWidget); // the tunnel row, not "Not detected"
    expect(find.text('Not detected'), findsNothing);
    expect(
        find.text('A VPN is active. OrbVPN is installed on this phone, so '
            'OrbGuard treats it as yours. Android does not tell any app which '
            'app runs a VPN.'),
        findsOneWidget);
    expect(find.text('This VPN is mine'), findsNothing);
    expect(find.text('It is not mine any more'), findsNothing);
  });

  testWidgets(
      "the native firewall fact names OrbGuard's tunnel even when "
      'the Dart flag says off', (tester) async {
    tunnel = true;
    metaOwnFirewall = true;
    await pump(
        tester,
        HiddenVpnProxyScreen(
            watch: watchFor(TargetPlatform.android),
            ownFirewallOn: () => false));

    expect(find.text('This tunnel is OrbGuard’s own tracker firewall.'),
        findsOneWidget);
    expect(find.text('This VPN is mine'), findsNothing);
  });

  testWidgets('a stale Dart firewall flag cannot hide another VPN',
      (tester) async {
    tunnel = true;
    metaOwnFirewall = false;
    await pump(
        tester,
        HiddenVpnProxyScreen(
            watch: watchFor(TargetPlatform.android),
            ownFirewallOn: () => true));

    expect(find.text('This VPN is mine'), findsOneWidget);
    expect(find.text('This tunnel is OrbGuard’s own tracker firewall.'),
        findsNothing);
  });

  testWidgets('nothing active offers nothing to answer', (tester) async {
    await pump(
        tester, HiddenVpnProxyScreen(watch: watchFor(TargetPlatform.android)));

    expect(find.text('No active VPN or proxy found'), findsOneWidget);
    expect(find.text('This VPN is mine'), findsNothing);
    expect(find.text('This proxy is mine'), findsNothing);
  });

  testWidgets('no em or en dash, arrow or middle dot anywhere on the screen',
      (tester) async {
    tunnel = true;
    proxyHost = '10.0.0.9:8080';
    await pump(
        tester, HiddenVpnProxyScreen(watch: watchFor(TargetPlatform.android)));
    await tapAndWait(tester, 'Open VPN settings'); // reveals the written steps
    for (final t in visible(tester)) {
      expect(RegExp('[—–→←·]').hasMatch(t), isFalse, reason: t);
    }
  });

  testWidgets('by default the screen answers VpnWatch.shared', (tester) async {
    tunnel = true;
    await pump(tester, const HiddenVpnProxyScreen());
    await tapAndWait(tester, 'This VPN is mine');

    expect(await VpnWatch.shared.saidItIsMine, isTrue);
    await VpnWatch.shared.forgetMine();
  });
}
