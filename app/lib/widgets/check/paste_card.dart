/// The paste card on the Check tab: paste a link, a message or a number, and
/// the scam shield's own analyser judges it.
///
/// It calls the same [ScamDetectionProvider.analyzeContent] the Scam shield
/// screen does, and draws its answer through [PasteVerdict], which adds no
/// judgement of its own. "Check it" is the Check tab's one lime action.
///
/// A check here is one a person starts, so it goes through the scan-credit
/// gate first. A check that got no answer is not paid for twice: trying
/// again, or checking something else, rides on what was already paid.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/theme/colors.dart';
import '../../presentation/widgets/brand_button.dart';
import '../../presentation/widgets/duotone_icon.dart';
import '../../presentation/widgets/glass_rows.dart';
import '../../providers/scam_detection_provider.dart';
import '../../utils/device_words.dart';
import '../scan_credits/scan_gate.dart';
import 'paste_verdict.dart';

/// Judges what was pasted. Null, or a throw, is no answer.
typedef PasteAnalyser = Future<ScamAnalysisResult?> Function(
    BuildContext context, String input);

/// The real analyser: the scam shield's, asked about a link as a link, a
/// number as a number and anything else as a message. It needs the network;
/// when OrbGuard cannot be reached it falls back to its on-device rules and
/// marks the answer offline.
Future<ScamAnalysisResult?> scamShieldAnalyser(
    BuildContext context, String input) {
  final String content = input.trim();
  return context.read<ScamDetectionProvider>().analyzeContent(
        type: PasteKind.of(content).contentType,
        content: content,
      );
}

class PasteCard extends StatefulWidget {
  const PasteCard({super.key, this.analyse});

  /// How long an answer is waited for. The analyser reads the message with
  /// a language model, and a first answer was measured at 31 seconds on a
  /// phone; on a bad connection the request behind it retries for minutes.
  /// After this long the card says it could not check.
  static const Duration patience = Duration(seconds: 60);

  /// When a check still running starts to say that it is slow.
  static const Duration slowAfter = Duration(seconds: 8);

  /// Stands in for [scamShieldAnalyser], for tests.
  final PasteAnalyser? analyse;

  @override
  State<PasteCard> createState() => _PasteCardState();
}

enum _Phase { editing, checking, answered }

class _PasteCardState extends State<PasteCard> {
  final TextEditingController _text = TextEditingController();
  _Phase _phase = _Phase.editing;
  PasteVerdict? _verdict;
  PasteKind _kind = PasteKind.message;

  /// Counts checks, so an answer that arrives after the card was cleared is
  /// dropped.
  int _run = 0;

  /// The check under way has been running long enough to say so.
  bool _slow = false;
  Timer? _slowTimer;

  /// The gate let a check through that has not had an answer yet.
  bool _paid = false;

  /// The gate is deciding: a second press starts nothing.
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText);
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _text
      ..removeListener(_onText)
      ..dispose();
    super.dispose();
  }

  void _onText() => setState(() {});

  bool get _hasText => _text.text.trim().isNotEmpty;

  void _example() {
    _text.text = PasteVerdict.sample;
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  }

  Future<void> _check() async {
    if (!_hasText || _phase == _Phase.checking || _asking) return;
    FocusScope.of(context).unfocus();
    if (!_paid) {
      _asking = true;
      final bool go;
      try {
        go = await ensureScanCredit(context);
      } finally {
        _asking = false;
      }
      if (!go || !mounted) return;
      _paid = true;
    }
    final String input = _text.text;
    final PasteKind kind = PasteKind.of(input);
    final int run = ++_run;
    setState(() {
      _phase = _Phase.checking;
      _kind = kind;
      _verdict = null;
      _slow = false;
    });
    _slowTimer?.cancel();
    _slowTimer = Timer(PasteCard.slowAfter, () {
      if (mounted && run == _run && _phase == _Phase.checking) {
        setState(() => _slow = true);
      }
    });

    ScamAnalysisResult? result;
    bool late = false;
    try {
      result = await (widget.analyse ?? scamShieldAnalyser)(context, input)
          .timeout(PasteCard.patience);
    } on TimeoutException {
      late = true;
    } catch (_) {
      // It threw: nothing was judged.
      result = null;
    }
    if (!mounted || run != _run) return;
    _slowTimer?.cancel();
    final PasteVerdict verdict = late
        ? PasteVerdict.late
        : PasteVerdict.from(result, kind, noun: DeviceWords.noun);
    // Paid for until it is answered.
    if (verdict.tone != PasteTone.failed) _paid = false;
    setState(() {
      _phase = _Phase.answered;
      _slow = false;
      _verdict = verdict;
    });
  }

  void _clear() {
    _run++;
    _slowTimer?.cancel();
    _text.clear();
    setState(() {
      _phase = _Phase.editing;
      _slow = false;
      _verdict = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    final PasteVerdict? verdict = _verdict;
    final bool editing = _phase == _Phase.editing;

    return BrandGlass(
      radius: 24,
      elevated: false,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(controller: _text, readOnly: !editing),
          Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_phase == _Phase.checking)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 14, 2, 2),
                    child: _Checking(
                      text: 'Checking this ${_kind.noun}',
                      // True by the card's own rule: at [PasteCard.patience]
                      // it stops waiting and says so.
                      note: _slow
                          ? 'Still checking. This can take up to a minute.'
                          : null,
                    ),
                  ),
                if (verdict != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _VerdictTile(verdict: verdict),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (verdict == null)
            _ButtonPair(
              glass: 'Try an example',
              onGlass: editing ? _example : null,
              lime: 'Check it',
              onLime: editing && _hasText ? _check : null,
            )
          else if (verdict.tone == PasteTone.failed)
            _ButtonPair(
              glass: 'Check something else',
              onGlass: _clear,
              lime: 'Try again',
              onLime: _check,
            )
          else
            BrandButton.secondary(
              label: 'Check something else',
              onPressed: _clear,
              padding: _ButtonPair.padding,
            ),
        ],
      ),
    );
  }
}

