// One pane of a window split in two, at the rect the shell's form gives it.
//
// Inside, the pane lays itself out as if it were the whole screen: it is
// told its own size, and only the edges of the screen it touches keep their
// safe-area insets and the keyboard's. So a page built for a phone works in
// a pane unchanged, and nothing in it slips under the hinge or the notch.
import 'package:flutter/widgets.dart';

class Pane extends StatelessWidget {
  const Pane({super.key, required this.rect, required this.child});

  /// Where the pane sits in the window.
  final Rect rect;
  final Widget child;

  /// What a pane at [rect] in a window described by [window] is told.
  static MediaQueryData mediaFor(MediaQueryData window, Rect rect) {
    final Size whole = window.size;
    const double touch = 0.5;
    final bool left = rect.left <= touch;
    final bool top = rect.top <= touch;
    final bool right = rect.right >= whole.width - touch;
    final bool bottom = rect.bottom >= whole.height - touch;

    EdgeInsets keep(EdgeInsets e) => EdgeInsets.fromLTRB(
          left ? e.left : 0,
          top ? e.top : 0,
          right ? e.right : 0,
          bottom ? e.bottom : 0,
        );

    return window.copyWith(
      size: rect.size,
      padding: keep(window.padding),
      viewPadding: keep(window.viewPadding),
      viewInsets: keep(window.viewInsets),
      systemGestureInsets: keep(window.systemGestureInsets),
      // The shell has already split the window at its folds.
      displayFeatures: const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fromRect(
      rect: rect,
      child: MediaQuery(
        data: mediaFor(MediaQuery.of(context), rect),
        child: child,
      ),
    );
  }
}

/// A page of a pane's own navigator. It rises in the way the prototype's
/// views do, a short fade with six points of travel, and simply appears for
/// someone who asked for less motion. Its child is read afresh each time the
/// pane is drawn, so the page always shows what is true now.
class PanePage extends Page<void> {
  const PanePage({required LocalKey super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _PaneRoute(this);
}

class _PaneRoute extends PageRoute<void> {
  _PaneRoute(PanePage page) : super(settings: page);

  PanePage get _page => settings as PanePage;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 240);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      _page.child;

  /// The pane's first page is the pane itself: there is nothing under it to
  /// go back to, so a back button on it does not empty the pane.
  @override
  bool didPop(void result) {
    if (isFirst) return false;
    return super.didPop(result);
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final Animation<double> rise =
        CurvedAnimation(parent: animation, curve: Curves.easeOut);
    return FadeTransition(
      opacity: rise,
      child: AnimatedBuilder(
        animation: rise,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 6 * (1 - rise.value)),
          child: child,
        ),
        child: child,
      ),
    );
  }
}
