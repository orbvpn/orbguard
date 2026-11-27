// The share card: a result someone can send a friend. It says only what an
// all clear from today says, in the first person, under the same whole ring
// Home shows, and ends on the question that brings the friend in.
//
// It is offered only after a check that ran clean today, with no gap left
// open and nothing that broke, so it can never say more than Home does.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../../presentation/theme/brand.dart';
import '../../presentation/widgets/app_sheet.dart';
import '../../presentation/widgets/brand_button.dart';
import 'orb_ring.dart';

/// Hands a picture of the card to the system's share sheet. [origin] is
/// where the share sheet points from on an iPad or a Mac.
typedef ShareImage = Future<void> Function(Uint8List png, {Rect? origin});

/// The system's share sheet. Tests put a recorder here.
ShareImage shareResultImage = _systemShare;

Future<void> _systemShare(Uint8List png, {Rect? origin}) async {
  await SharePlus.instance.share(ShareParams(
    files: [
      XFile.fromData(png, mimeType: 'image/png', name: 'orbguard-result.png'),
    ],
    fileNameOverrides: const ['orbguard-result.png'],
    sharePositionOrigin: origin,
  ));
}

/// The card itself, the same in the sheet and in the picture sent.
class ShareCard extends StatelessWidget {
  const ShareCard({super.key});

  static const String headline = 'No signs I am being watched.';
  static const String when = 'Checked today with OrbGuard';
  static const String question = 'Is your circle closed?';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Brand tokens flip with the theme
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Brand.glassBorder),
        ),
        child: Stack(
          children: [
            const BrandBed(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const ExcludeSemantics(
                    child: OrbRing(status: OrbStatus.whole(), size: 104),
                  ),
                  const SizedBox(height: 20),
                  Text(headline,
                      textAlign: TextAlign.center,
                      style: BrandText.heading(size: 18, color: Brand.text)
                          .copyWith(height: 1.22)),
                  const SizedBox(height: 8),
                  Text(when,
                      textAlign: TextAlign.center,
                      style: BrandText.body(size: 13.5, color: Brand.text2)
                          .copyWith(height: 1.45)),
                  const SizedBox(height: 20),
                  Text(question,
                      textAlign: TextAlign.center,
                      style: BrandText.heading(size: 15, color: Brand.text)
                          .copyWith(height: 1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Share your result": the card as it will be sent, and one lime Share.
class ShareSheet extends StatefulWidget {
  const ShareSheet({super.key});

  static Future<void> show(BuildContext context) =>
      showAppSheet<void>(context, child: const ShareSheet());

  @override
  State<ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<ShareSheet> {
  final GlobalKey _card = GlobalKey();
  final GlobalKey _button = GlobalKey();
  bool _sharing = false;

  /// The card at three times its size, as a PNG.
  Future<Uint8List?> _picture() async {
    final RenderObject? box = _card.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary) return null;
    final ui.Image image = await box.toImage(pixelRatio: 3);
    try {
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Rect? _origin() {
    final RenderObject? box = _button.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final Uint8List? png = await _picture();
      if (png != null) await shareResultImage(png, origin: _origin());
    } on Object catch (e) {
      debugPrint('[OrbGuard] The result was not shared: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      padding: EdgeInsets.fromLTRB(
          22, 20, 22, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Share your result',
                style: BrandText.h2(color: cs.onSurface, size: 23)),
          ),
          const SizedBox(height: 16),
          RepaintBoundary(key: _card, child: const ShareCard()),
          const SizedBox(height: 16),
          BrandButton(
            key: _button,
            label: 'Share',
            isLoading: _sharing,
            onPressed: _sharing ? null : _share,
          ),
        ],
      ),
    );
  }
}
