// The score sheet tells the truth about the number: seven rules that add up
// to it, the points each one earned, what is missing and what would earn it
// back. Every number on it comes from the engine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/widgets/brand_button.dart';
import 'package:orbguard/services/home/privacy_score_engine.dart';
import 'package:orbguard/services/iap/iap_service.dart';
import 'package:orbguard/widgets/home/score_sheet.dart';

import '../../support/real_fonts.dart';
import '../../support/sale_fakes.dart';

const PrivacyScoreEngine _engine = PrivacyScoreEngine();

/// Everything checked and fine: 1000.
const PrivacySignals _perfect = PrivacySignals(
  daysSinceScan: 1,
  guardsActive: 4,
  guardsAvailable: 4,
  breachedAccounts: 0,
  riskyPermissionApps: 0,
  unknownVpnActive: false,
  notificationsGranted: true,
);

PrivacySignals _with({
  int? breached = 0,
  bool vpn = false,
  bool audit = true,
  bool alertsPossible = true,
  bool alerts = true,
  int active = 4,
  int? days = 1,
}) =>
    PrivacySignals(
      daysSinceScan: days,
      guardsActive: active,
      guardsAvailable: 4,
      breachedAccounts: breached,
      riskyPermissionApps: audit ? 0 : null,
      unknownVpnActive: vpn,
      notificationsGranted: alerts,
      appAuditPossible: audit,
      alertsPossible: alertsPossible,
    );

