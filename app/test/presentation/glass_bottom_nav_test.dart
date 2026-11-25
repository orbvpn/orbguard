// The floating tab bar. These tests hold what a person relies on: a press
// changes tab, the keyboard can too, a screen reader hears which tab is the
// current one, the labels survive the largest text size, and the bar never
// sits on top of the system's own controls.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:orbguard/presentation/widgets/duotone_icon.dart';
import 'package:orbguard/presentation/widgets/glass_bottom_nav.dart';

const _items = [
  NavItem(label: 'Home', iconPath: AppIcons.homeSmile),
  NavItem(label: 'Protect', iconPath: AppIcons.shieldCheck),
  NavItem(label: 'Check', iconPath: AppIcons.search),
  NavItem(label: 'Me', iconPath: AppIcons.userRounded),
];

Future<void> _show(
  WidgetTester tester, {
  int current = 0,
  ValueChanged<int>? onTap,
  double textScale = 1,
  double bottomInset = 0,
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(platform: platform),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: GlassBottomNavBar(
                currentIndex: current,
                onTap: onTap ?? (_) {},
                items: _items,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Distance from the bottom of the bar's glass to the bottom of the screen.
double _gapUnderBar(WidgetTester tester) =>
    844 - tester.getRect(find.byType(BackdropFilter)).bottom;

void main() {
  testWidgets('a press reports the tab that was pressed', (tester) async {
    int? pressed;
    await _show(tester, onTap: (i) => pressed = i);

    await tester.tap(find.text('Check'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(pressed, 2);
  });

  testWidgets('the keyboard can change tab', (tester) async {
    int? pressed;
    await _show(tester, onTap: (i) => pressed = i);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));

    expect(pressed, 1, reason: 'the second tab stop is Protect');
  });

  testWidgets('a screen reader hears which tab is the current one',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _show(tester, current: 1);

    expect(
      tester.getSemantics(find.bySemanticsLabel('Protect')),
      isSemantics(
          label: 'Protect',
          isButton: true,
          isSelected: true,
          hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Home')),
      isSemantics(label: 'Home', isButton: true, isSelected: false),
    );
    handle.dispose();
  });

  testWidgets('the labels fit at the largest text size a phone offers',
      (tester) async {
    // 3.1 is iOS's largest accessibility size.
    await _show(tester, textScale: 3.1);

    expect(tester.takeException(), isNull);
    expect(find.text('Protect'), findsOneWidget);
  });

  testWidgets('on Android the bar stays clear of the navigation buttons',
      (tester) async {
    // Three-button navigation: the whole 48 inset is the buttons themselves.
    await _show(tester, bottomInset: 48);

    expect(_gapUnderBar(tester), greaterThan(48));
  });

  testWidgets('on an iPhone the bar sits just above the home indicator',
      (tester) async {
    // Of the 34 an iPhone reserves, the indicator itself uses the lowest 13.
    await _show(tester, bottomInset: 34, platform: TargetPlatform.iOS);

    final double gap = _gapUnderBar(tester);
    expect(gap, greaterThanOrEqualTo(21),
        reason: 'clear of the home indicator');
    expect(gap, lessThan(34),
        reason: 'not floating a whole inset above the edge');
  });
}