/// The paste box: the kit's `.paste-box`, a hairline well for the text.
class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.readOnly});

  final TextEditingController controller;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final OutlineInputBorder edge = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Brand.rMd),
      borderSide: BorderSide(color: Brand.border),
    );
    return TextField(
      controller: controller,
      readOnly: readOnly,
      minLines: 3,
      maxLines: 6,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      style: BrandText.body(size: 15, color: Brand.text)
          .copyWith(height: Brand.bodyHeight(1.45)),
      cursorColor: Brand.focus,
      decoration: InputDecoration(
        hintText: 'Paste a link, message or number',
        hintStyle:
            BrandText.body(size: 15).copyWith(height: Brand.bodyHeight(1.45)),
        hintMaxLines: 2,
        filled: true,
        fillColor: Brand.hairline,
        isDense: true,
        contentPadding: const EdgeInsets.all(14),
        border: edge,
        enabledBorder: edge,
        disabledBorder: edge,
        focusedBorder: edge.copyWith(
            borderSide: BorderSide(color: Brand.focus, width: 1.5)),
      ),
    );
  }
}

/// A line with a small lime dot: something is running.
class _Checking extends StatelessWidget {
  const _Checking({required this.text, this.note});

  final String text;

  /// A second, quieter line under [text], lined up with its words.
  final String? note;

  @override
  Widget build(BuildContext context) {
    final String? note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(shape: BoxShape.circle, color: Brand.limeInk),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: BrandText.body(size: 14, weight: FontWeight.w500)
                      .copyWith(height: Brand.bodyHeight(1.42))),
            ),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(left: 15, top: 2),
            child: Text(note,
                style: BrandText.body(size: 13.5, color: Brand.text2)
                    .copyWith(height: Brand.bodyHeight(1.45))),
          ),
      ],
    );
  }
}

/// The answer, in the kit's `.verdict-card`: amber for a warning, lime for
/// no signs found, plain for no answer.
class _VerdictTile extends StatelessWidget {
  const _VerdictTile({required this.verdict});

  final PasteVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final PasteVerdict v = verdict;
    final String? body = v.body;
    final String? note = v.note;
    final (Color fill, Color line, Color tile, Color ink, String icon) =
        switch (v.tone) {
      PasteTone.warn => (
          Brand.amberPill,
          Brand.amberLine,
          Brand.amberPill,
          Brand.amberInk,
          AppIcons.dangerTriangle,
        ),
      PasteTone.calm => (
          AppColors.accentPill,
          Brand.border,
          AppColors.accentPill,
          Brand.limeInk,
          AppIcons.checkCircle,
        ),
      PasteTone.failed => (
          Brand.hairline,
          Brand.border,
          Brand.hairline,
          Brand.text2,
          AppIcons.infoCircle,
        ),
    };
    final TextStyle small =
        BrandText.body(size: 13.5).copyWith(height: Brand.bodyHeight(1.4));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Brand.rMd),
        border: Border.all(color: line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: icon, color: ink, fill: tile),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.title,
                    style: BrandText.title(size: 16)
                        .copyWith(height: Brand.displayHeight(1.3))),
                if (body != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(body, style: small),
                  ),
                if (v.reasons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final String r in v.reasons)
                          _Reason(text: r, dot: ink, style: small),
                      ],
                    ),
                  ),
                for (final String a in v.advice)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(a, style: small.copyWith(color: Brand.text)),
                  ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(note, style: small),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({required this.text, required this.dot, required this.style});

  final String text;
  final Color dot;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(top: 8, right: 9),
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}

/// A glass button and a lime one, side by side, or one over the other when
/// a label would not fit beside the other.
class _ButtonPair extends StatelessWidget {
  const _ButtonPair({
    required this.glass,
    required this.onGlass,
    required this.lime,
    required this.onLime,
  });

  final String glass;
  final VoidCallback? onGlass;
  final String lime;
  final VoidCallback? onLime;

  /// The kit's small button: 44 tall.
  static const EdgeInsets padding =
      EdgeInsets.symmetric(horizontal: 14, vertical: 11);
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    final Widget left = BrandButton.secondary(
        label: glass, onPressed: onGlass, padding: padding);
    final Widget right =
        BrandButton(label: lime, onPressed: onLime, padding: padding);

    return LayoutBuilder(builder: (context, constraints) {
      final TextScaler scaler = MediaQuery.textScalerOf(context);
      double need(String label) {
        final TextPainter p = TextPainter(
          text: TextSpan(
              text: label,
              style: BrandText.title(size: 16, weight: FontWeight.w700)),
          textDirection: Directionality.of(context),
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final double w = p.width;
        p.dispose();
        return w + padding.horizontal + 2;
      }

      final double half = (constraints.maxWidth - _gap) / 2;
      if (need(glass) <= half && need(lime) <= half) {
        return Row(
          children: [
            Expanded(child: left),
            const SizedBox(width: _gap),
            Expanded(child: right),
          ],
        );
      }
      // The lime action goes first when they stack: it is the one to see.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [right, const SizedBox(height: _gap), left],
      );
    });
  }
}
