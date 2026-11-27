// The results sheet tells the truth about a check: what it found, what ran
// clean, what this device cannot run and what broke, never counting either
// of those as passed, and never a number the record does not hold.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/services/home/check_results.dart';
import 'package:orbguard/services/home/home_brief.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/home/orb_ring.dart';
import 'package:orbguard/widgets/home/results_sheet.dart';
import 'package:orbguard/widgets/home/share_card.dart';
import 'package:orbguard/widgets/sale/credit_line.dart';

import '../../support/real_fonts.dart';
import '../../support/sale_fakes.dart';

const List<String> _five = [
  'Network connections',
  'Running processes',
  'File system',
  'App databases',
  'Memory',
];
const List<String> _six = [
  'Certificate analysis',
  'Permission abuse',
  'Accessibility abuse',
  'Keylogger detection',
  'Location stalkers',
  'App malware scan',
];

HomeGap _gap(Shield shield, String id, int points, String title) => HomeGap(
      shield: shield,
      factor: ScoreFactor(id: id, label: id, points: points),
      title: title,
      detail: 'detail',
    );

final HomeGap _breach = _gap(
    Shield.identity, 'fix_breaches', 100, 'Your email was in a data breach');
final HomeGap _vpn =
    _gap(Shield.hiddenVpn, 'review_vpn', 50, 'A VPN or proxy is active');

const Map<String, dynamic> _spy = {
  'id': 'f1',
  'name': 'Spyware traces in a system folder',
  'description': 'Files that match a known spyware kit.',
  'severity': 'HIGH',
  'stage': 'File system',
};
Map<String, dynamic> _app(String id, String severity) => {
      'id': id,
      'name': 'An app can read your messages',
      'description': 'It asked for access to your texts and your screen.',
      'severity': severity,
      'path': 'com.example.reader',
      'stage': 'Permission abuse',
    };

