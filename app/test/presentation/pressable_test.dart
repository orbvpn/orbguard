// Pressable is the kit's small press target. These tests hold what a person
// can rely on: a press reaches the caller, the keyboard can press it, it is
// announced as one button by the name it is given, and without an action it is
// not a button at all.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/pressable.dart';

Future<void> _show(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('a press reaches the caller', (tester) async {
    int presses = 0;
    await _show(
        tester,
        Pressable(
            onTap: () => presses++,
            child: const SizedBox.square(dimension: 44)));

    await tester.tap(find.byType(Pressable));
    await tester.pump(const Duration(milliseconds: 200));

    expect(presses, 1);
  });

  testWidgets('the keyboard can press it', (tester) async {
    int presses = 0;
    await _show(
        tester,
        Pressable(
            onTap: () => presses++,
            child: const SizedBox.square(dimension: 44)));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 200));

    expect(presses, 1);
  });

  testWidgets('it is one button, read by the name it is given', (tester) async {
    final handle = tester.ensureSemantics();
    await _show(
        tester,
        Pressable(
            onTap: () {}, semanticLabel: 'Alerts', child: const Text('3')));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Alerts')),
      isSemantics(label: 'Alerts', isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });

  testWidgets('it can say that it is the selected one of a set',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _show(
        tester,
        Pressable(
            onTap: () {},
            semanticLabel: 'Protect',
            selected: true,
            child: const Text('x')));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Protect')),
      isSemantics(isButton: true, isSelected: true),
    );
    handle.dispose();
  });

  testWidgets('with nothing to do it is not announced as a button',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _show(
        tester,
        const Pressable(
            onTap: null, semanticLabel: 'Alerts', child: Text('3')));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Alerts')),
      isNot(isSemantics(isButton: true)),
    );
    handle.dispose();
  });
}
