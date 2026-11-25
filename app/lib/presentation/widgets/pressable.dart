/// A plain press target in the kit's manner: it dips when pressed, shows the
/// kit focus ring for keyboard users, and is announced as one button.
///
/// Use it for small chrome (a round glass button, a chip, a row). The one
/// primary action on a screen is still a [BrandButton].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/brand.dart';

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.selected,
    this.radius = const BorderRadius.all(Radius.circular(Brand.rPill)),
  });

  /// Null makes it inert: drawn the same, but not a button.
  final VoidCallback? onTap;
  final Widget child;

  /// When set, this is read in place of whatever [child] contains.
  final String? semanticLabel;

  /// For one of a set (a tab): whether this is the current one. Null when it
  /// is not part of a set.
  final bool? selected;

  /// Shape of the focus ring.
  final BorderRadius radius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _focused = false;

  void _press(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion = MediaQuery.disableAnimationsOf(context);
    final VoidCallback? onTap = widget.onTap;
    final String? label = widget.semanticLabel;

    Widget body = AnimatedScale(
      scale: _down ? 0.955 : 1,
      duration: Duration(milliseconds: reduceMotion ? 0 : 110),
      curve: Curves.easeOut,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          border: _focused ? Border.all(color: Brand.focus, width: 2) : null,
        ),
        child: widget.child,
      ),
    );
    if (label != null) body = ExcludeSemantics(child: body);

    if (onTap == null) {
      // Still its own node, so its name is not run together with a
      // neighbour's.
      return label == null
          ? body
          : Semantics(container: true, label: label, child: body);
    }

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      label: label,
      onTap: onTap,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (show) => setState(() => _focused = show),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapDown: (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: body,
        ),
      ),
    );
  }
}
