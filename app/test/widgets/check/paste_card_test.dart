// The paste card on the Check tab: paste something, press "Check it", and
// the scam shield's own analyser judges it. These tests stand a fake in for
// the analyser (the real one needs the network) and walk every state.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/theme/app_theme.dart';
import 'package:orbguard/presentation/theme/brand.dart';
import 'package:orbguard/presentation/theme/colors.dart';
import 'package:orbguard/providers/scam_detection_provider.dart';
import 'package:orbguard/widgets/check/paste_card.dart';
import 'package:orbguard/widgets/check/paste_verdict.dart';

import '../../support/real_fonts.dart';

ScamAnalysisResult _scam() => ScamAnalysisResult(
      id: '1',
      contentType: ScamContentType.text,
      content: PasteVerdict.sample,
      isScam: true,
      confidence: 0.92,
      riskScore: 0.92,
      severity: 'high',
      indicatorDetails: const [
        ScamIndicator(
            type: 'url',
            description: 'The link is not a real carrier address',
            confidence: 0.9),
        ScamIndicator(
            type: 'urgency',
            description: 'It pushes you to pay fast',
            confidence: 0.8),
      ],
      recommendations: const ['Do not open the link. Delete the message.'],
    );

ScamAnalysisResult _clean() => ScamAnalysisResult(
      id: '2',
      contentType: ScamContentType.text,
      content: 'See you at six',
      isScam: false,
      confidence: 0.04,
      riskScore: 0.04,
      severity: 'none',
    );

/// A stand-in analyser that records what it was asked and answers when told.
class _FakeAnalyser {
  final List<String> asked = [];
  Completer<ScamAnalysisResult?> _next = Completer();

  Future<ScamAnalysisResult?> call(BuildContext context, String input) {
    asked.add(input);
    _next = Completer();
    return _next.future;
  }

  void answer(ScamAnalysisResult? result) => _next.complete(result);
  void fail() => _next.completeError(StateError('backend down'));
}