void main() {
  setUpAll(loadRealFonts);
  setUp(() => IapService.instance.debugSeed(available: false, products: []));

  Future<List<String>> open(
    WidgetTester tester,
    PrivacyScore score, {
    TargetPlatform platform = TargetPlatform.android,
    double width = 390,
    bool dark = true,
  }) async {
    final List<String> tapped = [];
    final FakeSaleAccount account = FakeSaleAccount();
    await pumpSale(
      tester,
      account: account,
      credits: SaleCredits(account: account).provider,
      width: width,
      height: 1000,
      dark: dark,
      child: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => ScoreSheet.show(context,
                score: score, onFactorTap: tapped.add, platform: platform),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    return tapped;
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  Iterable<BrandButton> buttons(WidgetTester tester) =>
      tester.widgetList<BrandButton>(find.byType(BrandButton));

  testWidgets('a perfect score: the number, the band, seven full rules, Done',
      (tester) async {
    final PrivacyScore score = _engine.compute(_perfect);
    expect(score.value, 1000);
    await open(tester, score);

    expect(find.text('How your score adds up'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('of 1000'), findsOneWidget);
    expect(find.text('Excellent'), findsOneWidget);
    for (final ScoreRule rule in score.rules) {
      expect(find.text(rule.label), findsOneWidget);
      expect(find.text('${rule.max} of ${rule.max}'), findsWidgets);
    }
    // No chevron anywhere: nothing is missing, so no row is a button.
    expect(find.byKey(const ValueKey('rule_chevron')), findsNothing);
    // One lime Done and nothing else.
    expect(buttons(tester), hasLength(1));
    expect(buttons(tester).single.label, 'Done');
    expect(buttons(tester).single.variant, BrandButtonVariant.primary);

    await tester.tap(find.text('Done'));
    await settle(tester);
    expect(find.text('How your score adds up'), findsNothing);
  });

  testWidgets('the bar is seven segments sized by what each rule is worth',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    final PrivacyScore score = _engine.compute(_with(breached: 1));
    await open(tester, score);

    expect(
        find.bySemanticsLabel('${score.value} of 1000 points'), findsOneWidget);
    final List<double> widths = [
      for (int i = 0; i < 7; i++)
        tester.getSize(find.byKey(ValueKey('score_segment_$i'))).width,
    ];
    final List<int> max = [for (final r in score.rules) r.max];
    expect(max, [200, 200, 150, 250, 100, 50, 50]);
    for (int i = 0; i < 7; i++) {
      expect(widths[i] / widths[0], closeTo(max[i] / max[0], 0.02));
      expect(
          tester.getSize(find.byKey(ValueKey('score_segment_$i'))).height, 8);
    }
    // 3 between each.
    final double gap = tester
            .getTopLeft(find.byKey(const ValueKey('score_segment_1')))
            .dx -
        tester.getTopRight(find.byKey(const ValueKey('score_segment_0'))).dx;
    expect(gap, closeTo(3, 0.01));
    handle.dispose();
  });

  testWidgets('a rule short of its ceiling is amber and opens its fix',
      (tester) async {
    final PrivacyScore score = _engine.compute(_with(breached: 1));
    expect(score.value, 900);
    final List<String> tapped = await open(tester, score);

    expect(find.text('900'), findsOneWidget);
    expect(find.text('0 of 100'), findsOneWidget);
    expect(tester.widget<Text>(find.text('0 of 100')).style?.color,
        Brand.amberInk);
    expect(tester.widget<Text>(find.text('150 of 150')).style?.color,
        isNot(Brand.amberInk));
    expect(find.byKey(const ValueKey('rule_chevron')), findsOneWidget);

    // A full rule is not a button.
    await tester.tap(find.text('OrbGuard is installed'));
    await settle(tester);
    expect(tapped, isEmpty);
    expect(find.text('How your score adds up'), findsOneWidget);

    // The short one closes the sheet, then starts its fix.
    await tester.tap(find.text('No breached accounts'));
    await settle(tester);
    expect(tapped, ['fix_breaches']);
    expect(find.text('How your score adds up'), findsNothing);
  });

  testWidgets('the top fix is the one lime action, with a quiet Done',
      (tester) async {
    final PrivacyScore score = _engine.compute(_with(breached: 1));
    final List<String> tapped = await open(tester, score);

    final BrandButton lime = buttons(tester)
        .singleWhere((b) => b.variant == BrandButtonVariant.primary);
    expect(lime.label, 'Close the gap, earn 100');
    expect(find.text('Done'), findsOneWidget);
    expect(
        buttons(tester).where((b) => b.variant == BrandButtonVariant.primary),
        hasLength(1));

    await tester.tap(find.text('Close the gap, earn 100'));
    await settle(tester);
    expect(tapped, ['fix_breaches']);
  });

  testWidgets('a VPN nobody confirmed is a row of its own, 50 off',
      (tester) async {
    final PrivacyScore score = _engine.compute(_with(vpn: true));
    expect(score.penalty, 50);
    final List<String> tapped = await open(tester, score);

    expect(find.text('950'), findsOneWidget);
    expect(find.text('A VPN or proxy is not confirmed'), findsOneWidget);
    expect(find.text('50 off'), findsOneWidget);
    expect(
        tester.widget<Text>(find.text('50 off')).style?.color, Brand.amberInk);
    // It comes after the seven rules.
    expect(
        tester.getTopLeft(find.text('A VPN or proxy is not confirmed')).dy,
        greaterThan(tester
            .getTopLeft(find.text('No apps with spyware-style access'))
            .dy));

    await tester.tap(find.text('A VPN or proxy is not confirmed'));
    await settle(tester);
    expect(tapped, ['review_vpn']);
  });

  group('the button names the fix', () {
    const Map<String, String> words = {
      'resolve_threats': 'Close the gap, earn 150',
      'review_apps': 'Close the gap, earn 150',
      'fix_breaches': 'Close the gap, earn 150',
      'review_vpn': 'Close the gap, earn 150',
      'run_check': 'Run a check, earn 150',
      'enable_guards': 'Turn on shields, earn 150',
      'check_breaches': 'Check your email, earn 150',
      'enable_alerts': 'Turn on alerts, earn 150',
    };
    for (final MapEntry<String, String> e in words.entries) {
      testWidgets(e.key, (tester) async {
        final PrivacyScore base = _engine.compute(_perfect);
        final PrivacyScore score = PrivacyScore(
          value: 850,
          band: 'Excellent',
          rules: base.rules,
          factors: [ScoreFactor(id: e.key, label: e.key, points: 150)],
        );
        final List<String> tapped = await open(tester, score);
        expect(find.text(e.value), findsOneWidget);
        await tester.tap(find.text(e.value));
        await settle(tester);
        expect(tapped, [e.key]);
      });
    }
  });

  group('points given because the device cannot', () {
    testWidgets('the app audit on iPhone', (tester) async {
      await open(tester, _engine.compute(_with(audit: false)),
          platform: TargetPlatform.iOS);
      expect(
          find.text('iPhone cannot audit other apps, so those last 50 points '
              'are yours. You are never marked down for something the system '
              'forbids.'),
          findsOneWidget);
    });

    testWidgets('the app audit on a Mac', (tester) async {
      await open(tester, _engine.compute(_with(audit: false)),
          platform: TargetPlatform.macOS);
      expect(
          find.text('OrbGuard does not audit other apps on a Mac yet, so '
              'those last 50 points are yours.'),
          findsOneWidget);
    });

    testWidgets('the app audit on a computer', (tester) async {
      await open(tester, _engine.compute(_with(audit: false)),
          platform: TargetPlatform.windows);
      expect(
          find.text('OrbGuard does not audit other apps on a computer yet, '
              'so those last 50 points are yours.'),
          findsOneWidget);
    });

    testWidgets('alerts', (tester) async {
      await open(tester, _engine.compute(_with(alertsPossible: false)),
          platform: TargetPlatform.linux);
      expect(
          find.text('Alerts are not available on this computer yet, so '
              'those 50 points are yours.'),
          findsOneWidget);
    });

    testWidgets('nothing waived, no note', (tester) async {
      await open(tester, _engine.compute(_perfect));
      expect(find.textContaining('points are yours'), findsNothing);
    });
  });

  group('fits', () {
    final Map<String, PrivacyScore> cases = {
      'perfect': _engine.compute(_perfect),
      'several gaps': _engine.compute(
          _with(breached: 2, vpn: true, alerts: false, active: 1, days: 12)),
      'never checked': _engine.compute(_with(days: null, breached: null)),
      'waived': _engine.compute(_with(audit: false, alertsPossible: false)),
    };
    for (final double width in [390.0, 320.0]) {
      for (final bool dark in [true, false]) {
        testWidgets('${width.toInt()} wide, ${dark ? 'dark' : 'light'}',
            (tester) async {
          for (final MapEntry<String, PrivacyScore> c in cases.entries) {
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
