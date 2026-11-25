/// What the paste card says about one answer from the scam shield's
/// analyser ([ScamDetectionProvider.analyzeContent]).
///
/// It adds no judgement of its own. A scam is what the analyser calls a
/// scam; a warning is a risk the analyser rated; "no signs" is only ever an
/// answer the full analyser gave. No answer, or an answer from the offline
/// fallback that found nothing, is a check that did not run, and says so.
library;

import '../../providers/scam_detection_provider.dart';

/// What was pasted, as the analyser is asked about it.
enum PasteKind {
  link(ScamContentType.url, 'link'),
  number(ScamContentType.phone, 'number'),
  message(ScamContentType.text, 'message');

  const PasteKind(this.contentType, this.noun);

  /// How the analyser is asked about it.
  final ScamContentType contentType;

  /// The word for it in a sentence: "this link".
  final String noun;

  static final RegExp _link = RegExp(
    r'^(https?://)?([a-z0-9-]+\.)+[a-z]{2,}(:\d+)?([/?#]\S*)?$',
    caseSensitive: false,
  );
  static final RegExp _number = RegExp(r'^\+?[\d\s().-]+$');

  /// A bare link is a link, a bare number of seven digits or more is a
  /// number, and anything else is a message.
  static PasteKind of(String input) {
    final String s = input.trim();
    if (_link.hasMatch(s)) return link;
    if (_number.hasMatch(s) && RegExp(r'\d').allMatches(s).length >= 7) {
      return number;
    }
    return message;
  }
}

enum PasteTone {
  /// The analyser called it a scam, or rated a risk in it.
  warn,

  /// The full analyser ran and rated no risk.
  calm,

  /// No real answer came back.
  failed,
}

class PasteVerdict {
  const PasteVerdict._({
    required this.tone,
    required this.title,
    this.body,
    this.reasons = const [],
    this.advice = const [],
    this.note,
  });

  /// The example "Try an example" puts in the field. The analyser judges it
  /// like anything else.
  static const String sample = 'Your parcel is on hold. Pay the 1.99 fee '
      'today or it goes back: parcel-fee-redelivery.example/track';

  final PasteTone tone;
  final String title;

  /// A plain sentence under the title, when there is one.
  final String? body;

  /// The analyser's own reasons, at most three.
  final List<String> reasons;

  /// What to do about it.
  final List<String> advice;

  /// How it was checked, when that is not the usual way.
  final String? note;

  /// The analyser was asked and did not answer in time. It was slow, not
  /// out of reach, so the words do not send the person to their connection.
  static const PasteVerdict late = PasteVerdict._(
    tone: PasteTone.failed,
    title: 'Could not check this',
    body: 'The scam check took too long to answer, so nothing was judged. '
        'Try again in a moment.',
  );

  /// Reads [result], the answer about something of [kind]. Null is no
  /// answer. [noun] names this device in the offline note.
  factory PasteVerdict.from(
    ScamAnalysisResult? result,
    PasteKind kind, {
    String noun = 'phone',
  }) {
    if (result == null) {
      return const PasteVerdict._(
        tone: PasteTone.failed,
        title: 'Could not check this',
        body: 'OrbGuard could not reach its scam check, so nothing was '
            'judged. Check your connection and try again.',
      );
    }

    final bool rated = result.isScam || result.riskLevel != 'Safe';
    if (!rated) {
      if (result.offline) {
        // The fallback on the device is a few keyword rules. Finding none of
        // them is not a clean result.
        return PasteVerdict._(
          tone: PasteTone.failed,
          title: 'Could not check this',
          body: 'OrbGuard could not reach its scam check. A quick look on '
              'this $noun found no warning signs, but that is not the same '
              'as a full check.',
        );
      }
      final String? explanation = result.explanation;
      return PasteVerdict._(
        tone: PasteTone.calm,
        title: 'No signs of a scam found',
        body: 'Checked this ${kind.noun} for the signs of a scam.',
        reasons: [if (explanation != null) explanation],
      );
    }

    final List<String> reasons = <String>{
      for (final ScamIndicator i in result.indicatorDetails)
        if (i.description.trim().isNotEmpty) i.description.trim(),
    }.take(3).toList();
    final String? explanation = result.explanation;
    if (reasons.isEmpty && explanation != null) reasons.add(explanation);

    // The analyser opens its advice with a line that only restates the
    // verdict, marked with a warning sign. The title above already says it,
    // so that line is not advice.
    final List<String> tips = result.recommendations
        .map((String t) => t.trim())
        .where((String t) => t.isNotEmpty && !t.startsWith('\u26a0'))
        .take(2)
        .toList();

    return PasteVerdict._(
      tone: PasteTone.warn,
      title: result.isScam ? 'This looks like a scam' : 'This looks suspicious',
      reasons: reasons,
      advice: tips.isNotEmpty ? tips : [_advice(kind)],
      note: result.offline
          ? 'Checked on this $noun only. The full check could not be reached.'
          : null,
    );
  }

  static String _advice(PasteKind kind) => switch (kind) {
        PasteKind.link => 'Do not open the link.',
        PasteKind.number => 'Do not call it back or answer it.',
        PasteKind.message => 'Do not open any link in it, and do not reply.',
      };
}