CheckResults _results({
  List<Map<String, dynamic>> findings = const [],
  List<String>? ran = const [..._five, ..._six],
  List<String> notPossible = const [],
  List<String> failed = const [],
  List<HomeGap> gaps = const [],
}) =>
    CheckResults.from(
      findings: findings,
      stagesRan: ran,
      stagesNotPossible: notPossible,
      stagesFailed: failed,
      gaps: gaps,
    );

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  final List<Object> opened = [];

  Future<void> open(
    WidgetTester tester,
    CheckResults results, {
    TargetPlatform platform = TargetPlatform.android,
    double width = 390,
    bool dark = true,
    bool premium = false,
    bool checkedToday = false,
  }) async {
    opened.clear();
    final FakeSaleAccount account =
        FakeSaleAccount(loggedIn: true, premium: premium);
    await pumpSale(
      tester,
      account: account,
      credits: SaleCredits(account: account, balance: 3).provider,
      width: width,
      dark: dark,
      child: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => ResultsSheet.show(
              context,
              results: results,
              onOpenThing: opened.add,
              onOpenGap: opened.add,
              platform: platform,
              checkedToday: checkedToday,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Iterable<BrandButton> buttons(WidgetTester tester) =>
      tester.widgetList<BrandButton>(find.byType(BrandButton));

  OrbStatus ring(WidgetTester tester) =>
      tester.widget<OrbRing>(find.byType(OrbRing)).status;

  group('sharing', () {
    testWidgets('an all clear from today can be shared, beside a lime Done',
        (tester) async {
      await open(tester, _results(), checkedToday: true);
      final List<BrandButton> all = buttons(tester).toList();
      expect(all.map((b) => b.label), ['Share', 'Done']);
      expect(
          all
              .where((b) => b.variant == BrandButtonVariant.primary)
              .map((b) => b.label),
          ['Done']);

      await tester.tap(find.text('Share'));
      await settle(tester);
      expect(find.text('Share your result'), findsOneWidget);
      expect(find.byType(ShareCard), findsOneWidget);
      expect(find.text('No signs I am being watched.'), findsOneWidget);
      expect(find.text('Checked today with OrbGuard'), findsOneWidget);
      expect(find.text('Is your circle closed?'), findsOneWidget);
    });

    testWidgets('a check from another day is not offered as today\'s',
        (tester) async {
      await open(tester, _results());
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('a check with a gap still open is not shared as all clear',
        (tester) async {
      await open(tester, _results(gaps: [_breach]), checkedToday: true);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('a check that broke in part is not shared', (tester) async {
      await open(tester, _results(failed: const ['Memory']),
          checkedToday: true);
      expect(find.text('Share'), findsNothing);
    });

    testWidgets('Share sends the card as a picture', (tester) async {
      final Completer<int> sent = Completer<int>();
      final ShareImage before = shareResultImage;
      shareResultImage = (png, {origin}) async => sent.complete(png.length);
      addTearDown(() => shareResultImage = before);

      await open(tester, _results(), checkedToday: true);
      await tester.tap(find.text('Share'));
      await settle(tester);
      await tester.tap(find.widgetWithText(BrandButton, 'Share').last);
      await tester.pump();
      // The picture is drawn off the test's clock: let real time pass for
      // the engine, then the test's clock for what follows it, in turn.
      for (int i = 0; i < 40 && !sent.isCompleted; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      expect(sent.isCompleted, isTrue);
      expect(await sent.future, greaterThan(1000));
    });
  });

  group('all clear', () {
    testWidgets('a whole ring, the count, every clean check, one lime Done',
        (tester) async {
      await open(tester, _results());

      expect(find.text('All clear'), findsOneWidget);
      expect(find.text('11 checks ran clean.'), findsOneWidget);
      expect(ring(tester), const OrbStatus.whole());
      expect(tester.getSize(find.byType(OrbRing)).width, 84);
      expect(find.text('Spyware traces in files'), findsOneWidget);
      expect(find.text('Keyloggers'), findsOneWidget);
      expect(find.byType(CreditLine), findsOneWidget);
      expect(find.text('3 scan credits left'), findsOneWidget);
      expect(buttons(tester), hasLength(1));
      expect(buttons(tester).single.label, 'Done');
      expect(buttons(tester).single.variant, BrandButtonVariant.primary);

      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.text('All clear'), findsNothing);
    });

    testWidgets('one check reads in the singular', (tester) async {
      await open(tester, _results(ran: const ['Memory']));
      expect(find.text('1 check ran clean.'), findsOneWidget);
    });

    testWidgets('a record that never named its checks gives no count',
        (tester) async {
      await open(tester, _results(ran: null));
      expect(find.text('All clear'), findsOneWidget);
      expect(find.textContaining('ran clean'), findsNothing);
    });

    testWidgets('a subscriber sees no credit line', (tester) async {
      await open(tester, _results(), premium: true);
      expect(find.textContaining('scan credit'), findsNothing);
    });
  });

  group('nothing found, other gaps open', () {
    testWidgets('says the checks are clean and one gap is still open',
        (tester) async {
      await open(tester, _results(gaps: [_breach]));

      expect(find.text('Checks are clean'), findsOneWidget);
      expect(find.text('11 checks ran clean. One gap is still open.'),
          findsOneWidget);
      expect(ring(tester), OrbStatus.open([Shield.identity.angle]));
      expect(find.text('STILL OPEN'), findsOneWidget);
      expect(find.text('Your email was in a data breach'), findsOneWidget);
      expect(find.text('Closing it adds 100 to your score'), findsOneWidget);

      final BrandButton lime = buttons(tester)
          .singleWhere((b) => b.variant == BrandButtonVariant.primary);
      expect(lime.label, 'Close the gap');
      expect(
          buttons(tester)
              .singleWhere((b) => b.variant == BrandButtonVariant.secondary)
              .label,
          'Done');
    });

    testWidgets('a gap opens its fix and the sheet stays', (tester) async {
      await open(tester, _results(gaps: [_breach, _vpn]));
      await tester.tap(find.text('A VPN or proxy is active'));
      await settle(tester);
      expect(opened, [_vpn]);
      expect(find.text('Checks are clean'), findsOneWidget);

      await tester.tap(find.text('Close the gap'));
      await settle(tester);
      expect(opened, [_vpn, _breach]);
    });

    testWidgets('two gaps in words, five and more in digits', (tester) async {
      await open(tester, _results(gaps: [_breach, _vpn]));
      expect(find.text(
          // The VPN gap keeps the connection check from being called clean.
          '10 checks ran clean. Two gaps are still open.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      await open(
          tester,
          _results(
              gaps: [for (int i = 0; i < 5; i++) i.isEven ? _breach : _vpn]));
      expect(find.text('10 checks ran clean. 5 gaps are still open.'),
          findsOneWidget);
    });

    testWidgets('no count when the record never named its checks',
        (tester) async {
      await open(tester, _results(ran: null, gaps: [_breach]));
      expect(find.text('One gap is still open.'), findsOneWidget);
      expect(find.textContaining('ran clean'), findsNothing);
    });
  });

  group('things found', () {
    testWidgets('one thing: its card, the count, See what to do',
        (tester) async {
      await open(tester, _results(findings: [_spy]));

      expect(find.text('Your check found 1 thing'), findsOneWidget);
      expect(find.text('10 checks ran clean.'), findsOneWidget);
      expect(ring(tester), OrbStatus.open([Shield.spyware.angle]));
      expect(find.text('Spyware traces in a system folder'), findsOneWidget);
      expect(
          find.text('Files that match a known spyware kit.'), findsOneWidget);
      expect(find.textContaining('more'), findsNothing);
      // The severity mark takes the ramp's high ink.
      final Iterable<Color?> marks = tester
          .widgetList<Container>(find.byKey(const ValueKey('severity_mark')))
          .map((c) => (c.decoration as BoxDecoration?)?.color);
      expect(marks.single, AppColors.severityHigh.withValues(alpha: 0.14));

      final BrandButton lime = buttons(tester)
          .singleWhere((b) => b.variant == BrandButtonVariant.primary);
      expect(lime.label, 'See what to do');
      expect(find.text('Done'), findsOneWidget);
      // The check found it: no clean row claims the folder check.
      expect(find.text('Spyware traces in files'), findsNothing);
    });

    testWidgets('an app found twice is one card, with and 1 more',
        (tester) async {
      await open(
          tester,
          _results(
              findings: [_spy, _app('a', 'MEDIUM'), _app('b', 'CRITICAL')]));
      expect(find.text('Your check found 2 things'), findsOneWidget);
      expect(find.text('and 1 more'), findsOneWidget);
      expect(ring(tester),
          OrbStatus.open([Shield.spyware.angle, Shield.watching.angle]));
    });

    testWidgets('a card opens its thing and the sheet stays', (tester) async {
      final CheckResults r = _results(findings: [_spy]);
      await open(tester, r);
      await tester.tap(find.text('Spyware traces in a system folder'));
      await settle(tester);
      expect(opened, [r.things.single]);
      expect(find.text('Your check found 1 thing'), findsOneWidget);

      await tester.tap(find.text('See what to do'));
      await settle(tester);
      expect(opened, hasLength(2));
      expect(identical(opened.last, r.things.first), isTrue);
    });

    testWidgets('a long description stops at two lines', (tester) async {
      await open(
          tester,
          _results(findings: [
            {..._spy, 'description': 'A very long description. ' * 20},
          ]));
      final Text d = tester.widget<Text>(find.textContaining('A very long'));
      expect(d.maxLines, 2);
    });

    testWidgets('nothing ran clean: no count line', (tester) async {
      await open(
          tester, _results(findings: [_spy], ran: const ['File system']));
      expect(find.text('Your check found 1 thing'), findsOneWidget);
      expect(find.textContaining('ran clean'), findsNothing);
    });
  });

  group('checks not possible here', () {
    testWidgets('on iPhone', (tester) async {
      await open(tester, _results(ran: _five, notPossible: _six),
          platform: TargetPlatform.iOS);
      expect(find.text('6 checks are not possible on iPhone'), findsOneWidget);
      expect(
          find.text('Untrusted certificates, Risky app permissions, '
              'Stalkerware services, Keyloggers, Location tracking, App '
              'malware. iOS does not let any app run these, so they are not '
              'counted as passed.'),
          findsOneWidget);
      expect(find.text('5 checks ran clean.'), findsOneWidget);
    });

    testWidgets('one, on a Mac', (tester) async {
      await open(tester,
          _results(ran: _five, notPossible: const ['Certificate analysis']),
          platform: TargetPlatform.macOS);
      expect(find.text('1 check is not possible on this Mac'), findsOneWidget);
      expect(
          find.text('Untrusted certificates. OrbGuard cannot run this on a '
              'Mac yet, so it is not counted as passed.'),
          findsOneWidget);
    });

    testWidgets('on a computer', (tester) async {
      await open(tester, _results(ran: _five, notPossible: _six),
          platform: TargetPlatform.windows);
      expect(find.text('6 checks are not possible on this computer'),
          findsOneWidget);
      expect(
          find.textContaining('OrbGuard cannot run these on a computer yet, '
              'so they are not counted as passed.'),
          findsOneWidget);
    });

    testWidgets('on a phone', (tester) async {
      await open(
          tester,
          _results(
              ran: _five, notPossible: const ['Keylogger detection', 'Memory']),
          platform: TargetPlatform.android);
      expect(
          find.text('2 checks are not possible on this phone'), findsOneWidget);
      expect(
          find.text('Keyloggers, Memory tampering. This version of OrbGuard '
              'cannot run these, so they are not counted as passed.'),
          findsOneWidget);
    });
  });

  group('checks that broke', () {
    testWidgets('named, not passed, and asked to run again', (tester) async {
      await open(
          tester,
          _results(
              ran: _five, failed: const ['Memory', 'Keylogger detection']));
      expect(find.text('2 checks could not run this time'), findsOneWidget);
      expect(
          find.text('Memory tampering, Keyloggers. They are not counted as '
              'passed. Run the check again.'),
          findsOneWidget);
    });

    testWidgets('one, in the singular', (tester) async {
      await open(tester, _results(ran: _five, failed: const ['Memory']));
      expect(find.text('1 check could not run this time'), findsOneWidget);
      expect(
          find.text('Memory tampering. It is not counted as passed. Run the '
              'check again.'),
          findsOneWidget);
    });

    testWidgets('nothing found is not called all clear', (tester) async {
      await open(
          tester,
          _results(
              ran: const ['Memory', 'File system'],
              failed: const ['Keylogger detection']));

      expect(find.text('All clear'), findsNothing);
      expect(find.text('Nothing found so far'), findsOneWidget);
      expect(find.text('2 checks ran clean. 1 could not run.'), findsOneWidget);
      // The ring shows the check as it went: a part for each check that ran,
      // a hatched part for the one that did not.
      expect(
          ring(tester),
          const OrbStatus.checking(
              [OrbSegment.done, OrbSegment.done, OrbSegment.unavailable]));
      expect(buttons(tester).single.label, 'Done');
    });

    testWidgets('with a gap open the checks are not called clean either',
        (tester) async {
      await open(
          tester,
          _results(
              ran: _five,
              failed: const ['Keylogger detection'],
              gaps: [_breach]));

      expect(find.text('Checks are clean'), findsNothing);
      expect(find.text('Nothing found so far'), findsOneWidget);
      expect(
          find.text('5 checks ran clean. 1 could not run. '
              'One gap is still open.'),
          findsOneWidget);
    });

    testWidgets('when no check ran, nothing is called checked', (tester) async {
      await open(
          tester,
          _results(
              ran: const [], failed: const ['Memory', 'Keylogger detection']));

      expect(find.text('All clear'), findsNothing);
      expect(find.text('Nothing was checked'), findsOneWidget);
      expect(find.text('2 checks could not run.'), findsOneWidget);
      expect(
          ring(tester),
          const OrbStatus.checking(
              [OrbSegment.unavailable, OrbSegment.unavailable]));
    });
  });

  group('fits', () {
    final Map<String, CheckResults> cases = {
      'all clear': _results(),
      'gaps': _results(gaps: [_breach, _vpn]),
      'found': _results(
          findings: [_spy, _app('a', 'LOW'), _app('b', 'MEDIUM')],
          gaps: [_breach]),
      'cannot and broke': _results(
          ran: const ['Running processes'],
          notPossible: _six,
          failed: const ['Memory', 'File system']),
    };
    for (final double width in [390.0, 320.0]) {
      for (final bool dark in [true, false]) {
        testWidgets('${width.toInt()} wide, ${dark ? 'dark' : 'light'}',
            (tester) async {
          for (final MapEntry<String, CheckResults> c in cases.entries) {
            await open(tester, c.value,
                platform: TargetPlatform.iOS, width: width, dark: dark);
            expect(tester.takeException(), isNull, reason: c.key);
            expect(cutOffText(tester), isEmpty, reason: c.key);
            expect(forbiddenMarks(tester), isEmpty, reason: c.key);
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  });
}
