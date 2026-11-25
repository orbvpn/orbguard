// The breach fix sheet Home opens on the Identity & breach gap: real words
// from real data, three plain steps, one lime way to close the gap, and an
// honest empty state.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbguard/models/api/sms_analysis.dart';
import 'package:orbguard/models/api/threat_indicator.dart';
import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/providers/darkweb_provider.dart';
import 'package:orbguard/screens/darkweb/darkweb_screen.dart';
import 'package:orbguard/widgets/shields/breach_fix_sheet.dart';

import '../support/real_fonts.dart';

final DateTime _checked = DateTime(2026, 11, 20, 9);

MonitoredAsset _email(String id, String value, {int breachCount = 0}) =>
    MonitoredAsset(
      id: id,
      type: AssetType.email,
      value: value,
      addedAt: DateTime(2026),
      lastChecked: _checked,
      breachCount: breachCount,
    );

BreachInfo _breach(String name, {DateTime? date}) => BreachInfo(
      name: name,
      title: name,
      domain: '',
      breachDate: date,
      dataClasses: const [],
      isVerified: true,
      isSensitive: false,
    );

BreachCheckResult _result(String email, List<BreachInfo> breaches) =>
    BreachCheckResult(
      email: email,
      isBreached: breaches.isNotEmpty,
      breachCount: breaches.length,
      breaches: breaches,
      checkedAt: _checked,
    );

BreachAlert _alert(String id, String assetId, String name) => BreachAlert(
      id: id,
      assetId: assetId,
      assetType: '',
      assetValue: '',
      breach: _breach(name),
      severity: SeverityLevel.high,
      alertedAt: DateTime(2026, 11, 2),
      isRead: false,
    );

/// Every string a person can read on screen right now.
List<String> _visibleText(WidgetTester tester) => [
      for (final p in tester.allRenderObjects.whereType<RenderParagraph>())
        p.text.toPlainText(),
    ];

