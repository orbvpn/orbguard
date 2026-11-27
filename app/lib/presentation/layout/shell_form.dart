// Which shape the app takes for a window.
//
// Worked out from the window alone: its size, the folds and hinges the
// system reports, and the platform. The shell reads it on every build, so a
// foldable that opens, a tablet that turns or a desktop window that is
// dragged narrower changes shape at once.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum ShellKind {
  /// One column with the tab bar under it.
  phone,

  /// Two panes side by side: the ring on one, what it opens on the other.
  split,

  /// Half open on a table: the ring above the fold, the rest below it.
  tabletop,

  /// A computer window: a sidebar, the ring's column and a side column.
  desk,
}

@immutable
class ShellForm {
  const ShellForm._(this.kind, this.primary, this.secondary);

  factory ShellForm.of({
    required Size size,
    required List<DisplayFeature> features,
    required TargetPlatform platform,
  }) {
    final Rect window = Offset.zero & size;

    for (final DisplayFeature f in features) {
      if (f.type == DisplayFeatureType.cutout) continue;
      final Rect b = f.bounds;
      final bool across = b.width > b.height;
      if (across) {
        // A fold across the screen only splits it when the screen is bent,
        // or when there is a hinge in the way to keep clear of.
        final bool bent = f.state == DisplayFeatureState.postureHalfOpened;
        if (!bent && b.height == 0) continue;
        if (b.top < minHalf || size.height - b.bottom < minHalf) continue;
        return ShellForm._(
          ShellKind.tabletop,
          Rect.fromLTRB(0, 0, size.width, b.top),
          Rect.fromLTRB(0, b.bottom, size.width, size.height),
        );
      }
      // A fold down the middle splits there, so nothing sits on it. A fold
      // that would leave a pane too narrow to read is not split at, unless a
      // hinge is in the way.
      final bool occludes = b.width > 0;
      if (!occludes && (b.left < minPane || size.width - b.right < minPane)) {
        continue;
      }
      return ShellForm._(
        ShellKind.split,
        Rect.fromLTRB(0, 0, b.left, size.height),
        Rect.fromLTRB(b.right, 0, size.width, size.height),
      );
    }

    if (size.height < minHeight || size.width < minPane * 2) {
      return ShellForm._(ShellKind.phone, window, Rect.zero);
    }
    if (_computer(platform) && size.width >= deskMinWidth) {
      return ShellForm._(ShellKind.desk, window, Rect.zero);
    }
    final double ring = math.min(size.width / 2, ringColumn);
    return ShellForm._(
      ShellKind.split,
      Rect.fromLTWH(0, 0, ring, size.height),
      Rect.fromLTRB(ring, 0, size.width, size.height),
    );
  }

  /// The narrowest pane the phone layout still reads well in.
  static const double minPane = 320;

  /// The shortest window two panes are worth it in. A phone on its side is
  /// shorter, and keeps the phone layout.
  static const double minHeight = 480;

  /// The least height each half of a tabletop screen needs.
  static const double minHalf = 240;

  /// The ring's column, when a window is wider than two even panes need.
  static const double ringColumn = 440;

  /// The desktop sidebar.
  static const double sidebar = 224;

  /// A computer window narrower than this gets the panes instead.
  static const double deskMinWidth = sidebar + ringColumn + minPane;

  final ShellKind kind;

  /// The ring's side, or the whole window for the phone and the desk.
  final Rect primary;

  /// What the ring opens, or [Rect.zero] when there is one column.
  final Rect secondary;

  static bool _computer(TargetPlatform p) =>
      p == TargetPlatform.macOS ||
      p == TargetPlatform.windows ||
      p == TargetPlatform.linux;

  @override
  bool operator ==(Object other) =>
      other is ShellForm &&
      other.kind == kind &&
      other.primary == primary &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(kind, primary, secondary);

  @override
  String toString() => 'ShellForm(${kind.name}, $primary, $secondary)';
}
