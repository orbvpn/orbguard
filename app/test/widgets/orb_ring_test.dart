// OrbRing's motion contract: the ring moves only while something real runs,
// plays the closing of a gap exactly once, and never moves when the platform
// asks for reduced motion. How it looks is checked by eye from rendered frames;
// what these tests hold is when it is allowed to animate at all, because a ring
// that breathes with nothing on watch would be claiming protection that is not
// there.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/widgets/home/orb_ring.dart';

Future<void> _show(
  WidgetTester tester,
  OrbStatus status, {
  bool reduceMotion = false,
  VoidCallback? onTap,
  Widget? child,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: OrbRing(
              status: status,
              onTap: onTap,
              semanticLabel: 'Privacy score',
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// Pumps enough fixed frames for any one-shot animation to finish.
Future<void> _letOneShotsFinish(WidgetTester tester) async {
  for (int i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a live ring keeps moving', (tester) async {
    await _show(tester, const OrbStatus.whole(live: true));

    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('a whole ring with nothing on watch holds still', (tester) async {
    await _show(tester, const OrbStatus.whole(live: false));

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a ring that was never checked holds still', (tester) async {
    await _show(tester, const OrbStatus.fresh());

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a running check keeps the ring moving', (tester) async {
    await _show(
      tester,
      const OrbStatus.checking(
          [OrbSegment.done, OrbSegment.running, OrbSegment.pending]),
    );

    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('reduced motion stops a live ring', (tester) async {
    await _show(tester, const OrbStatus.whole(live: true), reduceMotion: true);

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('closing a gap plays once, then the ring rests', (tester) async {
    await _show(tester, const OrbStatus.open([150], live: false));
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'an open ring with nothing on watch does not move');

    await _show(tester, const OrbStatus.whole(live: false));
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'the two ends travel toward each other');

    await _letOneShotsFinish(tester);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion closes a gap at once, with no animation',
      (tester) async {
    await _show(tester, const OrbStatus.open([150], live: false),
        reduceMotion: true);
    await _show(tester, const OrbStatus.whole(live: false), reduceMotion: true);

    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a tap reaches the caller', (tester) async {
    int taps = 0;
    await _show(tester, const OrbStatus.whole(live: false),
        onTap: () => taps++);

    await tester.tap(find.byType(OrbRing));
    await _letOneShotsFinish(tester);

    expect(taps, 1);
  });

  testWidgets(
      'it is announced as one focusable button, by the label it is given',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _show(
      tester,
      const OrbStatus.whole(live: false),
      onTap: () {},
      child: const Text('900'),
    );

    // The label is matched exactly: what sits in the hole is not read twice.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Privacy score')),
      isSemantics(
        label: 'Privacy score',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('the keyboard can press it', (tester) async {
    int taps = 0;
    await _show(tester, const OrbStatus.whole(live: false),
        onTap: () => taps++);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _letOneShotsFinish(tester);

    expect(taps, 1);
  });

  testWidgets('the hole shows what it is given', (tester) async {
    await _show(tester, const OrbStatus.whole(live: false),
        child: const Text('900'));

    expect(find.text('900'), findsOneWidget);
  });
}