void main() {
  setUpAll(loadRealFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<DarkWebProvider> pump(
    WidgetTester tester, {
    List<MonitoredAsset> assets = const [],
    List<BreachAlert> alerts = const [],
    Map<String, BreachCheckResult> checkResults = const {},
    double width = 390,
    bool dark = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
    addTearDown(() => AppColors.uiBrightness = Brightness.dark);

    final provider = DarkWebProvider(autoInit: false);
    await provider.debugLoad(
        assets: assets, alerts: alerts, checkResults: checkResults);

    await tester.pumpWidget(ChangeNotifierProvider<DarkWebProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: Scaffold(
          backgroundColor: Brand.bg,
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showBreachFixSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return provider;
  }

  group('one open address', () {
    testWidgets('names the real breach and year, three steps, one lime action',
        (tester) async {
      await pump(
        tester,
        assets: [_email('a1', 'alex@example.com', breachCount: 1)],
        checkResults: {
          'alex@example.com': _result('alex@example.com',
              [_breach('Canva', date: DateTime(2019, 5, 24))]),
        },
      );

      expect(find.text('Your email was in a data breach'), findsOneWidget);
      expect(find.text('al***@example.com was in the Canva breach in 2019.'),
          findsOneWidget);
      expect(find.text('Change your Canva password'), findsOneWidget);
      expect(find.text('Change it anywhere you reused it'), findsOneWidget);
      expect(find.text('Turn on two-step sign-in'), findsOneWidget);

      final lime = tester
          .widgetList<BrandButton>(find.byType(BrandButton))
          .where((b) => b.variant == BrandButtonVariant.primary);
      expect(lime.map((b) => b.label), ['I changed it. Close the gap']);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('See what leaked'), findsOneWidget);
    });

    testWidgets('with no name known it says only the real count',
        (tester) async {
      await pump(tester,
          assets: [_email('a1', 'alex@example.com', breachCount: 2)]);

      expect(find.text('al***@example.com was found in 2 known breaches.'),
          findsOneWidget);
      expect(find.text('Change the password of each breached account'),
          findsOneWidget);
      // No year, no name: nothing was invented.
      expect(
          _visibleText(tester)
              .where((t) => RegExp(r'\b(19|20)\d\d\b').hasMatch(t)),
          isEmpty);
    });

    testWidgets('a name from the alert feed with several breaches',
        (tester) async {
      await pump(
        tester,
        assets: [_email('a1', 'alex@example.com', breachCount: 3)],
        alerts: [_alert('al1', 'a1', 'Adobe')],
      );
      expect(
          find.text(
              'al***@example.com was found in 3 known breaches, including Adobe.'),
          findsOneWidget);
    });

    testWidgets('"I changed it" marks it handled and closes the sheet',
        (tester) async {
      final p = await pump(tester,
          assets: [_email('a1', 'alex@example.com', breachCount: 1)]);

      await tester.tap(find.text('I changed it. Close the gap'));
      await tester.pumpAndSettle();

      expect(p.openBreachedAccounts, 0);
      expect(find.text('Your email was in a data breach'), findsNothing);
    });

    testWidgets('"Not now" closes it and changes nothing', (tester) async {
      final p = await pump(tester,
          assets: [_email('a1', 'alex@example.com', breachCount: 1)]);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(p.openBreachedAccounts, 1);
      expect(find.text('Your email was in a data breach'), findsNothing);
    });

    testWidgets(
        '"See what leaked" opens the breach screen on THAT address\'s details',
        (tester) async {
      await pump(
        tester,
        assets: [_email('a1', 'alex@example.com', breachCount: 1)],
        checkResults: {
          'alex@example.com': _result('alex@example.com', [
            _breach('Canva', date: DateTime(2019, 5, 24)),
          ]),
        },
      );

      await tester.tap(find.text('See what leaked'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Your email was in a data breach'), findsNothing);
      expect(find.byType(DarkWebScreen), findsOneWidget);
      expect(find.text('Identity & breach'), findsWidgets);
      // The Email tab now shows this address's result and the breach.
      expect(find.text('alex@example.com'), findsWidgets);
      expect(find.text('Canva'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'an address known only masked cannot show its details, and the link '
        'says what it really opens', (tester) async {
      await pump(tester,
          assets: [_email('a1', 'al***@example.com', breachCount: 1)]);

      expect(find.text('See what leaked'), findsNothing);
      expect(find.text('Open Identity & breach'), findsOneWidget);

      await tester.tap(find.text('Open Identity & breach'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(DarkWebScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  testWidgets('says how many more addresses remain, with real numbers',
      (tester) async {
    await pump(tester, assets: [
      _email('a1', 'alex@example.com', breachCount: 1),
      _email('a2', 'sam@example.com', breachCount: 1),
      _email('a3', 'kim@example.com', breachCount: 4),
    ]);
    expect(find.text('2 more addresses are waiting after this one.'),
        findsOneWidget);
  });

  testWidgets('one more address reads in the singular', (tester) async {
    await pump(tester, assets: [
      _email('a1', 'alex@example.com', breachCount: 1),
      _email('a2', 'sam@example.com', breachCount: 1),
    ]);
    expect(
        find.text('1 more address is waiting after this one.'), findsOneWidget);
  });

  group('nothing open', () {
    testWidgets('no address watched: says so and offers Done', (tester) async {
      await pump(tester);
      expect(find.text('No open breaches'), findsOneWidget);
      expect(
          find.text('No email address is being watched yet.'), findsOneWidget);
      expect(find.text('I changed it. Close the gap'), findsNothing);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('No open breaches'), findsNothing);
    });

    testWidgets('watched but never checked', (tester) async {
      await pump(tester, assets: [
        MonitoredAsset(
            id: 'a1',
            type: AssetType.email,
            value: 'alex@example.com',
            addedAt: DateTime(2026)),
      ]);
      expect(find.text('Your watched addresses have not been checked yet.'),
          findsOneWidget);
    });

    testWidgets('checked, and everything dealt with', (tester) async {
      await pump(tester, assets: [_email('a1', 'alex@example.com')]);
      expect(
          find.text('No watched address has a breach you have not dealt with.'),
          findsOneWidget);
    });
  });

  group('fits', () {
    for (final double width in [390, 320]) {
      for (final bool dark in [true, false]) {
        final label = '${width.toInt()} wide, ${dark ? 'dark' : 'light'}';

        testWidgets('open state, $label', (tester) async {
          await pump(
            tester,
            width: width,
            dark: dark,
            assets: [
              _email('a1', 'alexandra.longname.person@example-company.com',
                  breachCount: 3),
              _email('a2', 'sam@example.com', breachCount: 1),
              _email('a3', 'kim@example.com', breachCount: 1),
            ],
            checkResults: {
              'alexandra.longname.person@example-company.com':
                  _result('alexandra.longname.person@example-company.com', [
                _breach('Canva', date: DateTime(2019, 5, 24)),
                _breach('Adobe', date: DateTime(2013, 10, 4)),
                _breach('LinkedIn', date: DateTime(2012, 5, 5)),
              ]),
            },
          );
          expect(tester.takeException(), isNull);
          for (final p
              in tester.allRenderObjects.whereType<RenderParagraph>()) {
            expect(p.didExceedMaxLines, isFalse,
                reason: 'cut off: ${p.text.toPlainText()}');
          }
          for (final t in _visibleText(tester)) {
            expect(RegExp('[—–→←·]').hasMatch(t), isFalse, reason: t);
          }
        });

        testWidgets('empty state, $label', (tester) async {
          await pump(tester, width: width, dark: dark);
          expect(tester.takeException(), isNull);
          for (final p
              in tester.allRenderObjects.whereType<RenderParagraph>()) {
            expect(p.didExceedMaxLines, isFalse,
                reason: 'cut off: ${p.text.toPlainText()}');
          }
        });
      }
    }
  });
}
