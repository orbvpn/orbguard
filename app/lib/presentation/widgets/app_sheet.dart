import 'package:flutter/material.dart';

/// The app's ONE modal presentation: every pop-up slides up as an iOS-style
/// sheet — rounded top, a drag handle, drag-to-dismiss, and the parent left
/// visible behind — never a full-screen push or a centered dialog.
///
/// - Full-screen content (a results page, a detail screen) → pass a
///   [heightFactor] (e.g. 0.94) and the sheet takes that fraction of the
///   screen height, with the parent peeking at the top.
/// - Small content (a confirm, an info card) → omit [heightFactor] and the
///   sheet sizes to its content.
///
/// [child] renders inside the rounded, clipped sheet surface; a full page's
/// own header/scaffold still works within it.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget child,
  double? heightFactor,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (ctx) {
      final handle = Container(
        width: 38,
        height: 4,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(3),
        ),
      );
      final surface = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: child,
      );

      // Full-screen content: an explicit fraction of the screen height (with
      // a bounded box so the inner Expanded is unambiguous). Small content:
      // shrink-wrap to the child.
      if (heightFactor != null) {
        final h = MediaQuery.of(ctx).size.height * heightFactor.clamp(0.3, 0.98);
        return SizedBox(
          height: h,
          child: Column(
            children: [handle, Expanded(child: surface)],
          ),
        );
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [handle, Flexible(child: surface)],
      );
    },
  );
}
