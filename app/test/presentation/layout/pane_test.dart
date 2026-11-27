// A pane is a part of the window that lays itself out as if it were the
// whole screen: it is told its own size, and only the edges of the screen
// it touches keep their safe-area insets.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/layout/pane.dart';

void main() {
  const MediaQueryData window = MediaQueryData(
    size: Size(841, 701),
    padding: EdgeInsets.fromLTRB(12, 24, 14, 16),
    viewPadding: EdgeInsets.fromLTRB(12, 24, 14, 16),
    viewInsets: EdgeInsets.only(bottom: 300),
  );

  test('the left pane keeps the left, top and bottom insets', () {
    final MediaQueryData m =
        Pane.mediaFor(window, const Rect.fromLTWH(0, 0, 420, 701));
    expect(m.size, const Size(420, 701));
    expect(m.padding, const EdgeInsets.fromLTRB(12, 24, 0, 16));
    expect(m.viewPadding, const EdgeInsets.fromLTRB(12, 24, 0, 16));
    expect(m.viewInsets, const EdgeInsets.only(bottom: 300));
  });

  test('the right pane keeps the right, top and bottom insets', () {
    final MediaQueryData m =
        Pane.mediaFor(window, const Rect.fromLTWH(420, 0, 421, 701));
    expect(m.size, const Size(421, 701));
    expect(m.padding, const EdgeInsets.fromLTRB(0, 24, 14, 16));
  });

  test('the top half of a tabletop screen has no bottom inset or keyboard',
      () {
    final MediaQueryData m =
        Pane.mediaFor(window, const Rect.fromLTWH(0, 0, 841, 340));
    expect(m.padding, const EdgeInsets.fromLTRB(12, 24, 14, 0));
    expect(m.viewInsets, EdgeInsets.zero);
  });

  test('a pane reports no folds of its own', () {
    final MediaQueryData m = Pane.mediaFor(
      window.copyWith(displayFeatures: const [
        DisplayFeature(
          bounds: Rect.fromLTWH(420, 0, 0, 701),
          type: DisplayFeatureType.fold,
          state: DisplayFeatureState.postureFlat,
        ),
      ]),
      const Rect.fromLTWH(420, 0, 421, 701),
    );
    expect(m.displayFeatures, isEmpty);
  });

  testWidgets('a pane places its child and tells it its size', (tester) async {
    tester.view.physicalSize = const Size(841, 701);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Size seen;
    await tester.pumpWidget(MaterialApp(
      home: Stack(
        children: [
          Pane(
            rect: const Rect.fromLTWH(420, 0, 421, 701),
            child: Builder(builder: (context) {
              seen = MediaQuery.sizeOf(context);
              return const SizedBox.expand(key: Key('inside'));
            }),
          ),
        ],
      ),
    ));
    expect(seen, const Size(421, 701));
    expect(tester.getRect(find.byKey(const Key('inside'))),
        const Rect.fromLTWH(420, 0, 421, 701));
  });
}
