// Which shape the app takes for a window, worked out from the window alone.
//
// A pure function of the window's size, the folds and hinges the system
// reports, and the platform. The rules it holds:
//  - a phone-sized window stays a phone, in either orientation
//  - a window wide enough for two readable columns gets two panes, and an
//    unfolded foldable is split at its fold, so nothing sits under the hinge
//  - half open on a table, the screen splits at the fold into a top and a
//    bottom half
//  - a computer window wide enough gets the desktop layout; a narrow one
//    falls back to the panes or the phone
//  - a camera cutout is not a fold

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/layout/shell_form.dart';

DisplayFeature _fold(Rect bounds,
        {DisplayFeatureType type = DisplayFeatureType.fold,
        DisplayFeatureState state = DisplayFeatureState.postureFlat}) =>
    DisplayFeature(bounds: bounds, type: type, state: state);

ShellForm _form(
  double width,
  double height, {
  TargetPlatform platform = TargetPlatform.android,
  List<DisplayFeature> features = const [],
}) =>
    ShellForm.of(
        size: Size(width, height), features: features, platform: platform);

void main() {
  group('a phone', () {
    test('stays a phone upright', () {
      expect(_form(390, 844).kind, ShellKind.phone);
    });

    test('stays a phone on its side: too short for two panes', () {
      expect(_form(844, 390).kind, ShellKind.phone);
    });

    test('a camera cutout is not a fold', () {
      final ShellForm f = _form(390, 844, features: [
        _fold(const Rect.fromLTWH(170, 0, 50, 30),
            type: DisplayFeatureType.cutout,
            state: DisplayFeatureState.unknown),
      ]);
      expect(f.kind, ShellKind.phone);
    });

    test('a folded foldable\'s cover screen is a phone', () {
      expect(_form(360, 760).kind, ShellKind.phone);
    });
  });

  group('an unfolded foldable', () {
    test('splits at its fold, one pane each side', () {
      final ShellForm f = _form(841, 701, features: [
        _fold(const Rect.fromLTWH(420, 0, 0, 701)),
      ]);
      expect(f.kind, ShellKind.split);
      expect(f.primary, const Rect.fromLTWH(0, 0, 420, 701));
      expect(f.secondary, const Rect.fromLTWH(420, 0, 421, 701));
    });

    test('keeps both panes off a hinge that has width', () {
      final ShellForm f = _form(1114, 720, features: [
        _fold(const Rect.fromLTWH(540, 0, 34, 720),
            type: DisplayFeatureType.hinge),
      ]);
      expect(f.kind, ShellKind.split);
      expect(f.primary.right, 540);
      expect(f.secondary.left, 574);
      expect(f.secondary.right, 1114);
    });

    test('half open on a table, splits into a top and a bottom half', () {
      final ShellForm f = _form(701, 841, features: [
        _fold(const Rect.fromLTWH(0, 420, 701, 0),
            state: DisplayFeatureState.postureHalfOpened),
      ]);
      expect(f.kind, ShellKind.tabletop);
      expect(f.primary, const Rect.fromLTWH(0, 0, 701, 420));
      expect(f.secondary, const Rect.fromLTWH(0, 420, 701, 421));
    });

    test('lying flat with the fold across, it is two panes side by side', () {
      final ShellForm f = _form(701, 841, features: [
        _fold(const Rect.fromLTWH(0, 420, 701, 0)),
      ]);
      expect(f.kind, ShellKind.split);
      expect(f.primary.height, 841);
    });

    test('a hinge across the screen is never sat on, even lying flat', () {
      final ShellForm f = _form(720, 1114, features: [
        _fold(const Rect.fromLTWH(0, 540, 720, 34),
            type: DisplayFeatureType.hinge),
      ]);
      expect(f.kind, ShellKind.tabletop);
      expect(f.primary.bottom, 540);
      expect(f.secondary.top, 574);
    });

    test('a fold that would leave a pane too narrow is not split at', () {
      final ShellForm f = _form(841, 701, features: [
        _fold(const Rect.fromLTWH(200, 0, 0, 701)),
      ]);
      expect(f.kind, ShellKind.split);
      expect(f.primary.width, f.secondary.width,
          reason: 'it falls back to the window\'s own halves');
    });
  });

  group('a tablet', () {
    test('upright, it gets two even panes', () {
      final ShellForm f = _form(820, 1180, platform: TargetPlatform.iOS);
      expect(f.kind, ShellKind.split);
      expect(f.primary.width, 410);
      expect(f.secondary.left, 410);
    });

    test('wide, the ring keeps a readable column and the detail the rest', () {
      final ShellForm f = _form(1180, 820, platform: TargetPlatform.iOS);
      expect(f.kind, ShellKind.split);
      expect(f.primary.width, ShellForm.ringColumn);
      expect(f.secondary.width, 1180 - ShellForm.ringColumn);
    });
  });

  group('a computer', () {
    for (final TargetPlatform p in const [
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    ]) {
      test('${p.name}: a wide window is the desktop layout', () {
        expect(_form(1180, 760, platform: p).kind, ShellKind.desk);
      });
    }

    test('a narrow window falls back to the panes', () {
      expect(_form(900, 700, platform: TargetPlatform.windows).kind,
          ShellKind.split);
    });

    test('a window as small as a phone is a phone', () {
      expect(_form(480, 760, platform: TargetPlatform.linux).kind,
          ShellKind.phone);
    });

    test('a phone never gets the desktop layout, however wide', () {
      expect(_form(1400, 900, platform: TargetPlatform.android).kind,
          ShellKind.split);
    });
  });
}
