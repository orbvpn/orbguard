import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/screens/pricing/pricing_screen.dart';

/// Phase 3.5 — the transparent pricing screen. This screen's whole pitch is
/// its honesty, so the guard here is as much about what ISN'T on screen
/// (fake urgency copy) as what is (the plain-language renewal promise).
void main() {
  Widget host() => const MaterialApp(home: PricingScreen());

  // The screen is a single tall ListView (3 plan cards + promise band) that
  // overflows the default 800×600 test surface, so Sliver virtualization
  // never builds the lower cards at the default size. Widen the surface
  // instead of scrolling — every assertion below then sees the whole tree.
  Future<void> pumpTall(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 4200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());
    await tester.pump();
  }

  testWidgets('renders the honest-pricing promise band', (tester) async {
    await pumpTall(tester);

    expect(
      find.text(
        'The price you see is the price that renews. Cancel anytime, in one '
        'tap. No hidden fees.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders all three plan names', (tester) async {
    await pumpTall(tester);

    // "Free" legitimately renders twice — the plan-name heading AND the
    // price itself (a $0 tier is honestly labelled "Free" as its price too).
    expect(find.text('Free'), findsAtLeastNWidgets(1));
    expect(find.text('Guard'), findsOneWidget);
    expect(find.text('Guard+'), findsOneWidget);
  });

  testWidgets('contains no fake-urgency / dark-pattern copy', (tester) async {
    await pumpTall(tester);

    // Gather every literal Text string on screen (case-insensitive) and
    // assert none of the classic dark-pattern markers appear anywhere —
    // mirrors the same "urgency keyword" family the app's own scam
    // detector (ScamDetectionProvider._localAnalysis) flags in incoming
    // messages, applied here to its own pricing copy.
    final allText = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join(' \n ')
        .toLowerCase();

    const bannedPhrases = [
      'hurry',
      'limited time',
      'act now',
      "don't wait",
      'act fast',
      'expires in',
      'expires soon',
      'countdown',
      'time is running out',
      'people are viewing',
      'people viewing',
      'while supplies last',
      'sale ends',
    ];

    for (final phrase in bannedPhrases) {
      expect(
        allText.contains(phrase),
        isFalse,
        reason: 'found fake-urgency / dark-pattern copy: "$phrase"',
      );
    }
  });

  testWidgets('yearly toggle shows the real effective per-month price',
      (tester) async {
    await pumpTall(tester);

    await tester.tap(find.text('Yearly'));
    await tester.pump();

    // Guard: $49.90/yr ÷ 12 = $4.1583... → honestly rounded to $4.16/mo.
    expect(find.text('\$4.16'), findsOneWidget);
    expect(find.text('Billed \$49.90 once a year.'), findsOneWidget);
    // The math is exact (49.90 == 10 × 4.99), so the "2 months free" claim
    // is literally true and allowed.
    expect(
      find.text("That's 2 months free versus paying monthly."),
      findsWidgets,
    );
  });

  testWidgets('no plan CTA is disabled and tapping one surfaces feedback',
      (tester) async {
    await pumpTall(tester);

    await tester.tap(find.text('Choose Guard'));
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
