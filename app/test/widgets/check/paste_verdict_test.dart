// What the paste card says about one answer from the scam shield's analyser.
// The card adds no judgement of its own: every word of a verdict is either
// the analyser's, or a plain reading of the analyser's own fields.

import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/providers/scam_detection_provider.dart';
import 'package:orbguard/widgets/check/paste_verdict.dart';

ScamAnalysisResult _result({
  bool isScam = false,
  double risk = 0,
  String? severity,
  List<String> reasons = const [],
  String? explanation,
  List<String> tips = const [],
  bool offline = false,
  ScamContentType type = ScamContentType.text,
}) =>
    ScamAnalysisResult(
      id: '1',
      contentType: type,
      content: 'x',
      isScam: isScam,
      confidence: risk,
      riskScore: risk,
      severity: severity,
      indicatorDetails: [
        for (final String r in reasons)
          ScamIndicator(type: 't', description: r, confidence: 0.5),
      ],
      explanation: explanation,
      recommendations: tips,
      offline: offline,
    );

void main() {
  group('what was pasted', () {
    test('a bare link is checked as a link', () {
      expect(
          PasteKind.of('parcel-fee-redelivery.example/track'), PasteKind.link);
      expect(PasteKind.of('  https://example.com/a?b=1 '), PasteKind.link);
      expect(PasteKind.link.contentType, ScamContentType.url);
    });

    test('a bare number is checked as a number', () {
      expect(PasteKind.of('+44 20 7946 0958'), PasteKind.number);
      expect(PasteKind.of('(555) 010-4477'), PasteKind.number);
      expect(PasteKind.number.contentType, ScamContentType.phone);
    });

    test('anything else is checked as a message', () {
      expect(PasteKind.of(PasteVerdict.sample), PasteKind.message);
      expect(PasteKind.of('call me 12'), PasteKind.message);
      expect(PasteKind.of('1234'), PasteKind.message);
      expect(PasteKind.message.contentType, ScamContentType.text);
    });
  });

  group('the verdict', () {
    test('a scam is called a scam, with the analyser\'s own reasons and advice',
        () {
      final PasteVerdict v = PasteVerdict.from(
        _result(
          isScam: true,
          risk: 0.9,
          severity: 'high',
          reasons: ['Urgent payment request', 'Lookalike domain'],
          tips: ['Do not click any links'],
        ),
        PasteKind.message,
      );
      expect(v.tone, PasteTone.warn);
      expect(v.title, 'This looks like a scam');
      expect(v.reasons, ['Urgent payment request', 'Lookalike domain']);
      expect(v.advice, ['Do not click any links']);
      expect(v.note, isNull);
    });

    test('repeated reasons are listed once, and at most three', () {
      final PasteVerdict v = PasteVerdict.from(
        _result(isScam: true, risk: 0.9, reasons: ['a', 'a', 'b', 'c', 'd']),
        PasteKind.message,
      );
      expect(v.reasons, ['a', 'b', 'c']);
    });

    test('with no reasons, the analyser\'s explanation is the reason', () {
      final PasteVerdict v = PasteVerdict.from(
        _result(isScam: true, risk: 0.8, explanation: 'Known scam wording'),
        PasteKind.message,
      );
      expect(v.reasons, ['Known scam wording']);
    });

    test('with no advice from the analyser, says what to do with the thing',
        () {
      expect(
          PasteVerdict.from(_result(isScam: true, risk: 1), PasteKind.link)
              .advice,
          ['Do not open the link.']);
      expect(
          PasteVerdict.from(_result(isScam: true, risk: 1), PasteKind.number)
              .advice,
          ['Do not call it back or answer it.']);
      expect(
          PasteVerdict.from(_result(isScam: true, risk: 1), PasteKind.message)
              .advice,
          ['Do not open any link in it, and do not reply.']);
    });

    test('an answer that did not come in time blames no connection', () {
      const PasteVerdict v = PasteVerdict.late;

      expect(v.tone, PasteTone.failed);
      expect(v.title, 'Could not check this');
      expect(
          v.body,
          'The scam check took too long to answer, so nothing was judged. '
          'Try again in a moment.');
      expect(v.body, isNot(contains('connection')));
      expect(v.reasons, isEmpty);
    });

    // The analyser opens its advice with a line that only restates the
    // verdict, marked with a warning sign. The card's title already says it.
    test('the analyser\'s alert line is not advice', () {
      final PasteVerdict v = PasteVerdict.from(
        _result(isScam: true, risk: 0.9, tips: const [
          '\u26a0\ufe0f HIGH ALERT: This appears to be a scam.',
          'Do not engage with this content.',
          'Report this to the relevant authorities.',
        ]),
        PasteKind.message,
      );

      expect(v.advice, [
        'Do not engage with this content.',
        'Report this to the relevant authorities.',
      ]);
    });

    test('when the alert line is all the analyser said, the card advises', () {
      final PasteVerdict v = PasteVerdict.from(
        _result(risk: 0.5, severity: 'medium', tips: const [
          '\u26a0\ufe0f This content has suspicious characteristics.',
        ]),
        PasteKind.link,
      );

      expect(v.advice, ['Do not open the link.']);
    });

    test('a risk the analyser rates but does not call a scam is suspicious',
        () {
      final PasteVerdict v = PasteVerdict.from(
          _result(risk: 0.5, severity: 'medium'), PasteKind.message);
      expect(v.tone, PasteTone.warn);
      expect(v.title, 'This looks suspicious');
    });

    test('a clean answer says no signs were found, and what was checked', () {
      final PasteVerdict v = PasteVerdict.from(
          _result(risk: 0.05, severity: 'none'), PasteKind.link);
      expect(v.tone, PasteTone.calm);
      expect(v.title, 'No signs of a scam found');
      expect(v.body, 'Checked this link for the signs of a scam.');
      expect(v.title.toLowerCase(), isNot(contains('safe')));
      expect(v.body!.toLowerCase(), isNot(contains('safe')));
    });

    test('no answer at all is a check that did not run', () {
      final PasteVerdict v = PasteVerdict.from(null, PasteKind.message);
      expect(v.tone, PasteTone.failed);
      expect(v.title, 'Could not check this');
      expect(v.body, contains('nothing was judged'));
      expect(v.reasons, isEmpty);
    });

    test('a scam found offline still warns, and says how it was checked', () {
      final PasteVerdict v = PasteVerdict.from(
        _result(isScam: true, risk: 0.6, offline: true),
        PasteKind.message,
      );
      expect(v.tone, PasteTone.warn);
      expect(
          v.note,
          'Checked on this phone only. The full check could not '
          'be reached.');
    });

    test('a clean answer from the offline fallback is never shown as clean',
        () {
      final PasteVerdict v = PasteVerdict.from(
        _result(risk: 0.1, severity: 'none', offline: true),
        PasteKind.message,
      );
      expect(v.tone, PasteTone.failed);
      expect(v.title, 'Could not check this');
      expect(v.body, contains('not the same as a full check'));
    });
  });
}
