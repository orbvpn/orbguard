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
///
/// Under a [SheetHost] the sheet opens where the host says: in one pane of a
/// foldable or a tablet, or as a centred column in a desktop window.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget child,
  double? heightFactor,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  final SheetHost? host = SheetHost._of(context);
  final BuildContext? pane = host?.navigator?.currentContext;
  final double? maxWidth = host?.maxWidth;
  final double most = host?.maxHeightFactor ?? 0.98;
  return showModalBottomSheet<T>(
    context: pane ?? context,
    // A desktop window's sheet is the window's, not the column's that asked.
    useRootNavigator: host != null && pane == null,
    isScrollControlled: true,
    constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth),
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
        final h = MediaQuery.of(ctx).size.height *
            heightFactor.clamp(0.3, most < 0.3 ? 0.3 : most);
        return SizedBox(
          height: h,
          child: Column(
            children: [handle, Expanded(child: surface)],
          ),
        );
      }
      final Widget hug = Column(
        mainAxisSize: MainAxisSize.min,
        children: [handle, Flexible(child: surface)],
      );
      // A host that caps the height caps a sheet that hugs its content too.
      if (host?.maxHeightFactor == null) return hug;
      return ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * most),
        child: hug,
      );
    },
  );
}

/// Says where the sheets under it open.
///
/// The shell puts one above both panes of a foldable or a tablet, naming the
/// pane sheets belong to, so a sheet never lies across the hinge whichever
/// pane asked for it. On a desktop window it keeps a sheet to a centred
/// column, as tall as [maxHeightFactor] of the window at most.
class SheetHost extends InheritedWidget {
  const SheetHost({
    super.key,
    this.navigator,
    this.maxWidth,
    this.maxHeightFactor,
    required super.child,
  });

  /// The navigator of the pane sheets open in. Null is the app's own.
  final GlobalKey<NavigatorState>? navigator;

  /// The widest a sheet may be. Null lets it span its pane.
  final double? maxWidth;

  /// The tallest a sheet may be, as a share of its pane's height.
  final double? maxHeightFactor;

  static SheetHost? _of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SheetHost>();

  @override
  bool updateShouldNotify(SheetHost oldWidget) =>
      oldWidget.navigator != navigator ||
      oldWidget.maxWidth != maxWidth ||
      oldWidget.maxHeightFactor != maxHeightFactor;
}