void main() {
  setUpAll(loadRealFonts);

  Future<void> pump(
    WidgetTester tester,
    _FakeAnalyser fake, {
    double width = 390,
    bool dark = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.reset);
    AppColors.uiBrightness = dark ? Brightness.dark : Brightness.light;
    addTearDown(() => AppColors.uiBrightness = Brightness.dark);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        backgroundColor: Brand.bg,
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: PasteCard(analyse: fake.call),
        ),
      ),
    ));
  }

  Finder button(String label) => find
      .ancestor(of: find.text(label), matching: find.byType(GestureDetector))
      .first;

  /// Nothing overflows and no line of text is cut short.
  void expectFits(WidgetTester tester) {
    expect(tester.takeException(), isNull);
    for (final RenderParagraph p
        in tester.allRenderObjects.whereType<RenderParagraph>()) {
      expect(p.didExceedMaxLines, isFalse,
          reason: 'cut off: "${p.text.toPlainText()}"');
    }
  }

  testWidgets('starts empty, with the hint and "Check it" disabled',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    expect(find.text('Paste a link, message or number'), findsOneWidget);
    expect(find.text('Try an example'), findsOneWidget);
    await tester.tap(find.text('Check it'));
    await tester.pump();
    expect(fake.asked, isEmpty);
  });

  testWidgets('"Try an example" fills in the sample and checks nothing',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    await tester.tap(find.text('Try an example'));
    await tester.pump();

    expect(find.text(PasteVerdict.sample), findsOneWidget);
    expect(fake.asked, isEmpty);
  });

  testWidgets('"Check it" hands what was pasted to the analyser, and says so',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    await tester.enterText(find.byType(TextField), PasteVerdict.sample);
    await tester.pump();
    await tester.tap(find.text('Check it'));
    await tester.pump();

    expect(fake.asked, [PasteVerdict.sample]);
    expect(find.text('Checking this message'), findsOneWidget);

    // A second press while one check runs starts nothing.
    await tester.tap(find.text('Check it'));
    await tester.pump();
    expect(fake.asked, hasLength(1));

    fake.answer(_clean());
    await tester.pump();
  });

  testWidgets('a link is announced as a link while it is checked',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    await tester.enterText(find.byType(TextField), 'example.com/login');
    await tester.pump();
    await tester.tap(find.text('Check it'));
    await tester.pump();
    expect(find.text('Checking this link'), findsOneWidget);
    fake.answer(_clean());
    await tester.pump();
  });

  testWidgets('a scam verdict shows its reasons and what to do',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    await tester.tap(find.text('Try an example'));
    await tester.pump();
    await tester.tap(find.text('Check it'));
    await tester.pump();
    fake.answer(_scam());
    await tester.pump();

    expect(find.text('This looks like a scam'), findsOneWidget);
    expect(find.text('The link is not a real carrier address'), findsOneWidget);
    expect(find.text('It pushes you to pay fast'), findsOneWidget);
    expect(
        find.text('Do not open the link. Delete the message.'), findsOneWidget);
    expect(find.text('Checking this message'), findsNothing);

    // One way on: clear the card. "Check it" steps aside.
    expect(find.text('Check it'), findsNothing);
    await tester.tap(find.text('Check something else'));
    await tester.pump();

    expect(find.text('This looks like a scam'), findsNothing);
    expect(find.text('Paste a link, message or number'), findsOneWidget);
    expect(find.text('Check it'), findsOneWidget);
  });

  testWidgets('a clean verdict says what was checked, and never "safe"',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    await tester.enterText(find.byType(TextField), 'See you at six');
    await tester.pump();
    await tester.tap(find.text('Check it'));
    await tester.pump();
    fake.answer(_clean());
    await tester.pump();

    expect(find.text('No signs of a scam found'), findsOneWidget);
    expect(find.text('Checked this message for the signs of a scam.'),
        findsOneWidget);
    expect(find.textContaining(RegExp('safe', caseSensitive: false)),
        findsNothing);
    expect(find.text('Check something else'), findsOneWidget);
  });

  testWidgets('no answer is said plainly, and "Try again" asks again',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    await tester.enterText(find.byType(TextField), 'See you at six');
    await tester.pump();
    await tester.tap(find.text('Check it'));
    await tester.pump();
    fake.answer(null);
    await tester.pump();

    expect(find.text('Could not check this'), findsOneWidget);
    expect(find.text('No signs of a scam found'), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(fake.asked, ['See you at six', 'See you at six']);
    expect(find.text('Checking this message'), findsOneWidget);
    fake.answer(_clean());
    await tester.pump();
  });

  testWidgets('an analyser that throws is a check that did not run',
      (tester) async {
    final _FakeAnalyser fake = _FakeAnalyser();
    await pump(tester, fake);

    await tester.enterText(find.byType(TextField), 'See you at six');
    await tester.pump();
    await tester.tap(find.text('Check it'));
    await tester.pump();
    fake.fail();
    await tester.pump();

    expect(find.text('Could not check this'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  group('an analyser that never answers', () {
    // Seen on a phone with a slow connection: the request retried for
    // minutes, and the card said "Checking this message" the whole time.
    testWidgets('is waited for, for a while', (tester) async {
      final _FakeAnalyser fake = _FakeAnalyser();
      await pump(tester, fake);

      await tester.enterText(find.byType(TextField), 'See you at six');
      await tester.pump();
      await tester.tap(find.text('Check it'));
      await tester.pump();
      await tester.pump(PasteCard.patience - const Duration(milliseconds: 500));

      expect(find.text('Checking this message'), findsOneWidget);
      expect(find.text('Could not check this'), findsNothing);

      fake.answer(_clean());
      // One pump lets the answer in, the next one draws it.
      await tester.pump();
      await tester.pump();
      expect(find.text('No signs of a scam found'), findsOneWidget);
    });

    testWidgets('is owned up to while it is slow', (tester) async {
      final _FakeAnalyser fake = _FakeAnalyser();
      await pump(tester, fake);
      const String note = 'Still checking. This can take up to a minute.';

      await tester.enterText(find.byType(TextField), 'See you at six');
      await tester.pump();
      await tester.tap(find.text('Check it'));
      await tester.pump();
      await tester
          .pump(PasteCard.slowAfter - const Duration(milliseconds: 500));
      expect(find.text(note), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Checking this message'), findsOneWidget);
      expect(find.text(note), findsOneWidget);
      expectFits(tester);

      fake.answer(_clean());
      await tester.pump();
      await tester.pump();
      expect(find.text(note), findsNothing);
      expect(find.text('No signs of a scam found'), findsOneWidget);
    });

    testWidgets('the next check starts without the slow note', (tester) async {
      final _FakeAnalyser fake = _FakeAnalyser();
      await pump(tester, fake);
      const String note = 'Still checking. This can take up to a minute.';

      await tester.enterText(find.byType(TextField), 'See you at six');
      await tester.pump();
      await tester.tap(find.text('Check it'));
      await tester.pump();
      await tester.pump(PasteCard.slowAfter + const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(note), findsOneWidget);
      fake.answer(null);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.text('Checking this message'), findsOneWidget);
      expect(find.text(note), findsNothing);
      fake.answer(_clean());
      await tester.pump();
      await tester.pump();
    });

    test('the wait is long enough for the real analyser', () {
      // Measured on a phone: a first answer took 31 seconds.
      expect(PasteCard.patience,
          greaterThanOrEqualTo(const Duration(seconds: 45)));
      expect(PasteCard.slowAfter, lessThan(PasteCard.patience));
    });

    testWidgets('is given up on, and said plainly', (tester) async {
      final _FakeAnalyser fake = _FakeAnalyser();
      await pump(tester, fake);

      await tester.enterText(find.byType(TextField), 'See you at six');
      await tester.pump();
      await tester.tap(find.text('Check it'));
      await tester.pump();
      await tester.pump(PasteCard.patience + const Duration(milliseconds: 500));
      await tester.pump();

      expect(find.text('Checking this message'), findsNothing);
      expect(find.text('Could not check this'), findsOneWidget);
      // It was slow, not unreachable: the words say which.
      expect(find.textContaining('took too long to answer'), findsOneWidget);
      expect(find.textContaining('connection'), findsNothing);
      expect(find.text('No signs of a scam found'), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expectFits(tester);
    });

    testWidgets('a late answer does not replace what was said', (tester) async {
      final _FakeAnalyser fake = _FakeAnalyser();
      await pump(tester, fake);

      await tester.enterText(find.byType(TextField), 'See you at six');
      await tester.pump();
      await tester.tap(find.text('Check it'));
      await tester.pump();
      await tester.pump(PasteCard.patience + const Duration(milliseconds: 500));
      await tester.pump();
      fake.answer(_clean());
      await tester.pump();
      await tester.pump();

      expect(find.text('Could not check this'), findsOneWidget);
      expect(find.text('No signs of a scam found'), findsNothing);
    });
  });

  for (final bool dark in [true, false]) {
    for (final double width in [390.0, 320.0]) {
      final String where = '${width.toInt()} wide, ${dark ? 'dark' : 'light'}';

      testWidgets('every state fits at $where', (tester) async {
        final _FakeAnalyser fake = _FakeAnalyser();
        await pump(tester, fake, width: width, dark: dark);
        expectFits(tester);

        await tester.tap(find.text('Try an example'));
        await tester.pump();
        expectFits(tester);

        await tester.tap(button('Check it'));
        await tester.pump();
        expectFits(tester);

        fake.answer(_scam());
        await tester.pump();
        expectFits(tester);

        await tester.tap(find.text('Check something else'));
        await tester.pump();
        await tester.tap(find.text('Try an example'));
        await tester.pump();
        await tester.tap(find.text('Check it'));
        await tester.pump();
        fake.answer(null);
        await tester.pump();
        expectFits(tester);

        await tester.tap(find.text('Try again'));
        await tester.pump();
        fake.answer(_clean());
        await tester.pump();
        expectFits(tester);
      });
    }
  }
}
